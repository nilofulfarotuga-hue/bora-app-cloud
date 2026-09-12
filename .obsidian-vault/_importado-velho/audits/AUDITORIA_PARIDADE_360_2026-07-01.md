# Auditoria de Paridade 360° — Bora App

> **Data:** 2026-07-01 · **Modo:** 100% READ-ONLY (nenhum ficheiro de código, migration, edge function, RPC ou config foi alterado) · **Orquestração:** CEO-AI + 5 subagentes de inventário (1 por superfície) · **Projeto Supabase:** `ojykpzwqrtusfeakzrna` · **Branch:** `autonomous-night-2026-04-29`

## Metodologia

Cada superfície foi inventariada e cruzada, nesta ordem, contra 3 réguas:
1. **`business_rules.md`** (`.claude/.ai/business_rules.md`) + knowledge/Obsidian.
2. **As outras superfícies** (se o backend tem X, o admin gere X? o cliente vê X? o estafeta recebe X?).
3. **Padrão de mercado** (Glovo / Uber Eats / iFood / Bolt / Fresha / Booksy).

Legenda de prioridade: **P0** = bloqueia lançamento / compliance / dinheiro / segurança · **P1** = fricção séria ou paridade quebrada visível · **P2** = melhoria / diferencial.

---

## 🧭 Sumário executivo

O **backend é maduro e completo** (~120 tabelas, 50 edge functions, ~330 RPCs, 72 triggers, RLS em tudo) — suporta todos os verticais: delivery, favores/errand, TVDE, serviços/agendamentos, reservas "Pro", tokens, ledger append-only, settlements. As **apps cliente e parceiro-comida** têm cobertura larga. Os buracos concentram-se em **3 eixos**:

1. **Compliance & dinheiro do lado do motorista/estafeta** — KYC não-bloqueante, TVDE sem documentos próprios, e o estafeta **não vê nem saca** os ganhos reais (só tokens).
2. **Paridade do vertical Serviços** — assimétrico face ao parceiro-comida (sem pausar, sem horário de loja, sem chat, onboarding mais fraco).
3. **Poder de configuração do Admin** — **zonas/taxas/surge inexistentes**, exportações e alguns CRUDs em falta. Só **1 de 20 domínios** tem paridade admin completa.

**Bugs mais graves detectados:** onboarding TVDE possivelmente partido (`driver_signup` força `motorcycle`); PIN de entrega validado client-side (fraude); `admin_approve_driver` duplicado no schema; 3 buckets públicos com listing.

---

## 1. Backend (Supabase)

### ✅ Existe
- **Pricing & financeiro** (zona protegida — só mapeado): `pricing_calculate(_errand)`, `quote_order_pricing`, `create_order`, `compute_refund_split`, `compute_driver_settlement`, `compute_partner_weekly_settlement`, `compute_provider_weekly_payout`. Ledger append-only (`ledger_entries` + triggers `ledger_no_delete/update/recompute` + `enforce_financial_immutability`). Refund cap (`_enforce_refund_cap`), cash limit €40 (`enforce_cash_payment_limit`), pagamento-antes-de-preparar.
- **Tokens** (zona protegida): `bora_tokens`, `add/consume/mark_token_failed`, trigger `trg_award_tokens_on_delivery`.
- **Dispatch**: EF `dispatch-engine` v57, `driver_accept/reject_offer`, `driver_cancel_order`, `dispatch_cancel_expired_order`, `driver_locations`.
- **Cancelamento & refund**: EFs `client-cancel-order`, `cancel-order-with-choice`, `execute-cancellation`, `admin-cancel-order`, `refund`, `reprocess-refund`; tabela `cancellation_requests`.
- **Favores/errand** (BR §55), **TVDE** (vertical isolada completa: `tvde_rides`, `tvde_*` RPCs, `notify-tvde-driver`), **Serviços/agendamentos** (`service_providers`, `appointments`, `appointment_payouts`), **Reservas "Pro"** (floor plans, pacing, turn times, waitlist, notify list — supera padrão de mercado).
- **Suporte/IA/robot** (RAG `support_knowledge_chunks`, `robot-b`, `admin-ai-assistant`), **Admin & auditoria** (`admin_audit_log` append-only via `log_admin_action`, ~150 RPCs `admin_*`, `platform_settings` 49 linhas), **Notificações/push** completas.

