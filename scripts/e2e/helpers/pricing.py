"""Helpers para tests de pricing (Grupo 1 — T01-T08).

Adaptações vindas do audit 7E-B (Fase A) e validações MCP em prod:

- ``pricing_calculate`` retorna TABLE em EUR ``numeric`` (não jsonb cents).
  Em Python via supabase-py, ``result.data`` é uma lista de dicts; usamos
  ``rows[0]``.
- Asserções em EUR com tolerância ``EPSILON = 0.005`` (1/2 cent) para
  encaixar arredondamentos ``ROUND(numeric, 2)``.
- ``partner_service_fee_client`` e ``partner_commission_visible`` NÃO
  existem no return de ``pricing_calculate``. Derivam-se em
  ``create_order`` (=service_fee / =platform_commission quando
  ``is_partner_store=true``). Aqui validamos os campos raw.
- ``bag_fee`` no return é fixo: €0.30 restaurant, €0.00 outros — NÃO
  multiplica por ``bag_count`` (regra actual confirmada via MCP).
- Apartment delivery aplica DOIS surcharges em paralelo:
  - ``delivery_fee  += €1.50``
  - ``platform_commission += €0.50``
  (driver share +€1.00 não é validado aqui — entra em assert dedicada
  para Grupo Pricing-driver.)
- T06 ``storeShopping`` retorna ``bag_fee=0`` — documentado como
  BUG-7E-B-003 (regra antiga dizia €0.10/saco, comportamento actual €0).
"""
from typing import Any, Dict
from supabase import Client

EPSILON: float = 0.005  # 1/2 cent — tolera ROUND(numeric, 2) cumulativo


def calculate_pricing(
    admin_client: Client,
    service_type: str,
    subtotal_eur: float,
    distance_km: float,
    is_partner_store: bool = False,
    apartment_delivery: bool = False,
    is_stacked_partner: bool = False,
) -> Dict[str, Any]:
    """Chama RPC ``pricing_calculate`` e devolve a 1ª linha do TABLE.

    Args:
        admin_client: cliente Supabase com service_role.
        service_type: ``restaurant`` | ``storeShopping`` | ``carryGroceries``
            | ``sendPackage``.
        subtotal_eur: subtotal em EUR (numeric — ex.: ``10.00``).
        distance_km: distância em km (mínimo aplicado server-side é 1.0).
        is_partner_store: ``true`` activa caminho parceiro (10/5/5).
        apartment_delivery: ``true`` aplica surcharge total €1.50 + split
            (€0.50 platform, €1.00 driver).
        is_stacked_partner: bonus para entregas batched (Grupo 2).

    Returns:
        Dict com keys: ``delivery_fee``, ``service_fee``,
        ``platform_commission``, ``driver_earnings``, ``customer_total``,
        ``partner_markup_hidden``, ``bag_fee``.

    Raises:
        RuntimeError: se a RPC devolver 0 linhas (caso anormal).
    """
    result = admin_client.rpc(
        'pricing_calculate',
        {
            'p_service_type': service_type,
            'p_subtotal': subtotal_eur,
            'p_distance_km': distance_km,
            'p_is_partner_store': is_partner_store,
            'p_apartment_delivery': apartment_delivery,
            'p_is_stacked_partner': is_stacked_partner,
        },
    ).execute()
    rows = result.data
    if not rows:
        raise RuntimeError("pricing_calculate retornou 0 linhas — RPC partida")
    return rows[0]


def assert_partner_hybrid(breakdown: Dict[str, Any], subtotal_eur: float) -> None:
    """§2.4 parceiro híbrido: 10% visible + 5% hidden + 5% service ⇒ 20% total cliente.

    Valida os 3 campos raw devolvidos por ``pricing_calculate``:
    - ``service_fee`` = subtotal × 0.05
    - ``platform_commission`` = subtotal × 0.10 (visible)
    - ``partner_markup_hidden`` = subtotal × 0.05
    """
    expected_service = round(subtotal_eur * 0.05, 2)
    expected_commission = round(subtotal_eur * 0.10, 2)
    expected_hidden = round(subtotal_eur * 0.05, 2)
    assert abs(breakdown['service_fee'] - expected_service) < EPSILON, (
        f"service_fee parceiro esperado €{expected_service:.2f}, "
        f"recebido €{breakdown['service_fee']:.2f}"
    )
    assert abs(breakdown['platform_commission'] - expected_commission) < EPSILON, (
        f"platform_commission parceiro esperado €{expected_commission:.2f}, "
        f"recebido €{breakdown['platform_commission']:.2f}"
    )
    assert abs(breakdown['partner_markup_hidden'] - expected_hidden) < EPSILON, (
        f"partner_markup_hidden esperado €{expected_hidden:.2f}, "
        f"recebido €{breakdown['partner_markup_hidden']:.2f}"
    )


