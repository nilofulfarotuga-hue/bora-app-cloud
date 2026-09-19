"""Lista chunks de conhecimento recentes (FAQ/knowledge) do support RAG.

Uso: python list_faqs.py [--source-type faq] [--limit 30]
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-type")
    ap.add_argument("--limit", type=int, default=30)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    q = ("support_knowledge_chunks?select=id,source_type,section_title,char_count,"
         "embedding,indexed_at&order=indexed_at.desc&limit=%d" % args.limit)
    if args.source_type:
        q += f"&source_type=eq.{args.source_type}"
    r = ctx.rest("GET", q, ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log("Sem chunks.")
        return 0
    log(f"{len(rows)} chunk(s) recentes:")
    for c in rows:
        emb = "emb✅" if c.get("embedding") else "emb⌛(pendente)"
        log(f"  - [{c.get('source_type')}] {c.get('section_title','')[:60]} · {emb}")
    # contagem de pendentes (embedding NULL)
    rp = requests.get(f"{ctx.supabase_url}/rest/v1/support_knowledge_chunks?embedding=is.null&select=id",
                      timeout=30, headers={"Authorization": f"Bearer {ctx.service_role_key}",
                      "apikey": ctx.anon_key, "Prefer": "count=exact", "Range": "0-0"})
    cr = rp.headers.get("Content-Range", "")
    if "/" in cr:
        log(f"Chunks pendentes de embedding: {cr.split('/')[-1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