### ❌ Falta
- **P1 — Idempotency de refund** (BR §8.4.3 é TODO): falta `orders.refund_idempotency_key`. Com `refund`+`reprocess-refund`, risco de duplicar refund em retry. 🔴 Lista Vermelha — só reportado.
- **P1 — Zonas de entrega / cobertura geográfica**: sem `delivery_zones`/`service_areas`; dispatch usa raio fixo hardcoded (≤10km, ≤200m). Bloqueia escalar além da Guarda.
- **P1 — Surge / pricing dinâmico**: inexistente (aceitável em MVP local, gap estrutural).
- **P2 — Disputas Stripe / chargebacks**: sem máquina de estados ligada a `charge.dispute.created` (confirmar no código do `stripe-webhook`).
- **P2 — Tabelas aparentemente órfãs**: `token_config`, `client_wallets`/`wallet_transactions`, `product_variants`, `market_update_schedule` a 0 linhas (config de tokens vive em `platform_settings` = fonte-dupla).
- **P2 — 40+ tabelas `_backup_*`/staging em produção** (poluição de schema/ruído de advisors).

### 🔗 Quebra de paridade
- `guarda_businesses` (156 linhas) + EF `import-guarda-businesses` — diretório existe; confirmar se há UI que o exponha.
- Reservas "Pro" (waitlist/notify/combinar mesas) — schema muito além do que a UI parceiro provavelmente expõe.
- `restaurant_menu_credits` + `partner_reservation_payouts` (crédito €2/reserva) — confirmar visibilidade na UI.
- `tvde_subscriptions`/`tvde_ride_counters` (0 linhas) — modelo de subscrição sem dados; confirmar se a app expõe compra.

### 🐛 Bugs / riscos
- **P1 — 3 buckets públicos com LISTING** (`avatars`, `product-images`, `restaurant-assets`): clientes podem enumerar ficheiros. **Confirmar que `driver-documents` (selfies/docs) é privado.**
- **P1 — 82 SECURITY DEFINER executáveis por `anon`**: auditar que nenhum `admin_*`/`create_order`/`pricing_*`/`finalize_*` é anon-executável.
- **P1 (perf) — RLS não-otimizado à escala**: 337× `multiple_permissive_policies`, 125× `auth_rls_initplan` (`auth.uid()` reavaliado por linha em `orders`/`products` 46k/`messages`).
- **P2** — `function_search_path_mutable` (`_haversine_km`, `_errand_normalize`); leaked-password protection desligado; 34× FK sem índice.
- ℹ️ 43 tabelas com RLS on / 0 policies = deny-all (seguro; são backup/staging).

---

## 2. App Cliente

### ✅ Existe
Shell 4-tabs (`client_main_screen`: Início/Entrega/Reserva/Perfil). Descoberta (`stores_screen` com busca+ordenação, `market_store_screen`, `restaurant_menu`, `product_detail` com opções/toppings/grupos obrigatórios). Carrinho/checkout (`cart_screen` com gorjeta+carteira, `payment_method_screen`: Cartão/MBWay/Cash + desconto por tokens). Pós-pedido (`order_tracking` realtime + 2 chats + cancelamento self-service + rating; `order_details` com **talão do favor visível**; `rating_screen`). **Verticais completas**: favores (`errand_form`, `carry_groceries`, `send_package`), serviços (`client/services/*` booking+agenda), reservas (`client/reservation/*` + waitlist/notify), TVDE escondido (`client/tvde/*`). Fidelização (`wallet_history`, `referral`, `client_promo_code`, `addresses`, `favorites`).

**Cobertura backend→cliente: completa** em todos os verticais.

### ❌ Falta
- **P1 — Reorder só para favores**: restaurantes/lojas/mercados sem "Pedir de novo" funcional (tab mercado é placeholder). Atrito no caso mais frequente (padrão Glovo/Uber).
- **P1 — Sem campo de código promo no checkout**: `ClientPromoCodeScreen` só resgata tokens; a RPC `create_order` já trata erros de promo, mas não há UI para aplicar cupão ao pedido.
- **P1 — Sem agendamento de entrega** ("para mais tarde") — zero suporte em cart/checkout/home.
- **P2 — Busca global ausente na home** (existe só dentro de `stores_screen`, sobre lista já carregada; sem busca cross-loja/produto).
- **P2 — Sem filtros de descoberta** (preço, tempo, promoções, "aberto agora", dietético).
- **P2 — Split payment** inexistente.

### 🔗 Quebra de paridade
- **Promo por pedido**: backend aceita, sem UI de input no fluxo de compra.
- **Reorder mercado**: `MarketReorderTab` importado mas comentado como placeholder pós-launch.

