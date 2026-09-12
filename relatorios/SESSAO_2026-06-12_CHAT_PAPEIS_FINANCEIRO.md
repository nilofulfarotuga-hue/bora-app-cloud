# Sessão 2026-06-12 — Chat por papéis (C) + Financeiro (F1/F2/F3)

> Branch `autonomous-night-2026-04-29` · commits `1612657` (C) + `e29a593` (F2) · flutter analyze **0 errors**
> Knowledge lido no arranque: CEO-AI SKILL + BORA_DNA + 05-business-rules + relatórios M11/B2.

---

## PARTE C — Chat: separação por papéis ✅

### Bugs encontrados (4 reais, todos corrigidos)

1. **Chat com loja NÃO-parceira existia** (a foto do Leroy Merlin). Provado em DB: pedido
   `32b97c20` (Leroy, `is_partner_store=false`, `restaurant_id=NULL`) tinha mensagem
   `driver_partner` — e a resposta do pipeline foi `recipient_not_resolved` (pg_net id 1717).
   O chat ia literalmente para o vazio.
2. **`chat_mark_read` rebentava SEMPRE** com `operator does not exist: uuid = text`
   (messages.order_id uuid vs parâmetro text). O Flutter engole o erro → `read` nunca foi
   marcado desde M11: badges nunca zeravam, ✓✓ nunca aparecia.
3. **Mark-read não filtrava o par**: abrir o chat do estafeta zerava o badge do parceiro
   (threads misturadas na leitura).
4. **Tap no push / order_details abriam o par errado** (resolução por status: `preparing`
   → client_partner mesmo em loja não-parceira).

### Fixes

| Onde | O quê |
|---|---|
| `order_tracking_screen` | "Falar com o Restaurante" só com `order.isPartnerStore` |
| `driver_home_screen` | Seletor estafeta: "Chat · Cliente" sempre + "Chat · Restaurante" só parceiro |
| `driver_map_screen` | Botão do sheet → `openDriverChat` (chooser); **FAB flutuante NOVO** sempre visível no mapa com badge vermelho realtime (`driver_chat_fab.dart`) |
| `chat_mark_read` v2 (migration `20260612001000`) | cast `order_id::text` + parâmetro `p_conversation_type` (marca lidas só do par aberto; NULL legacy = todos) |
| `notify-chat-message` **v11** (deployed + espelho repo) | fallback conversation_type vazio → par direto (client↔driver); razão `no_partner_for_order` explícita |
| `notification_service` | tap no push abre o par do payload (`conversation_type`), nunca por status |
| `order_details_screen` | card estafeta → `client_driver` explícito |

### Provas de push (INSERT de teste + respostas pg_net, mensagens apagadas depois)

| Par | Resultado |
|---|---|
| cliente → **estafeta** | `{"ok":true,"sent":1}` ✅ (era o que nunca chegava) |
| estafeta → **cliente** | `{"ok":true,"sent":2}` ✅ |
| sem conversation_type (fallback v11) | `{"ok":true,"sent":2}` ✅ |
| cliente → **parceiro** | `no_fcm_token` ⚠️ — resolução OK, mas o único token do parceiro está `active=false` |

**⚠️ AÇÃO DANILO (parceiro):** o push ao parceiro só funciona depois de **1 login no
device do parceiro com build ≥ que inclua o B2** (commit `ee70325` corrigiu o registo
do token). Depois disso o pipeline está provado de ponta a ponta.

**Badges:** o contador agora zera ao abrir a thread certa (era impossível antes do fix 2).
Verificação visual no device fica para o próximo build (CI gera versionCode novo).

---

## PARTE F1 — Auditoria financeira transversal ✅ (read-only, ZERO dados alterados)

### ✅ Confere ao cêntimo (provado com os pedidos reais de 11/06)

