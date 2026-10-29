# Proposta 01 — `supabase/functions/_shared/cobranca_stripe.ts` (v2, 28/10/2026)

Missão `missao-geral-2026-10-28`, Bloco 2 (dinheiro), parte do servidor. Agente `pagamentos-wallet`
(só propõe). **Não aplicado.** O ficheiro do repo continua igual ao que está no ar.

## Porque muda

Regra do Danilo (28/10, 18:24): quem paga com MB Way ou cartão recebe pelo mesmo meio (por defeito);
pode escolher 100% em saldo; os tokens gastos voltam como TOKENS, com a validade que tinham; acabou
o 80% saldo + 20% tokens.

O `_shared` de hoje (igual no repo e no ar, empacotado no client-cancel-order v29,
cancel-order-with-choice v18, execute-cancellation v15 e admin-cancel-order v14) tem duas linhas
que impedem a regra quando o servidor passar a gravar `tokens_applied_count` (proposta 03, passo 1):

- linha 40/46: `tokensCents` só conta quando `tokens_applied_count > 0`. Hoje a contagem é sempre 0
  (SELECT 28/10: 21 pedidos com tokens nos últimos 60 dias, 0 com contagem), por isso os tokens
  **perdem-se** em todos os cancelamentos do cliente e do admin.
- linha 92: `carteiraCents = min(pedido - stripe, walletCents + tokensCents)` — mal a contagem
  passe a ser gravada, o valor dos tokens entra na parte da carteira e é creditado como **SALDO**
  (`wallet_credit_refund_split`, 100% saldo desde 18:27) — tokens a virar dinheiro livre, sem o
  limite dos 50%.

O que esta versão faz: os tokens deixam de entrar no "pago" e na carteira (`tokensCents` fica
sempre 0, por compatibilidade com o client-cancel-order v29, que soma os três campos à mão na linha
115); o valor e a contagem passam a vir em campos novos só de leitura (`tokensValorCents`,
`tokensCount`); `repartirReembolso` devolve 100% ao meio escolhido — Stripe até ao que ainda se
pode devolver, o resto só até ao que se pagou com saldo. Os tokens voltam como tokens pelo gatilho
do banco (proposta 03, passo 2).

## Matemática (exemplos)

Pedido 10,00 € = 2,00 € em tokens (400 tokens) + 8,00 € no MB Way. Taxa antes do estafeta 1,50 €.

- Hoje (contagem 0): pago = 8,00; reembolso = min(10,00 − 1,50; 8,00) = 8,00 → 8,00 ao MB Way,
  400 tokens perdidos.
- `_shared` velho + contagem gravada: pago = 10,00; reembolso = 8,50 → 8,00 ao MB Way + 0,50 €
  de tokens creditados como SALDO. Errado.
- Esta versão + gatilho (proposta 03) + index.ts v19/v16 (base sem o valor dos tokens quando a
  contagem > 0): reembolso em dinheiro = min(10,00 − 1,50 − 2,00; 8,00) = 6,50 → 6,50 ao MB Way;
  400 tokens voltam como tokens com a validade original; a taxa (1,50) sai do dinheiro.

Pedido a dinheiro 10,00 € com 3,00 € de saldo e taxa 0 (graça): pago = 3,00 → 3,00 voltam ao saldo.

## Ficheiro inteiro proposto

