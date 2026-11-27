// Quartier Coop · fonction Supabase « cts-temps-reel »
// Interroge l'API temps réel REST de la CTS (SIRI Lite) avec le token gardé secret côté serveur,
// et renvoie au site les prochains passages aux arrêts du quartier.
// Secret requis : CTS_TOKEN  (Supabase > Edge Functions > Secrets)

// Fonctions pures (testables) : lecture des réponses SIRI Lite de la CTS.
function norm(s: string): string {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

// Découverte des arrêts : renvoie les codes (StopPointRef) dont le nom correspond exactement.
function codesArret(disc: any, nom: string): string[] {
  const racine = disc?.StopPointsDelivery?.AnnotatedStopPointRef
    ?? disc?.Siri?.StopPointsDelivery?.AnnotatedStopPointRef
    ?? [];
  const n = norm(nom), out = new Set<string>();
  for (const s of racine) if (norm(s.StopName) === n && s.StopPointRef) out.add(String(s.StopPointRef));
  return [...out];
}

function texte(v: any): string {
  if (Array.isArray(v)) return texte(v[0]);
  if (v && typeof v === "object") return texte(v.value ?? v.Value ?? v.text ?? "");
  return v == null ? "" : String(v);
}

// Passages d'un arrêt : [heure_reelle_epoch, ligne, direction, heure_prevue_epoch|null]
function passages(mon: any): any[] {
  const deliveries = mon?.ServiceDelivery?.StopMonitoringDelivery ?? mon?.Siri?.ServiceDelivery?.StopMonitoringDelivery ?? [];
  const out: any[] = [];
  for (const d of deliveries) {
    for (const v of d.MonitoredStopVisit ?? []) {
      const j = v.MonitoredVehicleJourney ?? {}, c = j.MonitoredCall ?? {};
      const att = c.ExpectedDepartureTime || c.ExpectedArrivalTime || c.AimedDepartureTime || c.AimedArrivalTime;
      const pre = c.AimedDepartureTime || c.AimedArrivalTime;
      const t = att ? Date.parse(att) / 1000 : NaN;
      if (!isFinite(t)) continue;
      const p = pre ? Date.parse(pre) / 1000 : NaN;
      const ligne = texte(j.PublishedLineName) || texte(j.LineRef);
      const dest = texte(j.DestinationName) || texte(c.DestinationDisplay);
      out.push([Math.round(t), ligne, dest, isFinite(p) ? Math.round(p) : null]);
    }
  }
  out.sort((a, b) => a[0] - b[0]);
  return out;
}

const API = "https://api.cts-strasbourg.eu/v1/siri/2.0";
const ARRETS: Array<[string, string]> = [["Starcoop", "tram"], ["Capitainerie", "bus"], ["Coopérative", "bus"]];
const LIGNES_EXCLUES = new Set(["N3"]);
// Sites autorisés à appeler cette fonction (ajoutez l'adresse finale ici).
const AUTORISES = new Set([
  "https://kristof67-blip.github.io",
  "https://quartiercoop.fr",
  "https://www.quartiercoop.fr",
]);

let discoCache: { t: number; codes: Record<string, string[]> } | null = null;
let rep: { t: number; corps: string } | null = null;

function entetes(origine: string | null) {
  const h: Record<string, string> = { "Content-Type": "application/json; charset=utf-8", "Vary": "Origin" };
  if (origine && AUTORISES.has(origine)) {
    h["Access-Control-Allow-Origin"] = origine;
    h["Access-Control-Allow-Headers"] = "authorization, apikey, content-type, x-client-info";
  }
  return h;
}

async function cts(chemin: string): Promise<any> {
  const token = Deno.env.get("CTS_TOKEN");
  if (!token) throw new Error("secret CTS_TOKEN absent");
  const r = await fetch(API + chemin, {
    headers: { Authorization: "Basic " + btoa(token + ":"), Accept: "application/json" },
    signal: AbortSignal.timeout(8000),
  });
  if (!r.ok) throw new Error("CTS " + r.status);
  return await r.json();
}

async function codes(): Promise<Record<string, string[]>> {
  if (discoCache && Date.now() - discoCache.t < 6 * 3600e3) return discoCache.codes;
  const d = await cts("/stoppoints-discovery");
  const c: Record<string, string[]> = {};
  for (const [nom] of ARRETS) c[nom] = codesArret(d, nom);
  discoCache = { t: Date.now(), codes: c };
  return c;
}

Deno.serve(async (req) => {
  const origine = req.headers.get("origin");
  const h = entetes(origine);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: h });
  if (origine && !AUTORISES.has(origine)) return new Response('{"erreur":"origine refusée"}', { status: 403, headers: h });
  try {
    const url = new URL(req.url);
    // Diagnostic (réponse brute de la CTS) : ?debug=decouverte  ou  ?debug=arret:NOM
    const dbg = url.searchParams.get("debug");
    if (dbg) {
      const c = await codes();
      if (dbg === "decouverte") return new Response(JSON.stringify({ codes: c }), { headers: h });
      const nom = dbg.replace(/^arret:/, "");
      const q = (c[nom] || []).map((x) => "MonitoringRef=" + encodeURIComponent(x)).join("&");
      return new Response(JSON.stringify(await cts("/stop-monitoring?" + q)).slice(0, 20000), { headers: h });
    }
    if (rep && Date.now() - rep.t < 20e3) return new Response(rep.corps, { headers: h }); // 20 s de cache
    const c = await codes();
    const arrets = [];
    for (const [nom, mode] of ARRETS) {
      if (!c[nom]?.length) { arrets.push({ nom, mode, erreur: "arret_introuvable", passages: [] }); continue; }
      const q = c[nom].map((x) => "MonitoringRef=" + encodeURIComponent(x)).join("&");
      const p = passages(await cts("/stop-monitoring?" + q)).filter((x) => !LIGNES_EXCLUES.has(x[1]));
      arrets.push({ nom, mode, passages: p.slice(0, 40) });
    }
    const corps = JSON.stringify({ maj: new Date().toISOString(), arrets });
    rep = { t: Date.now(), corps };
    return new Response(corps, { headers: h });
  } catch (e) {
    return new Response(JSON.stringify({ erreur: String((e as Error).message || e) }), { status: 502, headers: h });
  }
});
