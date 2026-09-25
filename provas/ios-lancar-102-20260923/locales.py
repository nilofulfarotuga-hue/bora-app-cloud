# -*- coding: utf-8 -*-
"""Que idiomas a ficha da app suporta (appInfoLocalizations)."""
import asc_api as a
INFO = "ee0d7708-82a1-4a1e-9fe3-f3dd0045d55e"
c, v = a.get("/v1/appInfos/%s/appInfoLocalizations" % INFO,
             **{"fields[appInfoLocalizations]": "locale,name,subtitle"})
print("HTTP", c)
for d in v.get("data", []):
    print("  ", d["attributes"].get("locale"), "|", d["attributes"].get("name"))
