"""Dig into kimbino folheto NUXT for actual page URLs / PDF asset URL."""
import json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
TMP = r"c:/Users/danil/Desktop/projetosflutter/bora_app/.claude/.ai/tmp"
nuxt = open(f"{TMP}/kimbino_im_main_folheto_nuxt.json", encoding="utf-8").read()

print(f"NUXT len: {len(nuxt)}")

# All URLs within NUXT
urls = sorted(set(re.findall(r'https?:\\?\/\\?\/[^"\\,\s<>]+', nuxt)))
# filter to cdn / cloudfront / kimbicdns
cdn_urls = [u for u in urls if any(h in u for h in ["cloudfront", "kimbicdns", "intermarche", ".pdf", "thumbor"])]
print(f"\nCDN-like URLs ({len(cdn_urls)}):")
for u in cdn_urls[:25]: print(" ", u[:160])

# PDF ids (kimbino uses {hash}.pdf format)
pdf_hashes = sorted(set(re.findall(r'[a-f0-9]{40,64}\.pdf', nuxt)))
print(f"\nPDF hashes ({len(pdf_hashes)}):")
for h in pdf_hashes[:20]: print(" ", h)

# thumbor-l pages (folheto images)
thumbor = sorted(set(re.findall(r'eu\.kimbicdns\.com/thumbor-l/[^"\\]{20,200}', nuxt)))
print(f"\nThumbor image URLs ({len(thumbor)}):")
for u in thumbor[:10]: print(" ", u[:200])

# Look for "pdf" or "file" keys/values
for k in ['"pdf"', '"file"', '"url"', '"fileUrl"', '"download"', '"source"', '"pages"', '"page"', '"images"']:
    cnt = nuxt.count(k)
    if cnt: print(f"  key {k}: {cnt}")

# Look for date strings + name+price patterns
# Any product-like entries
price_matches = re.findall(r'"price"?\s*:\s*\d+\.?\d*', nuxt)
print(f"\n'price' field mentions: {len(price_matches)}")
product_matches = re.findall(r'"name"\s*:\s*"([^"]{5,80})"', nuxt)
print(f"'name' field samples (first 15):")
for n in product_matches[:15]: print(" ", n)

# any "offer" / "product" object shape
print("\nscanning for offer/product blocks:")
for pat in [r'"discount"', r'"offer', r'"originalPrice"', r'"discountPrice"', r'"image"']:
    cnt = nuxt.count(pat)
    if cnt: print(f"  {pat}: {cnt}")
