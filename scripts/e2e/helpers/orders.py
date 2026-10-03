"""Helpers para tests de orders (Grupos 1, 4, 7 + dispatch).

Implementa ``create_test_order`` via RPC ``create_order(jsonb)``. Schema
input validado via MCP em prod (audit 7E-B FASE A).

``create_order`` valida server-side:
- ``service_type ∈ {restaurant, storeShopping, carryGroceries, sendPackage}``
- ``payment_method ∈ {cash, mbway, card}`` — NÃO ``"wallet"`` (a carteira
  é aplicada via ``wallet_applied_cents`` em paralelo a outro método).
- ``dropoff_lat/lng`` obrigatórios sempre.
- ``pickup_lat/lng`` obrigatórios para tipos com pickup
  (``restaurant``, ``storeShopping``, ``carryGroceries``).
- ``wallet_applied_cents > 0`` só se balance disponível.
- ``WALLET_BLOCKED`` se ``balance < wallet_max_negative_balance_cents``
  (default −€10 / −1000 cents).

``is_test_order=true`` é aplicado via UPDATE pós-create (a RPC não aceita
o campo no input). Tem race-condition mínima — triggers UPDATE podem
disparar antes do flag ser visível, é aceitável.

``STATUS_AT_COLUMNS`` reduzido conforme audit (apenas ``delivered_at`` e
``cancelled_at`` existem em prod):
- ``delivered`` / ``cancelled``: UPDATE ``status`` + ``<status>_at``.
- Outros status: apenas UPDATE ``status`` (sem timestamp dedicado).

⚠️ 17 triggers em ``UPDATE orders`` (lista em
``helpers/dispatch.py:simulate_offer_accept``). Aceitar side effects —
contidos a ``is_test_order=true`` + cleanup conftest.
"""
from typing import Any, Dict, List, Optional
from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

#: GPS Guarda centro — pickup default em testes.
GUARDA_CENTER_LAT: float = 40.5378
GUARDA_CENTER_LNG: float = -7.2682

#: GPS dropoff default (próximo do pickup mas distinto).
GUARDA_DROPOFF_LAT: float = 40.5404
GUARDA_DROPOFF_LNG: float = -7.2683

#: Apenas estes status têm timestamp dedicado em prod (audit confirmou).
STATUS_AT_COLUMNS: Dict[str, str] = {
    'delivered': 'delivered_at',
    'cancelled': 'cancelled_at',
}

#: Service types válidos (CHECK server-side em ``create_order``).
VALID_SERVICE_TYPES = ('restaurant', 'storeShopping', 'carryGroceries', 'sendPackage')

#: Payment methods válidos (CHECK server-side em ``create_order``).
VALID_PAYMENT_METHODS = ('cash', 'mbway', 'card')


# ─────────────────────────────────────────────────────────────
# Create order
# ─────────────────────────────────────────────────────────────

def create_test_order(
    admin_client: Client,
    user_id: str,
    restaurant_id: Optional[str] = None,
    vendor_name: Optional[str] = None,
    subtotal_eur: float = 10.00,
    distance_km: float = 2.0,
    service_type: str = 'restaurant',
    payment_method: str = 'cash',
    is_partner_store: bool = True,
    apartment_delivery: bool = False,
    bag_count: int = 0,
    wallet_applied_cents: int = 0,
    pickup_lat: float = GUARDA_CENTER_LAT,
    pickup_lng: float = GUARDA_CENTER_LNG,
    dropoff_lat: float = GUARDA_DROPOFF_LAT,
    dropoff_lng: float = GUARDA_DROPOFF_LNG,
    product_lines: Optional[List[Dict[str, Any]]] = None,
) -> str:
    """Cria pedido de teste via RPC ``create_order(jsonb)``.

    Marca ``is_test_order=true`` via UPDATE imediato pós-create.

    Args:
        admin_client: cliente Supabase service_role.
        user_id: UUID do cliente (auth.users).
        restaurant_id: id do restaurante (opcional — se ``vendor_name``
            for passado, RPC faz lookup por nome).
        vendor_name: nome legível (ex.: ``E2E_TEST_PartnerRest``).
        subtotal_eur: subtotal em EUR (default €10).
        distance_km: distância pickup→dropoff em km (default 2 km).
        service_type: enum ∈ ``VALID_SERVICE_TYPES`` (default ``restaurant``).
        payment_method: enum ∈ ``VALID_PAYMENT_METHODS``. **NÃO ``"wallet"``**.
        is_partner_store: ``True`` activa pricing parceiro (10/5/5).
        apartment_delivery: aplica surcharge total €1.50.
        bag_count: número de sacos (passado mas pricing_calculate ignora).
        wallet_applied_cents: parte do total a debitar da carteira.
        pickup_lat / pickup_lng: GPS recolha (default Guarda centro).
        dropoff_lat / dropoff_lng: GPS entrega (default próximo).
        product_lines: lista ``[{product_id, quantity, unit_price}]``. Se
            ausente, server usa ``subtotal_eur`` directo. Se presente,
            server recalcula (lookup ``products.price`` ou fallback
            ``unit_price`` × quantity, com markup ×1.15 em non-partner).

    Returns:
        ``order_id`` (TEXT — UUID em string).

    Raises:
        ValueError: ``service_type`` ou ``payment_method`` inválidos.
        RuntimeError: RPC devolve shape inesperado ou sem ``order_id``.
    """
    if service_type not in VALID_SERVICE_TYPES:
        raise ValueError(
            f"service_type inválido: {service_type!r}. "
            f"Use um de {VALID_SERVICE_TYPES}."
        )
    if payment_method not in VALID_PAYMENT_METHODS:
        raise ValueError(
            f"payment_method inválido: {payment_method!r}. "
            f"Use cash/mbway/card (NÃO 'wallet' — wallet_applied_cents é separado)."
        )

    payload: Dict[str, Any] = {
        'user_id': user_id,
        'service_type': service_type,
        'payment_method': payment_method,
        'distance_km': distance_km,
        'is_partner_store': is_partner_store,
        'apartment_delivery': apartment_delivery,
        'subtotal': subtotal_eur,
        'bag_count': bag_count,
        'wallet_applied_cents': wallet_applied_cents,
        'pickup_lat': pickup_lat,
        'pickup_lng': pickup_lng,
        'dropoff_lat': dropoff_lat,
        'dropoff_lng': dropoff_lng,
    }
    if vendor_name:
        payload['vendor_name'] = vendor_name
    if restaurant_id:
        payload['restaurant_id'] = restaurant_id
    if product_lines:
        payload['product_lines'] = product_lines

    result = admin_client.rpc('create_order', {'p_input': payload}).execute()
    data = result.data

    # RPC devolve jsonb com chave ``order_id`` (auto-deserialized).
    if isinstance(data, dict):
        order_id = data.get('order_id') or data.get('id')
    elif isinstance(data, str):
        order_id = data
    else:
        raise RuntimeError(
            f"create_order devolveu shape inesperado: {type(data).__name__} = {data!r}"
        )

    if not order_id:
        raise RuntimeError(f"create_order não devolveu order_id: {data!r}")

    # Marca test_order=true (RPC não aceita no input — aplicado via UPDATE).
    admin_client.table("orders").update(
        {"is_test_order": True}
    ).eq("id", order_id).execute()

    return order_id


