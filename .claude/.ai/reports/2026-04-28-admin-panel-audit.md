# Auditoria Painel Admin — Bora App

> **Data:** 2026-04-28
> **Modo:** PROTECÇÃO TOTAL · FASE 1 (relatório, zero código)
> **Auditor:** CEO-AI orchestrator
> **Project Supabase:** `ojy***rna`
> **Admin actual:** `nilofulfarotuga@gmail.com` (gate por email allowlist hardcoded)
> **Objectivo:** Diagnóstico exaustivo + plano para painel de classe mundial (Uber / Glovo / iFood)

---

## 1.1 — Mapeamento exaustivo do que existe HOJE

### Árvore de ficheiros admin

```
bora_app/
├── lib/
│   ├── main.dart                                            (rota '/admin' L11+L157)
│   ├── screens/
│   │   ├── profile_screen.dart                              (L420-441 — gate email allowlist)
│   │   └── admin/
│   │       ├── admin_dashboard_screen.dart                  (482 L)
│   │       ├── admin_driver_approval_screen.dart            (508 L)
│   │       ├── admin_drivers_screen.dart                    (265 L)
│   │       ├── admin_orders_screen.dart                     (269 L)
│   │       ├── admin_driver_payments_screen.dart            (290 L)
│   │       ├── admin_partners_screen.dart                   (143 L)
│   │       ├── admin_ratings_screen.dart                    (141 L)
│   │       └── admin_reservations_screen.dart               (93 L)
│   └── (sem) views/admin/   ← NÃO EXISTE
│   └── (sem) stores/admin/  ← NÃO EXISTE
│   └── (sem) services/admin_service.dart  ← NÃO EXISTE
└── supabase/
    ├── migrations/
    │   ├── 20260409000003_admin_dashboard_metrics.sql       (RPC agregados)
    │   └── 20260424100000_set_admin_role.sql                (define bora_role='admin' em user_metadata)
    └── functions/                                           (NENHUMA chamada pelo admin)
```

**Total código admin:** 2 191 linhas Flutter, 1 RPC dedicada, 0 stores, 0 services, 0 widgets reutilizáveis, 0 testes.

### Tabela — ecrã × dados × acções

| Ecrã | RPC / Tabela | Botões / Acções existentes | Notas |
|---|---|---|---|
| `admin_dashboard_screen` | RPC `admin_dashboard_metrics()` | Refresh · 7 nav cards (Pedidos · Estafetas · Aprovações · Pagamentos · Parceiros · Reservas · Avaliações) | KPIs: `platform_revenue`, `orders_today`, `drivers_payable`, `restaurants_payable` + gráfico daily_orders |
| `admin_driver_approval_screen` | `from('drivers')` SELECT/UPDATE | 3 tabs (Pendentes/Aprovados/Rejeitados) · Aprovar (com validação obrigatória de docs) · Rejeitar (com motivo dialog) · Detail bottom sheet (read-only) · Fullscreen image viewer | **BUG 1** L95-103 |
| `admin_drivers_screen` | `from('drivers')` SELECT · `from('driver_balances')` | Refresh · Detail bottom sheet · Aprovar/Rejeitar **só para pending** | **BUG 2** L106-135 |
| `admin_orders_screen` | `from('orders')` SELECT/UPDATE | Filtro por status (chip) · Cancelar (set status='rejected' direct) | **BUG 3** L67-95 — sem reason, sem refund, sem reatribuir |
| `admin_driver_payments_screen` | `from('v_driver_weekly_earnings')` · `from('driver_transactions')` | Refresh · Read-only | Sem export, sem "marcar como pago", sem trigger de payout |
| `admin_partners_screen` | `from('restaurants')` SELECT/UPDATE | Refresh · Switch is_active | **BUG 4** — coluna `is_active` NÃO existe! |
| `admin_ratings_screen` | `from('ratings')` SELECT | Filtro "só denúncias" · Read-only | Sem moderação, sem responder, sem banir |
| `admin_reservations_screen` | `from('reservations')` SELECT | Refresh | 100% read-only, zero acções |

### RPCs disponíveis na DB (36) — usadas pelo admin

