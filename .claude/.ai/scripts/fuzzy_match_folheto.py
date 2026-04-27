"""Fuzzy match flyer products (32) vs BD (62). Threshold >=0.85 on normalized names.
Outputs match table + proposed UPDATE SQL, but does NOT execute anything.
"""
import json, os, re, sys, unicodedata
from difflib import SequenceMatcher
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"

flyer = json.load(open(f"{TMP}/lidl_folheto_products_raw.json", encoding="utf-8"))
bd = json.load(open(f"{TMP}/bd_lidl_snapshot.json", encoding="utf-8"))

def normalize(s):
    if not s: return ""
    s = unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode()
    s = s.lower()
    # remove punctuation and common noise words
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    # noise words
    for w in ["xxl", "formato familiar", "emb", "cada", "unid", "kg", "g ",
              "emb.", "cada emb.", "cada unid.", "vendido ao kg"]:
        s = s.replace(w, " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s

THRESHOLD = 0.85

# Build index of BD by normalized name
bd_index = [(b, normalize(b["name"])) for b in bd]

matches = []
unmatched = []
for fp in flyer:
    fn = normalize(fp["name"])
    best_score = 0.0
    best = None
    for b, bn in bd_index:
        # try both direct ratio and token-set match
        r1 = SequenceMatcher(None, fn, bn).ratio()
        # also try containment check
        contain_bonus = 0.0
        if bn and bn in fn: contain_bonus = 0.05
        elif fn and fn in bn: contain_bonus = 0.05
        score = min(1.0, r1 + contain_bonus)
        if score > best_score:
            best_score = score; best = b
    row = {
        "flyer_name": fp["name"],
        "flyer_brand": fp.get("brand"),
        "flyer_page": fp.get("page"),
        "flyer_price_normal": fp["price_normal"],
        "flyer_price_promo": fp["price_promo"],
        "flyer_discount_pct": fp["discount_pct"],
        "score": round(best_score, 3),
        "bd_id": best["id"] if best else None,
        "bd_name": best["name"] if best else None,
        "bd_brand": best["brand"] if best else None,
        "bd_price_normal": float(best["price"]) if best else None,
    }
    if best_score >= THRESHOLD:
        matches.append(row)
    else:
        unmatched.append(row)

# Dedupe matches: same bd_id may attract 2 flyer rows — keep highest score
best_by_id = {}
for m in matches:
    k = m["bd_id"]
    if k not in best_by_id or m["score"] > best_by_id[k]["score"]:
        best_by_id[k] = m
matches_dedup = list(best_by_id.values())
matches_dedup.sort(key=lambda x: -x["score"])

# Duplicates (flyer rows that collapsed to same bd_id)
collisions = {}
for m in matches:
    k = m["bd_id"]
    collisions.setdefault(k, []).append(m)
collisions = {k: v for k, v in collisions.items() if len(v) > 1}

# Sanity check: where flyer price_promo > bd_price_normal → suspicious
sus = []
for m in matches_dedup:
    if m["bd_price_normal"] and m["flyer_price_promo"] > m["bd_price_normal"]:
        sus.append({**m, "reason": "flyer promo > BD normal — inverse discount?"})

out = {
    "summary": {
        "flyer_total": len(flyer),
        "bd_total": len(bd),
        "threshold": THRESHOLD,
        "match_count_dedup": len(matches_dedup),
        "unmatched_flyer": len(unmatched),
        "collisions_count": len(collisions),
        "suspicious_count": len(sus),
    },
    "matches": matches_dedup,
    "unmatched_flyer": unmatched,
    "collisions": collisions,
    "suspicious": sus,
}

with open(f"{TMP}/lidl_folheto_matches.json", "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)

print("=== SUMMARY ===")
print(json.dumps(out["summary"], indent=2))
print(f"\n=== MATCHES ({len(matches_dedup)}) ===")
print(f"{'score':<6} {'bd_name':<42} | flyer_name:<42 | €bd -> €promo (-%)")
for m in matches_dedup:
    bn = (m['bd_name'] or '')[:40]
    fn = (m['flyer_name'] or '')[:40]
    print(f"{m['score']:<6} {bn:<42} | {fn:<42} | {m['bd_price_normal']} -> {m['flyer_price_promo']} (-{m['flyer_discount_pct']}%)")

print(f"\n=== COLLISIONS ({len(collisions)} bd_ids with multiple flyer matches) ===")
for k, v in collisions.items():
    print(f" {k}: {len(v)} flyer rows")
    for m in v:
        print(f"   score={m['score']}  flyer={m['flyer_name']!r}")

print(f"\n=== UNMATCHED flyer rows ({len(unmatched)}) ===")
for u in unmatched[:20]:
    print(f" best={u['score']:.2f}  flyer={u['flyer_name']!r}  ~ bd={u['bd_name']!r}")

print(f"\n=== SUSPICIOUS ({len(sus)}) ===")
for s in sus:
    print(f" {s['bd_name']}: BD={s['bd_price_normal']} promo={s['flyer_price_promo']}")

print(f"\nSaved: {TMP}/lidl_folheto_matches.json")
