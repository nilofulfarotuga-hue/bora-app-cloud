"""Auchan encoding fix: PT mojibake + HTML entities.

Patterns observed (408 rows):
 - 370× `ÃO` → `ão`   (SalmÃO, CamarÃO, PÃO...)
 -  13× `ÃE` → `ãe`   (MÃE, PÃEzinhos)
 -   2× `ÃS` word-end → `ãs` (AvelÃS, RomÃS) — but FrancÃS → Francês
 -  32× `ã[A-Z]`     → `ã<lower>` (ProduÇãO → Produção)
 -  68× HTML entities (&Agrave;, &Ecirc;, &Uacute;, &ccedil;, ...)
 -   * standalone Ã before space/end → `ã` (HortelÃ, AvelÃ, RomÃ, SertÃ)

Strategy: dry-run first, output diff + overrides review.
"""
import os, sys, re, html, json, time, unicodedata
from dotenv import load_dotenv
import httpx
import concurrent.futures

env_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\backend\.env"
load_dotenv(env_path)
url = os.environ.get("SUPABASE_URL")
svc = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
assert url and svc, "missing env"

HTML_ENT = {
    "&Agrave;": "À", "&agrave;": "à",
    "&Aacute;": "Á", "&aacute;": "á",
    "&Acirc;":  "Â", "&acirc;":  "â",
    "&Atilde;": "Ã", "&atilde;": "ã",
    "&Eacute;": "É", "&eacute;": "é",
    "&Ecirc;":  "Ê", "&ecirc;":  "ê",
    "&Iacute;": "Í", "&iacute;": "í",
    "&Icirc;":  "Î", "&icirc;":  "î",
    "&Oacute;": "Ó", "&oacute;": "ó",
    "&Ocirc;":  "Ô", "&ocirc;":  "ô",
    "&Otilde;": "Õ", "&otilde;": "õ",
    "&Uacute;": "Ú", "&uacute;": "ú",
    "&Ucirc;":  "Û", "&ucirc;":  "û",
    "&Ntilde;": "Ñ", "&ntilde;": "ñ",
    "&Ccedil;": "Ç", "&ccedil;": "ç",
    "&Ordm;":   "º", "&ordm;":   "º",
    "&Ordf;":   "ª", "&ordf;":   "ª",
    "&Nbsp;":   " ", "&nbsp;":   " ",
}

# After general rule runs, some words become `ãs` but should be `ês` (French loans, etc.)
WORD_OVERRIDES = {
    "franc\u00e3s": "franc\u00eas",  # Francês (French cheese etc.)
}

def _unwrap_double_encoding(s: str) -> str:
    # "Ã" + U+0080..U+00BF  (two chars that, as latin-1 bytes, form a valid UTF-8 sequence)
    def repl(m):
        try:
            return m.group(0).encode("latin-1").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            return m.group(0)
    return re.sub(r"\u00c3[\u0080-\u00bf]", repl, s)

def fix_name(s: str) -> str:
    # 0. Unwrap double-UTF-8-encoded pairs (Ã + ctrl-char → real accented char)
    s = _unwrap_double_encoding(s)
    # 1. HTML entities
    for k, v in HTML_ENT.items():
        s = s.replace(k, v)
    s = html.unescape(s)
    # 2. `Ã` + uppercase letter → `ã` + that letter lowercased
    s = re.sub(r"Ã([A-ZÇ])", lambda m: "ã" + m.group(1).lower(), s)
    # 3. `ã` + uppercase letter → keep `ã`, lowercase the letter
    s = re.sub(r"ã([A-ZÇ])", lambda m: "ã" + m.group(1).lower(), s)
    # 4. Standalone `Ã` not followed by a letter → `ã`
    s = re.sub(r"Ã(?![A-Za-zÀ-ÿ])", "ã", s)
    # 4b. Any upper-case accented letter + upper-case ASCII → both lowercased
    #     (Fixes broken title-case from scraper: DÉLifrance→Délifrance, FrancÊS→Francês,
    #     MadagÁScar→Madagáscar, TrÊS→Três, DÚZia→Dúzia, ProduÇãO→Produção already done.)
    s = re.sub(r"([\u00c0-\u00d6\u00d8-\u00dd])([A-Z])",
               lambda m: m.group(1).lower() + m.group(2).lower(), s)
    # 4c. lowercase letter + upper-case accented → lowercase the accented
    #     (ProduÇão → Produção; AÇÚcar → Açúcar)
    s = re.sub(r"([a-z])([\u00c0-\u00d6\u00d8-\u00dd])",
               lambda m: m.group(1) + m.group(2).lower(), s)
    # Normalise to NFC so combining tildes collapse to precomposed ã
    s = unicodedata.normalize("NFC", s)
    # 5. Word-level overrides (francês etc.)
    def _word_sub(m):
        w = m.group(0)
        key = unicodedata.normalize("NFC", w.lower())
        if key in WORD_OVERRIDES:
            fixed = WORD_OVERRIDES[key]
            if w[0].isupper():
                fixed = fixed[0].upper() + fixed[1:]
            return fixed
        return w
    s = re.sub(r"[A-Za-zÀ-ÿ]+", _word_sub, s)
    return s