Apenas **1** das 36 RPCs é usada pelo admin: `admin_dashboard_metrics`. As restantes (`pricing_calculate`, `apply_driver_cash_settlement`, `auto_payout_pending`, `bora_dispatch_maintenance`, `create_payout`, `request_driver_help`, `invoke_dispatch_engine`, `recompute_user_balance`, etc.) **não são chamadas pelo admin**.

### Edge Functions (16) — usadas pelo admin

**Zero.** Nenhuma das Edge Functions (`refund`, `dispatch-engine`, `notify-client`, `notify-driver`, `notify-partner`, `charge-extra`, `client-cancel-order`, `delete-account`, `update-products`) é chamada pelo painel admin. → Quando admin cancela um pedido **não há reembolso Stripe, não há cleanup do dispatch, não há notificação ao cliente/estafeta/parceiro**.

### Tabelas tocadas pelo admin

`drivers`, `orders`, `restaurants`, `ratings`, `reservations`, `driver_balances`, `driver_transactions`, `v_driver_weekly_earnings`. Não toca: `users` (clientes), `bora_tokens`, `ledger_entries`, `payouts`, `messages`, `products`, `order_financials`, `mbway_debug_errors`.

### Gate de acesso

```dart
// profile_screen.dart L421-422
if (user?.email == 'nilofulfarotuga@gmail.com' ||
    user?.email == 'nilofulfaro@gmail.com')
```

⚠️ **Frágil:** allowlist hardcoded em código cliente. A migration `20260424100000_set_admin_role.sql` define `bora_role='admin'` no JWT mas o painel não verifica. RLS policies não distinguem admin de utilizador normal nas tabelas `drivers`/`orders`/`restaurants`.

---

## 1.2 — Diagnóstico secção a secção

### a) Aprovação de estafetas (Pendentes)
- ✅ Lista carrega (API logs `200 GET /drivers`)
- ✅ Botão Rejeitar funciona com motivo dialog
- ✅ Detail bottom sheet mostra fotos + IBAN + docs
- 🐛 **BUG 1** Aprovar aborta se faltar doc, sem override admin
- ❌ Sem opção "aprovar com observação" / "pedir mais docs ao estafeta"
- ❌ Sem comparação visual com docs anteriores
- ⚠️ Bottom sheet não tem botões de acção (admin tem que fechar e voltar à lista)
- ❌ Sem auditoria de quem aprovou (apenas grava `approved_by` mas não há ecrã para ver)

### b) Estafetas aprovados (gestão pós-aprovação)
- ✅ Lista carrega com badge online/offline
- 🐛 **BUG 2** Detail só tem 3 linhas (telefone, veículo, saldo) e ZERO acções para aprovados
- ❌ Sem banir / desbanir
- ❌ Sem remover (soft-delete)
- ❌ Sem reactivar (após rejeição)
- ❌ Sem editar dados (corrigir IBAN, telefone, etc.)
- ❌ Sem forçar logout
- ❌ Sem enviar mensagem
- ❌ Sem histórico de pedidos do estafeta
- ❌ Sem score / rating agregado
- ❌ Sem ver localização actual no mapa
- ❌ Sem ver token balance

### c) Estafetas rejeitados
- ✅ Lista carrega
- ✅ Detail mostra motivo de rejeição
- ❌ Sem reabrir candidatura
- ❌ Sem editar motivo
- ❌ Sem contactar estafeta para correcção

### d) Gestão de pedidos
- ✅ Lista carrega com filtro por status (created/preparing/callingDriver/driverAccepted/pickedUp/onTheWay/delivered/rejected)
- ✅ Cancelar funciona (mas só seta status='rejected')
- 🐛 **BUG 3** Cancelar é destrutivo: sem motivo, sem refund Stripe, sem notify-client, sem cleanup do `current_driver_offer_id`, sem libertar estafeta
- ❌ Sem pesquisa (id, cliente, estafeta, parceiro)
- ❌ Sem filtro por data, valor, payment_method, vendor
- ❌ Sem detalhe completo (timeline de eventos, items, totals breakdown)
- ❌ Sem reatribuir estafeta
- ❌ Sem forçar próximo estado (admin override)
- ❌ Sem refund parcial / total
- ❌ Sem editar valores (corrigir extra_charge, tip, etc.)
- ❌ Sem contactar cliente / estafeta / parceiro
- ❌ Sem mapa em tempo real
- ❌ Sem vista kanban
- ❌ Sem export CSV
- ⚠️ Lista limitada a 100 (sem paginação)