### 🐛 Bugs
1. **Rating da loja não abre** quando `order.restaurantId` é vazio/nulo (`order_tracking_screen.dart:170`) — pedidos non-partner nunca convidam a avaliar o vendedor.
2. **"Pedir de novo"** no histórico só funciona para errand (`orders_screen.dart:122`); não repete pedidos de comida.
3. Herdado: discrepância tokens `ROUND(price×3)` vs "3%" (§32.4) — afeta o valor que o cliente vê acumular (pendente decisão Danilo).

---

## 3. App Estafeta / Motorista (inc. TVDE)

### ✅ Existe
**Delivery**: `driver_signup/login/pending/rejected/permissions`, `driver_home`, `driver_map` (rota + seta com bearing + PIN 4 dígitos + navegação Google Maps externa), fluxos `storeShopping`/`carryGroceries`/`sendPackage`/errand, `OfferPresentationGate` (FG laranja / BG-unlocked fullscreen / locked CallKit), `driver_earnings` (conversão tokens→€ + compra de prioridade), heartbeat 90s + GPS.
**TVDE**: isolamento sólido — `main.dart:566` roteia por `vehicleType == carPassengers` → `TvdeDriverHomeScreen`. Store/RPCs (`tvde_accept/reject/start/finish/cancel_ride`, `tvde_rate`), realtime `tvde_rides`, push `notify-tvde-driver` — todos separados do delivery (reusa deliberadamente heartbeat+GPS+`toggleAvailability`).

### ❌ Falta
- **P0 — KYC do estafeta não-bloqueante**: uploads (selfie, doc ID, carta/livrete, veículo) são todos "opcional" e falha de upload **nunca bloqueia** o submit → estafeta pode ser criado **sem carta**. Sem campos para licença TVDE/seguro/CAE; sem re-upload pós-registo.
- **P0 — TVDE sem fluxo de documentos próprio**: registo usa o mesmo `driver_signup` (moto), não recolhe carta TVDE, dístico, seguro de passageiros.
- **P0/P1 — Estafeta não faz saque real dos ganhos**: `driver_earnings` só converte **tokens**; os €3,80+€0,20/km do acerto semanal não têm UI de saque/pedido de pagamento.
- **P1 — Estafeta não vê settlements/extrato semanal** (corridas, km, total, pago/pendente) — só existe no admin.
- **P1 — TVDE sem tela de ganhos nem de assinatura semanal** (modelo existe, UI não).
- **P1 — Sem histórico de corridas/entregas** no app do motorista (cliente TVDE tem, motorista não).
- **P2 — Navegação só via Google Maps externo** (sem turn-by-turn embebido); sem toggle entrega↔TVDE.

### 🔗 Quebra de paridade
- **KYC assimétrico**: o admin aprova documentos que o app **não garante ter recolhido**; TVDE não envia docs TVDE-específicos.
- **Settlements invisíveis ao estafeta**: backend + admin calculam e marcam pago; o estafeta só vê tokens. O **parceiro tem cartão de fecho semanal, o estafeta não**.

### 🐛 Bugs
1. **`driver_signup_screen` força `p_vehicle_type: 'motorcycle'`** (~linha 299) → um motorista TVDE novo nunca fica `carPassengers` → **onboarding TVDE possivelmente partido** (confirmar caminho alternativo). **P0.**
2. **Prova de entrega valida PIN client-side** (`driver_map_screen.dart:1148` `entered != deliveryCode`) → app modificado poderia auto-confirmar sem o cliente. **Risco de fraude — devia ser RPC server-side. P0/P1.**
3. KYC não-bloqueante (conformidade).
4. `is_online`/heartbeat partilhados TVDE↔delivery (frágil se um driver tivesse ambos os modos).

---

## 4. App Parceiro (restaurantes/lojas + serviços)

### ✅ Existe
**Registo**: `register_partner_screen` (mesmo wizard cria os dois tipos — categoria `restaurant`→`restaurants`, não-restaurante→`service_providers`; NIF, IBAN, logo, Termos).
**Comida/loja**: `partner_dashboard` (toggle ONLINE/OFFLINE, aceitar / aceitar-com-ETA, marcar pronto, chamar estafeta, chat cliente/estafeta, modal dispatch), `partner_products` + `add_product` (alergénios) + `product_options_manage`, `partner_hours`, `partner_earnings` (KPIs, top produtos, horas pico, **fecho semanal read-only**), **Reservas Pro** (8 ecrãs: floor plan, pacing, walk-in, client profiles, stats).
**Serviços**: `partner_services_hub` + `partner_appointments_store` (completo), `partner_agenda` (concluir/no-show/cancelar), `partner_manage_services`, `partner_manage_staff` (+disponibilidade semanal), `partner_block_slot`, `partner_add_walk_in`, `partner_appointments_finance` (liquidações).

