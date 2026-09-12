"""Aprova ou rejeita uma candidatura de estafeta (UPDATE direto + auditoria).

Dry-run por defeito (mostra a mudança). --commit aplica.
Idempotente: se já estiver no estado pretendido → mensagem informativa, exit 0.

Uso:
  python decide.py --driver-id <uuid> --action approve --commit
  python decide.py --driver-id <uuid> --action reject --reason-code docs_invalidos --reason "CC ilegível" --commit
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


def _load_reason_text(code: str | None, reason: str | None) -> str:
    if reason:
        return reason
    if code and REASONS_FILE.exists():
        data = yaml.safe_load(REASONS_FILE.read_text(encoding="utf-8")) or {}
        return str(data.get("codes", {}).get(code, code))
    return code or "Sem motivo especificado."


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--driver-id", required=True)
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

    r = ctx.rest("GET", f"drivers?id=eq.{args.driver_id}&select=id,name,approval_status",
                 ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"driver {args.driver_id} não encontrado.", "ERROR")
        return 1
    d = rows[0]
    target = "approved" if args.action == "approve" else "rejected"
    if d.get("approval_status") == target:
        log(f"Estafeta já está '{target}'. Nada a fazer (idempotente).")
        return 0

    if args.action == "reject" and not (args.reason or args.reason_code):
        log("Rejeição exige --reason ou --reason-code.", "ERROR")
        return 2

    patch = {"approval_status": target, "approved_by": admin_id or None, "reviewed_at": _now()}
    if args.action == "approve":
        patch["approved_at"] = _now()
    else:
        patch["rejection_reason"] = _load_reason_text(args.reason_code, args.reason)

    if not args.commit:
        log(f"[DRY-RUN] {d.get('name')} ({d['id']}): {d.get('approval_status')} → {target}")
        log(f"[DRY-RUN] patch: {patch}")
        log("Use --commit para aplicar.")
        return 0

    resp = ctx.rest("PATCH", f"drivers?id=eq.{args.driver_id}", ctx.service_role_key, patch)
    if resp.status_code >= 300:
        log(f"UPDATE falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
        return 1
    audit_log(ctx, f"driver_application_{target}", "driver", args.driver_id,
              {"reason_code": args.reason_code, "reason": patch.get("rejection_reason"),
               "previous_status": d.get("approval_status")})
    log(f"✅ Estafeta {d.get('name')} → {target}. Auditado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
