# Relatório de Fecho — Campanha Bugfix 2026-04-19

**Projecto:** Bora App (Flutter + Supabase)
**Data:** 2026-04-19
**Modo:** Protecção Total (CEO-AI orchestrator)
**Status final:** ✅ FASES 1–4 concluídas, 0 erros / 0 warnings

---

## 1. Resumo Executivo

Campanha de 3 fases de correcção (1: dispatch/dados, 2: fluxo cliente, 3: polimento UI) seguida de uma fase de validação final (4). Todas as alterações foram **cirúrgicas, fora das zonas protegidas** (pricing_service, dispatch-engine, Stripe, bora_tokens, driver_capacity_service, finalizePurchase, fotos reais).

Resultado: app pronta para teste fim-a-fim do Danilo. Nenhuma regressão detectada por `flutter analyze` ou pelos checks SQL de integridade Supabase.

---

## 2. Bugs Resolvidos por Fase

### FASE 1 — Dispatch & Dados (concluída antes desta sessão)
- Sincronização realtime de ofertas via `current_driver_offer_id`.
- Correcções nos modelos/stores para casts UUID↔TEXT (legacy `assigned_driver_id`).
- Endurecimento de `_advanceStatus` (comparação por ID, não referência).

### FASE 2 — Fluxo Cliente (concluída antes desta sessão)
- Polimento das screens de checkout, carrinho e detalhe de produto.
- Ajustes de copy e estados vazios.
- Correcção de bordas/separadores e contraste pontual.

### FASE 3 — Polimento UI (esta sessão)

| ID | Bug | Ficheiro | Correcção |
|----|-----|----------|-----------|
| V1 | Setas "voltar" invisíveis (branco-em-branco) em screens de loja | `stores_screen.dart`, `store_categories_screen.dart`, `store_products_screen.dart` | AppBar: `foregroundColor: AppColors.primary` (#1B5E20) + `iconTheme(size: 26)` |
| V2 | Cards de categoria de supermercado pequenos / ícone esmagado | `store_categories_screen.dart` | `childAspectRatio` 1.4→1.0; `_CategoryCard` reescrito com `Stack` + `FractionallySizedBox(0.62)` + gradient bottom-overlay para legibilidade |
| V3 | Popup branco tapava o card laranja inline no 1º pedido único | `driver_home_screen.dart` (`_showNewOrderDialog`) | Early-return quando `store.myOrders.isEmpty` — popup só aparece com ≥1 pedido activo (stacking 2+) |
| V4 | Contraste branco-em-cinzento-claro no painel do estafeta | `driver_earnings_screen.dart` (`_StatChip`), `driver_home_screen.dart` (`_buildEmptyState`) | Background `Colors.white` + `boxShadow` suave; texto `grey.shade700` no empty state |

### FASE 4 — Validação Final (esta sessão, sem alterações de código)

| Verificação | Resultado |
|-------------|-----------|
| V1 — Zonas protegidas intactas (mtime) | ✅ pricing_service 2026-04-17, dispatch-engine 2026-04-15, payment_service 2026-04-17, driver_capacity_service intacto, pubspec 2026-04-15 — **todas anteriores a 2026-04-19** |
| V2 — `flutter analyze` | ✅ 0 errors / 0 warnings nos 5 ficheiros da Fase 3 (3 info-only pré-existentes em `directions_service_web.dart` e `place_autocomplete_service_web.dart`, não modificados) |
| V3 — Integridade Supabase (MCP) | ✅ 13/13 checks PASS via CTE; RPC `search_products('cafe', NULL, 5)` devolve 5 linhas |
| V4 — Ficheiros modificados na campanha | ✅ 15 ficheiros, todos fora de zonas protegidas |
| V5 — Imports / dependências | ✅ `pubspec.yaml` e `pubspec.lock` intactos; sem novas dependências |

---

## 3. Ficheiros Modificados (Campanha Completa)

**Fase 3 (esta sessão — 5 ficheiros):**
- `lib/screens/stores_screen.dart`
- `lib/screens/store_categories_screen.dart`
- `lib/screens/store_products_screen.dart`
- `lib/screens/driver_home_screen.dart`
- `lib/screens/driver_earnings_screen.dart`

**Fases 1 + 2 (sessões anteriores — 10 ficheiros):**
- `lib/widgets/bora/bora_app_bar.dart`
- `lib/config/app_theme.dart`
- `lib/screens/profile_screen.dart`
- `lib/screens/product_detail_screen.dart`
- + alterações nas stores/models confirmadas pelo CEO-AI nas fases anteriores.

Total: **15 ficheiros** modificados desde 2026-04-19, **zero** dentro das zonas protegidas.

---

## 4. Migrations Aplicadas

Nenhuma migration nova nesta campanha. Confirmado via `mcp__supabase__list_migrations`. Schema estável.

---

## 5. Zonas Protegidas Verificadas Intactas

| Zona | mtime | Status |
|------|-------|--------|
| `lib/services/pricing_service.dart` | 2026-04-17 | ✅ Intacta |
| `supabase/functions/dispatch-engine/` | 2026-04-15 | ✅ Intacta |
| `lib/services/payment_service.dart` (Stripe) | 2026-04-17 | ✅ Intacta |
| Triggers `bora_tokens` (DB) | — | ✅ Schema inalterado |
| `lib/services/driver_capacity_service.dart` | (não tocado) | ✅ Intacta |
| `finalizePurchase` (CartStore) | (não tocado) | ✅ Intacta |
| Fotos reais (produtos/pratos) | (não tocadas) | ✅ Intactas |

---

## 6. Pendências (Launch Readiness)

Do checklist do `SKILL.md` — **bloqueadores remanescentes**:

- [ ] **Teste fim-a-fim com dados reais** (TEST_CHECKLIST.md) — depende do Danilo
- [ ] **Push notifications**: adicionar `google-services.json` + `GoogleService-Info.plist` + secrets Supabase + deploy `notify-driver`
- [ ] **Pagamento real Stripe**: validação test mode → live mode

Tudo o resto do checklist já está ✅ marcado pelo SKILL.

---

## 7. Riscos Conhecidos

1. **Realtime sync entre dispositivos** — corrigido na Fase 1 (canal `_driverActiveNotifyChannel`), mas precisa de validação real com 2 telemóveis simultâneos.
2. **Push em background** — drivers offline não recebem ofertas até integração Firebase concluída.
3. **Stripe live** — `BACKEND_BASE_URL` precisa ser configurado em build de produção (`--dart-define`).

---

## 8. Instruções para o Danilo Testar

1. `flutter clean && flutter pub get && flutter run`
2. **Cliente**: abrir loja → confirmar setas verdes visíveis no AppBar
3. **Cliente**: entrar numa loja com categorias → confirmar grelha de cards quadrados grandes com ícone bem visível
4. **Estafeta**: simular 1ª oferta → deve aparecer **só** o card laranja inline (sem popup branco)
5. **Estafeta**: simular 2ª oferta sobre activo → popup branco deve aparecer normalmente
6. **Estafeta**: ir a Ganhos → confirmar contraste dos chips (fundo branco com sombra suave)
7. **Estafeta**: ver empty state quando sem pedidos → texto cinzento legível em fundo branco

Se algum passo falhar → reportar ID do bug (V1/V2/V3/V4) para correcção cirúrgica.

---

**Fim do relatório.**