# ----- DRY RUN (fetch all Auchan products with Ã or HTML entity) -----
headers = {"apikey": svc, "Authorization": f"Bearer {svc}", "Content-Type": "application/json"}
client = httpx.Client(headers=headers, timeout=30.0, base_url=url)

r = client.get("/rest/v1/restaurants?select=id,name&name=ilike.*auchan*")
rest_ids = [x["id"] for x in r.json()]
print(f"Auchan restaurants: {rest_ids}")

rows = []
offset = 0
page = 1000
rest_filter = "in.(" + ",".join(rest_ids) + ")"
# Need to union Ã and & entities → do 2 queries
for pattern_name, postgrest in [("A", f"like.*{chr(0x00C3)}*"), ("ent", "like.*&*")]:
    offset = 0
    while True:
        r = client.get("/rest/v1/products", params={
            "select": "id,name,name_original",
            "restaurant_id": rest_filter,
            "name": postgrest,
            "limit": str(page),
            "offset": str(offset),
        })
        chunk = r.json()
        if not chunk:
            break
        rows.extend(chunk)
        offset += page
        if len(chunk) < page:
            break

# Dedupe by id
seen = set()
uniq = []
for row in rows:
    if row["id"] in seen:
        continue
    seen.add(row["id"])
    uniq.append(row)
rows = uniq

# Filter: only keep rows that actually have Ã OR HTML entity
rows = [r for r in rows if ("\u00c3" in r["name"]) or re.search(r"&[A-Za-z]+;", r["name"])]
print(f"Rows to process: {len(rows)}")

pairs = []
still_bad = 0
samples_bad = []
for row in rows:
    old = row["name"]
    new = fix_name(old)
    if new != old:
        pairs.append({"id": row["id"], "old": old, "new": new,
                      "already_fixed": row.get("name_original") is not None})
    if "\u00c3" in new or re.search(r"&[A-Za-z]+;", new):
        still_bad += 1
        if len(samples_bad) < 10:
            samples_bad.append(new)

print(f"Fixable: {len(pairs)}  Still-bad: {still_bad}")
if samples_bad:
    print("Still-bad samples:")
    for s in samples_bad:
        print(f"  {s}")

# Random sample of 15 before/after
import random
random.seed(7)
sample = random.sample(pairs, min(15, len(pairs)))
print("\n--- SAMPLES ---")
for p in sample:
    print(f"  OLD: {p['old']}")
    print(f"  NEW: {p['new']}")

# Write JSON + exit (for --dry) or apply
mode = sys.argv[1] if len(sys.argv) > 1 else "dry"
out_path = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\reports\auchan_encoding_fixes.json"
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(pairs, f, ensure_ascii=False, indent=2)
print(f"\nWrote {len(pairs)} fixes to {out_path}")

if mode != "apply":
    print("\n[dry-run] Pass 'apply' to commit PATCHes.")
    client.close()
    sys.exit(0)

# APPLY
def apply_one(item):
    pid = item["id"]
    body = {"name": item["new"]}
    if not item["already_fixed"]:
        body["name_original"] = item["old"]
    r = client.patch(f"/rest/v1/products?id=eq.{pid}",
                     headers={**headers, "Prefer": "return=minimal"}, json=body)
    return (pid, r.status_code in (200, 204), r.status_code)

ok = err = 0
t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=20) as ex:
    for pid, good, st in ex.map(apply_one, pairs):
        if good:
            ok += 1
        else:
            err += 1
            if err < 5:
                print(f"  ERR {pid}: {st}")
print(f"\nDone in {time.time()-t0:.1f}s — OK={ok} ERR={err}")
client.close()
