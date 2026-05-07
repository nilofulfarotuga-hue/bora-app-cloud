"""T09 — ``find_nearest_driver`` retorna driver mais próximo do pickup.

Pickup em Guarda centro ``(40.5378, -7.2682)``:
- Driver_A em ``(40.5378, -7.2682)`` → 0 km ✅ escolhido.
- Driver_B em ``(40.5450, -7.2750)`` → ~1 km.
- Driver_C em ``(40.5300, -7.2600)`` → ~1 km.

Helper filtra ``E2E_TEST_%`` + ``is_online=true`` + ``haversine ≤ raio``
e devolve candidato com menor ``distance_km``.
"""
from helpers.dispatch import find_nearest_driver


def test_t09_nearest_is_driver_a_at_guarda_center(admin_client, dispatch_setup):
    """3 drivers online com GPS distinct → escolhe Driver_A (0 km)."""
    nearest = find_nearest_driver(
        admin_client,
        pickup_lat=40.5378,
        pickup_lng=-7.2682,
        max_radius_km=5.0,
    )
    assert nearest is not None, "Esperava encontrar driver online no raio 5 km"
    assert nearest['name'] == 'E2E_TEST_Driver_A', (
        f"Esperava Driver_A (0 km), recebido {nearest['name']!r} "
        f"a {nearest.get('distance_km')} km"
    )
    assert nearest['distance_km'] < 0.1, (
        f"Distância esperada ~0 km, recebido {nearest['distance_km']} km"
    )