- **Totais não-parceiro**: subtotal + entrega + fee €2.50 + sacos = total. Leroy: 4.89+3.94+2.50+0.10=11.43 ✓ (entrega 2.50+0.50×2.878km ✓)
- **Driver earnings (fórmula completa c/ 30% profit share)**: 5.29 / 5.30 / 6.34 batem EXATOS com `pricing_service` nos 3 pedidos
- **Cash settlement**: dívida = final_total − earnings (5.64 e 3.45 no ledger ✓; trigger com UNIQUE anti-duplicação ✓)
- **Tokens**: cliente ROUND(total×3) (26, 33 ✓); driver +40 ✓; conversões ×€0.005 exatas (580→2.90 … 18→0.09) ✓
- **Parceiro 10+5+5** (pedidos ifxfixif 27/05): visible 0.30=10% ✓, hidden 0.15 ✓, service client 0.15 ✓, partner_share ledger 2.70=subtotal−10% ✓
- **Marcações**: sinal €3 nos pagos ✓; cancelamentos com depósito nunca pago → nada a repartir ✓; no-show 11/06 tinha `deposit_status=waived` → €0 (consistente)

### ⚠️ Divergências encontradas (NÃO corrigi dados — decisão tua)

1. **ifxfixif 27/05 ×2: driver_earnings = €3.00 vs fórmula €4.75** (3.80+0.20×4.767).
   Anomalia histórica em 2 pedidos de teste; a fórmula ATUAL no código está correta.
2. **pizza danilo 26/05: colunas partner_commission_* = 0** mas ledger correto (4.10/36.90).
   Pedido pré-população das colunas Batch D. Só histórico.
3. **driver_balances = −17.13** não reconcilia com ledger nem settlements à vista
   (semana atual: dívida cash 9.09; all-time pós-settlements: −366.89). Investigar o
   trigger/reset noutra sessão — não mexi.
4. **`compute_driver_settlement.tokens_converted_value` sempre 0** → **CORRIGIDO no F2**
   (única correção, porque faz parte do fecho que mandaste implementar).
5. **€5.40 de partner_share (ifxfixif) ainda sem payout** (payouts 505.25 vs share 510.65)
   — agora aparece no fecho semanal novo.
6. 📝 `orders.total` = snapshot da criação (sacos default); `final_total` = autoritativo
   pós-compra v2. Dinheiro real usa final_total ✓; tokens usam `total` (±1 token possível).
7. 📝 Profit share calcula markup como subtotal×15% em vez de (subtotal−subtotal/1.15)
   — sobreavalia o lucro Bora ~15% do markup → cêntimos A FAVOR do estafeta. Decisão de
   implementação Batch D; mudar = mexer em pricing (não toquei).
8. 📝 Stripe: só 1 pedido card delivered (45.55, pré-buffer) — amostra insuficiente para
   auditoria Stripe↔orders; pedidos novos validam ±5% server-side na EF.
9. Wallet (0 transações) e Reservas mesa (0 rows): nada para auditar com dados reais.

---

## PARTE F2 — Fecho semanal ✅ (estende o existente, não duplica)

**Já existia** (e foi aproveitado): `driver_weekly_settlements` + `compute_driver_settlement`
+ cron `close-weekly-settlements` (seg 00:05) + ecrã admin de estafetas +
`compute_provider_weekly_payout` (serviços/barbearias, cron seg 08:00) + `auto_payout_pending`.

**Novo:**
- Tabela **`partner_weekly_settlements`** (RLS: parceiro lê só o seu; escrita só via RPC)
- `compute_partner_weekly_settlement` — vendas brutas, comissão, parte do parceiro
  (ledger = fonte), **cash-takeaway entra ao contrário** (parceiro já recebeu → deve a diferença)
- `run_weekly_closeout()` — fecha estafetas+parceiros, cria notificação admin e **manda push**
  (EF `notify-admin-urgent` v12, modo generic; caminho crosstalk intacto). O cron de segunda
  00:05 agora chama isto.
- `admin_weekly_bora_totals` — receita, comissões, fees, sacos, sinais de marcações da semana
- **Ecrã admin "Fechos Semanais"** (PT-BR): totais Bora + secção Estafetas (existente) +
  secção Parceiros com detalhe expandível, **FECHAR SEMANA com dupla confirmação**,
  estados Aberto/Fechado/Pago/Recebido/Disputa, tudo no audit log
