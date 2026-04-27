"""Find the correct kimbino slug for Intermarche Portugal."""
import json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"

t = open(f"{TMP}/kimbino_im_nuxt.json", encoding="utf-8").read()

# Look for URLs mentioning intermarche
urls = sorted(set(re.findall(r'[\/a-z0-9\-]{5,80}(?:intermarche|intermarch\u00e9)[\/a-z0-9\-]{0,80}', t, flags=re.I)))
print("URLS with intermarche:")
for u in urls[:30]: print(" ", u)

# Context around "Intermarché" or "intermarche"
print("\nContext samples:")
for m in list(re.finditer(r'intermarch[eé]', t, flags=re.I))[:10]:
    s = t[max(0, m.start()-60):m.end()+120]
    print(" ---", s)

# slug-like tokens
slugs = sorted(set(re.findall(r'"([a-z0-9\-]*intermarche[a-z0-9\-]*)"', t, flags=re.I)))
print("\nPossible slugs:")
for s in slugs: print(" ", s)
