"""
Fase 0 — INSPEÇÃO de estrutura de preço continente.pt (read-only, ZERO writes BD).
Faz fetch de produtos-amostra (com e sem promoção), grava o HTML cru em tmp/
e imprime só status+len. A análise da estrutura faz-se depois via Grep nos HTML.
"""
import urllib.request, urllib.error, os, time

BASE = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai"
TMP = os.path.join(BASE, "tmp")
os.makedirs(TMP, exist_ok=True)

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0 Safari/537.36"
URL = "https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Product-Show?pid={pid}"

SAMPLES = [
    ("7795050", "Sanex Cuidado Experto Protector 600ml (espera PROMO; PVPR 5.99)"),
    ("7795037", "Sanex Zero% Pele Seca 600ml (espera PROMO; PVPR 5.99)"),
    ("8496362", "Vaseline Manteiga Karite 700ml (PVPR 4.99)"),
    ("7626664", "Gresso UHT Magro s/Lactose 1L (espera SEM promo; 1.06)"),
]

def fetch(pid):
    req = urllib.request.Request(URL.format(pid=pid),
        headers={"User-Agent": UA, "Accept-Language": "pt-PT,pt;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, r.geturl(), r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, URL.format(pid=pid), ""
    except Exception as e:
        return -1, URL.format(pid=pid), f"ERR:{e}"

if __name__ == "__main__":
    import sys
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    for i, (pid, label) in enumerate(SAMPLES):
        st, final, html = fetch(pid)
        blocked = st in (403, 429)
        path = os.path.join(TMP, f"phase0_{pid}.html")
        if html and not html.startswith("ERR:"):
            with open(path, "w", encoding="utf-8") as f:
                f.write(html)
        print(f"{pid} | status={st} blocked={blocked} len={len(html) if html else 0} | {label}")
        print(f"     final_url={final[:90]}")
        if i < len(SAMPLES) - 1:
            time.sleep(4)
    print("DONE — HTML gravado em tmp/phase0_<pid>.html")
