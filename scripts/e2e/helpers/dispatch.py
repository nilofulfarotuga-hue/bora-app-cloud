"""Helpers para tests de dispatch (Grupo 2 — T09-T13).

Adaptações 7E-B audit + validação MCP em prod:

1. Drivers ``E2E_TEST_*`` arrancam ``is_online=false``. Tests dispatch
   precisam de invocar ``activate_test_drivers()`` antes (e
   ``deactivate_test_drivers()`` em cleanup).
2. Os 3 drivers de teste partilham GPS ``(40.5404, -7.2683)`` em prod.
   Para tests de discriminação espacial usar ``reposition_test_drivers()``
   e repor com ``reset_test_drivers_gps()``.
3. Existem 17 triggers em ``UPDATE orders`` (lista no docstring de
   ``simulate_offer_accept``). Aceitamos side effects — são contidos por
   ``is_test_order=true`` + cleanup conftest. NÃO usamos
   ``session_replication_role='replica'`` (privilege escalation).
4. ``orders`` tem dois campos para offer expiry duplicados
   (``offer_expires_at`` + ``driver_offer_expires_at``) — tocamos apenas
   no segundo se necessário; aqui não tocamos.
5. ``STATUS_AT_COLUMNS`` reduzido: só ``delivered``/``cancelled`` têm
   timestamp dedicado em prod (ver helpers/orders.py em B5). Outros
   status só fazem UPDATE de ``status``.

⚠️ BUG-7E-B-005 (referência cruzada): Danilo confirmou que tokens × 2
é a fórmula correcta — actualmente está × 20 (bonus 10x). Tests B2
documentam comportamento ACTUAL; fix em sessão dedicada futura.
"""
import math
from typing import List, Optional, Tuple
from supabase import Client

# ─────────────────────────────────────────────────────────────
# Configuração GPS — fixtures E2E em Guarda
# ─────────────────────────────────────────────────────────────

#: GPS distinct usado em tests de discriminação espacial.
E2E_DRIVER_GPS_DISTINCT: dict = {
    'E2E_TEST_Driver_A': (40.5378, -7.2682),  # Guarda centro
    'E2E_TEST_Driver_B': (40.5450, -7.2750),  # Norte (~1 km)
    'E2E_TEST_Driver_C': (40.5300, -7.2600),  # Sul (~1 km)
}

#: GPS partilhado em prod (estado pós-seed); usado em ``reset_test_drivers_gps``.
E2E_DRIVER_GPS_DEFAULT: Tuple[float, float] = (40.5404, -7.2683)


# ─────────────────────────────────────────────────────────────
# Geometria
# ─────────────────────────────────────────────────────────────

def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distância haversine (great-circle) entre 2 pontos GPS em km."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlng / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


# ─────────────────────────────────────────────────────────────
# Setup / Cleanup drivers de teste
# ─────────────────────────────────────────────────────────────

def activate_test_drivers(admin_client: Client) -> None:
    """Marca todos os ``E2E_TEST_*`` como ``is_online=true``.

    Pré-condição obrigatória para tests do Grupo 2 (Dispatch). Em prod,
    estes drivers arrancam ``is_online=false`` para não interferir com
    dispatch real. Reverter no cleanup com ``deactivate_test_drivers``.
    """
    admin_client.table("drivers").update(
        {"is_online": True}
    ).ilike("name", "E2E_TEST_%").execute()


def deactivate_test_drivers(admin_client: Client) -> None:
    """Repõe ``is_online=false`` em todos os ``E2E_TEST_*`` (cleanup)."""
    admin_client.table("drivers").update(
        {"is_online": False}
    ).ilike("name", "E2E_TEST_%").execute()


def reposition_test_drivers(admin_client: Client) -> None:
    """Põe GPS distinct nos 3 drivers de teste para tests de proximidade.

    Mapeamento via ``E2E_DRIVER_GPS_DISTINCT``. Reverter no cleanup com
    ``reset_test_drivers_gps``.
    """
    for name, (lat, lng) in E2E_DRIVER_GPS_DISTINCT.items():
        admin_client.table("drivers").update(
            {"lat": lat, "lng": lng}
        ).eq("name", name).execute()


def reset_test_drivers_gps(admin_client: Client) -> None:
    """Repõe GPS default partilhado (cleanup pós-test)."""
    lat, lng = E2E_DRIVER_GPS_DEFAULT
    admin_client.table("drivers").update(
        {"lat": lat, "lng": lng}
    ).ilike("name", "E2E_TEST_%").execute()


# ─────────────────────────────────────────────────────────────
# Mock de dispatch (UPDATE directo)
# ─────────────────────────────────────────────────────────────

