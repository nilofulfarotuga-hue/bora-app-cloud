"""Altera UMA chave de platform_settings. Dry-run por defeito; --commit aplica.

Dry-run: old→new + SQL + chaves dependentes. --commit: UPDATE + admin_audit_log +
nota ADR em .claude/.ai/knowledge/decisions/{data}-update-setting-{key}.md.
Chaves blindadas exigem --i-know-what-im-doing.

Uso:
  python update_setting.py --key reservation_prepayment_cents --value 400 --reason "..."           # dry
  python update_setting.py --key reservation_prepayment_cents --value 400 --reason "..." --commit
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

from _shared import Ctx, log, audit_log, admin_identity, is_blindada, REPO_ROOT
import show_setting


def _sql(key: str, value_json: str, admin_id: str) -> str:
    v = value_json.replace("'", "''")
    return (f"UPDATE platform_settings SET value = '{v}'::jsonb, updated_at = now(), "
            f"updated_by = '{admin_id or '<BORA_ADMIN_USER_ID>'}' WHERE key = '{key}';")


def _write_decision(key: str, old, new, reason: str, admin_email: str) -> Path:
    today = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    ddir = REPO_ROOT / ".claude" / ".ai" / "knowledge" / "decisions"
    ddir.mkdir(parents=True, exist_ok=True)
    path = ddir / f"{today}-update-setting-{key}.md"
    path.write_text(
        f"# {today} — platform_setting `{key}` alterado\n\n"
        f"- **Chave:** `{key}`\n- **Antes:** `{old}`\n- **Depois:** `{new}`\n"
        f"- **Por:** {admin_email or '(BORA_ADMIN_EMAIL não definido)'}\n"
        f"- **Porquê:** {reason}\n\n"
        f"> Alteração runtime via skill `update-platform-setting`. Registada em `admin_audit_log`.\n",
        encoding="utf-8")
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", required=True)
    ap.add_argument("--value", required=True, help="JSON: 400 / 0.15 / true / '\"texto\"'")
    ap.add_argument("--reason")
    ap.add_argument("--i-know-what-im-doing", dest="iknow", action="store_true")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    admin_id, admin_email = admin_identity()

    try:
        new_val = json.loads(args.value)
    except json.JSONDecodeError:
        log(f"--value não é JSON válido: {args.value} (ex.: 400, 0.15, true, '\"texto\"')", "ERROR")
        return 2

    if is_blindada(args.key) and not args.iknow:
        log(f"🔒 '{args.key}' é BLINDADA (contém fórmula sagrada). Reexecuta com "
            "--i-know-what-im-doing se tens a certeza.", "ERROR")
        return 1

    cur = show_setting.fetch(ctx, args.key)
    if not cur:
        log(f"Chave '{args.key}' não existe em platform_settings.", "ERROR")
        return 1
    old_val = cur["value"]
    if old_val == new_val:
        log(f"Valor já é {new_val}. Nada a fazer (idempotente).")
        return 0

    value_json = json.dumps(new_val, ensure_ascii=False)
    log(f"{args.key}: {old_val} → {new_val}")
    log("SQL: " + _sql(args.key, value_json, admin_id))
    rel = show_setting.related(ctx, args.key, cur.get("category"))
    if rel:
        log(f"Chaves dependentes/relacionadas ({len(rel)}): " + ", ".join(x["key"] for x in rel[:15]))
    if is_blindada(args.key):
        log("🔒 BLINDADA — confirma o impacto em pricing/dispatch/fees/comissões.", "WARN")

    if not args.commit:
        log("[DRY-RUN] nada escrito. Use --commit (com --reason) para aplicar.")
        return 0

    if not args.reason:
        log("--reason é obrigatório em --commit (vai p/ nota ADR + auditoria).", "ERROR")
        return 2
    if not admin_id:
        log("BORA_ADMIN_USER_ID em falta — necessário p/ auditoria.", "ERROR")
        return 1

    resp = ctx.rest("PATCH", f"platform_settings?key=eq.{args.key}", ctx.service_role_key,
                    {"value": new_val, "updated_by": admin_id})
    if resp.status_code >= 300:
        log(f"UPDATE falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
        return 1
    note = _write_decision(args.key, old_val, new_val, args.reason, admin_email)
    audit_log(ctx, "platform_setting_updated", "platform_setting", args.key,
              {"old": old_val, "new": new_val, "reason": args.reason, "blindada": is_blindada(args.key)})
    log(f"✅ {args.key} = {new_val}. Auditado. Nota ADR: {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
