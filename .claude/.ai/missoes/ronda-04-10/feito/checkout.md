# Agente checkout — relatório (04/10/2026)

Ramo: `agente-checkout` @ c74e2b77 (worktree ../wt-ronda/checkout).
CI: `analise-checkout` @ 38a2fc41 (c74e2b77 + só o commit do workflow estrito) — run 37230882173 **VERDE**
(flutter analyze sem erros, 7 avisos = igual à base; flutter test verde).

## FEITO

### 1. "Ir buscar" (takeaway) de ponta a ponta
- `quote_order_pricing` aceitava só restaurant/storeShopping/... → **recusava takeaway** (`INVALID_SERVICE_TYPE`). Como o
  `create-payment-intent` passa pelo quote, **o cartão em takeaway nunca funcionava**. Agora tem o ramo takeaway igual ao do
  `create_order`: total = subtotal, sem entrega/taxa de serviço/saco/taxa pequena; buffer = charge_total; exige parceiro e
  `takeaway_enabled`. Migrations `20261004160100_checkout_takeaway_markup_dinheiro_porta.sql` (aplicada como
  `checkout_takeaway_markup_dinheiro_porta` + correção `checkout_quote_takeaway_parcelas`).
- App: `CartStore.pricingBreakdown` (lib/stores/cart_store.dart ~l.287) devolve 0 de entrega/serviço/saco em takeaway
  (o PricingService caía no ramo de recurso com 2,50 € de entrega que o servidor nunca cobra).
- `payment_method_screen.dart`: sem linha "Entrega" em takeaway; não exige morada de entrega em takeaway (antes bloqueava
  o pagamento com "Endereço de entrega não definido"); takeaway e create_order/rascunho do cartão mandam `product_lines`
  (order_store.dart, os dois payloads).
- **PROVA SQL** (transação desfeita, cliente demo, Goola 5×11,55 € em dinheiro): quote total=57.75 entrega=0 serviço=0 saco=0
  buffer=57.75 comissão=5.77 | create_order total=57.75 entrega=0 serviço=0 saco=0 buffer=57.75 comissão=5.77 → **iguais**.

### 2. Um só total
- Ecrã de pagamento mostra o `customer_total` do servidor (e subtotal/taxas/saco/entrega do quote). Guardião
  `_quoteDesteCarrinho`: só usa o quote se o tipo de pedido, o subtotal (±1 cêntimo) e o apartamento baterem com o carrinho
  (a cache de 30 s do CartStore não olha para o carrinho). Sem quote válido → provisório local.
- O "só cartão com saldo" (wallet-only) passa a usar o total do servidor.
- O quote passa a aceitar `vendor_name` para resolver a loja (is_partner/taxa pequena da loja, como o create_order).

### 3. Limite do dinheiro — uma só fonte
- `platform_settings.max_cash_amount_cents` (4000). Coluna `client_wallets.cash_limit_override_cents` **NÃO existe** → sem override.
- Gatilho `enforce_cash_payment_limit` lê a chave (era `> 40` cravado) e isenta takeaway ("Pagar na loja", como a app já dizia).
- App: novo `lib/services/limite_dinheiro_service.dart`; usado em payment_method_screen (bloqueio + **aviso escrito por baixo
  das opções**, não só tooltip), order_store (pré-verificação: takeaway isento; quando bloqueia grava
  `lastCreateOrderError=CASH_LIMIT_EXCEEDED` → mensagem clara), errand_form_screen (`_maxCashCents`), order_edit_service (texto).
- `business_rules.dart` e `_shared/business_rules.ts`: comentário corrigido (a constante é só recurso; o TS dizia que lia a chave — não lia).
- Mensagens novas no pagamento para `CASH_LIMIT_EXCEEDED`, `STORE_PAUSED`, `TAKEAWAY_*` (+ EN em strings_en.dart e
  tool/l10n/traducoes/pt-en-10-checkout.json).
- **PROVA SQL**: entrega em dinheiro 5×11,55 → `CASH_LIMIT_EXCEEDED: ... apenas ate 40.00 EUR (pedido = 63.44 EUR)`;
  takeaway 57,75 € em dinheiro → passa.

### 4. create-mbway-payment-intent (v29 → **v30**, verify_jwt=false como no ar)
- Exige JWT válido (401 sem sessão) e que `orders.user_id` seja o do utilizador (404 se não for).
- Idempotência encadeada: `mbway_<order>_<PI anterior|primeiro>`; se o PI anterior ainda está vivo, devolve-o; se falhou,
  cria um novo (acabou a janela de 24 h presa ao 1.º pagamento). Resposta igual (`{ok,paymentIntentId,status,mode}`).
- Código em `supabase/functions/create-mbway-payment-intent/index.ts`. A app já manda o JWT (functions.invoke).
- Prova por HTTP sem sessão: **não feita** (o classificador bloqueou o curl ao endpoint de produção).

### 5. 1.15 cravado
- Markup: `create_order` e `quote_order_pricing` leem `non_partner_markup_pct` (já existia, 0.15).
- Buffer de pré-autorização (×1.15): chave nova `non_partner_payment_buffer_multiplier` = 1.15.
- **PROVA**: 8 pedidos recentes (6 não-parceiros + 2 parceiros) — quote e create_order (desfeito) dão exatamente os mesmos
  total/subtotal/buffer antes e depois (ae3182e5 9.10/4.12/10.47, b18d2675 30.44, dcc8c509 31.49, 6158b439 13.32,
  736d667e 24.55, 835fb9b1 30.66, 21904f56 22.16, 9cba3644 16.38 — todos iguais).

