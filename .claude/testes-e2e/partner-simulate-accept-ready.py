# -*- coding: utf-8 -*-
"""
Simula, SERVER-SIDE, exactamente o que o parceiro faria no painel (botões
"Aceitar" e "Pedido pronto") para um pedido de restaurante PARCEIRO — usado
pelo runner E2E quando não há um 3º telemóvel/sessão de parceiro no rig
(README: papel de PARCEIRO é sempre no admin/web, nunca telemóvel).

Replica ao byte o que lib/stores/order_store.dart faz (nada de RPC — o
Flutter também só faz UPDATE directo + invoke da Edge Function):

  restaurantAcceptOrder(order):
    if order.status == 'created': UPDATE orders SET status='preparing'

  restaurantMarkReady(order):
    if order.status == 'preparing':
      UPDATE orders SET status='callingDriver'
      invoke Edge Function 'dispatch-engine' com body {orderId}
      (dispatch-engine é --no-verify-jwt; usa a própria SERVICE_ROLE_KEY —
      chamamos com apikey/Authorization = service role, igual ao app)

NÃO mexe em pricing/dispatch/Stripe/tokens — só o campo `status` do pedido
(exactamente as 2 transições que o botão do parceiro dispara) + invocação da
função de dispatch já deployada (zona vermelha só na EDIÇÃO do motor, não na
chamada normal que qualquer pedido dispara).

Uso: python partner-simulate-accept-ready.py --order-id <uuid>
Saída: exit 0 em sucesso (ou no-op seguro se o pedido não for
restaurante-parceiro); exit 1 em erro real.
"""
import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent


def load_env() -> dict:
    env = {}
    for f in (BASE / ".env", BASE.parent.parent / "backend" / ".env"):
        if f.exists():
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*[\"']?([^\"'#]+)", line)
                if m:
                    env.setdefault(m.group(1), m.group(2).strip())
    return env


def http(method: str, url: str, key: str, body=None, extra_headers=None):
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if extra_headers:
        headers.update(extra_headers)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--order-id", required=True)
    args = ap.parse_args()

    env = load_env()
    url = env.get("SUPABASE_URL")
    key = env.get("SUPABASE_SERVICE_ROLE_KEY")
    if not (url and key):
        print("ERRO: SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY em falta (.env)")
        return 1

    order_id = args.order_id
    if not order_id:
        print("ERRO: --order-id vazio (poll_db não encontrou o pedido a tempo?)")
        return 1

    q = (f"{url}/rest/v1/orders?id=eq.{urllib.parse.quote(order_id)}"
         f"&select=id,status,is_partner_store,service_type,payment_method")
    status, body = http("GET", q, key)
    if status != 200:
        print(f"ERRO: GET pedido falhou HTTP {status}: {body[:300]}")
        return 1
    rows = json.loads(body)
    if not rows:
        print(f"ERRO: pedido {order_id} não encontrado")
        return 1
    order = rows[0]
    print(f"pedido {order_id}: status={order['status']} is_partner_store={order.get('is_partner_store')} "
          f"service_type={order.get('service_type')}")

    if not order.get("is_partner_store") or order.get("service_type") != "restaurant":
        print("AVISO: pedido não é restaurante-parceiro — nada a simular (no-op seguro)")
        return 0

    # ── restaurantAcceptOrder: created → preparing ──────────────────────
    if order["status"] == "created":
        qu = f"{url}/rest/v1/orders?id=eq.{urllib.parse.quote(order_id)}&status=eq.created"
        status, body = http("PATCH", qu, key, body={"status": "preparing"},
                            extra_headers={"Prefer": "return=representation"})
        print(f"restaurantAcceptOrder (created->preparing): HTTP {status}")
        if status not in (200, 204):
            print(f"ERRO: {body[:400]}")
            return 1
        order["status"] = "preparing"
        time.sleep(1.5)
    else:
        print(f"pedido já não está em 'created' (status={order['status']}) — salta accept")

    # ── restaurantMarkReady: preparing → callingDriver + invoke dispatch ─
    if order["status"] == "preparing":
        qu = f"{url}/rest/v1/orders?id=eq.{urllib.parse.quote(order_id)}&status=eq.preparing"
        status, body = http("PATCH", qu, key, body={"status": "callingDriver"},
                            extra_headers={"Prefer": "return=representation"})
        print(f"restaurantMarkReady (preparing->callingDriver): HTTP {status}")
        if status not in (200, 204):
            print(f"ERRO: {body[:400]}")
            return 1

        fn_url = f"{url}/functions/v1/dispatch-engine"
        status, body = http("POST", fn_url, key, body={"orderId": order_id})
        print(f"dispatch-engine invoke: HTTP {status} {body[:300]!r}")
        # não-fatal: o trigger DB (dispatch_trigger_pgcron) é rede de segurança
        # se a invocação directa falhar por qualquer motivo transitório.
    else:
        print(f"pedido não está em 'preparing' (status={order['status']}) — salta markReady")

    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
