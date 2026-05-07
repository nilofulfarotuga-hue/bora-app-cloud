"""Sessão 7E-A — cleanup das fixtures E2E. Apaga APENAS markers E2E.

Decisão arquitectural #7: cleanup escopo APENAS markers E2E. Garantia formal:
nunca toca em produção. Filtros usados:
- auth.users.email LIKE '%@boraapp.test' OU '%@driver.bora.app' (com phone E2E)
- restaurants.id LIKE 'E2E_TEST_%'
- orders.is_test_order = true (cobertura para dados gerados em 7E-B/C/D)

Uso:
    python cleanup.py            # dry-run (lista o que apagaria)
    python cleanup.py --confirm  # apaga real

Ordem de DELETE respeita foreign keys:
  1. orders WHERE is_test_order=true
  2. drivers WHERE id IN (auth.users e2e)
  3. client_wallets WHERE user_id IN (auth.users e2e)
  4. restaurants WHERE id LIKE 'E2E_TEST_%' (cascata em products via FK)
  5. auth.users com domain @boraapp.test ou phone E2E

NOTA: este cleanup NUNCA apaga produção. Dupla guarda:
- Filtros explícitos (não há fallback `.delete()` global).
- Modo default = dry-run.
"""

from __future__ import annotations

import sys

from helpers.auth import (
    TEST_DRIVER_EMAIL_DOMAIN,
    TEST_EMAIL_DOMAIN,
    TEST_RESTAURANT_PREFIX,
    admin_client,
)

E2E_DRIVER_PHONES = {"910000901", "910000902", "910000903"}


def _list_e2e_users(client) -> list[dict]:
    """Lista users com markers E2E."""
    res = client.auth.admin.list_users()
    users = res if isinstance(res, list) else getattr(res, "users", [])
    matched: list[dict] = []
    for u in users:
        email = getattr(u, "email", None) or (u.get("email") if isinstance(u, dict) else None) or ""
        uid = getattr(u, "id", None) or u.get("id")
        if email.endswith(TEST_EMAIL_DOMAIN):
            matched.append({"id": uid, "email": email, "kind": "client"})
            continue
        if email.endswith(TEST_DRIVER_EMAIL_DOMAIN):
            phone = email.split("@")[0]
            if phone in E2E_DRIVER_PHONES:
                matched.append({"id": uid, "email": email, "kind": "driver"})
    return matched


def _list_e2e_restaurants(client) -> list[dict]:
    res = client.table("restaurants").select("id, name").like("id", f"{TEST_RESTAURANT_PREFIX}%").execute()
    return res.data or []


def _list_e2e_orders(client) -> list[dict]:
    res = client.table("orders").select("id, status").eq("is_test_order", True).execute()
    return res.data or []


def main() -> int:
    confirm = "--confirm" in sys.argv
    client = admin_client()

    print("Bora E2E cleanup — markers E2E only (nunca toca produção)")
    print(f"Modo: {'APAGAR REAL' if confirm else 'DRY-RUN (sem mutações)'}\n")

    e2e_users = _list_e2e_users(client)
    e2e_restaurants = _list_e2e_restaurants(client)
    e2e_orders = _list_e2e_orders(client)

    print(f"orders is_test_order=true ........ {len(e2e_orders)}")
    print(f"restaurants E2E_TEST_*  .......... {len(e2e_restaurants)}")
    print(f"auth.users E2E (clients+drivers) . {len(e2e_users)}")

    if not confirm:
        print("\n(dry-run — re-correr com --confirm para apagar)")
        return 0

    # 1. Orders primeiro (FKs em ledger_entries, wallet_transactions etc.).
    if e2e_orders:
        client.table("orders").delete().eq("is_test_order", True).execute()
        print(f"✓ apagados {len(e2e_orders)} orders")

    # 2/3. drivers + client_wallets (FK auth.users) — cascata via auth.users delete
    #      mas explicito para clareza.
    user_ids = [u["id"] for u in e2e_users]
    if user_ids:
        client.table("drivers").delete().in_("id", user_ids).execute()
        client.table("client_wallets").delete().in_("user_id", user_ids).execute()
        print(f"✓ apagadas linhas drivers/client_wallets para {len(user_ids)} users")

    # 4. restaurants (cascata em products via FK).
    if e2e_restaurants:
        client.table("restaurants").delete().like("id", f"{TEST_RESTAURANT_PREFIX}%").execute()
        print(f"✓ apagados {len(e2e_restaurants)} restaurants (+ products via cascade)")

    # 5. auth.users — admin.delete_user(uid).
    for u in e2e_users:
        try:
            client.auth.admin.delete_user(u["id"])
        except Exception as e:
            print(f"  ⚠ falhou delete user {u['email']}: {e}")
    print(f"✓ apagados {len(e2e_users)} auth.users")

    print("\n✓ cleanup completo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
