#!/usr/bin/env python3
"""Quartier Coop : extrait les passages PRÉVUS (horaires théoriques GTFS de la CTS) pour quelques arrêts
et écrit un petit fichier horaires.json lu par le site. Bibliothèque standard uniquement.

Utilisation (par GitHub Actions) :  python scripts/horaires.py
Test local :  python horaires.py --local google_transit.zip --aujourdhui 2026-11-16 --sortie /tmp/horaires.json
"""
import argparse, csv, io, json, sys, unicodedata, urllib.request, zipfile
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

# Arrêts à afficher : (nom exact tel qu'écrit dans les données CTS, mode)
ARRETS = [("Starcoop", "tram"), ("Capitainerie", "bus"), ("Coopérative", "bus")]
JOURS = 3  # nombre de jours de passages conservés (aujourd'hui compris)
PARIS = ZoneInfo("Europe/Paris")
# Fichier principal (zip GTFS) du jeu de données « Données théoriques (GTFS) et temps réel (SIRI-lite) du réseau CTS »
# sur data.gouv.fr : cette adresse « permanente » redirige toujours vers la version la plus récente.
URL_PRINCIPALE = "https://www.data.gouv.fr/api/1/datasets/r/eeea9e52-4f8a-459e-aef5-a093a3b05356"
API_DATAGOUV = "https://www.data.gouv.fr/api/1/datasets/donnees-theoriques-gtfs-et-temps-reel-siri-lite-du-reseau-cts/"
API_PAN = "https://transport.data.gouv.fr/api/datasets/donnees-theoriques-gtfs-et-temps-reel-siri-lite-du-reseau-cts"
SECOURS = "http://opendata.cts-strasbourg.fr/fichiers/gtfs/google_transit.zip"
UA = {"User-Agent": "quartier-coop-horaires/1.0"}


def norm(s):
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn").strip()


def telecharger(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def adresses_candidates():
    """Adresses à essayer, dans l'ordre. Les suivantes ne servent que si la première échoue."""
    yield URL_PRINCIPALE
    for api in (API_DATAGOUV, API_PAN):
        try:
            d = json.loads(telecharger(api))
            for r in d.get("resources", []):
                fmt = (r.get("format") or "").lower()
                if (fmt in ("gtfs", "zip") or str(r.get("url", "")).lower().endswith(".zip")) and r.get("url"):
                    yield r["url"]
        except Exception as e:  # noqa: BLE001
            print("Interface indisponible :", api, ":", e)
    yield SECOURS


def charger_gtfs():
    """Télécharge le premier fichier GTFS valide parmi les adresses candidates."""
    erreurs = []
    for url in adresses_candidates():
        try:
            print("Essai :", url)
            brut = telecharger(url)
            if not zipfile.is_zipfile(io.BytesIO(brut)):
                raise ValueError("ce n'est pas un fichier zip")
            with zipfile.ZipFile(io.BytesIO(brut)) as z:
                if "stops.txt" not in z.namelist():
                    raise ValueError("pas de stops.txt dans le zip")
            print("Fichier reçu :", len(brut), "octets")
            return brut
        except Exception as e:  # noqa: BLE001
            print("Échec :", url, ":", e)
            erreurs.append(f"{url} : {e}")
    print("::error::Aucune adresse n'a fourni de fichier GTFS valide. " + " | ".join(erreurs))
    sys.exit(1)


def lire(z, nom):
    with z.open(nom) as f:
        yield from csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))


def hms(t):
    h, m, s = (int(x) for x in t.strip().split(":"))
    return h * 3600 + m * 60 + s


