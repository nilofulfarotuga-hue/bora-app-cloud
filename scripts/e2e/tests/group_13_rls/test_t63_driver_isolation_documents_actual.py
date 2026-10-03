"""T63 — RLS drivers SELECT (DOCUMENT_ACTUAL — bug RLS frouxa).

⚠️ Descoberta MCP: ``drivers_select_authenticated`` policy
qual=``auth.uid() IS NOT NULL`` → QUALQUER driver autenticado vê
TODOS os drivers (BUG real, não filtra por próprio).

Pattern DOCUMENT_ACTUAL:
- Test PASSA validando comportamento ACTUAL (vê outros drivers).
- Se RLS for apertada algum dia, este test FAIL e força revisão.
- BUG-7E-D-001 registado em BUGS_FOUND.md.

Cenário:
1. Login como driver (e2e_partner_a... wait, drivers usam emails sintéticos).
2. SELECT drivers → vê >1 driver (todos os 3 E2E + outros).
3. Documenta gap.
"""
import pytest

from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.rls import assert_query_returns_others, select_visible_drivers


def test_t63_driver_sees_all_drivers_documents_bug(
    admin_client,
    driver_a,
    driver_b,
    dispatch_setup,
):
    """Driver A logged sees other drivers (RLS frouxa — BUG-7E-D-001)."""
    # Driver A authed via email sintético
    driver_a_email = '910000901@driver.bora.app'
    driver_a_authed = login_as_user(driver_a_email, TEST_PASSWORD)

    visible = select_visible_drivers(driver_a_authed, limit=20)

    # ACTUAL: vê ≥2 drivers (próprio + outros)
    assert len(visible) >= 2, (
        f"esperava ≥2 drivers visíveis (RLS frouxa documentada como "
        f"BUG-7E-D-001), recebido {len(visible)}. Se este test FAIL com "
        f"len==1: RLS apertada server-side ✅ (actualizar test + fechar bug)."
    )

    # Confirmar que vê drivers alheios (não só o próprio)
    foreign = [d for d in visible if d.get('id') != driver_a['id']]
    assert foreign, (
        f"esperava drivers alheios visíveis (BUG-7E-D-001 ACTUAL), "
        f"recebido só próprios. Visible: {visible!r}"
    )
