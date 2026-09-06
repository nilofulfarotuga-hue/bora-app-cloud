"""Bane cliente / estafeta / parceiro. Dry-run por defeito; --commit aplica.

Mecanismo por tipo (ver _shared.ENTITY_MAP). Bloqueia se houver pedidos em curso.
Idempotente.

Uso:
  python ban.py --type driver --id <uuid> --reason-code misconduct --reason "..." [--until ISO] --commit
  python ban.py --type partner --id <text-id> --reason "..." --commit
  python ban.py --type client --id <uuid> --reason "..." [--until ISO] --commit
"""
from __future__ import annotations

import argparse
import datetime as dt
import sys

import requests

from _shared import (Ctx, log, audit_log, admin_identity, get_admin_jwt,
                     ENTITY_MAP, DRIVER_BAN_REASON_CODES, active_orders)


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _ban_duration(until: str | None) -> str:
    """Converte --until ISO em ban_duration GoTrue ('Nh'); permanente ~100 anos."""
    if not until:
        return "876000h"
    target = dt.datetime.fromisoformat(until.replace("Z", "+00:00"))
    hours = max(1, int((target - dt.datetime.now(dt.timezone.utc)).total_seconds() // 3600))
    return f"{hours}h"


def _auth_set_ban(ctx: Ctx, user_id: str, duration: str) -> bool:
    r = requests.put(
        f"{ctx.supabase_url}/auth/v1/admin/users/{user_id}", timeout=30,
        headers={"Authorization": f"Bearer {ctx.service_role_key}",
                 "apikey": ctx.service_role_key, "Content-Type": "application/json"},
        json={"ban_duration": duration})
    if r.status_code >= 300:
        log(f"Auth ban falhou: {r.status_code} {r.text[:160]}", "ERROR")
    return r.status_code < 300


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", required=True, choices=["client", "driver", "partner"])
    ap.add_argument("--id", required=True)
    ap.add_argument("--reason-code")
    ap.add_argument("--reason", required=True)
    ap.add_argument("--until", help="ISO datetime; ausente = permanente")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    admin_id, _ = admin_identity()
    if args.commit and not admin_id:
        log("BORA_ADMIN_USER_ID em falta — necessário p/ auditoria.", "ERROR")
        return 1

    cfg = ENTITY_MAP[args.type]
    if args.type == "driver" and args.reason_code and args.reason_code not in DRIVER_BAN_REASON_CODES:
        log(f"--reason-code inválido p/ driver. Usar: {DRIVER_BAN_REASON_CODES}", "ERROR")
        return 2

    # Existência
    r = ctx.rest("GET", f"{cfg['table']}?{cfg['id_col']}=eq.{args.id}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"{args.type} {args.id} não encontrado.", "ERROR")
        return 1
    ent = rows[0]

    # Idempotência
    if args.type == "driver" and ent.get("is_banned"):
        log(f"Estafeta já banido (até {ent.get('banned_until') or 'permanente'}). Nada a fazer.")
        return 0
    if args.type == "partner" and ent.get("is_active_admin") is False:
        log("Parceiro já desativado (is_active_admin=false). Nada a fazer.")
        return 0

    # Bloqueio por pedidos em curso
    blocking = active_orders(ctx, args.type, args.id)
    if blocking:
        log(f"❌ {len(blocking)} pedido(s) em curso — ban BLOQUEADO:", "ERROR")
        for o in blocking:
            log(f"   - {o['id']} [{o['status']}]", "ERROR")
        return 1

    details = {"reason": args.reason, "reason_code": args.reason_code,
               "until": args.until, "mechanism": cfg["table"]}

    if not args.commit:
        log(f"[DRY-RUN] BAN {args.type} {args.id} — {details}")
        if args.type == "client":
            log(f"[DRY-RUN] Auth ban_duration = {_ban_duration(args.until)}")
        elif args.type == "driver":
            log("[DRY-RUN] UPDATE drivers ban cols + is_online=false + force-logout")
        else:
            log("[DRY-RUN] UPDATE restaurants is_active_admin=false")
        log("Use --commit para aplicar.")
        return 0

    # ── COMMIT ──
    if args.type == "driver":
        patch = {"is_banned": True, "banned_at": _now(), "banned_by": admin_id,
                 "banned_until": args.until, "ban_reason": args.reason,
                 "ban_reason_code": args.reason_code, "is_online": False}
        resp = ctx.rest("PATCH", f"drivers?id=eq.{args.id}", ctx.service_role_key, patch)
        if resp.status_code >= 300:
            log(f"UPDATE drivers falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
            return 1
        # force-logout (best-effort; exige JWT de admin)
        try:
            jwt = get_admin_jwt(ctx)
            fr = requests.post(f"{ctx.supabase_url}/functions/v1/admin-force-driver-logout",
                               timeout=60, headers={"Authorization": f"Bearer {jwt}",
                               "apikey": ctx.anon_key, "Content-Type": "application/json"},
                               json={"driver_id": args.id, "reason": f"ban: {args.reason}"})
            log(f"force-logout: {fr.status_code}")
        except Exception as e:  # noqa: BLE001
            log(f"force-logout falhou (não fatal): {e}", "WARN")
    elif args.type == "partner":
        resp = ctx.rest("PATCH", f"restaurants?id=eq.{args.id}", ctx.service_role_key,
                        {"is_active_admin": False})
        if resp.status_code >= 300:
            log(f"UPDATE restaurants falhou: {resp.status_code} {resp.text[:160]}", "ERROR")
            return 1
    else:  # client
        if not _auth_set_ban(ctx, args.id, _ban_duration(args.until)):
            return 1

    audit_log(ctx, "entity_banned", args.type, args.id, details, text_id=cfg["text_id"])
    log(f"✅ {args.type} {args.id} banido. Auditado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