def assert_non_partner(breakdown: Dict[str, Any]) -> None:
    """§2.2 não-parceiro: ``service_fee`` é FIXO €2.50 (não percentagem).

    ``platform_commission`` aqui agrega ``non_partner_purchase_fee`` (€2.50)
    + ``apartment_platform_share`` (€0.50 quando aplicável). Validamos
    apenas o piso (≥ €2.50) — apartment é validado em
    ``assert_apartment_surcharge``.
    """
    assert abs(breakdown['service_fee'] - 2.50) < EPSILON, (
        f"service_fee não-parceiro esperado €2.50 fixo, "
        f"recebido €{breakdown['service_fee']:.2f}"
    )
    assert breakdown['platform_commission'] >= 2.50 - EPSILON, (
        f"platform_commission não-parceiro esperado ≥ €2.50, "
        f"recebido €{breakdown['platform_commission']:.2f}"
    )
    assert breakdown['partner_markup_hidden'] == 0, (
        f"partner_markup_hidden deve ser €0 em não-parceiro, "
        f"recebido €{breakdown['partner_markup_hidden']:.2f}"
    )


def assert_delivery_fee(
    breakdown: Dict[str, Any],
    distance_km: float,
    apartment: bool = False,
) -> None:
    """§2.1 delivery: €2.50 base ≤4km, +€0.50/km extra acima de 4km.

    Apartment surcharge (+€1.50) é somado quando ``apartment=true``.
    Distância mínima aplicada server-side é 1.0 km — aqui assumimos
    ``distance_km ≥ 1`` (cuidado em testes que passem 0).
    """
    expected = 2.50
    if distance_km > 4:
        expected += round((distance_km - 4) * 0.50, 2)
    if apartment:
        expected += 1.50
    assert abs(breakdown['delivery_fee'] - expected) < EPSILON, (
        f"delivery_fee esperado €{expected:.2f} "
        f"(distance={distance_km}km, apt={apartment}), "
        f"recebido €{breakdown['delivery_fee']:.2f}"
    )


def assert_apartment_surcharge(
    breakdown_no_apt: Dict[str, Any],
    breakdown_with_apt: Dict[str, Any],
) -> None:
    """§2.x apartment delivery: aplica DOIS surcharges em paralelo.

    Validado via MCP em prod (5 cenários):
    - ``delivery_fee`` aumenta em **€1.50** (apartment_surcharge_total)
    - ``platform_commission`` aumenta em **€0.50** (apartment_platform_share)

    O driver_share (+€1.00) entra em ``driver_earnings`` mas não é
    validado aqui — assert dedicada em testes T07/T08.

    Args:
        breakdown_no_apt: breakdown obtido com ``apartment_delivery=False``.
        breakdown_with_apt: breakdown obtido com ``apartment_delivery=True``
            mantendo todos os outros parâmetros constantes.
    """
    delivery_diff = breakdown_with_apt['delivery_fee'] - breakdown_no_apt['delivery_fee']
    commission_diff = (
        breakdown_with_apt['platform_commission']
        - breakdown_no_apt['platform_commission']
    )
    assert abs(delivery_diff - 1.50) < EPSILON, (
        f"Apartment delivery surcharge esperado €1.50, "
        f"recebido €{delivery_diff:.2f}"
    )
    assert abs(commission_diff - 0.50) < EPSILON, (
        f"Apartment commission surcharge esperado €0.50, "
        f"recebido €{commission_diff:.2f}"
    )


def assert_bag_fee_restaurant_fixed_30c(breakdown: Dict[str, Any]) -> None:
    """§2.x bag fee restaurante: €0.30 FIXO (não multiplica por bag_count).

    Comportamento actual confirmado via MCP — é a regra documentada em
    ``platform_settings.bag_fee_restaurant_cents = 30``. A interpretação
    inicial "€0.30 × bag_count" do prompt original era leitura errada;
    o comportamento actual está correcto e estável.
    """
    assert abs(breakdown['bag_fee'] - 0.30) < EPSILON, (
        f"bag_fee restaurante esperado €0.30 fixo, "
        f"recebido €{breakdown['bag_fee']:.2f}"
    )


def assert_bag_fee_zero_market(breakdown: Dict[str, Any]) -> None:
    """§2.x BUG-7E-B-003: bag_fee em ``storeShopping`` retorna €0 (regra antiga dizia €0.10/saco).

    Test valida o comportamento ACTUAL (€0). Entry em
    ``BUGS_FOUND.md`` cobre a divergência da regra de negócio para
    triagem em sessão futura.
    """
    assert breakdown['bag_fee'] == 0, (
        f"bag_fee storeShopping esperado €0.00 ACTUAL "
        f"(BUG-7E-B-003 — regra antiga dizia €0.10/saco), "
        f"recebido €{breakdown['bag_fee']:.2f}"
    )


def assert_driver_earnings_min(
    breakdown: Dict[str, Any],
    min_eur: float,
) -> None:
    """§3.1 driver: validação de piso mínimo (base + km × per_km).

    Settings em prod: base €3.80 + €0.20/km. Para distance=3km e
    non-partner adicionar profit_share. Aqui só validamos piso para
    permitir margem ao caminho non-partner (que tem cálculo dinâmico
    profit_share dependente de markup).
    """
    assert breakdown['driver_earnings'] >= min_eur - EPSILON, (
        f"driver_earnings esperado ≥ €{min_eur:.2f}, "
        f"recebido €{breakdown['driver_earnings']:.2f}"
    )
