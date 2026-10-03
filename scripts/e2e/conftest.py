"""Pytest fixtures globais para 7E-B (Grupos 1, 2, 4, 7).

Estado prod confirmado via MCP (2026-05-07):
- 3 clientes E2E em ``auth.users`` (``e2e_client_a/b/c@boraapp.test``).
- 3 restaurants ``E2E_TEST_*`` (PartnerRest, NonPartnerRest, Market). IDs
  são TEXT (legado).
- 3 drivers ``E2E_TEST_Driver_A/B/C`` (emails sintéticos
  ``910000901/2/3@driver.bora.app``).
- Wallets: A=€100, B=€0, C=€25.
- Drivers arrancam ``is_online=false``, GPS partilhado
  ``(40.5404, -7.2683)``.

Naming: as fixtures usam nomes PT (``cliente_a``, ``restaurant_partner``)
para coerência com os tests, mas as queries usam emails/IDs reais (EN).

Fixtures retornam dicts com chaves explícitas (não objectos ``Client``)
para os tests poderem inspeccionar estado sem fazer login extra.
"""
import pytest
from supabase import Client

from helpers.auth import TEST_PASSWORD, get_admin_client, login_as_user
from helpers.dispatch import (
    activate_test_drivers,
    deactivate_test_drivers,
    link_test_drivers_to_auth,
    reposition_test_drivers,
    reset_test_drivers_gps,
)


# ─────────────────────────────────────────────────────────────
# Admin client (session-scope — 1 instância)
# ─────────────────────────────────────────────────────────────

@pytest.fixture(scope="session")
def admin_client() -> Client:
    """Cliente Supabase service_role (bypass RLS)."""
    return get_admin_client()


# ─────────────────────────────────────────────────────────────
# Clientes (function-scope — re-confirma user_id por test)
# ─────────────────────────────────────────────────────────────

def _get_client_fixture(admin: Client, email: str) -> dict:
    """Lê ``auth.users`` por email; lança se não existir.

    Compatibilidade supabase-py: ``list_users()`` devolve ``list[User]``
    directamente em versões modernas; versões antigas devolviam um
    objecto com ``.users``. Aceitamos ambos.
    """
    page = admin.auth.admin.list_users()
    users_list = page if isinstance(page, list) else getattr(page, 'users', [])
    user = next((u for u in users_list if u.email == email), None)
    if not user:
        raise RuntimeError(
            f"Fixture {email!r} não existe — corre seed.py primeiro."
        )
    return {
        'user_id': user.id,
        'email': email,
        'password': TEST_PASSWORD,
    }


@pytest.fixture(scope="session")
def admin_user(admin_client) -> dict:
    """E2E_Admin user com ``app_metadata.role='admin'`` para chamar RPCs
    gated por ``_admin_op_guard()`` (ex.: ``admin_cancel_order`` em T38).

    Setup idempotente: cria se não existe, faz update do role se já
    existe sem ``role='admin'`` em ``app_metadata``. NÃO usa o admin
    real (Danilo) para não tocar em dados de produção.
    """
    email = "e2e_admin@boraapp.test"
    page = admin_client.auth.admin.list_users()
    users_list = page if isinstance(page, list) else getattr(page, 'users', [])
    user = next((u for u in users_list if u.email == email), None)

    if not user:
        result = admin_client.auth.admin.create_user({
            "email": email,
            "password": TEST_PASSWORD,
            "email_confirm": True,
            "app_metadata": {"role": "admin"},
        })
        user = result.user
    elif (user.app_metadata or {}).get('role') != 'admin':
        admin_client.auth.admin.update_user_by_id(
            user.id,
            {"app_metadata": {"role": "admin"}},
        )

    return {
        'user_id': user.id,
        'email': email,
        'password': TEST_PASSWORD,
    }


@pytest.fixture
def cliente_a(admin_client) -> dict:
    """E2E_Client_A — €100 free balance (testes pricing/wallet/cancel)."""
    return _get_client_fixture(admin_client, "e2e_client_a@boraapp.test")


@pytest.fixture
def cliente_b(admin_client) -> dict:
    """E2E_Client_B — €0 free balance (testes saldo zero)."""
    return _get_client_fixture(admin_client, "e2e_client_b@boraapp.test")


@pytest.fixture
def cliente_c(admin_client) -> dict:
    """E2E_Client_C — €25 free balance."""
    return _get_client_fixture(admin_client, "e2e_client_c@boraapp.test")


# ─────────────────────────────────────────────────────────────
# Restaurants (session-scope — read-only)
# ─────────────────────────────────────────────────────────────

def _get_restaurant_fixture(admin: Client, restaurant_id: str) -> dict:
    """Lê restaurant por ID (TEXT)."""
    result = (
        admin.table("restaurants")
        .select("id, name, is_partner")
        .eq("id", restaurant_id)
        .single()
        .execute()
    )
    if not result.data:
        raise RuntimeError(
            f"Fixture restaurant {restaurant_id!r} não existe — corre seed.py."
        )
    return result.data


