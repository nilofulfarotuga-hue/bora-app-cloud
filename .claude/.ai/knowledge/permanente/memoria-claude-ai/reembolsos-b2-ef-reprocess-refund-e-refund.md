---
id: memoria-claude-ai-reembolsos-b2-ef-reprocess-refund-e-refund
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# reembolsos-b2-ef-reprocess-refund-e-refund

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `reembolsos-b2-ef-reprocess-refund-e-refund`, origem `claude-code`, atualizada em 2026-10-29T15:44:43.408549+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: reembolsos b2 ef reprocess refund e refund · memoria claude.ai · claude_ai_memoria

# Proposta 04 — `reprocess-refund` (MB Way falhado ia para o saldo) e texto do `refund`

Missão `missao-geral-2026-10-28`, Bloco 2. Zona vermelha: o agente não escreve nestas funções.
**Não aplicado.**

## Repo vs ar (lido a 28/10)

- `reprocess-refund`: no ar v3. Mesma lógica do repo; só muda a chave (`SUPABASE_SERVICE_ROLE_KEY`
  no ar, `secretKey()` no repo). O defeito está nos dois.
- `refund`: no ar v25 = repo, igual.

## O defeito (prova por leitura)

`supabase/functions/reprocess-refund/index.ts:55`:
`} else if (o.refund_method === 'wallet' || o.payment_method !== 'card') {` → crédito na carteira
(`wallet_credit_refund_split`/`_full`). Ou seja, todo o reembolso falhado de **MB Way** (e de
qualquer meio que não seja exatamente `card`) vai para o SALDO quando o admin carrega em
"Reprocessar", mesmo quando o pedido diz `refund_method = 'stripe'`. Quem deixa pedidos em
`failed` com `refund_method = 'stripe'`: `admin-cancel-order:244-247`, `auto-refund-order:75`
(sistema), `client-cancel-order:249` (este último com `refund_method` nulo). Contra a regra de 28/10
(o meio original é o defeito; saldo só se o cliente escolher).

Também: manda à Stripe `refund_amount` inteiro, sem ver quanto ainda se pode devolver lá (num
pedido misto, `refund_amount` pode incluir a parte do saldo).

## O que muda

1. Vai à Stripe quando o pedido tem PaymentIntent, o meio é `card` ou `mbway` e `refund_method` não
   é `wallet`. Vai ao saldo só quando `refund_method = 'wallet'` (escolha do cliente/admin) ou não há
   Stripe (pedido a dinheiro com saldo).
2. Na Stripe devolve no máximo o que ainda se pode devolver (cobrado − já devolvido).
3. Chave do servidor como no repo (`secretKey()`).

## Ficheiro inteiro proposto

