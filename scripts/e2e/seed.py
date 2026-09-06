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
    {"slug": "driver_a", "phone": "910000901", "name": "E2E_TEST_Driver_A", "vehicle": "car",  "online": True,  "lat": 40.5404, "lng": -7.2683},
    {"slug": "driver_b", "phone": "910000902", "name": "E2E_TEST_Driver_B", "vehicle": "bike", "online": False, "lat": 40.5404, "lng": -7.2683},
    {"slug": "driver_c", "phone": "910000903", "name": "E2E_TEST_Driver_C", "vehicle": "car",  "online": True,  "lat": 40.5404, "lng": -7.2683},
]

# Partner owners — auth.users com bora_role=partner. Cada owner é "dono" de
# um restaurant via restaurants.user_ (BR §44 audit). Sem owner válido,
# restaurant_respond_to_rating em 7E-C parte.
PARTNER_OWNER_SPECS: list[dict[str, Any]] = [
    {"slug": "owner_a", "email": f"e2e_partner_a{TEST_EMAIL_DOMAIN}", "restaurant_id": f"{TEST_RESTAURANT_PREFIX}PartnerRest"},
    {"slug": "owner_b", "email": f"e2e_partner_b{TEST_EMAIL_DOMAIN}", "restaurant_id": f"{TEST_RESTAURANT_PREFIX}NonPartnerRest"},
    {"slug": "owner_c", "email": f"e2e_partner_c{TEST_EMAIL_DOMAIN}", "restaurant_id": f"{TEST_RESTAURANT_PREFIX}Market"},
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
        print(f"  [auth] [OK] existe: {email} ({uid})")
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


def seed_partner_owners(client) -> dict[str, str]:
    """Cria 3 partner owners em auth.users. Devolve dict slug→uid."""
    print("\n=== seed partner owners ===")
    owners: dict[str, str] = {}
    for spec in PARTNER_OWNER_SPECS:
        uid = _ensure_auth_user(client, spec["email"], TEST_PASSWORD, "partner", spec["slug"])
        owners[spec["slug"]] = uid
    return owners


def seed_restaurants(client, owners_by_restaurant: dict[str, str]) -> list[str]:
    """Cria 3 restaurantes e popula `user_` com o partner owner associado.

    `owners_by_restaurant`: dict mapping restaurant_id → owner_uid.
    """
    print("\n=== seed restaurantes ===")
    ids: list[str] = []
    for spec in RESTAURANT_SPECS:
        owner_uid = owners_by_restaurant.get(spec["id"])
        if owner_uid is None:
            raise RuntimeError(
                f"seed.py BUG: sem owner para restaurant {spec['id']!r}. "
                "Confirma PARTNER_OWNER_SPECS."
            )
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
                "user_": owner_uid,
            },
            on_conflict="id",
        ).execute()
        ids.append(spec["id"])
        print(f"  [restaurant] {spec['id']} · {spec['category']} · partner={spec['is_partner']} · owner={owner_uid[:8]}...")

    return ids


# ──────────────────────────────────────────────────────────────────────────
# Post-seed asserts (B4 — fail-loud, evita silent regressions)
# ──────────────────────────────────────────────────────────────────────────


def _count(client, table: str, **filters) -> int:
    """Wrapper para .select(count='exact') do supabase-py."""
    q = client.table(table).select("*", count="exact")
    for col, val in filters.items():
        if col.endswith("__like"):
            q = q.like(col[:-6], val)
        elif col.endswith("__is_null"):
            q = q.is_(col[:-9], "null") if val else q.not_.is_(col[:-9], "null")
        else:
            q = q.eq(col, val)
    return q.execute().count or 0


def _assert_post_seed(client, expected_clients: int, expected_drivers: int, expected_owners: int) -> None:
    """Confirma estado pós-seed. Raise RuntimeError se algum invariante falhar.

    Não chamar `print` para success — só `raise` em fail. O caller imprime "[OK]".
    """
    n_drivers = _count(client, "drivers", name__like="E2E_TEST_%")
    if n_drivers != 3:
        raise RuntimeError(
            f"_assert_post_seed: drivers WHERE name LIKE 'E2E_TEST_%' = {n_drivers}, esperado 3. "
            "Silent fail no upsert? Verifica response.data dos clientes/drivers/restaurants."
        )

    res = client.table("restaurants").select("id, user_").like("id", "E2E_TEST_%").execute()
    null_owners = [r["id"] for r in (res.data or []) if r.get("user_") is None]
    if null_owners:
        raise RuntimeError(
            f"_assert_post_seed: restaurants com user_=NULL: {null_owners}. "
            "B3 (UPDATE user_) falhou ou owners não foram criados antes."
        )
    if len(res.data or []) != 3:
        raise RuntimeError(
            f"_assert_post_seed: restaurants E2E_TEST_* = {len(res.data or [])}, esperado 3."
        )

    # auth.users com domínio @boraapp.test = 3 clientes + 3 partner owners = 6.
    # Estafetas usam @driver.bora.app, não contam para este assert.
    auth_res = client.auth.admin.list_users()
    users = auth_res if isinstance(auth_res, list) else getattr(auth_res, "users", [])
    boraapp_test_users = []
    for u in users:
        email = getattr(u, "email", None) or (u.get("email") if isinstance(u, dict) else None) or ""
        if email.endswith("@boraapp.test"):
            boraapp_test_users.append(email)
    if len(boraapp_test_users) != 6:
        raise RuntimeError(
            f"_assert_post_seed: auth.users com email @boraapp.test = {len(boraapp_test_users)}, "
            f"esperado 6 (3 clientes + 3 partner owners). Encontrados: {boraapp_test_users}"
        )


# ──────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────


def main() -> int:
    client = admin_client()
    print("Bora E2E seed — fixtures 3+3+3 + 3 partner owners (idempotente)")

    clients = seed_clients(client)
    drivers = seed_drivers(client)
    owners = seed_partner_owners(client)

    # Mapeamento restaurant_id → owner_uid (B3).
    owners_by_restaurant: dict[str, str] = {
        spec["restaurant_id"]: owners[spec["slug"]] for spec in PARTNER_OWNER_SPECS
    }
    restaurants = seed_restaurants(client, owners_by_restaurant)

    # B4 — fail-loud asserts. Raise se algo silenciosamente não foi criado.
    _assert_post_seed(client, len(clients), len(drivers), len(owners))

    print(
        f"\n[OK] Seed completo (asserts OK): {len(clients)} clientes, "
        f"{len(drivers)} estafetas, {len(owners)} partner owners, "
        f"{len(restaurants)} restaurantes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