### e) Pagamentos / Pagamentos de Estafetas
- ✅ Mostra `v_driver_weekly_earnings`
- ✅ Mostra conversão de tokens da semana
- ❌ Sem botão "marcar como pago" / criar `payout`
- ❌ Sem trigger de `auto_payout_pending` RPC
- ❌ Sem histórico de payouts
- ❌ Sem export para banca (SEPA / IBAN)
- ❌ Sem reconciliação Stripe / MB Way / dinheiro
- ❌ Sem reembolso a clientes
- ❌ Sem fees por parceiro (10%/5%/5%)
- ❌ Sem relatórios fiscais (IVA, recibos)

### f) Parceiros
- 🐛 **BUG 4** Toggle escreve em coluna inexistente `is_active` → falha silenciosa (snackbar de erro)
- ❌ Sem aprovação de novos parceiros (UI dedicada)
- ❌ Sem editar comissão por parceiro (10%+5%+5% fixo, não editável)
- ❌ Sem horários
- ❌ Sem pausar / reabrir parceiro
- ❌ Sem editar produtos / preços / fotos
- ❌ Sem importação massa CSV
- ❌ Sem stats por parceiro (GMV, pedidos, ticket médio)

### g) Avaliações
- ✅ Lista carrega
- ✅ Filtro "só denúncias"
- ❌ Sem responder à review
- ❌ Sem ocultar / moderar review
- ❌ Sem banir o autor
- ❌ Sem agrupar por estafeta / parceiro
- ❌ Sem export

### h) Reservas
- ✅ Lista carrega (limit 200)
- ❌ Acções zero — apenas leitura

### Funcionalidades AUSENTES no painel admin (categoria inteira)

- ❌ Gestão de **clientes** (sem ecrã!) — não há lista, detalhe, ban, tokens, suporte
- ❌ Gestão de **produtos / catálogo** (sem ecrã!) — não há editar produto, preço, foto, stock, importação
- ❌ **Promoções / cupões** (sem ecrã!) — não há criar campanha, primeiro pedido grátis, etc.
- ❌ Gestão de **tokens** (sem ecrã!) — não há ver saldo, ajustar manualmente, log
- ❌ **Suporte / chat** (sem ecrã!) — não há inbox de tickets, chat com utilizadores
- ❌ **Notificações / push broadcast** (sem ecrã!) — apesar das 3 Edge Functions notify-*
- ❌ **Auditoria / logs** (sem ecrã!) — não há audit_log table nem visualização
- ❌ **Configurações globais** (sem ecrã!) — taxas, fee, cash max, comissões hardcoded em código
- ❌ **Mapa operacional tempo real** (sem ecrã!) — apesar de drivers terem lat/lng
- ❌ **Permissões / roles** — só 1 admin email, sem suporte/financeiro/super-admin

---

## 1.3 — BUGS CONFIRMADOS (com logs Supabase)

### BUG 1 — Aprovação de estafeta com doc em falta volta em silêncio
- **Ficheiro:** `lib/screens/admin/admin_driver_approval_screen.dart`
- **Linhas:** 70-103
- **Comportamento:** `_approve(driverId)` valida `photo_url`, `document_photo_url`, `document_number`, `vehicle_photo_url` (se não bicycle). Se faltar um → snackbar "Falta: ..." + `return`. Sem caminho de override.
- **Evidência logs API:** `PATCH 204 /rest/v1/drivers?id=eq.519d0782...` (só executa quando docs completos). Quando docs faltam **não há request** → confirma o early return.
- **User expectation:** Admin (poder total) deve conseguir aprovar SEMPRE, com aviso mas sem bloqueio.
- **Snackbar invisível:** se contexto perder validade entre a clique no IconButton (L221) e o showSnackBar (L97), nada visível ao admin → percepção de "voltou em silêncio".

