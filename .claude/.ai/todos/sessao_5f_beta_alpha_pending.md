# 5F-β-α — TODOs Pendentes (pós-commit)

**Data:** 2026-05-07
**Status:** ✅ Sessão 5F-β-α + fix1 completas e committadas

---

## #1 ✅ RESOLVIDO via 5F-β-α-fix1

Diagnóstico inicial (.env stale relativo a platform key) **não se confirmou**.
Solução estrutural aplicada: Edge Fn refactor para `verify_jwt=true` +
JWT payload role check. À prova de rotação de key. Smoke S6 PASS.

---

## #2 — FUTURO: Refactor 7 update-* cron jobs

**Detectado em A3 (fora escopo 5F-β-α):**
- update-mercadona, update-continente, update-pingodoce, update-lidl, update-auchan, update-intermarche, update-restaurants

Usam `current_setting('app.settings.service_role_key', true)` (formato ANTIGO com `.settings.`). Provavelmente quebrados há tempo.

**Sessão separada:**
1. Audit `cron.job_run_details` (últimos 30d) — confirmar status_code 401/403 ou execuções a falhar
2. Refactor todos para vault (mesmo padrão B4)
3. Smoke fire-and-forget cada um
4. Pode ser batched numa sessão "5F-β-β cron jobs cleanup"

---

## #3 — FUTURO: Anonymization JS drift (5D)

`analyze-conversations` Edge Fn tem regex anonymization que pode divergir do helper SQL `_anonymize_pii`. Continua TODO desde 5F.

---

## #4 — OPCIONAL: Atualizar `scripts/rag/.env`

Copiar fresh service_role_key também para `scripts/rag/.env` (mesmo valor que vault). Mantém dev local em sync.
