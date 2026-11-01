// supabase/functions/stripe-relatorio-contabilista/index.ts — v1 (01/11/2026, missão contabilista-2026-11-01)
//
// O QUE FAZ: lê da API da Stripe (fetch direto, paginação por starting_after) TODAS as
// balance_transactions da conta do Bora desde o início — cobranças (charge/payment), reembolsos,
// payouts, taxas — classifica cada uma por tipo de serviço (entregas/mercados, TVDE, limpeza,
// reservas, lavagem, gorjetas, serviços de site, outros) pela metadata/descrição/cliente, guarda
// uma linha por movimento em public.stripe_extrato_contabilista (idempotente por bt_id), cruza
// com a base (RPC stripe_extrato_cruzar_base: orders, tvde_rides, cleaning_bookings, …) e devolve
// os agregados por mês (YYYY-MM, Europe/Lisbon) e por tipo (RPC stripe_extrato_resumo).
//
// PORQUÊ: o contabilista (Hugo) precisa de saber o que passou pela Stripe desde o início, por mês
// e por tipo, porque nada dessa conta foi declarado ainda.
//
// QUEM PODE CHAMAR (verify_jwt=true no portão + regra da casa em _shared/chaves.ts):
//   • o servidor (banco/cron/outra função com a chave secreta — exigirServidorOuAdmin), ou
//   • um admin com sessão (app_metadata.role = 'admin'), como em admin-payments.
// Nunca mexe em dinheiro: só lê a Stripe e escreve na tabela do extrato.
//
// Corpo aceite (todos opcionais):
//   { desde: 'YYYY-MM' }     primeiro mês a devolver no resumo (as linhas guardadas são sempre todas)
//   { ate: 'YYYY-MM' }       último mês a devolver
//   { guardar: false }       só calcula, não escreve na tabela (por defeito escreve)
//   { max_paginas: 200 }     travão de segurança da paginação (100 linhas por página)
//   { ping: true }           responde {pong:true} (vigia das chaves)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { exigirServidorOuAdmin, respostaAoPing } from '../_shared/chaves.ts';
import { corsHeaders } from '../_shared/cors.ts';

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const STRIPE_KEY = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');

type Categoria =
  | 'entregas_mercados' | 'tvde' | 'limpeza' | 'reservas' | 'lavagem' | 'gorjetas'
  | 'servicos_site' | 'outros' | 'payout' | 'taxa_stripe';

type Linha = {
  bt_id: string; tipo_stripe: string; objeto_id: string | null; payment_intent: string | null;
  criado_em: string; disponivel_em: string | null; mes: string; categoria: Categoria;
  categoria_fonte: string; descricao: string | null; cliente_nome: string | null;
  cliente_email: string | null; moeda: string; bruto_cents: number; taxa_cents: number;
  liquido_cents: number; estado: string | null; metadata: Record<string, unknown>;
};

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

function mesLisboa(unixSeconds: number): string {
  const p = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit' })
    .formatToParts(new Date(unixSeconds * 1000));
  const g = (t: string) => p.find((x) => x.type === t)?.value ?? '';
  return `${g('year')}-${g('month')}`;
}

async function stripeGet(path: string, params: Record<string, string | string[]>): Promise<Record<string, unknown>> {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (Array.isArray(v)) v.forEach((x) => q.append(k, x));
    else q.append(k, v);
  }
  const r = await fetch(`https://api.stripe.com/v1/${path}?${q.toString()}`, {
    headers: { Authorization: `Bearer ${STRIPE_KEY}`, 'Stripe-Version': '2023-10-16' },
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`stripe ${r.status} em ${path}: ${txt.slice(0, 300)}`);
  return JSON.parse(txt) as Record<string, unknown>;
}

