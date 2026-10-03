# Decisões de Design — Wallet 80/20, Promos, Referral, Cashback
> Data: 2026-04-30 · Autor: CEO-AI (autonomous session) · Branch: `autonomous-night-2026-04-29`

## Contexto

Bora App está em pré-lançamento. Stripe LIVE activo. Sistema de tokens (`bora_tokens`) já operacional desde Batch D.

Danilo (2026-04-30) decidiu introduzir **wallet híbrido 80/20** para reembolsos: cliente que cancela pedido pode escolher reembolso para cartão (5-10 dias) ou para a app (instantâneo). Se app, valor é dividido 80% saldo livre + 20% tokens.

Esta decisão integra-se com 11 features adicionais (audit viewer, aprovação de cancelamentos, mapa live, exports, settings, promos, referral, cashback, dashboard real-time) — todas com objectivo de diferenciar Bora face a iFood/Uber Eats/Glovo.

---

## Pesquisa de mercado (2026-04-30)

### iFood (Brasil) — referência principal
**Fonte:** [institucional.ifood.com.br/clientes/prazos-e-regras-para-reembolso-ifood-ao-cliente](https://institucional.ifood.com.br/clientes/prazos-e-regras-para-reembolso-ifood-ao-cliente/)

Padrão escolhido por Danilo:
- Cliente escolhe método de reembolso a cada transação (default configurável)
- **Saldo iFood = instantâneo** (mesmo dia), exclusivo dentro do app
- Cartão crédito = até 2 faturas (~30-60 dias), pré-pago/débito = até 30 dias
- Pix = mesmo dia
- Vale-refeição = 48h
- "A maneira mais rápida de receber é ativar o reembolso em saldo no iFood"

**Aplicado ao Bora:**
- Diálogo no cancelamento: "Cartão (5-10 dias úteis)" vs "App (instantâneo)"
- Default sugerido: app (push fricção positiva para retenção)
- Saldo na app não-reembolsável em dinheiro (compliance PT — texto rodapé)

### Uber Eats — Uber Cash/Credit
**Fonte:** [help.uber.com/en/ubereats/restaurants/article/how-does-uber-credit-work](https://help.uber.com/en/ubereats/restaurants/article/how-does-uber-credit-work?nodeId=3f9dc347-44e1-4b20-96d9-18ab66866183)

- Uber Cash aplicado em qualquer pedido via "Payment Options"
- Refund: payment method original é reembolsado, Uber Money é deduzido se houver saldo (ou seja, Uber prefere usar saldo internamente para minimizar fricção)
- Refund de Uber Money comprado: só para saldo não usado

**Aplicado ao Bora:** Switch "Usar saldo livre" no checkout (toggle on por default). Cobre o que pode, resto vai para Stripe.

### Glovo — Credits/Promos restritivos
**Fonte:** [glovoapp.com/en/promo](https://glovoapp.com/en/promo/), [referralcodes.com/shop/glovo-referral-code](https://referralcodes.com/shop/glovo-referral-code)

- Glovo créditos **expiram em 30-90 dias** se não usados
- Promo codes raramente site-wide — restritos a categorias (groceries), partners específicos, com mínimos (€10+)
- Apenas 1 promo code por pedido (sistema escolhe o de maior desconto se múltiplos)
- Convites: ~€8.50 crédito ao novo utilizador

**Aplicado ao Bora:**
- ❌ **NÃO** vamos pôr expiração no saldo livre (decisão Danilo: "NUNCA expira"). Diferencial vs Glovo.
- ✅ Promos: 1 por pedido, com `min_order_cents`, `partner_ids` opcional, `max_uses_per_user`, `valid_until` opcional.
- ✅ Referral: €5 ambos (€500 cents) ao 1º pedido entregue do convidado, expira em 30 dias.

---

## Decisões finais

### D1 — Wallet 80/20 split
- **Saldo livre**: tabela nova `client_wallets` (free_balance_cents). NUNCA expira. Sem regras de uso.
- **Tokens**: tabela existente `bora_tokens` (não duplicar). Regras existentes (50% desconto checkout).
- **Conversão**: token = €0.0005 (0.05 cents). 20% de €X em cents → tokens = (cents * 20% * 100 / 0.05) = cents * 4 (CORRECÇÃO: re-leitura do prompt — "tokens_count = tokens_amount_cents * 20"). Verificação:
  - 20% de 1000 cents (€10) = 200 cents = €2
  - €2 ÷ €0.0005/token = 4000 tokens
  - 200 cents × 20 = 4000 ✅
- Splits configuráveis em `platform_settings.wallet_split_free_pct` (default 0.80).

### D2 — Refund choice dialog (cliente)
Padrão iFood. Diálogo `RefundChoiceDialog` em `order_detail_screen` com:
- Radio "Cartão (5-10 dias úteis)" — chama Edge Fn `refund` (existente)
- Radio "App — instantâneo" — chama Edge Fn `cancel-order-with-choice` (nova)
  - Preview ao vivo: "€8.00 saldo livre + 4000 tokens (≈€2.00)"
  - Microcopy: "Saldo livre nunca expira. Tokens dão 50% desconto no checkout."
- Campo motivo (free text) obrigatório
- CTA: "Confirmar cancelamento"

### D3 — Wallet UI no perfil
- 2 cards no `profile_screen.dart`:
  - Verde: "Saldo Bora — €X (livre, não expira)"
  - Amarelo: "Tokens — Y (≈€Z)"
- Tap → `wallet_history_screen.dart` (lista wallet_transactions + bora_tokens)
- Rodapé compliance: "Saldo não reembolsável em dinheiro"

### D4 — Checkout free balance
- `checkout_screen.dart`: card "Saldo disponível: €X" + Switch "Usar saldo livre"
- Cálculo: `total_a_pagar = max(0, total - saldo_usado)`
- Se saldo cobre tudo: skip Stripe (cria order com `payment_method='wallet'`)

### D5 — Cancellation approval workflow
- Tabela `cancellation_requests` (NOVA — não havia scaffolding)
- Driver/partner pedem cancelamento → admin aprova/rejeita
- Admin escolhe `refund_method` na aprovação (stripe/wallet/none)
- Cliente continua a poder cancelar directamente (sem aprovação) se elegível por timing — wallet choice aplica também

### D6 — Audit Log Viewer
- Reusar `admin_audit_log` (já existe desde 20260428000000)
- Nova RPC `admin_list_audit_log` + nova screen `admin_audit_log_screen.dart`

### D7 — Platform Settings
- Tabela `platform_settings (key, value jsonb, ...)` — fonte de verdade configurável
- Migration seeds defaults (replicando business_rules)
- ⚠️ HIGH-RISK: refactor `pricing_calculate` para LER de settings — fica em sub-branch `draft/pricing-from-settings`, **NÃO merged** automaticamente

### D8 — Promo codes
- Tabela `promo_codes` + `promo_code_uses` (audit per-use)
- 3 tipos: `percent_off`, `fixed_off`, `free_delivery`
- Validações: `valid_until`, `max_uses`, `max_uses_per_user`, `min_order_cents`, `partner_ids[]`, `is_active`
- 1 promo por pedido (regra Glovo)

### D9 — Referral
- Tabela `referral_codes` (1 por user) + `referral_invites` (audit envios+conversões)
- Reward 500 cents ambos (configurável `referral_referrer_reward_cents` / `referral_invited_reward_cents`)
- Trigger em `orders` quando 1º pedido `delivered` do invited → credita ambos via `wallet_credit_refund_split` lógica adaptada (kind='referral' em wallet_transactions, +saldo livre)
- Expira em 30 dias

### D10 — Cashback automático
- Setting `cashback_pct=0.01` (1% default, range 0-5%)
- Trigger em `orders` (status→delivered) → +saldo livre
- Push: "Recebeste €X de cashback do teu pedido!"
- Badge no order_detail entregue

### D11 — Dashboard real-time
- Card "AGORA" topo `admin_dashboard_screen` com 4 métricas
- Auto-refresh 10s via Supabase realtime channel (orders + drivers_online)
- Alerta vermelho se pedido > 30min sem driver

### D12 — Live orders map
- `admin_live_orders_map_screen.dart` em Guarda
- Pinos cor-coded (pendentes laranja, activos verde, drivers azul, parceiros cinza)
- Padrão Glovo Operations / Uber Direct

### D13 — Exports
- CSV: pacote `csv` (pubspec) — pedidos/drivers/clientes/wallet/audit
- PDF: pacote `pdf` — KPIs investidores
- Share Intent (`share_plus`)

---

## Compliance PT
- Saldo Bora **NÃO é dinheiro**. Texto obrigatório em todas as superfícies wallet:
  - "Saldo não reembolsável em dinheiro"
- DGAE/Banco de Portugal: clarificar que crédito interno não é "moeda electrónica" pois (a) emitido por reembolso, (b) usável só na própria plataforma, (c) sem possibilidade de reconversão.
- TODO pós-lançamento: validar com jurista se acima de €X por user obriga registo IM (instituição de moeda electrónica).

## Não vamos fazer (out of scope desta sessão)
- Top-up de saldo livre por cartão (saldo só vem de refunds + cashback + referral + admin grant)
- Transferir saldo entre users
- Saque para conta bancária
- Saldo livre em web (Flutter only)