### BUG 2 — Click em estafeta aprovado não abre detalhe útil / sem acções
- **Ficheiros:** `lib/screens/admin/admin_drivers_screen.dart` (L77-140) **e** `admin_driver_approval_screen.dart` (L231-240)
- **Comportamento drivers_screen:** Modal só mostra nome + telefone + veículo + saldo. Botões Aprovar/Rejeitar guardados num `if (approval_status == 'pending')` (L106). Para aprovados → modal "vazio".
- **Comportamento approval_screen:** Tabs "Aprovados" e "Rejeitados" passam `_DriverList` SEM `actions:` parâmetro (L231-240) → sem botões nos rows. Detail sheet `_DriverDetailSheet` (L332-478) é puramente leitura.
- **Faltam:** banir, desbanir, reactivar, remover, editar IBAN/telefone, forçar logout, enviar mensagem, histórico de pedidos, infracções, score, mapa.

### BUG 3 — Acções de admin em pedidos incompletas
- **Ficheiro:** `lib/screens/admin/admin_orders_screen.dart`
- **Linhas:** 67-95 (`_cancel`)
- **Comportamento:** Único botão é "Cancelar" → `update({'status': 'rejected'})`. Sem motivo, sem reembolso, sem chamar Edge Function `refund`, sem `notify-client/driver/partner`, sem libertar `current_driver_offer_id`/`assigned_driver_id`.
- **Evidência logs API:** `PATCH 204 /rest/v1/orders?id=eq...` mas zero chamadas `/rest/v1/rpc/refund` ou `functions/v1/refund` no log window.
- **Faltam:** reatribuir estafeta, forçar próximo estado, refund parcial/total, editar valores, contactar partes, timeline, mapa, kanban, pesquisa por id/cliente/estafeta.

### BUG 4 (NOVO descoberto) — Toggle "Activar parceiro" escreve coluna inexistente
- **Ficheiro:** `lib/screens/admin/admin_partners_screen.dart`
- **Linhas:** 32 (SELECT), 54 (UPDATE)
- **Comportamento:** Lê e escreve `is_active` em `restaurants`. Confirmado por SQL: coluna não existe em `public.restaurants` (existem `is_partner` e `is_online`).
- **Resultado:** Switch nunca persiste. Admin vê snackbar "Erro: ..." (L58-60) ou nada se erro silenciado por RLS.

### BUG 5 (INFRA, fora de admin mas relevante) — `bora_dispatch_maintenance` falha cron a cada 2 min
- **Evidência logs Postgres:** Errors recorrentes (timestamp 1777399680025000, 1777399800024000, ...): `COALESCE could not convert type uuid[] to text[]` durante `cron job 22 starting: SELECT public.bora_dispatch_maintenance()`.
- **Impacto:** Manutenção do dispatch (timeouts, reset de offers expiradas) provavelmente quebrada em produção. **Não é admin-bug mas afecta operação.** Recomenda spawn de task separada.

---

## 1.4 — GAP ANALYSIS — Bora vs Uber / Glovo / iFood

Score actual estimado: **18/100** (vs Uber Eats Manager 95, Glovo Partners+Operations 90, iFood Portal do Parceiro+OPS 92).