```ts
// reprocess-refund — Bloco 4 (recuperacao de reembolso falhado). Admin-only, idempotente.
// v4 (28/10/2026, regra do Danilo 28/10 18:24 — missao-geral-2026-10-28 bloco 2): o reembolso
// volta pelo MEIO ORIGINAL. Antes, tudo o que não era payment_method = 'card' (o MB Way!) ia para
// a carteira, mesmo com refund_method = 'stripe'. Agora: cartão E MB Way com PaymentIntent voltam
// à Stripe (no máximo o que ainda se pode devolver lá); saldo só com refund_method = 'wallet'
// (escolha do cliente/admin) ou quando não há Stripe (pedido a dinheiro com saldo).
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { secretKey } from '../_shared/keys.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const json = (b: any, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const svc = secretKey() ?? '';
  if (!url || !anon || !svc) return json({ error: 'server_misconfigured' }, 500);

  let orderId: string | undefined;
  try { const b = await req.json(); orderId = b?.order_id; } catch (_) { return json({ error: 'invalid_body' }, 400); }
  if (!orderId || typeof orderId !== 'string') return json({ error: 'order_id required' }, 400);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);

  const userClient = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: ud } = await userClient.auth.getUser();
  const user = ud?.user;
  if (!user) return json({ error: 'unauthorized' }, 401);
  const { data: adm } = await userClient.rpc('is_admin');
  if (adm !== true) return json({ error: 'not_admin' }, 403);

  const admin = createClient(url, svc);

  const { data: claimed, error: cErr } = await admin
    .from('orders')
    .update({ refund_status: 'processing' })
    .eq('id', orderId).eq('refund_status', 'failed')
    .select('id, user_id, refund_amount, refund_method, payment_method, payment_intent_id');
  if (cErr) return json({ error: 'claim_failed', details: cErr.message }, 500);
  if (!claimed || claimed.length === 0) return json({ ok: true, idempotent: true, message: 'nada_a_reprocessar' });

  const o = claimed[0];
  const refundCents = Math.round(Number(o.refund_amount ?? 0) * 100);
  const meioStripe = o.payment_method === 'card' || o.payment_method === 'mbway';
  const vaiStripe = o.refund_method !== 'wallet' && !!o.payment_intent_id && meioStripe;
  let outcome = '';
  let newStatus = 'failed';

  try {
    if (refundCents <= 0) {
      newStatus = 'refunded'; outcome = 'zero';
    } else if (!vaiStripe) {
      // saldo: escolha 'wallet' ou pedido sem Stripe. 100% saldo (wallet_split_free_pct = 1).
      const { data: cr } = await admin.from('cancellation_requests').select('cancel_stage').eq('order_id', orderId).maybeSingle();
      const rpcName = cr?.cancel_stage === 'grace' ? 'wallet_credit_refund_full' : 'wallet_credit_refund_split';
      const { error: wErr } = await admin.rpc(rpcName, { p_order_id: orderId, p_user_id: o.user_id, p_total_cents: refundCents, p_reason: 'reprocess_cancel_refund' });
      if (wErr) throw new Error('wallet: ' + wErr.message);
      newStatus = 'completed'; outcome = 'wallet';
    } else {
      // cartão OU MB Way: volta ao meio original, no máximo o que ainda se pode devolver na Stripe
      const pi = await stripe.paymentIntents.retrieve(o.payment_intent_id, { expand: ['latest_charge'] });
      if (pi.status !== 'succeeded') throw new Error('pi_sem_cobranca:' + pi.status);
      // deno-lint-ignore no-explicit-any
      const charge: any = pi.latest_charge;
      const disponivel = Math.max(0, Number(pi.amount_received ?? 0) - Number(charge?.amount_refunded ?? 0));
      const valor = Math.min(refundCents, disponivel);
      if (valor <= 0) throw new Error('nada_por_devolver_na_stripe');
      const idem = `refund-${o.payment_intent_id}-${valor}`;
      const r = await stripe.refunds.create({ payment_intent: o.payment_intent_id, amount: valor }, { idempotencyKey: idem });
      newStatus = 'pending'; outcome = `stripe:${r.id}:${valor}`;
    }
  } catch (e) {
    await admin.from('orders').update({ refund_status: 'failed' }).eq('id', orderId);
    try { await admin.from('admin_audit_log').insert({ admin_id: user.id, admin_email: user.email, action: 'reprocess_refund', entity_type: 'order', entity_id_text: orderId, details: { result: 'error', error: String(e), admin_email: user.email } }); } catch (_) {}
    return json({ error: 'reprocess_failed', details: String(e) }, 502);
  }

  await admin.from('orders').update({ refund_status: newStatus }).eq('id', orderId);
  try { await admin.from('admin_audit_log').insert({ admin_id: user.id, admin_email: user.email, action: 'reprocess_refund', entity_type: 'order', entity_id_text: orderId, details: { old_status: 'failed', new_status: newStatus, result: outcome, admin_email: user.email } }); } catch (_) {}
  return json({ ok: true, order_id: orderId, refund_status: newStatus, outcome });
});
```

## `refund/index.ts` — só o texto (linha 81)

Hoje: `Reembolso de €X processado. Pode demorar 5-10 dias úteis a aparecer no cartão. Para crédito
instantâneo, escolhe wallet da próxima vez.` — diz "cartão" a quem pagou com MB Way e empurra para
a carteira. Proposta (a função não recebe o meio; texto neutro):

```ts
          const message = `Reembolso de €${amount.toFixed(2)} processado. No MB Way chega normalmente na hora; no cartão pode demorar 5 a 10 dias úteis a aparecer no extrato.`;
```

## Prova esperada (depois de publicar)

- `get_edge_function reprocess-refund`: linha `const vaiStripe = o.refund_method !== 'wallet' && ...`.
- Em teste: pedido MB Way de teste com `refund_status = 'failed'`, `refund_method = 'stripe'` →
  Reprocessar → `outcome` começa por `stripe:` e `wallet_transactions` sem linha nova para o pedido.

## Como reverter

Publicar de novo o index.ts do commit atual do repo.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

