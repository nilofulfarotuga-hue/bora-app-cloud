// _shared/stripe_contas.ts — as DUAS contas Stripe do Bora (missão stripe-empresa-2026-11-01,
// autorização do Danilo 01/11/2026 22:03). Ler docs/STRIPE_DUAS_CONTAS.md antes de mexer.
//
//   PESSOAL  ("bora app", acct_1T8MFaGlT3R2jCYp)  → TVDE / Bora Motorista e tudo o que já foi
//                                                   pago antes da mudança.
//   EMPRESA  ("Bora", Unipessoal Lda, acct_1UX67LGWwQxC9wR2) → entregas, Favores, limpeza,
//                                                   lavagem, Casa, marcações, reservas de mesa,
//                                                   gorjetas de entregas, dívida, peso, extras.
//
// Regra de ouro: O DINHEIRO MEXE-SE SEMPRE NA CONTA ONDE ENTROU. Reembolso, captura, extra,
// diferença de peso e conferência usam `contaGravada(linha.stripe_account)`, nunca a "atual".
//
// Segredos (Supabase Edge Function secrets):
//   STRIPE_SECRET_KEY / STRIPE_TEST_SECRET_KEY                 pessoal (live / teste, BORA_STRIPE_MODE)
//   STRIPE_SECRET_KEY_EMPRESA / STRIPE_TEST_SECRET_KEY_EMPRESA empresa
//   STRIPE_PUBLISHABLE_KEY(_EMPRESA) / STRIPE_TEST_PUBLISHABLE_KEY(_EMPRESA)  chaves públicas,
//                                                              devolvidas ao app na resposta
//   STRIPE_WEBHOOK_SECRET / STRIPE_WEBHOOK_SECRET_EMPRESA      assinatura de cada webhook
//
// Interruptor: platform_settings.stripe_conta_nao_tvde = 'pessoal' | 'empresa' (jsonb string).
// Compatibilidade: a empresa só se usa quando a app diz `stripe_contas_v2: true` no pedido;
// apps antigas só conhecem a chave pessoal e continuam na pessoal.
// Defensivo: chave da empresa em falta → cai para 'pessoal', regista e alerta; nunca deixa o
// cliente sem pagar.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';

export type ContaStripe = 'pessoal' | 'empresa';
export const CONTAS_STRIPE: readonly ContaStripe[] = ['pessoal', 'empresa'] as const;