| Área | Bora hoje | Uber/Glovo/iFood | Gap |
|---|---|---|---|
| **Dashboard / Home** | 4 KPIs estáticos + gráfico daily orders | KPIs tempo real (pedidos hoje, GMV, ticket médio, online drivers, ETA médio, taxa aceitação, taxa cancelamento) + comparação WoW/MoM + heatmap geográfico + alertas | ❌❌❌ |
| **Alertas inteligentes** | Nenhum | Push admin: pedidos > 10min sem estafeta, parceiro sem aceitar há 5min, picos de cancelamento, fraude suspeita, queda de payment provider | ❌❌❌ |
| **Estafetas — lista** | Sim (filtro por nome) | Filtros: estado, zona/poligono, online, score, vehicle, hours-active hoje | ❌❌ |
| **Estafetas — detalhe** | 3 linhas | Score (1-5), histórico completo de pedidos, infracções (cancelamentos, no-show, atrasos), ganhos por dia/semana/mês, docs com expiração, mapa último ping, fcm_token | ❌❌❌ |
| **Estafetas — acções** | Aprovar/rejeitar (pending) | + banir, desbanir, reactivar, remover, editar dados, forçar logout, enviar push, atribuir bónus, ajustar tokens, pause auto-dispatch | ❌❌❌ |
| **Pedidos — lista** | Filtro status, limit 100 | Pesquisa full-text (id, cliente, estafeta, vendor, telefone, morada), filtros multi-seleccion, paginação, export CSV/XLSX, auto-refresh | ❌❌❌ |
| **Pedidos — detalhe** | Inexistente | Timeline com timestamps, mapa, items+modificadores, breakdown financeiro, fotos package/groceries, comments, chat history | ❌❌❌ |
| **Pedidos — acções** | Cancelar | + reatribuir estafeta, forçar próximo estado, refund parcial/total via Stripe, editar valores, contactar (phone/SMS/push) cliente/estafeta/parceiro, marcar como fraude | ❌❌❌ |
| **Mapa operacional tempo real** | Inexistente | Mapa com drivers online, pedidos activos por status (cor), zonas quentes, ETA médio por zona, click no pin → detalhe | ❌❌❌ |
| **Vista kanban** | Inexistente | Colunas por status, drag-and-drop entre estados (admin override) | ❌❌ |
| **Clientes** | Inexistente (sem ecrã) | Lista, detalhe, histórico pedidos, tokens balance, suporte tickets, banir, reembolsar, ajustar tokens, ver fcm_token | ❌❌❌ |
| **Parceiros — aprovação** | Inexistente | Onboarding pipeline com docs (alvará, IVA, IBAN), aprovação multi-passo | ❌❌❌ |
| **Parceiros — config** | Toggle quebrado | Comissão custom (10%/5%/5% editável), horários, pausar 30min/1h/dia inteiro, fee de saco custom, min order, delivery zones | ❌❌❌ |
| **Parceiros — produtos** | Inexistente | Editar produto, preço, foto (NÃO substituir reais), stock, disponibilidade, modificadores; importação CSV; bulk edit | ❌❌❌ |
| **Parceiros — stats** | Inexistente | GMV diário/semanal/mensal, pedidos, ticket médio, taxa de aceitação, tempo de preparação, top items, low performers | ❌❌❌ |
| **Pagamentos / finanças** | Vista semanal read-only | Ledger completo, filtros, export SEPA, reconciliação Stripe (auto-match payment_intent_id), MB Way, dinheiro, refunds com motivo, IVA report | ❌❌❌ |
| **Promoções / cupões** | Inexistente | Criar cupão (% / fixo), código, limite uso, expiração, primeiro pedido grátis, free delivery, target (cliente novo, zona, parceiro), A/B test | ❌❌❌ |
| **Tokens / loyalty** | Inexistente UI | Ver saldo cliente/driver, ajustar manual com motivo (audit log), config rates (3%, 100=€0.50, max 50%) | ❌❌❌ |
| **Suporte / chat** | Inexistente | Inbox tickets, chat 3-way (cliente↔admin↔parceiro/estafeta), templates de resposta, SLA, atribuição | ❌❌❌ |
| **Notificações / broadcast** | Inexistente | Push para clientes/estafetas/parceiros, filtros (zona, status, último pedido > X dias), agendar, A/B test, métricas open/click | ❌❌ |
| **Auditoria / logs** | Inexistente | Tabela `admin_audit_log` (timestamp, admin_id, IP, action, target, before/after JSON), ecrã filtrável | ❌❌❌ |
| **Config globais** | Hardcoded em código | UI editável: fee €2.50+€0.50/km, cash max €40, comissões, token rates, dispatch timeout 40s, stacking radius 200m | ❌❌❌ |
| **Permissões / roles** | 1 email allowlist | Roles: super_admin, admin, support, finance, ops; RLS policies por role; 2FA; session log | ❌❌❌ |
| **UX / UI admin** | Modal bottom sheets · sem dark mode · não responsive web | Web admin dedicado · dark mode · responsive · atalhos teclado (J/K, /-search, esc-close) · multi-window (drag pedido para outro tab) | ❌❌ |
| **Bulk actions** | Inexistente | Multi-select linha, acção em massa (banir N drivers, cancelar N orders, push para N clients) | ❌❌ |
| **Export / relatórios** | Inexistente | CSV / XLSX / PDF — pedidos, drivers, payouts, IVA · scheduled reports por email | ❌❌ |