- **Painel do parceiro**: card "Fecho semanal" read-only em Ganhos — "Esta semana: X pedidos,
  €Y brutos, a receber €Z" + últimas semanas com estado
- **FIX**: tokens convertidos entram no net do estafeta (divergência F1-4)

**Provas com dados reais:**
- Fecho estafeta semana atual: 2 entregas · €10.59 ganhos · €19.68 cash · **€5.71 tokens**
  → net **−€3.38 driver_pays_bora** (persistido, visível no admin) ✓
- pizza danilo semana 25/05: bruto €41.00 · comissão €4.10 · **a transferir €36.90** =
  exatamente o payout real já registado no ledger ✓ (validação cruzada)
- Push admin: `push_success:1` no teu device (+26 tokens velhos limpos automaticamente)

**Nota horário:** o fecho corre segunda 00:05 UTC (madrugada de domingo→segunda em Lisboa)
para apanhar a semana completa até domingo 23:59 — a push chega-te na madrugada; vês segunda
de manhã. Se preferires domingo à noite (semana ainda aberta), digo-me que ajusto o cron.

---

## PARTE F3 — Lacunas de controlo financeiro (SÓ RELATÓRIO — nada implementado)

Prioridade alta → baixa, visão de contabilidade de marketplace:

1. **Fees do Stripe não registadas** (P1): a Bora recebe LÍQUIDO (ex.: 45.55 − ~1.4% − €0.25).
   Hoje nada guarda o fee → receita sobreavaliada. Solução típica: webhook guarda
   `balance_transaction.fee` por payment_intent numa coluna/tabela `stripe_fees`.
2. **Ledger de reembolsos incompleto** (P1): `refund_amount` existe em orders mas não há
   entries de refund no ledger → o ledger não fecha contra o Stripe em meses com refunds.
3. **Exportação CSV/Excel dos fechos** (P2): para contabilista/arquivo. Os dados já estão
   nas tabelas de settlements — falta botão exportar no admin.
4. **IVA / faturação PT** (P2, legal): comissões da Bora a parceiros exigem fatura com IVA
   (23%); recibos ao cliente final. Hoje não há número de fatura, série, nem SAF-T. Antes do
   lançamento real: decidir software certificado (ex.: InvoiceXpress/Moloni) + mapear o que
   é receita Bora vs repasse.
5. **Reconciliação mensal** (P2): job que compara Σ ledger vs Σ Stripe payouts vs Σ orders
   por mês e alerta diferenças (>€0.01). O F1 desta sessão foi manual — automatizar.
6. **driver_balances vs ledger** (P2): reconciliar a fonte (divergência F1-3) e decidir se
   settlements pagos fazem reset do balance.
7. **Idempotência/cap de refund** (P3, já no backlog como BUG-MN-004): verificar.
8. **Moeda/arredondamento canónico** (P3): hoje há numeric em €; considerar cents integer
   em tabelas novas (settlements usam numeric — consistente com o existente).

---

## Validação final
- flutter analyze: **0 errors** (warnings pré-existentes mantidos; órfãos meus limpos)
- Chat provado com mensagens de teste nos 3 papéis (server-side; parceiro bloqueado por
  token inactive — ação acima)
- Fecho semanal gerado com dados reais e visível no admin (semana atual + 25/05)
- Espelho admin: ecrã Fechos Semanais + audit log em todas as mudanças de estado ✓
- Dead code pré-existente notado (não removido): `_myRole` em chat_bubble_button.dart:46

## Pendências para o Danilo
1. **Instalar build novo** (CI gera) e verificar no device: chat Leroy SEM botão restaurante;
   FAB de chat no mapa do estafeta; badges zeram ao abrir; ✓✓ aparece.
2. **Login no device do parceiro** (1×) para registar token → push de chat ao parceiro.
3. Decidir as divergências F1 #1-#3 (históricas) e o horário do fecho (domingo vs segunda 00:05).
4. F3: escolher prioridades para próxima sessão (sugiro #1+#2 Stripe fees + refunds no ledger).
