# C7 — "Tirar e devolver" : o que falta no servidor (proposta, NÃO aplicada)

Missão `missao-geral-2026-10-28`, adendo 5, item 7 (29/10/2026). Escrito por quem fez a C7; só leu o
repo (nada de produção, nenhuma migração aplicada, nenhum commit).

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo descrito — nada aplicado. Só avança com o "autorizo" do
Danilo (com data).

## Em palavras simples

A C7 que já está feita guarda só a ESCOLHA do cliente ("trocar", "tirar e devolver" ou "falar comigo")
e mostra-a ao estafeta e ao admin. Não mexe em nenhum valor. Quando o cliente escolhe "tirar e devolver",
o estafeta marca "não há" no produto — e isso o servidor **já** trata hoje (ver abaixo). O que a regra
do Danilo de 28/10 pede a mais é que o dinheiro desse produto volte pelo **mesmo caminho por onde veio**
(MB Way na hora, cartão em 5 a 10 dias) e não para o saldo da Bora. É isso que esta proposta descreve.

## O que existe hoje (lido no repo)

1. O estafeta marca cada produto da lista como `bought` ou `unavailable`
   (`lib/screens/driver_map_screen.dart`, `_ShoppingListSheetContent`; envio em
   `OrderStore.finalizeStoreShoppingV2WithReceipt` / equivalente do restaurante não parceiro). A foto da
   prateleira vazia fica em `orders.items_unavailable_photos`.
2. Ao fechar o talão, `public.finalizar_talao_nao_parceiro(p_order_id, p_receipt_photo_url,
   p_driver_typed_total_cents, p_items, p_bag_count)` (migração `20260913193234`, zona vermelha) grava
   as linhas em `order_purchase_items_v2` e calcula `v_unavailable_cents` (soma dos produtos
   `unavailable`):
   - **dinheiro** (`v_is_cash`): desconta `v_items_delta_cents` de `final_total` e `cash_total_due`.
     O cliente paga menos na porta. Nada a devolver.
   - **cartão / MB Way**: faz `INSERT INTO wallet_transactions (kind 'refund_credit_free', reason
     'storeshopping_v2_unavailable_items', related_order_id, idempotency_key 'v2_unavail_' || order_id)`
     = **saldo Bora**, não o meio original. É isto que a regra de 28/10 muda.
   - avisa o cliente por `notify-purchase-finalized` (`unavailable_credit_cents`).
3. Troca por parecido existe no mesmo fecho (`status 'replaced'`, diferença de preço) e o chat com foto
   existe (`chat_screen.dart`, cartão de substituição que o cliente aprova/recusa). Por isso as outras duas
   opções da C7 não precisam de servidor novo.
4. Favor com lista (`errand`): não há linhas por produto (a lista é texto livre em `errand_description`,
   mais foto opcional). O cliente paga o valor do talão (`final_purchase_value`); "tirar" = o estafeta não
   compra aquilo e o talão sai mais baixo. Não li o fecho do Favor (a folha `errand_execution_sheet.dart` é
   zona vermelha, não lhe toquei) — **confirmar** se sobra algum excedente de pré-autorização a libertar.

## O que se propõe (3 peças, por esta ordem)

Princípio: o **cálculo** não muda (continua `v_unavailable_cents`, no mesmo sítio). Muda só **para onde
vai** a devolução, e só com um interruptor novo desligado. Pedidos sem escolha da C7 também passam a
devolver ao meio original quando o interruptor ligar — é a regra de 28/10 e não faria sentido ter dois
caminhos.

### Peça 1 — migração: interruptor e fila de devoluções por produto em falta