**Conclusão gap:** O painel actual cobre **~18%** do que um back-office de classe mundial cobre. As maiores lacunas são: gestão de pedidos com refund, gestão de clientes (sem ecrã!), config globais editáveis, mapa em tempo real, suporte, promoções, audit log.

---

## 1.5 — SUGESTÕES DE MELHORIA (existem em Uber / Glovo / iFood)

| # | Nome | Descrição | Impacto | Esforço | Prioridade |
|---|---|---|---|---|---|
| S1 | **Override admin (force approve)** | Botão "Aprovar mesmo assim" no modal de driver pendente (com aviso amarelo dos docs em falta + grava `force_approved_reason`) — Uber tem isto no Driver Onboarding ops | Alto | S | A |
| S2 | **Detail completo de estafeta com acções** | Bottom sheet substituído por screen full com tabs (Info · Docs · Pedidos · Ganhos · Infracções · Mapa) + acções (banir/desbanir/reactivar/editar/logout/push) — Glovo Driver Ops | Alto | M | A |
| S3 | **Cancelamento com motivo + refund** | Dialog ao cancelar: dropdown motivo (cliente pediu, fraude, parceiro fechado, sem estafeta, outro) + checkbox "reembolsar" + valor + chama Edge Fn `refund` + `notify-client` — iFood Cancelamento Ops | Crítico | M | A |
| S4 | **Reatribuir estafeta** | Em pedidos `callingDriver`/`driverAccepted` botão "Reatribuir" → lista drivers online próximos → click chama `dispatch-engine` com `force_driver_id` — Glovo Re-assign | Alto | M | B |
| S5 | **Forçar próximo estado** | Admin override do lifecycle (skip preparing→callingDriver→...→delivered) com confirmação dupla — iFood Pedido OPS | Médio | S | B |
| S6 | **Pesquisa global** | Search bar no dashboard: id pedido, telefone, email, vendor, IBAN — Uber Manager | Alto | M | B |
| S7 | **Mapa operacional tempo real** | Tab "Mapa" no dashboard: drivers online (cor por status) + pedidos activos (pin com status) + zonas quentes; usa `drivers.lat/lng` e `orders.driver_lat/lng` que já existem; supabase realtime — Uber Ops | Alto | L | B |
| S8 | **Vista kanban de pedidos** | Colunas por status, drag-and-drop muda estado (com confirmação) — iFood Operações | Médio | M | C |
| S9 | **Ecrã de clientes** | Nova rota `/admin/customers` — lista, detalhe, histórico pedidos, tokens, ban, ajustar tokens; chama `users` + `orders` + `bora_tokens` — Glovo Customer Ops | Alto | M | B |
| S10 | **Importação massa de produtos** | CSV upload + preview + apply; reutiliza `bora_scraper_insert_batch` RPC — iFood Importação | Alto | M | B |
| S11 | **Comissão por parceiro editável** | Form em detail do parceiro: 3 sliders (visible/hidden/service_fee) com soma 20% default; persiste em `restaurants.commission_*` (colunas novas) — iFood Comissões | Alto | M | B |
| S12 | **Promoções / cupões** | Nova rota `/admin/promotions` — CRUD cupões; nova tabela `promotions` — Uber Promotions | Médio | L | C |
| S13 | **Audit log** | Nova tabela `admin_audit_log` + trigger DB que regista UPDATE/DELETE em `drivers`/`orders`/`restaurants`; ecrã filtrável — Glovo Ops Audit | Alto | M | A |
| S14 | **Config globais UI** | Nova rota `/admin/config` — form editável (fee, cash max, comissões, dispatch timeout, stacking radius); persiste em `token_config` (já existe) ou nova `app_config` — Uber Config | Alto | M | B |
| S15 | **Push broadcast** | Form: target (clientes/drivers/parceiros) + filtros (zona, último pedido > X dias) + texto + agendar; chama `notify-client/driver/partner` Edge Fn — iFood Marketing | Médio | M | C |
| S16 | **Roles e permissões** | Migration + RLS: `super_admin`, `admin`, `support`, `finance`; `bora_role` no JWT já existe; cada ecrã verifica role — Uber RBAC | Alto | L | B |
| S17 | **Reembolso real Stripe** | Cancel order chama Edge Fn `refund` (existe!) com `payment_intent_id` (existe na DB!) + valor + motivo; idempotência via metadata — Uber Refunds | Crítico | S | A |
| S18 | **Export CSV / XLSX** | Botão "Exportar" em todas as listas; gera no cliente com pacote `csv` ou Edge Fn — todos | Médio | S | C |
| S19 | **Bulk actions** | Checkbox por linha + barra inferior com acções (cancelar N, banir N, push N) — Glovo Bulk | Médio | M | C |
| S20 | **Dark mode admin** | AppTheme já tem suporte; toggle no AppBar — Uber Manager | Baixo | S | D |
| S21 | **Atalhos teclado** | `/` search · `J/K` next/prev · `Esc` close modal · `R` refresh — Linear / Uber web | Baixo | S | D |
| S22 | **Alertas inteligentes** | Polling 30s: pedido `callingDriver` > 5min → banner vermelho + push admin; usa Supabase realtime — iFood Alerts | Alto | M | B |
| S23 | **Score de estafeta** | Coluna `drivers.score` (média de `ratings` onde `subject_type='driver'`); badge no detail e lista — Uber Driver Score | Médio | S | C |
| S24 | **Gestão de tokens com audit** | Botão "Ajustar tokens" no detail do cliente/driver → form (delta + motivo); insere em `bora_tokens` + `admin_audit_log` — iFood Loyalty Ops | Médio | M | C |
| S25 | **Web admin responsive** | Build Flutter web; rota `/admin` num browser dedicado para operação — Uber Manager é web-first | Alto | L | C |
| S26 | **Suporte / inbox** | Nova rota `/admin/support` — list de `messages` agrupada por `order_id`; chat 3-way — todos | Médio | L | D |