### ❌ Falta
- **P0 — Registo de Serviços sem IBAN validado/documentos/selfie** (vs. rigor exigido ao estafeta §11.1).
- **P0 — Sem "pausar loja" temporário** (só ONLINE/OFFLINE binário; sem snooze com auto-retoma — padrão Glovo/Uber Eats).
- **P1 — Gestão de avaliações/reviews ausente** no app parceiro (não vê nem responde; admin tem `admin_ratings`, parceiro não).
- **P1 — Sem stock/inventário por item** (só toggle `isAvailable`).
- **P1 — Sem promoções próprias do parceiro** (happy-hour, combos, cupões).
- **P1 — Sem relatórios exportáveis** (CSV/PDF) para contabilidade.
- **P2 — Serviços sem página pública editável** (capa, bio, horário de loja), **sem "reagendar" marcação**, **sem galeria/portfólio** (diferencial Booksy).

### 🔗 Quebra de paridade (Serviços vs. Comida)
- **Registo** assimétrico (serviços reutiliza wizard de comida sem campos próprios).
- **Horários**: comida tem `partner_hours`; **serviços não tem horário global de loja** (só `staff_availability` por barbeiro).
- **Estado online**: comida tem toggle; **serviços não** (disponibilidade implícita pela agenda).
- **Chat**: comida tem chat cliente/estafeta; **serviços não expõe chat com o cliente da marcação**.
- **Estatísticas**: comida ricas; serviços mais pobre (sem top-serviço/barbeiro).
- **Backend↔App**: `partner_cancel_appointment` devolve `refund_due` mas **o reembolso do sinal (€3) é processo manual do admin** (sem automação — risco de sinais retidos). 🔴 Lista Vermelha.

### 🐛 Bugs
1. **Registo `service_providers` sem gate `pending→approved` evidente** — verificar RLS/status (prestador pode ficar ativo sem revisão).
2. **`partner_hours` inacessível a parceiro só-serviços** (recebe `RestaurantModel`) → não define horário de funcionamento.
3. **Toggle ONLINE inexistente em serviços** → prestador não "fecha hoje" facilmente.
4. **Reembolso de sinal manual** (sem cron/automação).
5. **Chat ausente no vertical serviços** (cliente↔barbearia sem canal in-app).

---

## 5. Painel Admin (foco especial)

**73 telas `admin_*` + 140+ RPCs `admin_*`.** Cobertura larga: clientes, estafetas delivery, TVDE, parceiros restaurante/loja/serviços, pedidos, reservas, agendamentos, favores+talão OCR, catálogo, cupons, tokens/carteira, settlements, cancelamentos, broadcast, robot-b, KPIs, audit log, platform settings.

### ⬜ Veredito das 7 hipóteses do dono
1. **KYC de motorista TVDE no admin?** → **❌ NÃO.** Só aprova flag de acesso/subscrição + foto de perfil; nenhuma revisão de carta/licença TVDE/seguro/matrícula. **(P0 — compliance IMT/DL 45/2018)**
2. **Vertical Serviços/Agendamentos no admin?** → **⚠️ PARCIAL.** Aprova/rejeita/activa prestadores + paga/cancela agendamentos + métricas. Falta EDITAR/CRIAR agendamento e editar dados do prestador.
3. **Favores + disputa + revisão talão OCR?** → **✅ EXISTE.** `admin_errand_catalog` (aprovar/rejeitar/editar item) + `admin_receipts` (tab OCR Flag `ocr_flagged`/`ocr_diff_cents`, marcar reembolso pago, rejeitar/disputar).
4. **Zonas / taxa por zona / pedido mínimo / surge configuráveis?** → **❌ NÃO (derrubada total).** Zero telas, zero chaves em `platform_settings` (query devolveu `[]`), zero código. **(P0 estrutural)**
5. **Settlements parceiro E estafeta visíveis e exportáveis?** → **⚠️ PARCIAL.** Ambos visíveis + marcar pago; **parceiro exporta CSV, estafeta NÃO. (P1)**
6. **Cupons — CRUD completo?** → **⚠️ PARCIAL.** Create + list + deactivate; **sem EDIT.**
7. **Audit log de TODAS as ações?** → **⚠️ MAIORIA.** Escrito por RPCs `admin_*` + Edge Fns, mas UPDATE directo (ex. `service_providers`) pode não auditar e **não há EXPORT**.

