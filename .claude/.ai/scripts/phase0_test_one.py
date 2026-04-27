"""
Phase 0 validation — fetch 1 product from continente.pt to confirm PID format.
Product: glv-2003965 → "Infusão de Camomila Saquetas Lipton"
"""
import sys
import json
import re
import urllib.request
import urllib.error

PID = "2003965"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0 Safari/537.36"

URLS = [
    f"https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Product-Show?pid={PID}",
    f"https://www.continente.pt/produto/{PID}.html",
]

def fetch(url: str, timeout: int = 15):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8", errors="replace")
            return r.status, r.geturl(), body
    except urllib.error.HTTPError as e:
        return e.code, url, e.read().decode("utf-8", errors="replace")[:2000]
    except Exception as e:
        return -1, url, f"ERR: {e}"

def extract_price(html: str):
    patterns = [
        r'"price"\s*:\s*(?:{\s*"value"\s*:\s*)?"?(\d+[.,]\d+)"?',
        r'data-price\s*=\s*"(\d+[.,]\d+)"',
        r'"salePrice"\s*:\s*"?(\d+[.,]\d+)"?',
        r'itemprop=["\']price["\']\s+content=["\'](\d+[.,]\d+)["\']',
        r'<meta[^>]+property=["\']product:price:amount["\'][^>]+content=["\'](\d+[.,]\d+)["\']',
        r'class="[^"]*ct-price-formatted[^"]*"[^>]*>\s*(\d+[.,]\d+)\s*€',
    ]
    for p in patterns:
        m = re.search(p, html, re.IGNORECASE)
        if m:
            return m.group(1), p
    return None, None

def extract_title(html: str):
    m = re.search(r"<title[^>]*>(.*?)</title>", html, re.IGNORECASE | re.DOTALL)
    return m.group(1).strip() if m else None

for url in URLS:
    status, final_url, body = fetch(url)
    title = extract_title(body) if isinstance(body, str) else None
    price, pattern = extract_price(body) if isinstance(body, str) else (None, None)
    print(json.dumps({
        "url": url,
        "status": status,
        "final_url": final_url,
        "title": title,
        "body_len": len(body) if isinstance(body, str) else 0,
        "price": price,
        "pattern_hit": pattern,
    }, ensure_ascii=False))
    print("---")
    if price:
        sys.exit(0)