---

## 1.6 — PLANO DE EXECUÇÃO PRIORIZADO

### Fase A — Críticos (bugs que bloqueiam operação) — **2-3 dias**

| # | Item | Ficheiros | Complexidade | Risco |
|---|---|---|---|---|
| A1 | **BUG 1** — adicionar override "Aprovar mesmo assim" | `admin_driver_approval_screen.dart` (mod _approve + dialog) | S | Baixo |
| A2 | **BUG 2** — actions sheet completa em aprovados (banir/desbanir/editar/forçar logout) | `admin_drivers_screen.dart` + `admin_driver_approval_screen.dart` (mod _DriverDetailSheet) + migration `drivers.is_banned` | M | Médio (toca DB) |
| A3 | **BUG 3** — cancelamento com motivo + refund Stripe + notify | `admin_orders_screen.dart` (mod _cancel) + chamada Edge Fn `refund` (já existe) + `notify-client` | M | Médio (dinheiro real) |
| A4 | **BUG 4** — corrigir coluna toggle parceiro (`is_active`→`is_partner` ou nova `is_paused`) | `admin_partners_screen.dart` (L32, L54) | S | Baixo |
| A5 | **S13** — audit log mínimo (tabela + trigger nas 3 tabelas críticas) | nova migration + leitura no detail | M | Baixo |
| A6 | **S17** — wire refund Edge Fn (já fica feito em A3) | — | — | — |
| A7 | **BUG 5 INFRA** — corrigir `bora_dispatch_maintenance` (uuid[] vs text[]) — **spawn task separada** | `supabase/functions/dispatch-engine` ou migration RPC | M | Alto (cron prod) |

### Fase B — Essenciais (gaps grandes vs Uber/Glovo/iFood) — **5-7 dias**

