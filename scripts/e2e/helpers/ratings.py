"""Helpers para tests de ratings (Grupo 8 — T39-T45).

RPCs disponíveis (validadas via MCP em prod 2026-05-08):
- ``submit_rating(p_order_id, p_subject_type, p_subject_id, p_stars,
  p_comment, p_tags, p_is_private)`` → jsonb ``{rating_id, updated}``.
- ``rating_average(p_subject_type, p_subject_id)`` → jsonb com avg/count.
- ``get_driver_ratings_summary(p_driver_id)`` → jsonb.
- ``get_restaurant_ratings_summary(p_restaurant_id)`` → jsonb.
- ``restaurant_respond_to_rating(p_rating_id, p_response)`` → jsonb.
- ``admin_flag_rating(p_rating_id, p_flag)`` → jsonb.
- ``admin_list_ratings(...)`` → SETOF ratings.

Triggers automáticos:
- ``_update_driver_avg_rating`` — actualiza ``drivers.avg_rating`` +
  ``ratings_count`` quando ``subject_type='driver'`` AND ``is_private=false``.
- ``_update_restaurant_avg_rating`` — idem para ``restaurants``.
- ``_notify_partner_low_rating_trigger`` — chama Edge Fn
  ``notify-partner-low-rating`` quando ``stars<=2`` em rating partner.

Auth requirements para ``submit_rating``:
- ``auth.uid()`` obrigatório (cliente autenticado via ``login_as_user``).
- Se ``subject_type<>'app'``: ``orders.user_id == auth.uid()`` AND
  ``orders.status == 'delivered'``.
- ``subject_type ∈ {'driver', 'partner', 'app'}``.
- ``stars ∈ [1, 5]`` (smallint, validado server-side).

Schema ``ratings`` (relevante):
- ``order_id`` UUID — RPC faz CAST ``p_order_id::uuid``. Order IDs em
  prod são UUID-formatted mesmo sendo coluna TEXT, logo CAST funciona.
- ``subject_id`` TEXT (driver_id ou restaurant_id, ambos legacy TEXT).
- ``rater_user_id`` UUID = ``auth.uid()`` (RPC injecta).
- ``is_private`` BOOLEAN — quando TRUE não conta para AVG/triggers.

Idempotência ``submit_rating``: se já existe row com mesmo
``(order_id, subject_type, subject_id, rater_user_id)`` faz UPDATE
do stars/comment/tags em vez de INSERT (não duplica).
"""
from typing import Any, Dict, List, Optional
from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

VALID_SUBJECT_TYPES = ('driver', 'partner', 'app')
LOW_RATING_THRESHOLD: int = 2  # stars ≤ 2 dispara notify-partner-low-rating


# ─────────────────────────────────────────────────────────────
# RPC wrappers
# ─────────────────────────────────────────────────────────────

def submit_rating(
    client_authed: Client,
    order_id: Optional[str],
    subject_type: str,
    subject_id: str,
    stars: int,
    comment: Optional[str] = None,
    tags: Optional[List[str]] = None,
    is_private: bool = False,
) -> Dict[str, Any]:
    """Submete rating como cliente autenticado.

    Args:
        client_authed: cliente Supabase com JWT do cliente.
        order_id: id da order (TEXT). Pode ser ``None`` se
            ``subject_type='app'`` (feedback geral).
        subject_type: ``'driver'``, ``'partner'`` ou ``'app'``.
        subject_id: id do driver (UUID stringified) ou restaurant (TEXT)
            ou string vazia/loose se ``subject_type='app'``.
        stars: 1-5 (smallint).
        comment: texto livre opcional.
        tags: array de tags livres (preserva ordem).
        is_private: TRUE → não conta para AVG/triggers.

    Returns:
        ``{rating_id, updated}``.
    """
    if subject_type not in VALID_SUBJECT_TYPES:
        raise ValueError(
            f"subject_type inválido: {subject_type!r}. Use {VALID_SUBJECT_TYPES}."
        )
    if not (1 <= stars <= 5):
        raise ValueError(f"stars fora de range [1,5]: {stars}")

    result = client_authed.rpc(
        'submit_rating',
        {
            'p_order_id': order_id,
            'p_subject_type': subject_type,
            'p_subject_id': subject_id,
            'p_stars': stars,
            'p_comment': comment,
            'p_tags': tags,
            'p_is_private': is_private,
        },
    ).execute()
    return result.data or {}


def get_rating_average(
    admin_client: Client,
    subject_type: str,
    subject_id: str,
) -> Dict[str, Any]:
    """Lê ``rating_average(subject_type, subject_id)`` → ``{avg, count}``."""
    result = admin_client.rpc(
        'rating_average',
        {'p_subject_type': subject_type, 'p_subject_id': subject_id},
    ).execute()
    return result.data or {}