def jours_actifs(z, jours):
    noms = set(z.namelist())
    actifs = {}
    if "calendar.txt" in noms:
        for c in lire(z, "calendar.txt"):
            d0 = datetime.strptime(c["start_date"], "%Y%m%d").date()
            d1 = datetime.strptime(c["end_date"], "%Y%m%d").date()
            flags = [c[k] == "1" for k in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")]
            actifs[c["service_id"]] = {j for j in jours if d0 <= j <= d1 and flags[j.weekday()]}
    if "calendar_dates.txt" in noms:
        for c in lire(z, "calendar_dates.txt"):
            j = datetime.strptime(c["date"], "%Y%m%d").date()
            if j not in jours:
                continue
            s = actifs.setdefault(c["service_id"], set())
            if c["exception_type"] == "1":
                s.add(j)
            else:
                s.discard(j)
    return actifs


def extraire(z, aujourdhui):
    cibles = {norm(n): (n, m) for n, m in ARRETS}
    stops, candidats = {}, set()
    for s in lire(z, "stops.txt"):
        n = norm(s["stop_name"])
        if n in cibles:
            stops[s["stop_id"]] = cibles[n][0]
        elif any(k in n for k in cibles):
            candidats.add(s["stop_name"])
    for nom, _ in ARRETS:
        ids = [i for i, n in stops.items() if n == nom]
        print(f"Arrêt « {nom} » : {len(ids)} point(s) d'arrêt trouvé(s) {ids}")
        if not ids:
            debut = norm(nom)[:5]
            proches = sorted({s["stop_name"] for s in lire(z, "stops.txt") if debut in norm(s["stop_name"])})
            print(f"::warning::Arrêt « {nom} » introuvable. Noms proches dans les données : {proches[:20]}")
    if candidats:
        print("Noms voisins ignorés (vérifiez si l'un d'eux est le bon) :", sorted(candidats))

    jours = [aujourdhui + timedelta(days=i) for i in range(-1, JOURS)]  # la veille : trajets après minuit
    actifs = jours_actifs(z, set(jours))

    routes = {}
    for r in lire(z, "routes.txt"):
        routes[r["route_id"]] = (r.get("route_short_name") or r.get("route_long_name") or "").strip()
    trips = {}
    for t in lire(z, "trips.txt"):
        trips[t["trip_id"]] = (t["route_id"], t["service_id"], (t.get("trip_headsign") or "").strip())

    debut = datetime.combine(aujourdhui, time(0, 0), tzinfo=PARIS).timestamp()
    fin = datetime.combine(aujourdhui + timedelta(days=JOURS), time(0, 0), tzinfo=PARIS).timestamp()
    par_arret = {nom: [] for nom, _ in ARRETS}
    for st in lire(z, "stop_times.txt"):
        nom = stops.get(st["stop_id"])
        if not nom or st.get("pickup_type") == "1":
            continue
        heure = st.get("departure_time") or st.get("arrival_time")
        trip = trips.get(st["trip_id"])
        if not heure or not trip:
            continue
        route_id, service_id, cap = trip
        for j in actifs.get(service_id, ()):
            dt = datetime.combine(j, time(0, 0), tzinfo=PARIS) + timedelta(seconds=hms(heure))
            ts = int(dt.timestamp())
            if debut <= ts < fin:
                par_arret[nom].append([ts, routes.get(route_id, ""), cap])
    sortie = []
    for nom, mode in ARRETS:
        passages = sorted(set(map(tuple, par_arret[nom])))
        print(f"{nom} : {len(passages)} passage(s) sur {JOURS} jour(s)")
        sortie.append({"nom": nom, "mode": mode, "passages": [list(p) for p in passages]})
    return {
        "genere_le": datetime.now(PARIS).isoformat(timespec="minutes"),
        "valable_jusqu_a": int(fin),
        "source": "CTS – données ouvertes (GTFS), Licence Ouverte 2.0",
        "arrets": sortie,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--local", help="chemin d'un fichier GTFS (zip) déjà téléchargé")
    p.add_argument("--aujourdhui", help="date de référence AAAA-MM-JJ (tests)")
    p.add_argument("--sortie", default="horaires.json")
    a = p.parse_args()
    aujourdhui = date.fromisoformat(a.aujourdhui) if a.aujourdhui else datetime.now(PARIS).date()
    if a.local:
        brut = open(a.local, "rb").read()
    else:
        brut = charger_gtfs()
    with zipfile.ZipFile(io.BytesIO(brut)) as z:
        res = extraire(z, aujourdhui)
    if not any(a_["passages"] for a_ in res["arrets"]):
        print("::error::Aucun passage trouvé : le fichier n'est pas écrit. Vérifiez les noms d'arrêts (voir les lignes « introuvable » ci-dessus).")
        sys.exit(1)
    with open(a.sortie, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, separators=(",", ":"))
    print("Écrit :", a.sortie)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"::error::{type(e).__name__} : {e}")
        raise
