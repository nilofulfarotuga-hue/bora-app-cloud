"""Adiciona uma FAQ ao RAG (support_knowledge_chunks) + reindex (embedding).

Dry-run por defeito. --commit insere o chunk e chama reindex-knowledge.
Bloqueia respostas com promessas $ / instruções de refund/cancelamento (escalam a humano).

Uso:
  python add_faq.py --question "..." --answer "..." --category orders            # dry-run
  python add_faq.py --question "..." --answer "..." --category orders --commit
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import re
import sys

import requests

from _shared import Ctx, log, audit_log, get_admin_jwt

# Termos que NÃO podem aparecer numa resposta de FAQ (escalam a humano).
SENSITIVE = [
    r"reembols", r"estorno", r"devolv[ée]", r"cancelar o pedido", r"cancelamento do pedido",
    r"garant\w*\s+(o|a)?\s*(reembolso|devolu)", r"\bvale\b.*€", r"compensa[çc]",
]
SENSITIVE_RE = re.compile("|".join(SENSITIVE), re.I)


def is_sensitive(answer: str) -> list[str]:
    return SENSITIVE_RE.findall(answer or "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--question", required=True)
    ap.add_argument("--answer", required=True)
    ap.add_argument("--category", default="faq")
    ap.add_argument("--lang", default="pt-PT")
    ap.add_argument("--source-type", default="knowledge", help="enum válido em chunks (default knowledge)")
    ap.add_argument("--force-sensitive", action="store_true")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    hits = is_sensitive(args.answer)
    if hits and not args.force_sensitive:
        log(f"❌ Resposta contém tema sensível (escala a humano, não vai p/ FAQ): {set(hits)}", "ERROR")
        log("   Refund/cancelamento/promessas $ devem usar uma skill 'escalate', não FAQ.", "ERROR")
        log("   (Override consciente: --force-sensitive — desaconselhado.)", "ERROR")
        return 1
    if hits:
        log(f"⚠️ Tema sensível forçado: {set(hits)} — confirma que é informativo, não promessa.", "WARN")

    chunk_text = f"P: {args.question.strip()}\nR: {args.answer.strip()}"
    content_hash = hashlib.sha256(chunk_text.encode("utf-8")).hexdigest()
    section = f"FAQ [{args.category}] {args.question.strip()[:70]}"

    # dedup por content_hash
    dup = ctx.rest("GET", f"support_knowledge_chunks?content_hash=eq.{content_hash}&select=id",
                   ctx.service_role_key)
    if dup.status_code < 300 and dup.json():
        log("FAQ idêntica já existe (content_hash). Nada a fazer (idempotente).")
        return 0

    row = {"source_file": "faq:manual", "source_type": args.source_type,
           "chunk_index": 0, "section_title": section, "chunk_text": chunk_text,
           "char_count": len(chunk_text), "content_hash": content_hash,
           "indexed_at": dt.datetime.now(dt.timezone.utc).isoformat()}

    if not args.commit:
        log("[DRY-RUN] chunk a inserir:")
        log(f"  section: {section}")
        log(f"  texto  : {chunk_text[:160]}")
        log(f"  lang={args.lang} source_type={args.source_type} hash={content_hash[:12]}")
        log("Use --commit para gravar + reindex.")
        return 0

    resp = ctx.rest("POST", "support_knowledge_chunks", ctx.service_role_key, [row])
    if resp.status_code >= 300:
        log(f"INSERT chunk falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
        return 1
    log("✅ FAQ inserida em support_knowledge_chunks (embedding pendente).")

    # reindex (best-effort, admin-only)
    try:
        jwt = get_admin_jwt(ctx)
        rr = requests.post(f"{ctx.supabase_url}/functions/v1/reindex-knowledge", timeout=120,
                           headers={"Authorization": f"Bearer {jwt}", "apikey": ctx.anon_key,
                                    "Content-Type": "application/json"},
                           json={"mode": "pending", "max_chunks": 10})
        log(f"reindex-knowledge → {rr.status_code}: {rr.text[:160]}")
        if rr.status_code >= 300:
            log("⚠️ Embedding não gerado — correr reindex-knowledge depois (admin + GEMINI_API_KEY).", "WARN")
    except Exception as e:  # noqa: BLE001
        log(f"⚠️ Sem reindex ({e}). FAQ gravada mas PENDENTE de embedding.", "WARN")

    audit_log(ctx, "support_faq_added", "support_knowledge_chunk", content_hash,
              {"category": args.category, "lang": args.lang, "section": section,
               "sensitive_forced": bool(hits)})
    log("Auditado. (lógica do agente intocada — só conhecimento)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
