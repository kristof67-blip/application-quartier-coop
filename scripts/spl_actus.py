#!/usr/bin/env python3
"""Quartier Coop : récupère les articles de la SPL Deux-Rives étiquetés « Coop ».
Écrit spl-actus.json (titre, date, lien : jamais le texte ni les photos).
Si le flux est indisponible, l'ancien fichier est conservé."""
import json, re, sys, html, urllib.request, xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone

SOURCES = [
    "https://strasbourgdeuxrives.eu/fr/feed/",
    "https://strasbourgdeuxrives.eu/fr/?feed=rss2",
    "https://strasbourgdeuxrives.eu/?feed=rss2",
]
BASE = "https://strasbourgdeuxrives.eu/"
MAX = 6
UA = "QuartierCoop/1.0 (https://quartiercoop.fr; hello@quartiercoop.fr)"

def lire(src):
    if not src.startswith("http"):
        return open(src, "rb").read()
    req = urllib.request.Request(src, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=30).read()

def articles(data):
    racine = ET.fromstring(data)
    out = []
    for it in racine.iter("item"):
        t = (it.findtext("title") or "").strip()
        lien = (it.findtext("link") or "").strip()
        d = (it.findtext("pubDate") or "").strip()
        cats = [(c.text or "").strip() for c in it.findall("category")]
        desc = it.findtext("description") or ""
        try:
            dt = parsedate_to_datetime(d).astimezone(timezone.utc)
        except Exception:
            continue
        out.append({"titre": html.unescape(t), "lien": lien, "date": dt.isoformat(), "cats": cats, "desc": desc})
    return out

def garder(items):
    coop = re.compile(r"\bcoop\b", re.I)
    if any(i["cats"] for i in items):
        res = [i for i in items if any(coop.search(c) for c in i["cats"])]
    else:
        res = [i for i in items if coop.search(i["titre"] + " " + i["desc"])]
    return res

def main():
    sources = sys.argv[1:] or SOURCES
    for src in sources:
        try:
            items = garder(articles(lire(src)))
        except Exception as e:
            print("Source ignorée", src, "->", e)
            continue
        items = [i for i in items if i["lien"].startswith(BASE) and i["titre"]]
        items.sort(key=lambda i: i["date"], reverse=True)
        if items:
            try:
                ancien = json.load(open("spl-actus.json", encoding="utf-8")).get("articles", [])
            except Exception:
                ancien = []
            vus = {i["lien"] for i in items}
            items += [{"titre": x["titre"], "date": x["date"], "lien": x["lien"]} for x in ancien
                      if x.get("lien") not in vus and str(x.get("lien", "")).startswith(BASE)]
            items.sort(key=lambda i: i["date"], reverse=True)
            res = {"maj": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                   "source": "Strasbourg Deux—Rives", "url": BASE,
                   "articles": [{"titre": i["titre"], "date": i["date"], "lien": i["lien"]} for i in items[:MAX]]}
            with open("spl-actus.json", "w", encoding="utf-8") as f:
                json.dump(res, f, ensure_ascii=False, indent=1)
            print(len(res["articles"]), "articles enregistrés depuis", src)
            return
    print("Aucun article trouvé : fichier inchangé.")

main()