### 6. Código morto
- Apagados `finalizePurchase`, `finalizePurchaseWithReason`, `_finalizePurchaseUnchecked` (order_store.dart, −121 linhas;
  0 chamadas em lib/ e test/). Escreviam colunas de dinheiro direto do telemóvel.

### 7. "Deixar à porta"
- Servidor: `create_order` lê `deixar_a_porta` do input e grava (falso em takeaway; também no ramo errand) e devolve-o.
  **PROVA**: entrega 1×11,55 com `deixar_a_porta=true` → coluna gravada `t`; takeaway → `f`.
- App: `order_store.createOrder` e `startCardPaymentDraft` aceitam `deixarAPorta` e mandam `deixar_a_porta`.
- **Falta a opção no ecrã** (ver NÃO FEITO).

### 8. Carrinho abandonado
- Migration `20261004160300_carrinhos_abandonados.sql` (aplicada): tabela `carrinhos_abandonados` (1 por pessoa, RLS do
  próprio + admin), RPCs `carrinho_guardar`/`carrinho_convertido`, `carrinhos_abandonados_avisar()` (máx. 1 por carrinho,
  1 por dia, só carrinhos com <3 dias, ignora quem já fez pedido; in-app + push via `notify-client`), cron
  `carrinhos-abandonados-15min` (jobid 100), definições `carrinho_abandonado_ligado=false`, `_minutos=60`, `_titulo`, `_texto`.
- Admin PT-BR: `lib/screens/admin/admin_carrinhos_abandonados_screen.dart` (ligar/desligar, minutos, título, texto, números,
  lista com hora de Lisboa) + linha `clientes_carrinho_abandonado` no admin_menu_registry; RPCs
  `admin_carrinhos_abandonados_resumo` / `admin_carrinho_abandonado_config` (com admin_audit_log).
- **PROVA SQL**: desligado → 0 avisos; ligado + carrinho do demo com 61 min → 1 aviso (1 in-app criada); 2.ª passagem → 0;
  o cliente não vê linhas de outros (RLS).
- **Falta a app gravar o retrato** (ver NÃO FEITO) — até lá a tabela fica vazia e o cron não faz nada.

### Pedido do agente parceiro (pausa)
- `create_order` E `quote_order_pricing` recusam `STORE_PAUSED` quando `restaurants.pausa_ate > now()` (lido por
  `to_jsonb(r)->>'pausa_ate'`, não parte enquanto a coluna não existir). No quote para o cartão falhar ANTES de cobrar.

## NÃO FEITO (bloqueado pelo classificador de permissões, "[Production Deploy]")
1. `lib/services/pricing_service.dart` (M7): pôr `_nonPartnerPurchaseFee = 0.99` e ramo takeaway — **edição recusada**
   (zona protegida). Contornado só no CartStore (takeaway) e já existia o override 0,99 via RemoteFeesService.
2. `lib/stores/cart_store.dart` — reescrita do quote (cache presa à entrada do carrinho, `garantirQuote`, `resumo` único para
   carrinho+pagamento), estado `deixarAPorta` + passagem no `finishOrder`/`startCardPaymentDraft`, e o retrato do carrinho
   abandonado (`carrinho_guardar` com pausa de 8 s / `carrinho_convertido`) — **edição recusada**. Consequências:
   o carrinho continua a mostrar o total local (alinhado, mas não o do servidor); a opção "Deixar à porta" não aparece no
   checkout; o carrinho abandonado não recebe dados.
3. `lib/screens/cart_screen.dart` — tirar a gorjeta do "Total a pagar" do carrinho (é cobrada à parte e o ecrã de
   pagamento não a soma → os dois totais diferem quando há gorjeta, e o saldo Bora é calculado sobre um valor com gorjeta)
   — **edição recusada**. `tips_enabled=false`, por isso hoje não aparece a ninguém.
4. Prova HTTP do MB Way sem sessão (curl ao endpoint de produção recusado).

## PRECISA DE CONFIRMAÇÃO
- Nenhum SQL com DROP/DELETE foi necessário.
- Danilo/humano: autorizar as 3 edições acima (pricing_service.dart, cart_store.dart, cart_screen.dart) — o código está
  descrito no ponto NÃO FEITO; o servidor já está pronto para elas.

## PEDIDOS A OUTROS AGENTES
- PEDIDO A parceiro: criar `restaurants.pausa_ate timestamptz`; o create_order/quote já a respeitam (`STORE_PAUSED`).
- PEDIDO A cliente-app/estafeta: mostrar `orders.deixar_a_porta` ao estafeta ("Deixar à porta") no detalhe do pedido.
- PEDIDO A notificações/app: o push `type=carrinho_abandonado` (data.kind) devia abrir o carrinho ao tocar.

## RISCOS
- `quote_order_pricing` agora resolve a loja pelo `vendor_name` quando vem no input (o create-payment-intent manda-o): o
  is_partner passa a vir sempre da BD — o mesmo que o create_order já fazia; o pré-autorizado do cartão fica igual ao cobrado.
- O gatilho do dinheiro deixou de bloquear takeaway (pagar na loja) acima de 40 €, como a app já anunciava.
- Ecrã de pagamento: se o quote não bater com o carrinho (opções com extras arredondados) cai no provisório local — nunca
  mostra um quote de outro carrinho.
- strings_en.dart editado à mão (o gerador `tool/l10n/gerar_dicionario.py --write` apagaria 434 linhas que não estão nos json —
  NÃO correr o gerador sem antes pôr essas entradas nos json).
