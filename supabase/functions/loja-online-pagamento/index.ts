// supabase/functions/loja-online-pagamento/index.ts
//
// Loja Online (checkup-geral-15-11, B3.7): pagamento de uma compra da loja online dentro da app.
// Ordem do Danilo 15/11 17:53 (via Claude.ai 17:59); AUTORIZO do Danilo 14/11/2026 12:19: cartão e
// MB WAY pelo caminho Stripe que já existe, preço = 2 × custo do fornecedor (já gravado em
// loja_online_produtos.preco_bora_cents). Nunca dinheiro.
//
// verify_jwt = true. Duas ações (POST):
//   { acao: 'criar', produto_id, quantidade, metodo: 'card'|'mbway', nome, telefone, email?,
//     morada, codigo_postal, localidade, stripe_contas_v2: true }
//     → valida sessão + loja_online_visivel_para_mim() + produto ativo; o PREÇO vem SEMPRE da base
//       (o cliente não manda valores); grava a encomenda 'aguarda_pagamento'; cria o PaymentIntent
//       na conta Stripe do interruptor (stripe_contas.ts) com metadata.kind='loja_online'.
//       card  → devolve clientSecret + publishable_key (a app abre a folha / Payment Element).
//       mbway → confirma no servidor com o telefone (o cliente recebe o pedido na app MB WAY).
//   { acao: 'confirmar', encomenda_id }
//     → só o dono (ou admin). Lê o PaymentIntent na Stripe; succeeded → 'paga' (+ paga_em);
//       canceled/requires_payment_method → 'falhou_pagamento'. Idempotente.
//
// O stripe-webhook não é tocado: um PaymentIntent sem order_id/draft_id só fica registado lá.
// A confirmação é este 'confirmar' (a app chama-o no fim e o painel tem o botão "Ver pagamento").
//
// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { secretKey } from '../_shared/keys.ts';
import {
  respostaConta,
  stripeDaLinha,
  stripeParaNovoPagamento,
} from '../_shared/stripe_contas.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CP_RE = /^[0-9]{4}-[0-9]{3}$/;

/** Telemóvel PT → E.164 (+3519XXXXXXXX). null se não for um número móvel português. */
export function telefoneE164(bruto: unknown): string | null {
  const so = String(bruto ?? '').replace(/[\s().-]/g, '');
  const n = so.startsWith('+351') ? so.slice(4) : so.startsWith('00351') ? so.slice(5) : so;
  return /^9[1236][0-9]{7}$/.test(n) ? `+351${n}` : null;
}