// Classificação por tipo de serviço. Ordem: metadata.kind → order_id/draft_id → descrição → cliente.
function classificar(fonte: Record<string, unknown> | null, descricao: string, clienteNome: string, clienteEmail: string): { categoria: Categoria; fonte: string } {
  const meta = (fonte?.metadata ?? {}) as Record<string, string>;
  const kind = String(meta.kind ?? '').toLowerCase();
  if (kind) {
    if (kind.startsWith('tvde')) return { categoria: 'tvde', fonte: `metadata.kind=${kind}` };
    if (kind === 'cleaning') return { categoria: 'limpeza', fonte: 'metadata.kind=cleaning' };
    if (kind === 'carwash') return { categoria: 'lavagem', fonte: 'metadata.kind=carwash' };
    if (kind === 'appointment' || kind === 'service') return { categoria: 'reservas', fonte: `metadata.kind=${kind}` };
    if (kind === 'tip') return { categoria: 'gorjetas', fonte: 'metadata.kind=tip' };
    if (kind === 'order_weight_adjusted' || kind === 'peso_variavel' || kind === 'order' || kind === 'order_edit' || kind === 'debt') {
      return { categoria: 'entregas_mercados', fonte: `metadata.kind=${kind}` };
    }
  }
  if (meta.order_id || meta.draft_id) return { categoria: 'entregas_mercados', fonte: meta.order_id ? 'metadata.order_id' : 'metadata.draft_id' };
  if (meta.ride_id) return { categoria: 'tvde', fonte: 'metadata.ride_id' };
  if (meta.booking_id) return { categoria: 'limpeza', fonte: 'metadata.booking_id' };
  if (meta.appointment_id) return { categoria: 'reservas', fonte: 'metadata.appointment_id' };

  const d = descricao.toLowerCase();
  if (/gorjeta|tip\b/.test(d)) return { categoria: 'gorjetas', fonte: 'descricao' };
  if (/tvde|corrida|viagem|boleia|motorista/.test(d)) return { categoria: 'tvde', fonte: 'descricao' };
  if (/limpeza|cleaning/.test(d)) return { categoria: 'limpeza', fonte: 'descricao' };
  if (/lavagem|carwash/.test(d)) return { categoria: 'lavagem', fonte: 'descricao' };
  if (/marca[çc][ãa]o|reserva|barbearia|appointment|sinal/.test(d)) return { categoria: 'reservas', fonte: 'descricao' };
  if (/site|website|presen[çc]a|google|jaiagarwala|web/.test(d)) return { categoria: 'servicos_site', fonte: 'descricao' };
  if (/pedido|order|entrega|mercado|compra|bora app/.test(d)) return { categoria: 'entregas_mercados', fonte: 'descricao' };

  const c = `${clienteNome} ${clienteEmail}`.toLowerCase();
  if (/agarwal|\bjai\b/.test(c)) return { categoria: 'servicos_site', fonte: 'cliente=Jai Agarwal' };
  return { categoria: 'outros', fonte: 'sem_pista' };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const proibido = await exigirServidorOuAdmin(req, corsHeaders);
  if (proibido) return proibido;
  const pong = await respostaAoPing(req, corsHeaders);
  if (pong) return pong;
  if (!STRIPE_KEY) return json({ ok: false, error: 'stripe_key_missing', modo: STRIPE_MODE }, 500);

  // deno-lint-ignore no-explicit-any
  let b: any = {};
  try { b = await req.json(); } catch { /* corpo vazio */ }
  const desde = typeof b?.desde === 'string' && /^\d{4}-\d{2}$/.test(b.desde) ? b.desde : null;
  const ate = typeof b?.ate === 'string' && /^\d{4}-\d{2}$/.test(b.ate) ? b.ate : null;
  const guardar = b?.guardar !== false;
  const maxPaginas = Math.min(Math.max(Number(b?.max_paginas ?? 200), 1), 1000);

  const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', secretKey());

  // 1) Lê a Stripe inteira, 100 por página, com a origem (charge/refund/payout) expandida.
  const linhas: Linha[] = [];
  let startingAfter: string | null = null;
  let paginas = 0;
  const contagemTipos: Record<string, number> = {};
  const clientesVistos = new Map<string, { nome: string; email: string }>();

  async function dadosCliente(customerId: string): Promise<{ nome: string; email: string }> {
    const c = clientesVistos.get(customerId);
    if (c) return c;
    try {
      const cu = await stripeGet(`customers/${customerId}`, {});
      const d = { nome: String(cu.name ?? ''), email: String(cu.email ?? '') };
      clientesVistos.set(customerId, d);
      return d;
    } catch {
      const d = { nome: '', email: '' };
      clientesVistos.set(customerId, d);
      return d;
    }
  }

  while (paginas < maxPaginas) {
    const params: Record<string, string | string[]> = { limit: '100', 'expand[]': ['data.source'] };
    if (startingAfter) params.starting_after = startingAfter;
    const page = await stripeGet('balance_transactions', params);
    const data = (page.data ?? []) as Array<Record<string, unknown>>;
    paginas++;
    for (const bt of data) {
      const tipo = String(bt.type ?? '');
      contagemTipos[tipo] = (contagemTipos[tipo] ?? 0) + 1;
      const fonte = (bt.source && typeof bt.source === 'object') ? bt.source as Record<string, unknown> : null;
      const fonteId = typeof bt.source === 'string' ? bt.source : (fonte?.id ? String(fonte.id) : null);
      const descricao = String(bt.description ?? fonte?.description ?? '');
      const bd = (fonte?.billing_details ?? {}) as Record<string, unknown>;
      let clienteNome = String(bd.name ?? fonte?.receipt_email ?? '');
      let clienteEmail = String(bd.email ?? fonte?.receipt_email ?? '');
      const customerId = typeof fonte?.customer === 'string' ? fonte.customer : null;
      if (customerId && (!clienteNome || !clienteEmail) && (tipo === 'charge' || tipo === 'payment')) {
        const c = await dadosCliente(customerId);
        clienteNome = clienteNome || c.nome;
        clienteEmail = clienteEmail || c.email;
      }
      // Reembolso: a metadata vive no charge do reembolso; o fetch expandido traz refund.charge como id.
      let pi: string | null = typeof fonte?.payment_intent === 'string' ? fonte.payment_intent : null;
      let fonteParaClassificar = fonte;
      if ((tipo === 'refund' || tipo === 'payment_refund') && fonte && typeof fonte.charge === 'string') {
        try {
          const ch = await stripeGet(`charges/${fonte.charge}`, {});
          fonteParaClassificar = ch;
          pi = typeof ch.payment_intent === 'string' ? ch.payment_intent : pi;
          if (!clienteNome) clienteNome = String((ch.billing_details as Record<string, unknown>)?.name ?? '');
          if (!clienteEmail) clienteEmail = String((ch.billing_details as Record<string, unknown>)?.email ?? ch.receipt_email ?? '');
        } catch { /* fica com o que há */ }
      }

      let categoria: Categoria; let catFonte: string;
      if (tipo === 'payout') { categoria = 'payout'; catFonte = 'tipo=payout'; }
      else if (tipo === 'stripe_fee' || tipo === 'application_fee' || tipo === 'adjustment' || tipo === 'reserve_transaction') { categoria = 'taxa_stripe'; catFonte = `tipo=${tipo}`; }
      else { const c = classificar(fonteParaClassificar, descricao, clienteNome, clienteEmail); categoria = c.categoria; catFonte = c.fonte; }

      const criado = Number(bt.created ?? 0);
      linhas.push({
        bt_id: String(bt.id), tipo_stripe: tipo, objeto_id: fonteId, payment_intent: pi,
        criado_em: new Date(criado * 1000).toISOString(),
        disponivel_em: bt.available_on ? new Date(Number(bt.available_on) * 1000).toISOString() : null,
        mes: mesLisboa(criado), categoria, categoria_fonte: catFonte,
        descricao: descricao || null, cliente_nome: clienteNome || null, cliente_email: clienteEmail || null,
        moeda: String(bt.currency ?? 'eur'), bruto_cents: Number(bt.amount ?? 0), taxa_cents: Number(bt.fee ?? 0),
        liquido_cents: Number(bt.net ?? 0), estado: String(bt.status ?? '') || null,
        metadata: (fonteParaClassificar?.metadata ?? {}) as Record<string, unknown>,
      });
    }
    if (!page.has_more || data.length === 0) break;
    startingAfter = String(data[data.length - 1].id);
  }

  // 2) Guarda (idempotente) e cruza com a base.
  let guardadas = 0; let cruzadas: number | null = null; let erroGravacao: string | null = null;
  if (guardar && linhas.length > 0) {
    for (let i = 0; i < linhas.length; i += 500) {
      const lote = linhas.slice(i, i + 500).map((l) => ({ ...l, atualizado_em: new Date().toISOString() }));
      const { error } = await admin.from('stripe_extrato_contabilista').upsert(lote, { onConflict: 'bt_id' });
      if (error) { erroGravacao = error.message; break; }
      guardadas += lote.length;
    }
    if (!erroGravacao) {
      const { data: n, error: e2 } = await admin.rpc('stripe_extrato_cruzar_base');
      if (e2) erroGravacao = 'cruzar: ' + e2.message; else cruzadas = Number(n ?? 0);
    }
  }

  // 3) Agregados por mês e por tipo (da tabela, para incluir o cruzamento com a base).
  let resumo: unknown = null; let erroResumo: string | null = null;
  if (guardar && !erroGravacao) {
    const { data, error } = await admin.rpc('stripe_extrato_resumo', { p_desde: desde, p_ate: ate });
    if (error) erroResumo = error.message; else resumo = data;
  } else {
    // sem gravar: agrega em memória, sem cruzamento
    const porMes: Record<string, { bruto: number; taxas: number; reembolsos: number; liquido: number; payouts: number }> = {};
    const porTipo: Record<string, number> = {};
    for (const l of linhas) {
      if (desde && l.mes < desde) continue;
      if (ate && l.mes > ate) continue;
      const m = porMes[l.mes] ??= { bruto: 0, taxas: 0, reembolsos: 0, liquido: 0, payouts: 0 };
      if (l.tipo_stripe === 'charge' || l.tipo_stripe === 'payment') { m.bruto += l.bruto_cents; porTipo[`${l.mes}|${l.categoria}`] = (porTipo[`${l.mes}|${l.categoria}`] ?? 0) + l.bruto_cents; }
      if (l.tipo_stripe === 'refund' || l.tipo_stripe === 'payment_refund') m.reembolsos += l.bruto_cents;
      if (l.tipo_stripe === 'payout') m.payouts -= l.bruto_cents; else { m.taxas -= l.taxa_cents; m.liquido += l.liquido_cents; }
    }
    resumo = { por_mes: porMes, por_mes_e_tipo_bruto_cents: porTipo, nota: 'calculado em memória (guardar=false), sem cruzamento com a base' };
  }

  // Registo da corrida (melhor-esforço).
  try {
    await admin.from('e2e_log').insert({
      fluxo: 'contabilista-2026-11-01', passo: 'stripe-relatorio-contabilista',
      estado: erroGravacao || erroResumo ? 'erro' : 'ok',
      detalhe: `modo=${STRIPE_MODE} paginas=${paginas} linhas=${linhas.length} guardadas=${guardadas} cruzadas=${cruzadas ?? '-'} tipos=${JSON.stringify(contagemTipos)}${erroGravacao ? ' erro=' + erroGravacao : ''}${erroResumo ? ' erroResumo=' + erroResumo : ''}`.slice(0, 1000),
      device: 'edge',
    });
  } catch { /* registo é melhor-esforço */ }

  return json({
    ok: !erroGravacao && !erroResumo, modo: STRIPE_MODE, paginas, linhas: linhas.length, guardadas, cruzadas,
    tipos_stripe: contagemTipos, desde, ate, resumo,
    erro: erroGravacao ?? erroResumo ?? null,
  });
});