def find_nearest_driver(
    admin_client: Client,
    pickup_lat: float,
    pickup_lng: float,
    max_radius_km: float = 5.0,
    exclude_ids: Optional[List[str]] = None,
) -> Optional[dict]:
    """Retorna o driver ``E2E_TEST_*`` ``is_online=true`` mais próximo.

    Aplica filtros:
    - ``name ILIKE 'E2E_TEST_%'`` (apenas fixtures)
    - ``is_online = true``
    - ``id NOT IN exclude_ids`` (para tests de reassign)
    - ``haversine_km ≤ max_radius_km``

    Args:
        admin_client: cliente Supabase service_role.
        pickup_lat, pickup_lng: GPS do pedido.
        max_radius_km: raio máximo (default 5 km).
        exclude_ids: IDs a excluir — útil para T10 (reject reassigns).

    Returns:
        Dict do driver com chave extra ``distance_km``, ou ``None`` se
        nenhum candidato dentro do raio.
    """
    exclude_ids = exclude_ids or []
    result = (
        admin_client.table("drivers")
        .select("id, name, lat, lng, is_online")
        .ilike("name", "E2E_TEST_%")
        .eq("is_online", True)
        .execute()
    )
    candidates = []
    for d in result.data:
        if d['id'] in exclude_ids:
            continue
        if d.get('lat') is None or d.get('lng') is None:
            continue
        dist = haversine_km(pickup_lat, pickup_lng, d['lat'], d['lng'])
        if dist <= max_radius_km:
            candidates.append({**d, 'distance_km': dist})
    if not candidates:
        return None
    return min(candidates, key=lambda x: x['distance_km'])


def simulate_offer_accept(
    admin_client: Client,
    order_id: str,
    driver_id: str,
) -> None:
    """Simula driver a aceitar a oferta de dispatch via UPDATE directo.

    Campos actualizados:
    - ``current_driver_offer_id`` ← ``driver_id`` (single source memória 7E-A)
    - ``driver_id`` ← ``driver_id`` (uuid)
    - ``status`` ← ``'driverAccepted'``

    NÃO mexemos em ``assigned_driver_id``, ``driver_offer_history`` ou
    ``tried_driver_ids`` — deixamos os triggers tratarem se for caso disso.

    ⚠️ Triggers em ``UPDATE orders`` (lista snapshot 2026-05-07, 17 totais):
    ``trg_dispatch_on_calling_driver``, ``trg_dispatch_on_rejection``,
    ``orders_enforce_payment_before_preparing``, ``orders_financial_lock``,
    ``orders_set_delivered_at``, ``trg_award_tokens_on_delivery``,
    ``trg_award_cashback``, ``trg_notify_on_order_cancel``,
    ``trg_enforce_refund_cap``, ``trigger_credit_driver_on_delivery``,
    ``orders_post_to_ledger``, ``orders_cash_settlement``,
    ``trg_referral_reward``, ``orders_auto_confirm_cod``,
    ``orders_financial_split``, ``orders_storeshopping_pickup_guard``.

    Aceitamos side effects (cleanup conftest filtra ``is_test_order=true``).
    NÃO usar ``SET LOCAL session_replication_role='replica'`` — privilege
    escalation indesejável.
    """
    admin_client.table("orders").update(
        {
            "current_driver_offer_id": driver_id,
            "driver_id": driver_id,
            "assigned_driver_id": driver_id,  # PATCH B3.1: driver_cancel_order valida este campo (TEXT)
            "status": "driverAccepted",
        }
    ).eq("id", order_id).execute()


def link_test_drivers_to_auth(admin_client: Client) -> int:
    """Liga ``drivers.user_id`` ao ``auth.users.id`` correspondente via email.

    PATCH B8.0: drivers ``E2E_TEST_*`` em prod arrancam com ``user_id=NULL``;
    sem este link a RPC ``driver_cancel_order`` falha em
    ``WHERE user_id = auth.uid()``. Match feito por
    ``drivers.email == auth.users.email`` (sufixo ``@driver.bora.app``).

    Idempotente — pode ser invocado múltiplas vezes; já-linked saltam.

    Returns:
        Número de drivers efectivamente actualizados nesta chamada.
    """
    page = admin_client.auth.admin.list_users()
    users_list = page if isinstance(page, list) else getattr(page, 'users', [])
    email_to_uid = {
        u.email: u.id for u in users_list
        if u.email and '@driver.bora.app' in u.email
    }
    result = (
        admin_client.table("drivers")
        .select("id, name, email, user_id")
        .ilike("name", "E2E_TEST_%")
        .execute()
    )
    linked = 0
    for d in result.data or []:
        if d.get('user_id'):
            continue
        uid = email_to_uid.get(d.get('email'))
        if uid:
            admin_client.table("drivers").update(
                {"user_id": uid}
            ).eq("id", d['id']).execute()
            linked += 1
    return linked


def simulate_offer_reject(
    admin_client: Client,
    order_id: str,
    driver_id: str,
) -> None:
    """Simula driver a rejeitar — repõe ``status='callingDriver'`` e adiciona ID a ``tried_driver_ids``.

    Lê ``tried_driver_ids`` corrente, faz append idempotente, e devolve o
    pedido ao pool. ``current_driver_offer_id`` é limpo para outro driver
    poder ser oferecido (T10 reassign).
    """
    order = (
        admin_client.table("orders")
        .select("tried_driver_ids")
        .eq("id", order_id)
        .single()
        .execute()
    )
    tried = order.data.get('tried_driver_ids') or []
    if driver_id not in tried:
        tried.append(driver_id)
    admin_client.table("orders").update(
        {
            "current_driver_offer_id": None,
            "status": "callingDriver",
            "tried_driver_ids": tried,
        }
    ).eq("id", order_id).execute()