```ts
// supabase/functions/_shared/cobranca_stripe.ts — ronda 04/10 (05/10/2026), Bloco A.1/A.2
//
// O que o cliente pagou mesmo, por fonte: Stripe (cartão/MB Way), carteira e tokens.
// orders.stripe_charge_cents era sempre 0 (ninguém o gravava): aqui, se estiver a 0 e
// houver PaymentIntent, lê-se a Stripe e grava-se pela função public.registar_cobranca_stripe.
// O limite de reembolso do banco (_enforce_refund_cap) usa a soma destas três fontes.
//
// Revisão de contexto limpo (05/10): desconta-se o que a Stripe já devolveu; sem chave da
// Stripe com PI = erro (nunca "não pagou"); a gravação confirma-se lendo de volta.
//
// v2 (28/10/2026 — regra do Danilo 28/10 18:24, missao-geral-2026-10-28 bloco 2):
//   • Os TOKENS não são dinheiro: nunca entram no "pago" nem vão para a carteira como saldo.
//     Voltam como TOKENS, com a validade que tinham, pelo gatilho do banco
//     trg_orders_devolver_tokens → devolver_tokens_do_pedido (sabe QUAIS tokens o pedido gastou:
//     tabela pedido_tokens_gastos, escrita por consumir_tokens_do_pedido no create_order).
//   • Reembolso 100% ao meio escolhido: Stripe (cartão/MB Way) até ao que a Stripe ainda pode
//     devolver; o resto só até ao que se pagou com SALDO. Sem 80/20 (o banco tem
//     wallet_split_free_pct = 1 desde 28/10 18:27).
//   • Pago.tokensCents fica SEMPRE 0 (compatibilidade: o client-cancel-order v29 soma
//     stripe + wallet + tokens à mão). O valor e a contagem vêm em tokensValorCents/tokensCount,
//     só para informação e para o index.ts tirar o valor dos tokens da base do reembolso
//     quando eles voltam (tokensCount > 0).

// deno-lint-ignore no-explicit-any
type Cliente = any;

export interface Pago {
  piId: string | null;
  /** o que a Stripe cobrou (amount_received) */
  stripeCents: number;
  /** o que ainda se pode devolver pela Stripe (cobrado − já devolvido) */
  stripeDisponivelCents: number;
  /** o que se pagou com saldo da carteira */
  walletCents: number;
  /** v2: SEMPRE 0 — os tokens não são dinheiro (voltam como tokens, pelo banco) */
  tokensCents: number;
  /** v2: valor dos tokens usados no pedido (tokens_applied_value_cents) — só informação */
  tokensValorCents: number;
  /** v2: quantos tokens o servidor gastou e registou (tokens_applied_count); 0 = pedido antigo */
  tokensCount: number;
  /** preço do pedido (customer_total) — nada se devolve acima disto */
  totalCents: number;
  /** estado do PI na Stripe (null se não há PI) */
  piStatus: string | null;
}

/** soma do que foi pago em DINHEIRO (Stripe + saldo), nunca acima do preço do pedido */
export function totalPago(p: Pago): number {
  const soma = p.stripeCents + p.walletCents;
  return p.totalCents > 0 ? Math.min(soma, p.totalCents) : soma;
}

export async function lerPagoDoPedido(admin: Cliente, stripeKey: string, orderId: string): Promise<Pago> {
  const { data: o, error } = await admin.from('orders')
    .select('id, payment_intent_id, stripe_charge_cents, wallet_applied_cents, tokens_applied_count, tokens_applied_value_cents, customer_total, total')
    .eq('id', orderId).maybeSingle();
  if (error || !o) throw new Error(`pedido_nao_lido: ${error?.message ?? orderId}`);
  const pago: Pago = {
    piId: o.payment_intent_id ?? null,
    stripeCents: Math.max(0, Number(o.stripe_charge_cents ?? 0)),
    stripeDisponivelCents: 0,
    walletCents: Math.max(0, Number(o.wallet_applied_cents ?? 0)),
    tokensCents: 0,
    tokensValorCents: Math.max(0, Number(o.tokens_applied_value_cents ?? 0)),
    tokensCount: Math.max(0, Number(o.tokens_applied_count ?? 0)),
    totalCents: Math.max(0, Math.round(Number(o.customer_total ?? o.total ?? 0) * 100)),
    piStatus: null,
  };
  if (!pago.piId) return pago;
  if (!stripeKey) throw new Error('stripe_key_em_falta');

  const res = await fetch(
    `https://api.stripe.com/v1/payment_intents/${encodeURIComponent(pago.piId)}?expand[]=latest_charge`,
    { headers: { Authorization: `Bearer ${stripeKey}` }, signal: AbortSignal.timeout(15000) },
  );
  if (!res.ok) throw new Error(`stripe_pi_${res.status}`);
  const pi = await res.json();
  pago.piStatus = String(pi.status ?? '');
  if (pi.status !== 'succeeded') {
    // a Stripe não cobrou: nada a devolver por ela
    pago.stripeCents = 0;
    return pago;
  }
  const recebido = Number(pi.amount_received ?? 0);
  const devolvido = Number(pi.latest_charge?.amount_refunded ?? 0);
  if (pago.stripeCents === 0 && recebido > 0) {
    const { data: gravou, error: e2 } = await admin.rpc('registar_cobranca_stripe', {
      p_order_id: orderId, p_payment_intent_id: pago.piId, p_cents: recebido,
    });
    if (e2 || gravou !== true) {
      // confirma lendo de volta (outro processo pode ter gravado primeiro)
      const { data: o2 } = await admin.from('orders').select('stripe_charge_cents').eq('id', orderId).maybeSingle();
      if (Number(o2?.stripe_charge_cents ?? 0) <= 0) {
        throw new Error(`cobranca_nao_gravada: ${e2?.message ?? 'nenhuma linha'}`);
      }
    }
  }
  pago.stripeCents = recebido;
  pago.stripeDisponivelCents = Math.max(0, recebido - devolvido);
  return pago;
}