# ─────────────────────────────────────────────────────────────
# Manipulação de status
# ─────────────────────────────────────────────────────────────

def advance_status(
    admin_client: Client,
    order_id: str,
    new_status: str,
) -> None:
    """Avança ``status`` do pedido via UPDATE directo (bypass dispatch normal).

    Comportamento por status:
    - ``delivered`` / ``cancelled``: UPDATE ``status`` + ``<status>_at = now()``.
    - Outros (``created``, ``preparing``, ``callingDriver``,
      ``driverAccepted``, ``pickedUp``, ``onTheWay``): apenas UPDATE
      ``status`` (sem timestamp dedicado em prod).

    ⚠️ 17 triggers em ``UPDATE orders`` disparam — aceitar side effects
    (contidos a ``is_test_order=true``).

    Args:
        admin_client: cliente Supabase service_role.
        order_id: id do pedido.
        new_status: texto livre (não há CHECK em ``orders.status``).
    """
    update_payload: Dict[str, Any] = {"status": new_status}
    if new_status in STATUS_AT_COLUMNS:
        update_payload[STATUS_AT_COLUMNS[new_status]] = "now()"
    admin_client.table("orders").update(update_payload).eq("id", order_id).execute()


# ─────────────────────────────────────────────────────────────
# Leitura
# ─────────────────────────────────────────────────────────────

def get_order(admin_client: Client, order_id: str) -> Dict[str, Any]:
    """Lê pedido completo via admin client (bypass RLS).

    Returns:
        Dict com todas as colunas. Devolve ``{}`` se não encontrado.
    """
    result = (
        admin_client.table("orders")
        .select("*")
        .eq("id", order_id)
        .single()
        .execute()
    )
    return result.data or {}


def get_order_field(
    admin_client: Client,
    order_id: str,
    field: str,
) -> Any:
    """Lê 1 campo do pedido (mais leve que ``get_order``).

    Útil em asserts focados (ex.: status pós-cancel).
    """
    result = (
        admin_client.table("orders")
        .select(field)
        .eq("id", order_id)
        .single()
        .execute()
    )
    return (result.data or {}).get(field)


# ─────────────────────────────────────────────────────────────
# Cleanup (usado pelo conftest)
# ─────────────────────────────────────────────────────────────

def delete_test_orders(admin_client: Client) -> int:
    """Apaga todos os pedidos com ``is_test_order=true``.

    Estratégia: ``SELECT count`` prévio + ``DELETE``. Devolve o número
    estimado de linhas apagadas (lido do count antes do DELETE; o DELETE
    via supabase-py não devolve count fiável).
    """
    count_result = (
        admin_client.table("orders")
        .select("id", count="exact")
        .eq("is_test_order", True)
        .execute()
    )
    count = count_result.count or 0
    if count > 0:
        admin_client.table("orders").delete().eq("is_test_order", True).execute()
    return count
