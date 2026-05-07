"""Sessão 7E-A — seed de fixtures 3+3+3 (idempotente).

Cria/actualiza:
- 3 clientes (auth.users + client_wallets) com carteiras variadas
- 3 estafetas (auth.users + drivers) com states variados
- 3 restaurantes (prefixo E2E_TEST_*) — restaurant + non-partner + market

Re-corre sem duplicar (UPSERT por email/phone/id).

Uso:
    cd scripts/e2e
    python -m venv .venv && source .venv/bin/activate  # (Windows: .venv\\Scripts\\activate)
    pip install -r requirements.txt
    python seed.py
"""

from __future__ import annotations

from typing import Any

from helpers.auth import (
    TEST_DRIVER_EMAIL_DOMAIN,
    TEST_EMAIL_DOMAIN,
    TEST_PASSWORD,
    TEST_RESTAURANT_PREFIX,
    admin_client,
)

# ──────────────────────────────────────────────────────────────────────────
# Specs declarativas (single source).
# ──────────────────────────────────────────────────────────────────────────
CLIENT_SPECS: list[dict[str, Any]] = [
    {"slug": "client_a", "email": f"e2e_client_a{TEST_EMAIL_DOMAIN}", "wallet_eur": 100.00, "promo_eur": 0.00},
    {"slug": "client_b", "email": f"e2e_client_b{TEST_EMAIL_DOMAIN}", "wallet_eur": 0.00,   "promo_eur": 0.00},
    {"slug": "client_c", "email": f"e2e_client_c{TEST_EMAIL_DOMAIN}", "wallet_eur": 20.00,  "promo_eur": 5.00},
]

DRIVER_SPECS: list[dict[str, Any]] = [
    {"slug": "driver_a", "phone": "910000901", "name": "E2E Driver A", "vehicle": "car",  "online": True,  "lat": 40.5404, "lng": -7.2683},
    {"slug": "driver_b", "phone": "910000902", "name": "E2E Driver B", "vehicle": "bike", "online": False, "lat": 40.5404, "lng": -7.2683},
    {"slug": "driver_c", "phone": "910000903", "name": "E2E Driver C", "vehicle": "car",  "online": True,  "lat": 40.5404, "lng": -7.2683},
]

RESTAURANT_SPECS: list[dict[str, Any]] = [
    {"id": f"{TEST_RESTAURANT_PREFIX}PartnerRest",    "name": f"{TEST_RESTAURANT_PREFIX}PartnerRest",    "category": "restaurant",   "is_partner": True,  "lat": 40.5404, "lng": -7.2683},
    {"id": f"{TEST_RESTAURANT_PREFIX}NonPartnerRest", "name": f"{TEST_RESTAURANT_PREFIX}NonPartnerRest", "category": "restaurant",   "is_partner": False, "lat": 40.5404, "lng": -7.2683},
    {"id": f"{TEST_RESTAURANT_PREFIX}Market",         "name": f"{TEST_RESTAURANT_PREFIX}Market",         "category": "supermarket",  "is_partner": True,  "lat": 40.5404, "lng": -7.2683},
]


# ──────────────────────────────────────────────────────────────────────────
# Auth users — idempotência via auth.admin.list_users + email lookup.
# ──────────────────────────────────────────────────────────────────────────


def _find_user_by_email(client, email: str) -> dict | None:
    """Procura um user em auth.users por email. Devolve None se não existir."""
    # supabase-py 2.x expõe list_users com paginação simples; para 3+3 fixtures
    # uma chamada chega.
    res = client.auth.admin.list_users()
    users = res if isinstance(res, list) else getattr(res, "users", [])
    for u in users:
        u_email = getattr(u, "email", None) or (u.get("email") if isinstance(u, dict) else None)
        if u_email == email:
            return u
    return None


def _ensure_auth_user(client, email: str, password: str, role: str, name: str) -> str:
    """Cria ou recupera um user e devolve o seu UUID."""
    existing = _find_user_by_email(client, email)
    if existing is not None:
        uid = getattr(existing, "id", None) or existing.get("id")
        print(f"  [auth] ✓ existe: {email} ({uid})")
        return uid

    res = client.auth.admin.create_user(
        {
            "email": email,
            "password": password,
            "email_confirm": True,
            "user_metadata": {"bora_role": role, "name": name, "is_test": True},
        }
    )
    user = getattr(res, "user", None) or res.get("user")
    uid = getattr(user, "id", None) or user.get("id")
    print(f"  [auth] + criado: {email} ({uid})")
    return uid