/**
 * Reparte um reembolso em DINHEIRO pelo meio com que foi pago: primeiro volta ao cartão/MB Way
 * (até ao que ainda se pode devolver na Stripe); o resto volta ao saldo, mas só até ao que se
 * pagou com saldo. Os tokens nunca entram aqui (voltam como tokens, pelo banco). Nunca devolve
 * mais do que se pagou em dinheiro nem acima do preço do pedido.
 */
export function repartirReembolso(refundCents: number, pago: Pago): { stripeCents: number; carteiraCents: number } {
  const pedido = Math.min(Math.max(0, Math.round(refundCents)), totalPago(pago));
  const stripeCents = Math.min(pedido, pago.stripeDisponivelCents);
  const carteiraCents = Math.min(pedido - stripeCents, pago.walletCents);
  return { stripeCents, carteiraCents };
}
```

## Diferença em relação ao que está no ar (só isto muda)

- `Pago`: `tokensCents` passa a ser sempre 0; campos novos `tokensValorCents` e `tokensCount`.
- `lerPagoDoPedido`: deixa de usar `usouTokens`; preenche os campos novos.
- `totalPago`: soma só `stripeCents + walletCents`.
- `repartirReembolso`: `carteiraCents` limitado a `walletCents` (antes `walletCents + tokensCents`).

## Quem tem de ser publicado de novo com este `_shared` (empacotam-no)

1. `client-cancel-order` (v29 no ar) — com o index.ts da proposta 02.
2. `cancel-order-with-choice` (v18 no ar) — com o index.ts v19 já preparado no repo da cópia de
   trabalho (`supabase/functions/cancel-order-with-choice/index.ts`).
3. `execute-cancellation` (v15 no ar) — index.ts v16 já preparado no repo.
4. `admin-cancel-order` (v14 no ar) — index.ts v15 já preparado no repo.

Os quatro têm de ir **juntos e antes** do SQL da proposta 03 (passo 1 grava a contagem; com o
`_shared` velho no ar a contagem faria os tokens virar saldo).

## Prova já feita (local, 28/10)

O bloco `ts` acima foi extraído tal e qual para
`C:\Users\danil\AppData\Local\Temp\claude\C--BoraLocal-projetosflutter-bora-app-bora-app\84fbcd7f-d493-4816-b0cd-9144ae9fabd3\scratchpad\cobranca_stripe_v2.ts`
e provado com `bun provar_shared.ts` (saída em `prova_shared.saida.txt`, mesma pasta): 6 de 6 OK —
`totalPago` ignora tokens (800); MB Way 650 / saldo 0; pedir 1000 dá só 800 (tokens nunca viram
saldo); misto 500 Stripe + 300 saldo; Stripe já com 300 devolvidos → 200 Stripe + 300 saldo;
pedido a dinheiro com 3,00 € de saldo → 300 ao saldo.

## Prova esperada (depois de publicar)

- `get_edge_function` de cada uma das 4: o ficheiro `_shared/cobranca_stripe.ts` tem a linha
  `const carteiraCents = Math.min(pedido - stripeCents, pago.walletCents);` e não tem `usouTokens`.
- Prova de lógica sem rede (Deno, base falsa — memória `simular-edge-function-com-deno-e-base-falsa`):
  `repartirReembolso(650, {stripeDisponivelCents: 800, walletCents: 0, stripeCents: 800, tokensCents: 0, totalCents: 1000, ...})`
  → `{stripeCents: 650, carteiraCents: 0}`; com `walletCents: 300, stripeDisponivelCents: 500,
  stripeCents: 500` e reembolso 800 → `{stripeCents: 500, carteiraCents: 300}`; com tokens
  `tokensValorCents: 200, tokensCount: 400` nunca aparece carteira acima de `walletCents`.

## Como reverter

Publicar de novo as 4 funções com o `_shared/cobranca_stripe.ts` do commit atual do repo (igual ao
que está no ar a 28/10). Enquanto a contagem de tokens não for gravada (proposta 03 por aplicar),
as duas versões dão o mesmo resultado em todos os pedidos de hoje.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
