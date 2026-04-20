# PLANO DE FINALIZAÇÃO — BORA APP
**Data:** 2026-04-17
**Base:** `.claude/.ai/business_rules.md v2` §26.2
**Modo:** PROTECÇÃO TOTAL — nada é executado sem aprovação explícita do Danilo.

---

## 1. ESTADO ACTUAL (auditoria ao código)

| # | Feature (BR §26.2) | Estado | Evidência no código |
|---|---|---|---|
| 1 | Cardápio digital + Reservas (BR §14) | ❌ FALTA | Zero migrations `reservations`/`menu_items`; `restaurant_menu_screen.dart` existe mas só renderiza produtos estáticos; sem fluxo de reserva, sem pré-pagamento €3, sem status `customer_arrived`. |
| 2 | Takeaway em parceiros (BR §14.9) | ❌ FALTA | Referência única a "takeaway" em `pricing_service.dart`; não há toggle "Ir buscar" no checkout, não há supressão da taxa €2,50. |
| 3 | Gorjetas / Tips (BR §4.5) | ❌ FALTA | Zero ocorrências de `tip`/`gorjeta` em `lib/`; não há UI, coluna DB nem split 80/20. |
| 4 | Avaliações com etiquetas (BR §13) | 🟡 PARCIAL | `rating_model.dart` existe (rating + comment), `OrderStore` guarda ratings em memória — **mas** sem etiquetas (simpático/rápido/limpo/denúncia), sem ecrã de avaliação, sem persistência em Supabase, sem rating driver→cliente privado. |
| 5 | Driver Help (BR §5.2) | ❌ FALTA | Apenas constante `DRIVER_HELP_COST_EUR = 4.00` em `business_rules.dart`; sem botão "Preciso de ajuda", sem fluxo de dispatch auxiliar, sem split €8/€4. |
| 6 | Cancelamento pelo cliente (BR §8.3) | ❌ FALTA | Só existe `driver_cancel_order` RPC; `OrderStatus` enum não tem `cancelled`; webhook Stripe tem constantes `CANCEL_FEE_*` mas **não usadas** ("will be used when cancel flow is implemented"). |
| 7 | Painel admin completo (BR §16) | 🟡 PARCIAL | 6 ecrãs existem: dashboard, drivers, driver_approval, driver_payments, orders, partners. BR §16.2 pede 10+ áreas — falta: reservas, avaliações/denúncias, tokens/gorjetas, tickets de suporte, configuração de regras de negócio, métricas SLA. |
| 8 | GDPR — checkbox + apagar conta + cookies (BR §20) | ❌ FALTA | Zero matches `gdpr`/`consent`/`delete account` em `register_*_screen.dart`; `profile_screen.dart` tem "Terminar sessão" (linha 336) mas **não** "Apagar conta"; sem banner de cookies na 1ª abertura. |
| 9 | Foto obrigatória `sendPackage` / `carryGroceries` (BR §7.5/7.6) | ❌ FALTA | `send_package_form_screen.dart` e `carry_groceries_form_screen.dart` não importam `image_picker` nem têm campo foto; `order_model.dart` não tem coluna `package_photo_url`/`groceries_photo_url`. |
| 10 | Câmara do mapa a rodar com bearing (BR §7.2) | 🟡 PARCIAL | `driver_map_screen.dart` calcula `_bearing` via atan2 e usa em marcador + câmara (linhas ~94-100, 400-470). **Código existe mas NÃO foi validado em telemóvel físico — falta QA em Android real com GPS activo.** |

### Bugs / lacunas observáveis nos 3 fluxos

- **Cliente:** sem ecrã de avaliação pós-entrega; sem botão cancelar; sem apagar conta; sem consentimento GDPR; sem reservas/takeaway.
- **Estafeta:** sem botão "Preciso de ajuda"; sem validação de foto pré-aceitação em sendPackage/carryGroceries.
- **Parceiro:** sem secção reservas, sem gestão de menu em tempo real (o restaurante não pode editar disponibilidade por horário), sem timeline de reservas do dia.

---

## 2. PLANO EM LOTES

Ordenado por risco de lançamento × esforço. Cada lote é independente e aprovável em separado.

---

