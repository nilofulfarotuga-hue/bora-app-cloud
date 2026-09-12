"""Força logout de um estafeta via Edge Fn admin-force-driver-logout.

Preview por defeito; --confirm executa. --force-anyway ignora pedido em curso.

Uso:
  python logout.py --driver-id <uuid> --reason "..."              # preview
  python logout.py --driver-id <uuid> --reason "..." --confirm
  python logout.py --driver-id <uuid> --reason "..." --confirm --force-anyway
"""
from __future__ import annotations

import argparse
import re
import sys

import requests

from _shared import Ctx, log, get_admin_jwt, ACTIVE_ORDER_STATUSES

UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--driver-id", required=True)
    ap.add_argument("--reason", required=True)
    ap.add_argument("--confirm", action="store_true")
    ap.add_argument("--force-anyway", action="store_true")
    args = ap.parse_args()

    if not UUID_RE.match(args.driver_id):
        log("--driver-id tem de ser UUID válido (a Edge Fn rejeita não-UUID).", "ERROR")
        return 2

    ctx = Ctx.load(commit=args.confirm)
    ctx.require_knowledge()

    r = ctx.rest("GET", f"drivers?id=eq.{args.driver_id}&select=id,name,is_online", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"driver {args.driver_id} não encontrado.", "ERROR")
        return 1
    d = rows[0]
    log(f"Estafeta: {d.get('name','?')} · is_online={d.get('is_online')}")

    # Pedido em curso?
    statuses = ",".join(ACTIVE_ORDER_STATUSES)
    ro = ctx.rest("GET", f"orders?assigned_driver_id=eq.{args.driver_id}&status=in.({statuses})&select=id,status",
                  ctx.service_role_key)
    active = ro.json() if ro.status_code < 300 else []
    if active:
        log(f"⚠️ {len(active)} pedido(s) em curso: {[o['id'] for o in active]}", "WARN")
        if args.confirm and not args.force_anyway:
            log("Bloqueado: usa --force-anyway para forçar mesmo assim.", "ERROR")
            return 1

    if not args.confirm:
        log(f"[PREVIEW] Forçaria logout de {d.get('name')} ({args.driver_id}). Motivo: {args.reason}")
        log("Use --confirm para executar.")
        return 0

    # Executar via Edge Fn (JWT de admin)
    try:
        jwt = get_admin_jwt(ctx)
    except Exception as e:  # noqa: BLE001
        log(f"Sem JWT de admin: {e}", "ERROR")
        return 1
    resp = requests.post(f"{ctx.supabase_url}/functions/v1/admin-force-driver-logout",
                         timeout=60, headers={"Authorization": f"Bearer {jwt}",
                         "apikey": ctx.anon_key, "Content-Type": "application/json"},
                         json={"driver_id": args.driver_id, "reason": args.reason})
    log(f"Edge Fn → {resp.status_code}: {resp.text[:300]}")
    if resp.status_code >= 300:
        return 1

    # Verificar is_online=false
    v = ctx.rest("GET", f"drivers?id=eq.{args.driver_id}&select=is_online,last_forced_logout_at",
                 ctx.service_role_key)
    vr = v.json()[0] if v.status_code < 300 and v.json() else {}
    ok = vr.get("is_online") is False
    log(f"{'✅' if ok else '⚠️'} is_online={vr.get('is_online')} · last_forced_logout_at={vr.get('last_forced_logout_at')}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