@pytest.fixture(scope="session")
def restaurant_partner(admin_client) -> dict:
    """E2E_TEST_PartnerRest — ``is_partner=true``, id=TEXT."""
    return _get_restaurant_fixture(admin_client, "E2E_TEST_PartnerRest")


@pytest.fixture(scope="session")
def restaurant_non_partner(admin_client) -> dict:
    """E2E_TEST_NonPartnerRest — único ``is_partner=false`` em fixtures."""
    return _get_restaurant_fixture(admin_client, "E2E_TEST_NonPartnerRest")


@pytest.fixture(scope="session")
def restaurant_market(admin_client) -> dict:
    """E2E_TEST_Market — ``is_partner=true``; usar com ``service_type='storeShopping'``."""
    return _get_restaurant_fixture(admin_client, "E2E_TEST_Market")


# ─────────────────────────────────────────────────────────────
# Drivers (session-scope — read-only)
# ─────────────────────────────────────────────────────────────

def _get_driver_fixture(admin: Client, name: str) -> dict:
    """Lê driver por ``name`` (label E2E_TEST_*)."""
    result = (
        admin.table("drivers")
        .select("id, name, email, is_online, lat, lng, user_id")
        .eq("name", name)
        .single()
        .execute()
    )
    if not result.data:
        raise RuntimeError(
            f"Fixture driver {name!r} não existe — corre seed.py."
        )
    return result.data


@pytest.fixture(scope="session")
def driver_a(admin_client) -> dict:
    """E2E_TEST_Driver_A — usado em T13 (offer accept) e T37 (driver login)."""
    return _get_driver_fixture(admin_client, "E2E_TEST_Driver_A")


@pytest.fixture(scope="session")
def driver_b(admin_client) -> dict:
    """E2E_TEST_Driver_B — usado em T10/T11 (reject scenarios)."""
    return _get_driver_fixture(admin_client, "E2E_TEST_Driver_B")


@pytest.fixture(scope="session")
def driver_c(admin_client) -> dict:
    """E2E_TEST_Driver_C — usado em T11/T12 (offline scenario)."""
    return _get_driver_fixture(admin_client, "E2E_TEST_Driver_C")


# ─────────────────────────────────────────────────────────────
# Dispatch setup (function-scope — mutável + cleanup)
# ─────────────────────────────────────────────────────────────

@pytest.fixture
def dispatch_setup(admin_client):
    """Pré-condições para tests do Grupo 2 (Dispatch).

    Setup:
    - ``is_online=true`` em todos os 3 drivers ``E2E_TEST_*``.
    - GPS distinct (Driver_A=Guarda centro, B=Norte, C=Sul).
    - ``drivers.user_id`` linkado a ``auth.users`` (T37 precisa).

    Teardown:
    - ``is_online=false`` (estado base prod).
    - GPS partilhado restaurado ``(40.5404, -7.2683)``.
    - ``user_id`` NÃO desfeito — link é idempotente; fica para próximas
      sessões.

    ⚠️ Se um test crashar entre activate e o teardown, drivers ficam
    online. Mitigação: a próxima invocação de ``dispatch_setup`` volta a
    activar (no-op idempotente) e o teardown desliga novamente.
    """
    activate_test_drivers(admin_client)
    reposition_test_drivers(admin_client)
    link_test_drivers_to_auth(admin_client)
    yield
    deactivate_test_drivers(admin_client)
    reset_test_drivers_gps(admin_client)


# ─────────────────────────────────────────────────────────────
# Cleanup orders (function-scope — apaga após cada test)
# ─────────────────────────────────────────────────────────────

@pytest.fixture
def cleanup_test_orders(admin_client):
    """Apaga TODOS os pedidos com ``is_test_order=true`` no teardown.

    ⚠️ Apaga GLOBAL — em pytest paralelo (xdist) pode apagar pedidos de
    outros workers. Para 7E-B usar ``pytest`` single-thread.
    Cascading FK apaga ``wallet_transactions related_order_id`` quando
    aplicável.
    """
    yield
    admin_client.table("orders").delete().eq("is_test_order", True).execute()


# ─────────────────────────────────────────────────────────────
# Wallet snapshot/reset (factory para tests determinísticos)
# ─────────────────────────────────────────────────────────────

@pytest.fixture
def reset_wallet_state(admin_client):
    """Factory que escreve ``client_wallets.free_balance_cents`` directamente.

    Uso:
        def test_x(reset_wallet_state, cliente_a):
            reset_wallet_state(cliente_a['user_id'], free_cents=10000)

    Sem teardown — confiar no UPSERT do test seguinte para reset.
    """
    def _reset(user_id: str, free_cents: int = 10000) -> None:
        admin_client.table("client_wallets").upsert(
            {"user_id": user_id, "free_balance_cents": free_cents},
            on_conflict="user_id",
        ).execute()
    return _reset


# ─────────────────────────────────────────────────────────────
# Login factory (para tests T35/T36/T37 com JWT user)
# ─────────────────────────────────────────────────────────────

@pytest.fixture
def login_client():
    """Factory de login a um utilizador (function-scope porque cada
    test pode autenticar identidades diferentes).
    """
    def _login(email: str, password: str = TEST_PASSWORD) -> Client:
        return login_as_user(email, password)
    return _login