### LOTE 1 — GDPR & CANCELAMENTO CLIENTE (**CRÍTICO — bloqueador legal**)
**Motivo:** sem GDPR não podemos publicar em PT/UE; sem cancelar, vamos ter reclamações no dia 1.

#### Tarefa 1.1 — Checkbox de consentimento no registo (BR §20.1)
- **O que faz:** adicionar checkbox obrigatório "Aceito Termos e Política de Privacidade" nos 3 ecrãs de registo; guardar `consent_accepted_at timestamptz` nas tabelas `clients`, `drivers`, `partners`.
- **Ficheiros:** `register_client_screen.dart`, `register_driver_screen.dart`, `register_partner_screen.dart`, nova migration SQL.
- **Skills sugeridas:** `flow_guard`, `supabase_agent/executor`.
- **Esforço:** pequeno.

#### Tarefa 1.2 — Apagar conta (BR §20.2)
- **O que faz:** botão em `profile_screen.dart` "Apagar conta" com o aviso legal exato (10 anos faturas); Edge Function `delete-account` que apaga PII e mantém dados fiscais; reassignar `user_name = 'Utilizador apagado'` em pedidos antigos.
- **Ficheiros:** `profile_screen.dart`, novo `supabase/functions/delete-account/`.
- **Esforço:** média.

#### Tarefa 1.3 — Banner de cookies/tracking (BR §20.3)
- **O que faz:** diálogo modal na 1ª abertura com 3 botões (Aceitar / Rejeitar / Gerir); persistir em `SharedPreferences` chave `bora_app.consent_v1`.
- **Ficheiros:** novo `lib/widgets/consent_banner.dart`, hook em `main.dart`.
- **Esforço:** pequeno.

#### Tarefa 1.4 — Cancelamento pelo cliente (BR §8.3)
- **O que faz:** adicionar `OrderStatus.cancelled`; botão em `order_tracking_screen.dart` com cálculo de taxa (€1 antes de aceite / €2,50 a caminho / 100% após purchase); Edge Function `client-cancel-order` que faz refund via Stripe; persistência da razão.
- **Ficheiros:** `order_model.dart`, `order_store.dart` **(⚠ zona protegida — só leitura/addição, não tocar `finalizePurchase`)**, `order_tracking_screen.dart`, `stripe-webhook/index.ts`, nova function.
- **Esforço:** média-grande.
- **Aprovação:** OBRIGATÓRIA — mexe em Stripe e DB.

---

### LOTE 2 — AVALIAÇÕES + TIPS + FOTOS (**ALTA — experiência de utilizador**)

#### Tarefa 2.1 — Foto obrigatória em sendPackage/carryGroceries (BR §7.5/7.6)
- **O que faz:** adicionar `ImagePicker` em `send_package_form_screen.dart` e `carry_groceries_form_screen.dart`; upload para bucket Supabase; coluna `package_photo_url` em `orders`; mostrar foto no card de oferta do driver.
- **Ficheiros:** os 2 forms, `order_model.dart`, oferta do driver, migration SQL, policy de bucket.
- **Esforço:** média.

#### Tarefa 2.2 — Ecrã de avaliação com etiquetas (BR §13)
- **O que faz:** novo `rating_screen.dart` com 1-5 estrelas + chips de etiquetas (simpático, rápido, limpo, profissional, denúncia); tabela `ratings` em Supabase (driver_id, client_id, order_id, rating, tags text[], comment, created_at); avaliação cliente→estafeta é pública, estafeta→cliente é privada.
- **Ficheiros:** novo screen, `rating_model.dart` (expandir), nova migration.
- **Esforço:** média.

#### Tarefa 2.3 — Gorjetas/Tips (BR §4.5)
- **O que faz:** UI de tip (1/2/3/5€ + custom) em (a) checkout e (b) `rating_screen.dart`; coluna `tip_amount_cents` em `orders`; split 80/20 aplicado no trigger de payout do driver; Stripe charge adicional se já pago por cartão.
- **Ficheiros:** `payment_method_screen.dart`, `rating_screen.dart`, `order_model.dart`, trigger Supabase, possivelmente `stripe-webhook`.
- **Esforço:** média-grande.
- **Aprovação:** OBRIGATÓRIA — toca em pricing/Stripe.

---

### LOTE 3 — RESERVAS + TAKEAWAY (**ALTA — diferencial de parceiros**)