```sql
insert into public.platform_settings (key, value, description, category) values
  ('item_refund_original_method_enabled', 'false'::jsonb,
   'Produto em falta pago por cartão ou MB Way volta ao meio original (e não ao saldo Bora).', 'financeiro')
on conflict (key) do nothing;

create table if not exists public.order_item_refunds (
  order_id        text primary key references public.orders(id),
  user_id         uuid not null,
  cents           integer not null check (cents > 0),
  status          text not null default 'por_fazer'
                  check (status in ('por_fazer', 'a_processar', 'devolvido', 'falhou')),
  stripe_refund_id text,
  stripe_cents    integer,
  wallet_cents    integer,
  error           text,
  created_at      timestamptz not null default now(),
  done_at         timestamptz
);
alter table public.order_item_refunds enable row level security;
create policy order_item_refunds_cliente on public.order_item_refunds
  for select using (user_id = auth.uid());
create policy order_item_refunds_admin on public.order_item_refunds
  for select using (public.is_admin());
-- sem policy de escrita: só a função do fecho e a Edge (service_role) escrevem.
```

A chave primária é o pedido: uma linha por pedido (o fecho do talão já é idempotente e só aplica os
deltas na primeira vez).

### Peça 2 — mudança mínima em `finalizar_talao_nao_parceiro` (zona vermelha)

Só o bloco "CARTÃO/MB WAY" de `IF v_is_cash THEN … ELSE …`. Hoje:

```sql
IF v_unavailable_cents > 0 THEN
  INSERT INTO public.wallet_transactions (...) VALUES (... 'refund_credit_free', 'storeshopping_v2_unavailable_items' ...)
  ON CONFLICT (idempotency_key) DO NOTHING;
END IF;
```

Passa a:

```sql
IF v_unavailable_cents > 0 THEN
  IF coalesce((select value = 'true'::jsonb from public.platform_settings
                where key = 'item_refund_original_method_enabled'), false) THEN
    INSERT INTO public.order_item_refunds (order_id, user_id, cents)
    VALUES (p_order_id, v_order.user_id, v_unavailable_cents)
    ON CONFLICT (order_id) DO NOTHING;
    -- a Edge refund-item-em-falta trata do resto (chamada junto às outras net.http_post do fecho)
  ELSE
    INSERT INTO public.wallet_transactions (...)   -- exatamente como hoje
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;
END IF;
```

Antes de editar: ler a função **de produção** com `pg_get_functiondef` (o repo pode estar atrás do ar,
já aconteceu noutras funções). O diff é este bloco e mais uma chamada `net.http_post` à Edge nova, no
fim, igual às que já lá estão (`notify-admin-reimbursement`, `ocr-receipt`). A mensagem ao cliente em
`notify-purchase-finalized` tem de dizer o meio (MB Way na hora, cartão 5 a 10 dias úteis) em vez de
"crédito no saldo" quando o interruptor está ligado.

### Peça 3 — Edge Function nova `refund-item-em-falta` (zona vermelha, só `service_role`)

Usa o pacote do Bloco 2 (`_shared/cobranca_stripe.ts` v2: `lerPagoDoPedido`, `repartirReembolso`), que
já reparte um valor entre a Stripe (até ao que ainda se pode devolver lá) e o saldo (só até ao que se
pagou com saldo). Esboço:

```ts
// refund-item-em-falta — só service_role (mesmo jwtRole() da função refund)
const { order_id } = await req.json();
const admin = createClient(url, secretKey());
// 1) reclamar a linha: evita devolver duas vezes se a chamada repetir
const { data: row } = await admin.from('order_item_refunds')
  .update({ status: 'a_processar' })
  .eq('order_id', order_id).eq('status', 'por_fazer')
  .select().maybeSingle();
if (!row) return json({ ok: true, skip: 'nada_por_fazer' });

// 2) quanto se pagou e por onde (Bloco 2)
const pago = await lerPagoDoPedido(admin, stripeKey, order_id);
const { stripeCents, carteiraCents } = repartirReembolso(row.cents, pago);

// 3) meio original: Stripe (cartão e MB Way têm PaymentIntent)
let refundId: string | null = null;
if (stripeCents > 0) {
  const r = await stripe.refunds.create(
    { payment_intent: pago.piId!, amount: stripeCents,
      metadata: { order_id, kind: 'item_em_falta' } },
    { idempotencyKey: `item-falta-${order_id}` });
  refundId = r.id;
}
// 4) a parte que foi paga com saldo volta ao saldo
if (carteiraCents > 0) {
  await admin.rpc('wallet_credit_refund_full',            // a mesma que o reprocess-refund usa
    { p_order_id: order_id, p_user_id: row.user_id,
      p_total_cents: carteiraCents, p_reason: 'item_em_falta' });
}
await admin.from('order_item_refunds').update({
  status: 'devolvido', stripe_refund_id: refundId,
  stripe_cents: stripeCents, wallet_cents: carteiraCents, done_at: new Date().toISOString(),
}).eq('order_id', order_id);
// falha em 3 ou 4: status 'falhou' + error; o painel mostra e o admin repete.
```