### ❌ Falta (admin)
- **P0 — Config de zonas/taxa-zona/pedido-mínimo/surge** (inexistente).
- **P0 — Revisão documental KYC do motorista TVDE.**
- **P1 — Export CSV de settlements de estafeta** (assimetria com parceiro).
- **P1 — Export do log de auditoria.**
- **P1 — CRUD de produtos** (só edita preço/disponibilidade/foto; não cria nem apaga in-app).
- **P1 — Editar cupão** (valor/limite/validade).
- **P2 — Editar perfil / criar cliente; editar dados de prestador de serviços; reatribuir estafeta a pedido preso** (dispatch manual).

### 🐛 Bugs (admin)
- **`admin_approve_driver` DUPLICADO** no schema (2 rotinas homónimas → overload ambíguo no PostgREST; risco de chamar a assinatura errada). **P1.**
- Export inconsistente parceiro-vs-estafeta (provável esquecimento).

---

## 🎯 TEM QUE FAZER TAMBÉM (consolidado priorizado)

### 🔴 P0 — antes de operar a sério
1. **Corrigir onboarding TVDE** — `driver_signup` força `motorcycle`; novo motorista nunca fica `carPassengers`. Sem isto, o vertical TVDE não recruta pelo app. *(bug — Estafeta)*
2. **KYC bloqueante + documentos** — tornar carta/veículo obrigatórios no registo de estafeta; recolher carta TVDE/seguro/dístico/CAE no fluxo de motorista; **e dar ao admin a tela de revisão desses documentos**. Compliance IMT/DL 45/2018. *(Estafeta + Admin)*
3. **Prova de entrega server-side** — validar o PIN via RPC, não `entered != deliveryCode` no cliente. Fecha fraude de entrega. *(Estafeta — segurança)*
4. **Confirmar `driver-documents` privado + fechar listing dos 3 buckets públicos** (`avatars`, `product-images`, `restaurant-assets`). *(Backend — segurança)*
5. **Zonas de entrega / taxa por zona / pedido mínimo / surge** — modelar no backend + tela admin. *P0 para escalar; aceitável adiar enquanto for só Guarda, mas é o maior gap estrutural vs Glovo/Bolt.* *(Backend + Admin)*

### 🟠 P1 — fricção séria / paridade quebrada
6. **Estafeta ver e sacar ganhos reais** — extrato semanal (corridas/km/total/pago-pendente) + pedido de pagamento; hoje só vê tokens. Paridade com o cartão de fecho do parceiro. *(Estafeta + Admin)*
7. **Idempotency-key no refund** (BR §8.4.3) — evitar refund duplicado em retry. 🔴 Lista Vermelha. *(Backend)*
8. **`admin_approve_driver` duplicado** — remover overload ambíguo. *(Admin/Backend)*
9. **Registo de Serviços com IBAN/documentos próprios** + **gate `pending→approved`** explícito. *(Parceiro)*
10. **"Pausar loja" temporário** (snooze com auto-retoma) — comida; e **toggle online + horário de loja para Serviços**. *(Parceiro)*
11. **Chat no vertical Serviços** (cliente↔barbearia). *(Parceiro)*
12. **Automação do reembolso do sinal** de marcação cancelada (hoje manual). 🔴 Lista Vermelha. *(Parceiro + Backend)*
13. **Cliente**: campo de **cupão no checkout**, **reorder de comida/mercado**, **agendar entrega**. *(Cliente)*
14. **Admin**: **export CSV de settlements de estafeta**, **export do audit log**, **CRUD de produtos**, **editar cupão**, **gestão de reviews visível ao parceiro**. *(Admin + Parceiro)*
15. **Performance RLS à escala** — `(select auth.uid())` + consolidar policies permissivas em `orders`/`products`/`messages`; auditar os 82 DEFINER anon-executáveis. *(Backend)*