# ──────────────────────────────────────────────────────────────────────────
# Seed: clientes
# ──────────────────────────────────────────────────────────────────────────


def seed_clients(client) -> list[str]:
    """Cria 3 clientes + carteiras. Devolve lista de UUIDs criados."""
    print("\n=== seed clientes ===")
    user_ids: list[str] = []
    for spec in CLIENT_SPECS:
        uid = _ensure_auth_user(client, spec["email"], TEST_PASSWORD, "client", spec["slug"])
        user_ids.append(uid)

        # client_wallets — UPSERT (PK = user_id)
        balance_cents = int(round((spec["wallet_eur"] + spec["promo_eur"]) * 100))
        client.table("client_wallets").upsert(
            {"user_id": uid, "free_balance_cents": balance_cents},
            on_conflict="user_id",
        ).execute()
        print(f"  [wallet] {spec['slug']}: {balance_cents}c (€{spec['wallet_eur']:.2f} + €{spec['promo_eur']:.2f} promo)")

    return user_ids


# ──────────────────────────────────────────────────────────────────────────
# Seed: estafetas
# ──────────────────────────────────────────────────────────────────────────


def seed_drivers(client) -> list[str]:
    """Cria 3 estafetas (auth.users + drivers). Devolve lista de UUIDs."""
    print("\n=== seed estafetas ===")
    user_ids: list[str] = []
    for spec in DRIVER_SPECS:
        # Email synthetic conforme padrão prod: {phone}@driver.bora.app
        email = f"{spec['phone']}{TEST_DRIVER_EMAIL_DOMAIN}"
        uid = _ensure_auth_user(client, email, TEST_PASSWORD, "driver", spec["name"])
        user_ids.append(uid)

        # drivers — UPSERT (PK = id, FK auth.users)
        client.table("drivers").upsert(
            {
                "id": uid,
                "name": spec["name"],
                "phone": spec["phone"],
                "email": email,
                "vehicle_type": spec["vehicle"],
                "license_plate": f"E2E-{spec['slug'][-1].upper()}",
                "is_online": spec["online"],
                "lat": spec["lat"],
                "lng": spec["lng"],
            },
            on_conflict="id",
        ).execute()
        print(f"  [driver] {spec['slug']}: {spec['phone']} · {spec['vehicle']} · online={spec['online']}")

    return user_ids


# ──────────────────────────────────────────────────────────────────────────
# Seed: restaurantes
# ──────────────────────────────────────────────────────────────────────────


def seed_restaurants(client) -> list[str]:
    """Cria 3 restaurantes (TEXT id estável). Devolve lista de IDs."""
    print("\n=== seed restaurantes ===")
    ids: list[str] = []
    for spec in RESTAURANT_SPECS:
        client.table("restaurants").upsert(
            {
                "id": spec["id"],
                "name": spec["name"],
                "phone": "+351910000000",
                "address": "Guarda, Portugal (E2E)",
                "email": f"{spec['id']}{TEST_EMAIL_DOMAIN}",
                "photo_url": "",
                "cuisine_type": "test",
                "is_partner": spec["is_partner"],
                "category": spec["category"],
                "is_online": True,
                "lat": spec["lat"],
                "lng": spec["lng"],
            },
            on_conflict="id",
        ).execute()
        ids.append(spec["id"])
        print(f"  [restaurant] {spec['id']} · {spec['category']} · partner={spec['is_partner']}")

    return ids


# ──────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────


def main() -> int:
    client = admin_client()
    print("Bora E2E seed — fixtures 3+3+3 (idempotente)")

    clients = seed_clients(client)
    drivers = seed_drivers(client)
    restaurants = seed_restaurants(client)

    print(f"\n✓ Seed completo: {len(clients)} clientes, {len(drivers)} estafetas, {len(restaurants)} restaurantes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
