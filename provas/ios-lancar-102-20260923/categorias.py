# -*- coding: utf-8 -*-
"""Lê categoria primária/secundária e as localizações da ficha da app."""
import json
import asc_api as a

APP = "6809954739"
c, v = a.get("/v1/apps/%s/appInfos" % APP,
             include="primaryCategory,secondaryCategory")
print("appInfos HTTP", c)
for d in v.get("data", []):
    print(" appInfo", d["id"], json.dumps(d.get("attributes"), ensure_ascii=False))
    rel = d.get("relationships", {})
    for k in ("primaryCategory", "secondaryCategory"):
        print("   ", k, (rel.get(k, {}).get("data") or {}).get("id"))

c, loc = a.get("/v1/appStoreVersions/02c335b3-25f0-44c6-9590-0c6a18ca268d/appStoreVersionLocalizations",
               **{"fields[appStoreVersionLocalizations]": "locale,whatsNew"})
print("localizacoes da 1.0.2 HTTP", c)
for d in loc.get("data", []):
    at = d["attributes"]
    print("  ", d["id"], at.get("locale"), "| whatsNew:", (at.get("whatsNew") or "")[:60])
