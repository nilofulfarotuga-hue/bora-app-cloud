"""Look for structured offers/prices in the kimbino folheto NUXT."""
import re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
nuxt = open(f"{TMP}/kimbino_im_main_folheto_nuxt.json", encoding="utf-8").read()

# Context around every 'price' occurrence
for m in re.finditer(r'price', nuxt, flags=re.I):
    s = nuxt[max(0, m.start()-140):m.end()+160]
    print("---", s, "\n")

print("\n=== OFFER contexts ===")
for m in re.finditer(r'offer', nuxt, flags=re.I):
    s = nuxt[max(0, m.start()-80):m.end()+180]
    print("---", s[:400], "\n")