Cuidados: (a) a função `refund` atual recusa valores abaixo de 0,50 € — esta **não** deve herdar esse
corte (um produto em falta de 0,30 € também tem de voltar); (b) confirmar no banco a assinatura exata e a
idempotência de `wallet_credit_refund_full` antes de a usar; (c) tokens: não entram aqui (o pacote do
Bloco 2 devolve tokens só no cancelamento; um produto em falta não devolve tokens — **pergunta 2** abaixo).

### Painel admin (paridade)

A secção da C7 no detalhe do pedido (`AdminSubstituicaoSection`) já lê hoje o crédito no saldo
(`wallet_transactions` com `reason 'storeshopping_v2_unavailable_items'`). Com a Peça 1 passa a ler também
`order_item_refunds` (estado, valor na Stripe, valor no saldo) e a mostrar "Repetir devolução" quando o
estado for `falhou` — chamando a Edge com a sessão de admin. Isto só se faz depois de a tabela existir:
ler uma tabela que ainda não existe estragaria a secção.

## Como se prova (nada disto toca produção)

1. **SQL em PGlite/rollback** (como a proposta 03 do Bloco 2): modelo mínimo de `orders`,
   `platform_settings`, `wallet_transactions`; cenários — cartão 10 € com produto de 2 € em falta:
   interruptor desligado → 1 linha em `wallet_transactions`, 0 em `order_item_refunds` (igual a hoje);
   interruptor ligado → 0 em `wallet_transactions`, 1 linha `por_fazer` com 200; repetir o fecho → continua
   1 linha; pedido a dinheiro → nenhuma das duas (só o desconto).
2. **Edge com Deno e Stripe/Supabase falsos** (como o `cobranca_stripe` 6/6): `repartirReembolso(200,
   {stripeDisponivelCents: 1000, …})` → `{stripe: 200, carteira: 0}`; pedido misto (saldo 300 + Stripe 700,
   produto de 800) → `{stripe: 700, carteira: 100}`; chamar duas vezes → um só `refunds.create`.
3. **Em produção, só depois do "autorizo"**: `select` ao pedido de teste a seguir (linha `devolvido`,
   `stripe_refund_id` não nulo). A regra do Danilo é testar pagamentos só em dinheiro, mas dinheiro não
   exercita este caminho (não há Stripe) — o teste real exige um pagamento verdadeiro mínimo no cartão do
   Danilo. **Pergunta 3.**

## Ordem de aplicação (quando houver "autorizo")

1. O pacote do Bloco 2 (passos 1 a 3 do `LEIA-ME.md`) — esta proposta usa o `_shared` v2.
2. Peça 1 (migração, interruptor desligado) + Peça 3 (Edge) — sem efeito, ninguém as chama.
3. Peça 2 (mudança no fecho do talão) — ainda sem efeito com o interruptor desligado.
4. Ligar `item_refund_original_method_enabled` só depois da prova do ponto 3.
5. Pôr a migração também em `supabase/migrations` (`[skip ci]`).

## PARA O DANILO

1. Um produto em falta pago por cartão ou MB Way deve voltar ao meio original (como o cancelamento), ou
   continua a ir para o saldo Bora como hoje? Proposto: meio original, com o interruptor desligado até dizeres.
2. Os tokens gastos no pedido voltam quando falta um produto? Proposto: não (só no cancelamento).
3. Autorizas um pagamento real mínimo no cartão para provar a devolução de ponta a ponta?

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo descrito — confirma que eu preparo os ficheiros finais.
