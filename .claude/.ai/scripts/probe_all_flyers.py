"""Fetch metadata for all 7 flyer UUIDs, map to real names, check which have product data."""
import json, sys, time, os, requests
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

uuids = [
    "019c2400-8c10-7249-b1a7-d62a2834841b",
    "019ce724-074a-7c32-90f1-a17a9255192b",
    "019d30fe-9e8f-712f-ba36-dcedd910f503",
    "019d9077-7863-73dd-a263-be2166671ede",
    "019d96ba-7d3a-7572-a513-c784f18f60be",
    "019d96ba-f920-76a6-bd89-dfa45929e51d",
    "69f075ad-932b-11ec-8570-005056aefbf3",
]

s = requests.Session()
s.headers.update({"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9",
                  "Accept": "application/json, text/plain, */*",
                  "Origin": "https://lidl.leaflets.schwarz",
                  "Referer": "https://lidl.leaflets.schwarz/"})

summary = []
for u in uuids:
    url = f"https://endpoints.leaflets.schwarz/v4/flyer?flyer_identifier={u}"
    r = s.get(url, timeout=30)
    if r.status_code != 200:
        summary.append({"uuid": u, "status": r.status_code, "err": r.text[:100]}); continue
    try:
        d = r.json()
    except Exception as e:
        summary.append({"uuid": u, "parse_err": str(e)}); continue
    fl = d.get("flyer", {})
    pages = fl.get("pages", [])
    total_links = sum(len(p.get("links", [])) for p in pages)
    # Look at link structure on first non-empty
    sample_link = None
    for p in pages:
        for lk in p.get("links", []):
            sample_link = lk; break
        if sample_link: break
    # Save raw to file
    with open(f"{TMP}/lidl_flyer_{u}.json", "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    summary.append({
        "uuid": u,
        "status": r.status_code,
        "name": fl.get("name"),
        "title": fl.get("title"),
        "subcategory": fl.get("subcategory"),
        "startDate": fl.get("startDate"),
        "endDate": fl.get("endDate"),
        "status_field": fl.get("status"),
        "pages": len(pages),
        "total_page_links": total_links,
        "flyer_products_count": len(fl.get("products", [])),
        "sample_link_keys": list(sample_link.keys()) if sample_link else None,
        "pdf_url": fl.get("pdfUrl"),
        "flyer_url": fl.get("flyerUrlAbsolute"),
    })
    time.sleep(2)

print(json.dumps(summary, ensure_ascii=False, indent=2))
with open(f"{TMP}/lidl_all_flyers_summary.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)