/** 'live' por defeito; 'test' só com BORA_STRIPE_MODE=test (QA com cartões 4242). */
export const STRIPE_MODE: 'live' | 'test' =
  (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase() === 'test' ? 'test' : 'live';

// deno-lint-ignore no-explicit-any
type Cliente = any; // SupabaseClient (evita arrastar a versão do supabase-js para aqui)

function env(nome: string): string {
  return (Deno.env.get(nome) ?? '').trim();
}

/** Normaliza o que vier do banco/pedido para uma conta válida. Nulo/desconhecido = pessoal. */
export function contaGravada(valor: unknown): ContaStripe {
  return valor === 'empresa' ? 'empresa' : 'pessoal';
}

/** Chave secreta da conta (respeita o modo teste). Vazia se não existir. */
export function chaveSecreta(conta: ContaStripe): string {
  const sufixo = conta === 'empresa' ? '_EMPRESA' : '';
  return STRIPE_MODE === 'test'
    ? env(`STRIPE_TEST_SECRET_KEY${sufixo}`)
    : env(`STRIPE_SECRET_KEY${sufixo}`);
}

/** Chave publicável (pública) da conta, para o app abrir a folha de pagamento na conta certa. */
export function chavePublicavel(conta: ContaStripe): string {
  const sufixo = conta === 'empresa' ? '_EMPRESA' : '';
  return STRIPE_MODE === 'test'
    ? env(`STRIPE_TEST_PUBLISHABLE_KEY${sufixo}`)
    : env(`STRIPE_PUBLISHABLE_KEY${sufixo}`);
}

/** Segredo de assinatura do webhook da conta. */
export function segredoWebhook(conta: ContaStripe): string {
  return conta === 'empresa' ? env('STRIPE_WEBHOOK_SECRET_EMPRESA') : env('STRIPE_WEBHOOK_SECRET');
}

export function temChaveSecreta(conta: ContaStripe): boolean {
  return chaveSecreta(conta).length > 0;
}

const _clientes = new Map<ContaStripe, Stripe>();

/** Cliente Stripe da conta. Lança `stripe_chave_em_falta:<conta>` se o segredo não existir. */
export function stripePara(conta: ContaStripe): Stripe {
  const existente = _clientes.get(conta);
  if (existente) return existente;
  const chave = chaveSecreta(conta);
  if (!chave) throw new Error(`stripe_chave_em_falta:${conta}`);
  const cliente = new Stripe(chave, { apiVersion: '2023-10-16', httpClient: Stripe.createFetchHttpClient() });
  _clientes.set(conta, cliente);
  return cliente;
}

/** TVDE / Bora Motorista fica SEMPRE na pessoal: kind tvde_*, target 'tvde', ou corrida TVDE. */
export function ehFluxoTvde(opts: { kind?: unknown; target?: unknown; tvdeRideId?: unknown }): boolean {
  const kind = String(opts.kind ?? '');
  const target = String(opts.target ?? '');
  return kind.startsWith('tvde') || target === 'tvde' || target === 'tvde_driver' || !!opts.tvdeRideId;
}

/** O que vai na resposta de criar pagamento, para o app escolher a chave certa. */
export function respostaConta(conta: ContaStripe): { stripe_account: ContaStripe; publishable_key: string } {
  return { stripe_account: conta, publishable_key: chavePublicavel(conta) };
}

/** A app diz que sabe lidar com duas contas? (`stripe_contas_v2: true` no body) */
export function appSabeDuasContas(body: unknown): boolean {
  if (!body || typeof body !== 'object') return false;
  const v = (body as Record<string, unknown>)['stripe_contas_v2'];
  return v === true || v === 'true' || v === 1;
}

// ── interruptor (platform_settings.stripe_conta_nao_tvde) com cache de 60 s ─────────────────
const SETTING_INTERRUPTOR = 'stripe_conta_nao_tvde';
let _interruptor: { valor: ContaStripe; lidoEm: number } | null = null;
const CACHE_MS = 60_000;

/** Lê o interruptor. Falha do banco = 'pessoal' (o caminho que sempre funcionou). */
export async function lerInterruptor(admin: Cliente, semCache = false): Promise<ContaStripe> {
  if (!semCache && _interruptor && Date.now() - _interruptor.lidoEm < CACHE_MS) return _interruptor.valor;
  try {
    const { data, error } = await admin.from('platform_settings').select('value').eq('key', SETTING_INTERRUPTOR).maybeSingle();
    if (error) throw error;
    let bruto: unknown = data?.value;
    if (typeof bruto === 'string') { try { bruto = JSON.parse(bruto); } catch { /* fica string */ } }
    const valor = contaGravada(bruto);
    _interruptor = { valor, lidoEm: Date.now() };
    return valor;
  } catch (e) {
    console.warn('[stripe_contas] interruptor ilegível, fica pessoal:', e instanceof Error ? e.message : String(e));
    return 'pessoal';
  }
}

export interface DecisaoConta {
  conta: ContaStripe;
  /** porquê desta conta — fica no log e no e2e_log quando cai para a pessoal por defeito */
  motivo: 'tvde' | 'app_antiga' | 'interruptor_pessoal' | 'interruptor_empresa' | 'empresa_sem_chave' | 'fixa';
}

/**
 * Decide a conta de um PAGAMENTO NOVO.
 *   TVDE → pessoal. App antiga (sem stripe_contas_v2) → pessoal. Interruptor 'empresa' e chave
 *   da empresa presente → empresa. Interruptor 'empresa' sem chave → pessoal + alerta.
 */
export async function contaParaNovoPagamento(admin: Cliente, opts: {
  kind?: unknown; target?: unknown; tvdeRideId?: unknown;
  body?: unknown; appSabe?: boolean; origem: string;
}): Promise<DecisaoConta> {
  if (ehFluxoTvde(opts)) return { conta: 'pessoal', motivo: 'tvde' };
  const sabe = opts.appSabe ?? appSabeDuasContas(opts.body);
  if (!sabe) return { conta: 'pessoal', motivo: 'app_antiga' };
  const interruptor = await lerInterruptor(admin);
  if (interruptor !== 'empresa') return { conta: 'pessoal', motivo: 'interruptor_pessoal' };
  if (!temChaveSecreta('empresa')) {
    await alertarContaStripe(admin, opts.origem, 'interruptor em empresa mas STRIPE_SECRET_KEY_EMPRESA em falta; pagamento criado na pessoal');
    return { conta: 'pessoal', motivo: 'empresa_sem_chave' };
  }
  return { conta: 'empresa', motivo: 'interruptor_empresa' };
}

/**
 * Cliente Stripe para um pagamento novo + a conta decidida. Se a empresa falhar a construir
 * (não devia: a chave já foi verificada) cai para a pessoal e alerta.
 */
export async function stripeParaNovoPagamento(admin: Cliente, opts: Parameters<typeof contaParaNovoPagamento>[1]):
  Promise<{ stripe: Stripe; conta: ContaStripe; motivo: DecisaoConta['motivo'] }> {
  const d = await contaParaNovoPagamento(admin, opts);
  try {
    return { stripe: stripePara(d.conta), conta: d.conta, motivo: d.motivo };
  } catch (e) {
    if (d.conta === 'empresa') {
      await alertarContaStripe(admin, opts.origem, `stripePara(empresa) falhou: ${e instanceof Error ? e.message : String(e)}; pagamento criado na pessoal`);
      return { stripe: stripePara('pessoal'), conta: 'pessoal', motivo: 'empresa_sem_chave' };
    }
    throw e;
  }
}

/**
 * Cliente Stripe para mexer num pagamento JÁ EXISTENTE (reembolso, captura, extra, leitura):
 * usa a conta gravada na linha. Se a chave dessa conta não existir, lança — nunca se tenta
 * a outra conta às cegas (o PI não existe lá e a Stripe devolveria "No such payment_intent").
 */
export function stripeDaLinha(linha: { stripe_account?: unknown } | null | undefined): { stripe: Stripe; conta: ContaStripe } {
  const conta = contaGravada(linha?.stripe_account);
  return { stripe: stripePara(conta), conta };
}

/**
 * Em que conta vive um PaymentIntent? Procura-o nas tabelas que guardam PIs (a linha que o tem
 * diz a conta). Para funções que só recebem o id do PI (refund, reprocess-refund, painel).
 * Não encontrado = 'pessoal' (tudo o que existia antes de 01/11/2026 está lá).
 */
export async function contaDoPaymentIntent(admin: Cliente, piId: string | null | undefined): Promise<ContaStripe> {
  const pi = String(piId ?? '').trim();
  if (!pi.startsWith('pi_')) return 'pessoal';
  const sitios: Array<[string, string]> = [
    ['orders', 'payment_intent_id'],
    ['tips', 'stripe_payment_intent_id'],
    ['payment_drafts', 'payment_intent_id'],
    ['pending_charges', 'stripe_payment_intent_id'],
    ['reservations', 'prepayment_pi'],
    ['appointments', 'deposit_pi'],
    ['appointments', 'full_payment_pi'],
    ['cleaning_bookings', 'stripe_payment_intent_id'],
    ['carwash_bookings', 'stripe_payment_intent_id'],
  ];
  for (const [tabela, coluna] of sitios) {
    try {
      const { data, error } = await admin.from(tabela).select('stripe_account').eq(coluna, pi).limit(1).maybeSingle();
      if (error) { console.warn(`[stripe_contas] contaDoPaymentIntent ${tabela}.${coluna}:`, error.message); continue; }
      if (data) return contaGravada(data.stripe_account);
    } catch (e) {
      console.warn(`[stripe_contas] contaDoPaymentIntent ${tabela}:`, e instanceof Error ? e.message : String(e));
    }
  }
  return 'pessoal';
}

/**
 * Lê um PaymentIntent cuja conta ainda não está gravada (ex.: mark_held antes de a reserva ter o PI):
 * tenta a conta preferida e depois a outra. Só LÊ (nunca move dinheiro às cegas). null = não existe
 * em nenhuma das nossas contas.
 */
export async function localizarPaymentIntent(piId: string, preferida: ContaStripe = 'pessoal'):
  Promise<{ pi: Stripe.PaymentIntent; stripe: Stripe; conta: ContaStripe } | null> {
  const ordem: ContaStripe[] = preferida === 'empresa' ? ['empresa', 'pessoal'] : ['pessoal', 'empresa'];
  for (const conta of ordem) {
    if (!temChaveSecreta(conta)) continue;
    try {
      const stripe = stripePara(conta);
      const pi = await stripe.paymentIntents.retrieve(piId);
      return { pi, stripe, conta };
    } catch (e) {
      console.log(`[stripe_contas] PI ${piId} não está na conta ${conta}:`, (e instanceof Error ? e.message : String(e)).slice(0, 120));
    }
  }
  return null;
}

/** Alerta o admin (push urgente + e2e_log). Nunca lança. */
export async function alertarContaStripe(admin: Cliente, origem: string, detalhe: string): Promise<void> {
  console.error(`[stripe_contas] ${origem}: ${detalhe}`);
  try {
    await admin.from('e2e_log').insert({
      fluxo: 'stripe-duas-contas', passo: origem, estado: 'alerta', detalhe: detalhe.slice(0, 2000),
      device: 'edge', run_id: new Date().toISOString().slice(0, 10),
    });
  } catch (e) { console.error('[stripe_contas] e2e_log falhou:', e instanceof Error ? e.message : String(e)); }
  try {
    const { error } = await admin.rpc('notify_admin_urgent_push', {
      p_event_type: 'stripe_duas_contas',
      p_summary: `Stripe (${origem}): ${detalhe}`.slice(0, 300),
      p_entity_type: 'stripe',
      p_entity_id: null,
      p_payload: { origem, detalhe },
      p_deep_link: '/admin/stripe-contas',
    });
    if (error) console.error('[stripe_contas] notify_admin_urgent_push falhou:', error.message);
  } catch (e) { console.error('[stripe_contas] notify_admin_urgent_push lançou:', e instanceof Error ? e.message : String(e)); }
}

/** Coluna de `users` onde vive o Stripe Customer desta conta. */
export function colunaClienteStripe(conta: ContaStripe): 'stripe_customer_id' | 'stripe_customer_id_empresa' {
  return conta === 'empresa' ? 'stripe_customer_id_empresa' : 'stripe_customer_id';
}

/**
 * Stripe Customer do utilizador NA CONTA CERTA (idempotente; corrida entre dois pedidos resolve-se
 * ficando com o que o banco guardou primeiro). Nunca lança: null = segue sem customer.
 * Na empresa começa do zero: o cliente volta a guardar o cartão no primeiro pagamento.
 */
export async function obterOuCriarClienteStripe(admin: Cliente, conta: ContaStripe, userId: string): Promise<string | null> {
  const coluna = colunaClienteStripe(conta);
  try {
    const { data: userRow, error: selErr } = await admin
      .from('users').select(`${coluna}, email, name`).eq('id', userId).maybeSingle();
    if (selErr) { console.error(`[stripe_contas] users select falhou (${conta}):`, selErr.message); return null; }
    const existente = userRow?.[coluna];
    if (typeof existente === 'string' && existente) return existente;

    const stripe = stripePara(conta);
    const customer = await stripe.customers.create({
      email: (userRow?.email as string | undefined) ?? undefined,
      name: (userRow?.name as string | undefined) ?? undefined,
      metadata: { supabase_uid: userId, bora_conta: conta },
    });
    const { error: updErr } = await admin
      .from('users').update({ [coluna]: customer.id }).eq('id', userId).is(coluna, null);
    if (updErr) {
      const { data: refetch } = await admin.from('users').select(coluna).eq('id', userId).maybeSingle();
      const vencedor = refetch?.[coluna] as string | undefined;
      if (vencedor && vencedor !== customer.id) {
        try { await stripe.customers.del(customer.id); } catch { /* ignora */ }
        return vencedor;
      }
    }
    return customer.id;
  } catch (err) {
    console.error(`[stripe_contas] obterOuCriarClienteStripe(${conta}) falhou:`, err instanceof Error ? err.message : String(err));
    return null;
  }
}

/** Resumo das chaves presentes (só nomes/booleans — NUNCA valores), para o painel admin. */
export function estadoChaves(): Record<string, boolean | string> {
  return {
    modo: STRIPE_MODE,
    pessoal_secreta: temChaveSecreta('pessoal'),
    pessoal_publicavel: chavePublicavel('pessoal').length > 0,
    pessoal_webhook: segredoWebhook('pessoal').length > 0,
    empresa_secreta: temChaveSecreta('empresa'),
    empresa_publicavel: chavePublicavel('empresa').length > 0,
    empresa_webhook: segredoWebhook('empresa').length > 0,
  };
}