| # | Item | Ficheiros | Complexidade | Risco |
|---|---|---|---|---|
| B1 | **S2** — driver detail screen completa (tabs, score, infracções, ganhos) | novo ecrã `admin_driver_detail_screen.dart` | M | Médio |
| B2 | **S6** — pesquisa global no dashboard | mod `admin_dashboard_screen.dart` + RPC `admin_search_global` | M | Baixo |
| B3 | **S9** — gestão de clientes (novo ecrã + rota) | `admin_customers_screen.dart` + `admin_customer_detail_screen.dart` | L | Baixo |
| B4 | **S14** — config globais editáveis (UI + tabela) | novo ecrã + migration `app_config` | M | Médio (toca rules imutáveis — pedir aprovação) |
| B5 | **S11** — comissão por parceiro editável | mod `admin_partners_screen.dart` + form detail + migration colunas | M | Médio (toca comissões — pedir aprovação) |
| B6 | **S22** — alertas inteligentes (banner + Supabase realtime) | mod `admin_dashboard_screen.dart` + `realtime_admin_service.dart` | M | Baixo |
| B7 | **S16** — roles e permissões (super_admin/admin/support/finance) | migration RLS + check em cada ecrã | L | Alto (segurança) |
| B8 | **S7** — mapa operacional tempo real | novo ecrã `admin_operations_map_screen.dart` (Google Maps + realtime) | L | Baixo |
| B9 | **S4** — reatribuir estafeta | mod `admin_orders_screen.dart` + dialog | M | Médio |
| B10 | **S5** — forçar próximo estado | mod `admin_orders_screen.dart` + confirmation | S | Médio |
| B11 | **S10** — importação massa produtos (CSV) | novo ecrã + reutilizar `bora_scraper_insert_batch` | M | Médio (não substituir fotos reais!) |

### Fase C — Melhorias UX — **3-5 dias**

| # | Item | Ficheiros | Complexidade | Risco |
|---|---|---|---|---|
| C1 | **S8** — vista kanban de pedidos | novo widget + tab em `admin_orders_screen.dart` | M | Baixo |
| C2 | **S12** — promoções / cupões | novo ecrã + migration `promotions` | L | Baixo |
| C3 | **S15** — push broadcast | novo ecrã + chamadas `notify-*` | M | Baixo |
| C4 | **S18** — export CSV / XLSX | mod cada lista + pacote `csv` | S | Baixo |
| C5 | **S19** — bulk actions | mod cada lista + barra inferior | M | Médio |
| C6 | **S23** — score de estafeta | migration `drivers.score` + trigger + badge | S | Baixo |
| C7 | **S24** — gestão de tokens com audit | mod `admin_customer_detail_screen` + `admin_driver_detail_screen` + audit log | M | Médio |
| C8 | **S25** — Flutter web responsive admin | configurar build web + responsive layout | L | Médio |

### Fase D — Nice-to-have — **2-3 dias**

| # | Item | Ficheiros | Complexidade | Risco |
|---|---|---|---|---|
| D1 | **S20** — dark mode | toggle AppBar | S | Baixo |
| D2 | **S21** — atalhos teclado | `keyboard_listener_admin.dart` | S | Baixo |
| D3 | **S26** — suporte / inbox | novo ecrã + tabela `support_tickets` | L | Baixo |

### Estimativa total

- Fase A: **2-3 dias** (desbloqueia operação)
- Fase B: **5-7 dias** (paridade básica vs Uber/Glovo/iFood)
- Fase C: **3-5 dias** (UX de classe mundial)
- Fase D: **2-3 dias** (polish)

**Total: 12-18 dias** para painel admin de classe mundial.

---

## Notas de Restrição (REGRA DE OURO)

- ⚠️ Itens B4 (config globais), B5 (comissões), B7 (roles RLS) **tocam regras de negócio** — pedir aprovação Danilo antes de avançar.
- ⚠️ A3 (refund Stripe) **toca dinheiro real** — testar primeiro em ambiente de testes Stripe.
- ⚠️ B11 (importação produtos) — **não substituir fotos reais** existentes; só inserir/upsert produtos novos.
- ⚠️ BUG 5 (`bora_dispatch_maintenance`) é infra crítica fora de admin — recomenda task separada e urgente.
- ⚠️ Todas as Fases preservam o que funciona hoje (BUG 1-4 são adições, não substituições destrutivas).

---

## Próximo passo

**Aguarda aprovação do Danilo** para arrancar Fase A. Sugestão de ordem:
1. A4 (BUG 4 partners — 30min, zero risco)
2. A1 (BUG 1 override approve — 1h)
3. A2 (BUG 2 actions aprovados — 3h, inclui migration `is_banned`)
4. A3 + A6 (BUG 3 cancel com refund — 4h)
5. A5 (audit log — 2h)
6. A7 (BUG 5 dispatch_maintenance — spawn separado)

Após aprovação avançar para Fase B.