#### Tarefa 3.1 — Takeaway toggle (BR §14.9)
- **O que faz:** switch "Entrega / Ir buscar" em `cart_screen.dart`; se takeaway → taxa entrega = 0, sem dispatch, notificação ao cliente quando `status = ready`.
- **Ficheiros:** `cart_screen.dart`, `order_store.dart` (⚠ cuidado com `finalizePurchase`), `partner_dashboard_screen.dart`.
- **Esforço:** pequena-média.

#### Tarefa 3.2 — Cardápio digital editável pelo parceiro (BR §14.3)
- **O que faz:** `partner_products_screen.dart` já existe — expandir para: disponibilidade por horário (ex: almoço 12h-15h), toggle disponível/indisponível em tempo real.
- **Ficheiros:** `partner_products_screen.dart`, `partner_product.dart`, migration `menu_availability_window`.
- **Esforço:** média.

#### Tarefa 3.3 — Reservas de mesa (BR §14.4 a §14.8)
- **O que faz:** novo fluxo cliente (escolher data/hora/nº pessoas + pré-pagamento €3); tabela `reservations` com RLS; painel parceiro com pendentes / aceitar / sugerir / recusar; timeline do dia; botão "Marcar sentado" (`customer_arrived`); lembretes automáticos.
- **Ficheiros:** novo `reservation_flow_screen.dart`, novo `reservations_section` em `partner_dashboard_screen.dart`, migration completa, Edge Function `reservation-reminder`.
- **Esforço:** grande — é o maior lote do projecto.
- **Aprovação:** OBRIGATÓRIA — pré-pagamento via Stripe + RLS.

---

### LOTE 4 — DRIVER HELP + PAINEL ADMIN COMPLETO (**MÉDIA — operacional**)

#### Tarefa 4.1 — Driver Help (BR §5.2)
- **O que faz:** botão "Preciso de ajuda" em `driver_home_screen.dart` (só visível se pedido é mercado/não-parceiro); dispatch auxiliar usa o motor existente para escolher 2º driver (40s); split €8/€4 no payout.
- **Ficheiros:** `driver_home_screen.dart`, RPC nova `request_driver_help`, trigger payout.
- **Esforço:** média.
- **Aprovação:** OBRIGATÓRIA — toca no dispatch (⚠ zona protegida `dispatch-engine/index.ts`).

#### Tarefa 4.2 — Painel Admin — completar áreas em falta (BR §16.2)
- **O que faz:** adicionar ecrãs: `admin_reservations_screen.dart`, `admin_ratings_screen.dart` (casos problemáticos), `admin_tokens_screen.dart`, `admin_support_tickets_screen.dart`, `admin_sla_screen.dart`.
- **Ficheiros:** 5 novos screens, actualização de `admin_dashboard_screen.dart`.
- **Esforço:** média-grande (muitos ecrãs, mas cada um é CRUD simples).

---

## 3. NOTA FINAL

### Zonas protegidas (BR §25.3) — NÃO vou tocar em nenhum lote:
- `lib/services/pricing_service.dart`
- `lib/dispatch/driver_capacity_service.dart`
- `lib/stores/order_store.dart` método `finalizePurchase` (vou ler, adicionar métodos novos ao lado, nunca editar)
- Triggers DB: `bora_tokens`, `trg_award_tokens_on_delivery`
- Stripe: qualquer código de pagamento — **só via Edge Functions novas, nunca editando existentes**
- `supabase/functions/dispatch-engine/index.ts`

### Lotes que EXIGEM aprovação extra (validation gate CLAUDE.md):
- 1.4 (Stripe + DB)
- 2.1 (foto → Storage buckets + RLS)
- 2.3 (Stripe + split)
- 3.3 (Stripe + RLS)
- 4.1 (dispatch)

### Ordem recomendada de execução:
**Lote 1 → Lote 2 → Lote 3 → Lote 4.** Os lotes 1 e 2 podem ser parcialmente paralelos se o Danilo validar ambos antes.

---

## 4. DECISÃO PENDENTE

**Danilo, aprovas este plano?**
**Posso começar pelo Lote 1 (GDPR + cancelamento cliente)?**

Se sim, pára-me antes de cada task com "—" se quiseres rever o scope detalhado.
Se não, diz o que alterar e eu revojo o plano.