def get_driver_summary(admin_client: Client, driver_id: str) -> Dict[str, Any]:
    """RPC ``get_driver_ratings_summary``."""
    result = admin_client.rpc(
        'get_driver_ratings_summary',
        {'p_driver_id': driver_id},
    ).execute()
    return result.data or {}


def get_restaurant_summary(admin_client: Client, restaurant_id: str) -> Dict[str, Any]:
    """RPC ``get_restaurant_ratings_summary``."""
    result = admin_client.rpc(
        'get_restaurant_ratings_summary',
        {'p_restaurant_id': restaurant_id},
    ).execute()
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Direct table reads (asserts)
# ─────────────────────────────────────────────────────────────

def get_rating_row(
    admin_client: Client,
    rating_id: str,
) -> Dict[str, Any]:
    """Lê 1 row em ``ratings`` por id."""
    result = (
        admin_client.table("ratings")
        .select("*")
        .eq("id", rating_id)
        .single()
        .execute()
    )
    return result.data or {}


def get_driver_avg_from_table(
    admin_client: Client,
    driver_id: str,
) -> Dict[str, Any]:
    """Lê ``drivers.avg_rating`` + ``ratings_count`` (campos populados pelo trigger)."""
    result = (
        admin_client.table("drivers")
        .select("id, avg_rating, ratings_count")
        .eq("id", driver_id)
        .single()
        .execute()
    )
    return result.data or {}


def get_order_rated_at(admin_client: Client, order_id: str) -> Optional[str]:
    """Lê ``orders.rated_at`` (preenchido pela 1ª submit_rating não-app)."""
    result = (
        admin_client.table("orders")
        .select("rated_at")
        .eq("id", order_id)
        .single()
        .execute()
    )
    return (result.data or {}).get('rated_at')


# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────

def delete_ratings_for_order(admin_client: Client, order_id: str) -> int:
    """Apaga todas as rows ratings linkadas a ``order_id``.

    ⚠️ ratings.order_id é UUID — passar order_id stringified UUID-format.
    Necessário porque ``cleanup_test_orders`` apaga orders mas RLS pode
    bloquear cascade em ratings.
    """
    count_result = (
        admin_client.table("ratings")
        .select("id", count="exact")
        .eq("order_id", order_id)
        .execute()
    )
    n = count_result.count or 0
    if n > 0:
        admin_client.table("ratings").delete().eq("order_id", order_id).execute()
    return n


def reset_driver_avg(admin_client: Client, driver_id: str) -> None:
    """Reset ``drivers.avg_rating`` + ``ratings_count`` (setup limpo).

    Usado entre tests para garantir trigger calcula a partir de zero.
    """
    admin_client.table("drivers").update(
        {"avg_rating": None, "ratings_count": 0}
    ).eq("id", driver_id).execute()


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_rating_created(result: Dict[str, Any]) -> str:
    """Valida ``submit_rating`` devolveu rating_id; retorna o id."""
    rating_id = result.get('rating_id')
    assert rating_id, f"submit_rating sem rating_id: {result!r}"
    return rating_id


def assert_avg_updated(
    admin_client: Client,
    driver_id: str,
    expected_count: int,
    expected_avg_min: float,
    expected_avg_max: float,
) -> None:
    """Valida trigger ``_update_driver_avg_rating`` actualizou correctamente."""
    row = get_driver_avg_from_table(admin_client, driver_id)
    actual_count = row.get('ratings_count', 0) or 0
    actual_avg = float(row.get('avg_rating') or 0)
    assert actual_count == expected_count, (
        f"ratings_count esperado {expected_count}, recebido {actual_count}"
    )
    assert expected_avg_min <= actual_avg <= expected_avg_max, (
        f"avg_rating fora de range [{expected_avg_min}, {expected_avg_max}]: "
        f"recebido {actual_avg}"
    )


def assert_avg_unchanged(
    admin_client: Client,
    driver_id: str,
    expected_count: int,
) -> None:
    """Valida que rating private NÃO alterou avg/count."""
    row = get_driver_avg_from_table(admin_client, driver_id)
    actual_count = row.get('ratings_count', 0) or 0
    assert actual_count == expected_count, (
        f"ratings_count NÃO devia mudar (private): esperado {expected_count}, "
        f"recebido {actual_count}"
    )


def assert_tags_preserved(
    admin_client: Client,
    rating_id: str,
    expected_tags: List[str],
) -> None:
    """Valida que ``ratings.tags`` preserva input (ordem + valores)."""
    row = get_rating_row(admin_client, rating_id)
    actual = row.get('tags') or []
    assert actual == expected_tags, (
        f"tags esperadas {expected_tags!r}, recebidas {actual!r}"
    )


def assert_rated_at_set(admin_client: Client, order_id: str) -> None:
    """Valida que ``orders.rated_at`` foi preenchido (não-NULL)."""
    rated_at = get_order_rated_at(admin_client, order_id)
    assert rated_at is not None, (
        f"orders.rated_at devia estar preenchido após submit_rating, "
        f"recebido NULL para order_id={order_id}"
    )
