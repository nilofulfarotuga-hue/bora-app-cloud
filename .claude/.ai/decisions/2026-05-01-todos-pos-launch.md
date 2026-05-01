# TODOs Pós-Launch — 2026-05-01

Lista de itens identificados durante a sessão BUG 16+17+18 que NÃO bloqueiam launch e ficam para depois do produto estar estável.

---

## BUG 24 — Admin reset foto estafeta (MÉDIO)

Admin pode editar nome/phone/veículo/matrícula/IBAN/NIF do estafeta em [admin_driver_detail_screen.dart](../../lib/screens/admin/admin_driver_detail_screen.dart) (`_EditDriverSheet` L258, `updateDriver()` chamada com 6 campos), mas **NÃO tem botão para resetar/upload da `photo_url`**. Driver pode mudar a foto via [profile_screen.dart](../../lib/screens/profile_screen.dart), mas se a foto for ofensiva/corrompida, o admin não consegue intervir.

**Fix proposto:** adicionar widget photo editor em `_EditDriverSheet` ou novo botão "Resetar foto" em `_OverviewTab` que permita ao admin:
- Limpar `photo_url` (volta para iniciais)
- Substituir por upload manual

**Risk:** LOW (cosmético + moderação)
**Tempo estimado:** ~30 min
**Audit:** registar em `admin_audit_log` com action='driver_photo_reset'

---

## Tech-debt — Alinhar shell estafeta com cliente (BAIXO)

[driver_home_screen.dart](../../lib/screens/driver_home_screen.dart) usa Scaffold + AppBar simples + `Navigator.push` para navegar entre telas (driver_map default + AppBar icons para Perfil/Ganhos), enquanto [client_main_screen.dart](../../lib/screens/client_main_screen.dart) usa IndexedStack + `BoraBottomNav` com 3 tabs (Início / Pedidos / Perfil).

Inconsistência arquitectural mas funcional. O fix actual (Opção 2 — profile icon no AppBar) preserva o shell driver tal como estava, evitando risco de regressão sobre dispatch/GPS/lifecycle do mapa (que é PRONTO no launch checklist).

**Refactor proposto:** Driver shell para IndexedStack + BoraBottomNav com 3 tabs:
- Tab 0: `DriverMapScreen` (Mapa)
- Tab 1: `DriverEarningsScreen` (Ganhos)
- Tab 2: `ProfileScreen` (Perfil)

**Vantagens:**
- Padrão unificado driver↔cliente
- Tabs persistentes (vs Navigator.push) preservam estado de cada tela
- UX mais familiar

**Risco MÉDIO:** toca lifecycle do mapa (`_listenToDriverLocation`, `WidgetsBindingObserver`), GPS tracking idle, realtime channels do `DriverStore`/`OrderStore`. Risco de regressão BUG-002 (realtime sync) ou BUG-016 (GPS unificado).

**Pré-requisitos:**
- Launch estabilizado (sem incidentes 1 semana)
- TEST_CHECKLIST.md driver flow re-validado pós-refactor
- Branch separada draft + smoke E2E completo

**Tempo estimado:** 1-2h + 30min smoke

---

## Tech-debt referenciado em decisão paralela

Ver [2026-05-01-tech-debt-financial-bypass-guc.md](2026-05-01-tech-debt-financial-bypass-guc.md) — refactor do trigger `enforce_financial_immutability` para usar `current_user='postgres'` em vez de GUC `app.financial_bypass`. Pós-launch.

---

## Critério para começar a executar

Estes TODOs ficam parados até:
1. Launch público a primeiros utilizadores reais ✓
2. 7 dias sem incidentes críticos no flow de pagamento ✓
3. Stripe LIVE validado em produção real ✓
4. GPS BUG-016 fix testado com 2 dispositivos simultâneos ✓

Quando todos os 4 acima forem verdade, abrir uma issue (ou esta lista) para priorização.