### 🟡 P2 — melhoria / diferencial
16. Busca global + filtros na home do cliente; rating de loja com `restaurantId` nulo. *(Cliente)*
17. Navegação turn-by-turn embebida; histórico de corridas/entregas no motorista. *(Estafeta)*
18. Reagendar marcação, galeria/portfólio, página pública editável (Serviços). *(Parceiro)*
19. Editar/criar cliente; reatribuir estafeta a pedido preso; disputas Stripe. *(Admin + Backend)*
20. Limpar 40+ tabelas `_backup_*` de produção; documentar `token_config` vs `platform_settings`. *(Backend)*

---

## 📊 Placar de paridade admin

Regra do dono: cada domínio deve cobrir **VER · EDITAR · CRIAR · BANIR · CONFIGURAR · EXPORTAR · AUDITAR** (verbos "n/a" não contam).

- **Domínios avaliados:** 20
- **Com paridade completa (todos os verbos aplicáveis ✅):** **1** — só *Parceiros restaurante/loja* (e mesmo esse com EXPORTAR parcial). → **~5%**
- **Quase completos (falta 1 verbo, quase sempre EXPORTAR):** ~5 (Pedidos, Favores, Settlements parceiro, Broadcast, Robot-b).
- **Incompletos (≥1 verbo ❌/⚠️):** ~18.
- **Cobertura zero:** *Zonas / taxas / mínimo / surge* → **0/7**.

**Verbo mais fraco do sistema:** **EXPORTAR** — presente em apenas **2 de 20** domínios (Pedidos, Settlements parceiro). A seguir: **CRIAR** (~5/20) e **CONFIGURAR** (~4/20). **VER** e **AUDITAR** são fortes (~19/20).

| Domínio | VER | EDITAR | CRIAR | BANIR | CONFIG. | EXPORT. | AUDIT. |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Clientes | ✅ | ❌ | ❌ | ✅ | ⚠️ | ❌ | ✅ |
| Estafetas delivery | ✅ | ✅ | ❌ | ✅ | ⚠️ | ❌ | ✅ |
| Motoristas TVDE | ✅ | ❌ | ❌ | ✅ | ⚠️ | ❌ | ✅ |
| Parceiros restaurante/loja | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| Parceiros serviços | ✅ | ❌ | ❌ | ⚠️ | ⚠️ | ❌ | ⚠️ |
| Pedidos/orders | ✅ | ⚠️ | n/a | n/a | n/a | ✅ | ✅ |
| Reservas dine-in | ✅ | ⚠️ | ✅ | n/a | ⚠️ | ❌ | ✅ |
| Agendamentos/serviços | ✅ | ❌ | ❌ | n/a | ⚠️ | ❌ | ✅ |
| Favores + talão OCR + disputa | ✅ | ✅ | ❌ | n/a | n/a | ⚠️ | ✅ |
| Produtos/catálogo | ✅ | ✅ | ❌ | ⚠️ | ⚠️ | ❌ | ✅ |
| Pedidos de mercado | ✅ | ✅ | ❌ | n/a | n/a | ⚠️ | ✅ |
| Promoções/cupons | ✅ | ❌ | ✅ | ✅ | ⚠️ | ❌ | ✅ |
| Tokens/carteira | ✅ | ⚠️ | ✅ | ✅ | ⚠️ | ❌ | ✅ |
| Settlements parceiro | ✅ | n/a | n/a | n/a | ⚠️ | ✅ | ✅ |
| Settlements estafeta | ✅ | n/a | n/a | n/a | ⚠️ | ❌ | ✅ |
| Refunds/cobranças extra | ✅ | ⚠️ | ⚠️ | n/a | n/a | ⚠️ | ✅ |
| **Zonas/taxas/mínimo/surge** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Notificações/broadcast | ✅ | n/a | ✅ | n/a | ✅ | ❌ | ✅ |
| Robot-b | ✅ | ✅ | ⚠️ | ✅ | ✅ | ❌ | ✅ |
| Logs de auditoria | ✅ | n/a | n/a | n/a | n/a | ❌ | ✅ |

---

## 🔒 Nota sobre zonas protegidas

As zonas 🔴 Lista Vermelha (pricing, Stripe webhook, dispatch-engine, `finalizePurchase`, triggers de token, RLS financeiro) foram apenas **mapeadas**, nunca tocadas. Os itens acima que lhes tocam (refund idempotency #7, reembolso de sinal #12) exigem preparação + confirmação explícita do Danilo antes de qualquer alteração.

---

*Relatório gerado por CEO-AI + 5 subagentes de inventário read-only. Cópia gémea em `C:\Users\danil\Desktop\Bora\audits\`. Nenhuma alteração de código/DB foi aplicada.*