function texto(v: unknown, max = 200): string {
  return String(v ?? '').trim().slice(0, max);
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const serviceKey = secretKey() ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) return json({ error: 'server_misconfigured' }, 500);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ error: 'unauthorized' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: 'invalid_body' }, 400);
  }
  const admin = createClient(supabaseUrl, serviceKey);
  const acao = texto(body.acao, 20);

  try {
    // ── confirmar ──────────────────────────────────────────────────────────
    if (acao === 'confirmar') {
      const encomendaId = texto(body.encomenda_id, 40).toLowerCase();
      if (!UUID_RE.test(encomendaId)) return json({ error: 'invalid_encomenda_id' }, 400);
      const { data: enc } = await admin
        .from('loja_online_encomendas')
        .select('id, user_id, estado, payment_intent_id, stripe_account, total_cents')
        .eq('id', encomendaId)
        .maybeSingle();
      const ehAdmin = (user.app_metadata as Record<string, unknown> | null)?.role === 'admin';
      if (!enc || (enc.user_id !== user.id && !ehAdmin)) return json({ error: 'not_found' }, 404);
      if (enc.estado !== 'aguarda_pagamento' || !enc.payment_intent_id) {
        return json({ ok: true, estado: enc.estado });
      }
      const { stripe } = stripeDaLinha(enc);
      const pi = await stripe.paymentIntents.retrieve(enc.payment_intent_id);
      let estado = enc.estado;
      if (pi.status === 'succeeded' && pi.amount_received === enc.total_cents) {
        estado = 'paga';
      } else if (pi.status === 'canceled' || pi.status === 'requires_payment_method') {
        estado = 'falhou_pagamento';
      }
      if (estado !== enc.estado) {
        await admin
          .from('loja_online_encomendas')
          .update({
            estado,
            paga_em: estado === 'paga' ? new Date().toISOString() : null,
            atualizado_em: new Date().toISOString(),
          })
          .eq('id', enc.id)
          .eq('estado', 'aguarda_pagamento');
      }
      return json({ ok: true, estado, pi_status: pi.status });
    }

    if (acao !== 'criar') return json({ error: 'acao_invalida' }, 400);

    // ── criar ──────────────────────────────────────────────────────────────
    const { data: visivel, error: visErr } = await userClient.rpc('loja_online_visivel_para_mim');
    if (visErr || visivel !== true) return json({ error: 'loja_fechada' }, 403);

    const produtoId = texto(body.produto_id, 40).toLowerCase();
    const quantidade = Number(body.quantidade ?? 1);
    const metodo = texto(body.metodo, 10);
    const nome = texto(body.nome, 120);
    const email = texto(body.email, 160) || user.email || null;
    const morada = texto(body.morada, 300);
    const codigoPostal = texto(body.codigo_postal, 10);
    const localidade = texto(body.localidade, 80);
    const e164 = telefoneE164(body.telefone);

    if (!UUID_RE.test(produtoId)) return json({ error: 'invalid_produto_id' }, 400);
    if (!Number.isInteger(quantidade) || quantidade < 1 || quantidade > 5) {
      return json({ error: 'quantidade_invalida' }, 400);
    }
    if (metodo !== 'card' && metodo !== 'mbway') return json({ error: 'metodo_invalido' }, 400);
    if (nome.length < 3 || morada.length < 5 || !CP_RE.test(codigoPostal) || localidade.length < 2) {
      return json({ error: 'morada_incompleta' }, 400);
    }
    if (!e164) return json({ error: 'telefone_invalido' }, 400);

    const { data: produto } = await admin
      .from('loja_online_produtos')
      .select('id, titulo, ativo, preco_bora_cents, custo_fornecedor_cents, prazo_min_dias, prazo_max_dias')
      .eq('id', produtoId)
      .maybeSingle();
    if (!produto || produto.ativo !== true || !(produto.preco_bora_cents > 0)) {
      return json({ error: 'produto_indisponivel' }, 404);
    }
    const totalCents = produto.preco_bora_cents * quantidade;
    if (totalCents < 50) return json({ error: 'abaixo_do_minimo' }, 400);

    const { stripe, conta } = await stripeParaNovoPagamento(admin, {
      body,
      origem: 'loja-online-pagamento',
    });

    const { data: enc, error: insErr } = await admin
      .from('loja_online_encomendas')
      .insert({
        user_id: user.id,
        produto_id: produto.id,
        titulo: produto.titulo,
        quantidade,
        preco_unit_cents: produto.preco_bora_cents,
        total_cents: totalCents,
        custo_unit_cents: produto.custo_fornecedor_cents ?? 0,
        prazo_min_dias: produto.prazo_min_dias ?? 0,
        prazo_max_dias: produto.prazo_max_dias ?? 0,
        nome,
        telefone: e164,
        email,
        morada,
        codigo_postal: codigoPostal,
        localidade,
        metodo,
        stripe_account: conta,
      })
      .select('id')
      .single();
    if (insErr || !enc) {
      console.error('[loja-online-pagamento] insert falhou:', insErr?.message);
      return json({ error: 'encomenda_nao_gravada' }, 500);
    }

    const base = {
      amount: totalCents,
      currency: 'eur',
      description: `Bora Loja online: ${produto.titulo} x${quantidade}`.slice(0, 200),
      metadata: { kind: 'loja_online', encomenda_id: enc.id, user_id: user.id },
    };
    const intent = metodo === 'mbway'
      ? await stripe.paymentIntents.create({
        ...base,
        payment_method_types: ['mb_way'],
        payment_method_data: { type: 'mb_way', billing_details: { phone: e164 } },
        confirm: true,
      }, { idempotencyKey: `loja_online_${enc.id}` })
      : await stripe.paymentIntents.create({
        ...base,
        payment_method_types: ['card'],
      }, { idempotencyKey: `loja_online_${enc.id}` });

    await admin
      .from('loja_online_encomendas')
      .update({ payment_intent_id: intent.id, atualizado_em: new Date().toISOString() })
      .eq('id', enc.id);

    console.log('[loja-online-pagamento] criado', enc.id, intent.id, metodo, conta, intent.status);
    return json({
      ok: true,
      encomenda_id: enc.id,
      paymentIntentId: intent.id,
      clientSecret: metodo === 'card' ? intent.client_secret : null,
      status: intent.status,
      total_cents: totalCents,
      ...respostaConta(conta),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[loja-online-pagamento] erro:', message);
    return json({ error: message }, 500);
  }
});
