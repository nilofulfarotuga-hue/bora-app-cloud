# -*- coding: utf-8 -*-
"""Lê o estado real da versão 1.0.2 na Apple + o lookup público por país."""
import json
import requests
import asc_api as a

V = "02c335b3-25f0-44c6-9590-0c6a18ca268d"

c, v = a.get("/v1/appStoreVersions/" + V,
             **{"fields[appStoreVersions]": "versionString,appStoreState,appVersionState,releaseType"})
print("ASC HTTP", c, json.dumps(v.get("data", {}).get("attributes"), ensure_ascii=False))

for pais in ("pt", "br"):
    d = requests.get("https://itunes.apple.com/lookup",
                     params={"id": "6809954739", "country": pais}, timeout=30).json()
    r = d.get("results") or []
    print("itunes", pais, "count", d.get("resultCount"),
          "version", (r[0].get("version") if r else None),
          (r[0].get("currentVersionReleaseDate") if r else None))
