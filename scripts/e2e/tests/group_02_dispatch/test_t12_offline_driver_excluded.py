"""T12 — Driver offline NÃO entra no pool de candidatos.

Cenário: Driver_C é desactivado (``is_online=false``); A e B continuam
online. Pickup é colocado perto de C ``(40.5300, -7.2600)`` — C seria o
mais próximo, mas o filtro ``is_online=true`` em ``find_nearest_driver``
exclui-o.

Esperado: ``nearest != Driver_C``.

Cleanup: ``dispatch_setup`` teardown chama ``deactivate_test_drivers``
e ``reset_test_drivers_gps`` — isso reactiva todos no fim. Por isso
não é necessário re-activar C explicitamente neste test.
"""
from helpers.dispatch import find_nearest_driver


def test_t12_offline_driver_not_chosen(admin_client, dispatch_setup):
    """Desactivar C + pickup perto de C → nearest é A ou B."""
    admin_client.table("drivers").update(
        {"is_online": False}
    ).eq("name", "E2E_TEST_Driver_C").execute()

    nearest = find_nearest_driver(
        admin_client,
        pickup_lat=40.5300,
        pickup_lng=-7.2600,
        max_radius_km=5.0,
    )
    assert nearest is not None, "Esperava A ou B disponíveis"
    assert nearest['name'] != 'E2E_TEST_Driver_C', (
        f"Driver_C deveria estar excluído (offline), recebido {nearest['name']!r}"
    )
    assert nearest['name'] in ('E2E_TEST_Driver_A', 'E2E_TEST_Driver_B')
