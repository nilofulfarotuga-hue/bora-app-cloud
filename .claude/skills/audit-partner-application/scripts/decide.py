"""Aprova ou rejeita uma candidatura de parceiro (UPDATE direto + auditoria).

Dry-run por defeito. --commit aplica. Idempotente. NÃO liga is_online.

Uso:
  python decide.py --restaurant-id <text-id> --action approve --commit
  python decide.py --restaurant-id <text-id> --action reject --reason-code docs_invalidos --reason "..." --commit
"""
from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path

import yaml  # type: ignore

from _shared import Ctx, log, audit_log, admin_identity

REASONS_FILE = Path(__file__).resolve().parents[1] / "templates" / "rejection_reasons.yaml"


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _reason_text(code: str | None, reason: str | None) -> str:
    if reason:
        return reason
    if code and REASONS_FILE.exists():
        data = yaml.safe_load(REASONS_FILE.read_text(encoding="utf-8")) or {}
        return str(data.get("codes", {}).get(code, code))
    return code or "Sem motivo especificado."


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--restaurant-id", required=True)
    ap.add_argument("--action", required=True, choices=["approve", "reject"])
    ap.add_argument("--reason-code")
    ap.add_argument("--reason")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    admin_id, _ = admin_identity()
    if args.commit and not admin_id:
        log("BORA_ADMIN_USER_ID em falta — necessário p/ auditoria.", "ERROR")
        return 1

    r = ctx.rest("GET", f"restaurants?id=eq.{args.restaurant_id}&select=id,name,approval_status",
                 ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"restaurante {args.restaurant_id} não encontrado.", "ERROR")
        return 1
    d = rows[0]
    target = "approved" if args.action == "approve" else "rejected"
    if d.get("approval_status") == target:
        log(f"Parceiro já está '{target}'. Nada a fazer (idempotente).")
        return 0
    if args.action == "reject" and not (args.reason or args.reason_code):
        log("Rejeição exige --reason ou --reason-code.", "ERROR")
        return 2

    patch = {"approval_status": target, "approved_by": admin_id or None, "reviewed_at": _now()}
    if args.action == "approve":
        patch["approved_at"] = _now()
    else:
        patch["rejection_reason"] = _reason_text(args.reason_code, args.reason)

    if not args.commit:
        log(f"[DRY-RUN] {d.get('name')} ({d['id']}): {d.get('approval_status')} → {target}")
        log(f"[DRY-RUN] patch: {patch}")
        log("Nota: is_online NÃO é alterado (ir live é decisão separada).")
        return 0

    resp = ctx.rest("PATCH", f"restaurants?id=eq.{args.restaurant_id}", ctx.service_role_key, patch)
    if resp.status_code >= 300:
        log(f"UPDATE falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
        return 1
    audit_log(ctx, f"partner_application_{target}", "restaurant", args.restaurant_id,
              {"reason_code": args.reason_code, "reason": patch.get("rejection_reason"),
               "previous_status": d.get("approval_status")}, text_id=True)
    log(f"✅ Parceiro {d.get('name')} → {target}. Auditado. (is_online inalterado.)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
