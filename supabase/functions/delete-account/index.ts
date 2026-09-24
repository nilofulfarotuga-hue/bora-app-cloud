// supabase/functions/delete-account/index.ts
//
// ENCERRAMENTO DE CONTA A PEDIDO DO PROPRIO (RGPD art. 17 / App Store 5.1.1(v))
// Reescrito a 2026-09-07, missao `ios-lancamento`.
//
// A funcao que estava aqui era uma pagina HTML estatica: devolvia 200/text-html
// e a app mostrava "Conta apagada." sem nada ter sido apagado.
//
// A conta e ANONIMIZADA NO LUGAR, nao apagada: client_wallets.user_id e
// wallet_transactions.user_id sao NOT NULL com ON DELETE CASCADE, logo apagar
// auth.users destruiria o livro da carteira.
//
// CONTRATO: 200 nao chega. O corpo tem de trazer ok:true e prova.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MARCADOR = '00000000-0000-4000-8000-000000000001';

const FINAIS = {
  orders: ['delivered', 'cancelled', 'rejected'],
  reservations: ['cancelled', 'completed', 'no_show', 'cancelled_client', 'cancelled_partner'],
  tvde_rides: ['finalizada', 'cancelada_cliente', 'cancelada_motorista', 'cancelada'],
  appointments: ['cancelled', 'completed', 'no_show', 'blocked'],
  cleaning_bookings: ['cancelled_client', 'cancelled_cleaner', 'completed', 'done'],
};

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

async function sha256(texto: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) return json({ ok: false, error: 'server_misconfigured' }, 500);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ ok: false, error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ ok: false, error: 'unauthorized' }, 401);
  if (user.id === MARCADOR) return json({ ok: false, error: 'conta_de_sistema' }, 403);

  const uid = user.id;
  const db = createClient(supabaseUrl, serviceKey);

  let corpo: { confirm?: boolean; motivo?: string } = {};
  try { corpo = await req.json(); } catch { /* corpo vazio e aceitavel */ }

  const prova: Record<string, unknown> = {};
  const bloqueios: string[] = [];

  const [estafeta, lojas, prestador, limpeza, lavagem] = await Promise.all([
    db.from('drivers').select('id, debt_cents').eq('user_id', uid).maybeSingle(),
    db.from('restaurants').select('id, name').eq('user_id', uid),
    db.from('service_providers').select('id').eq('user_id', uid).maybeSingle(),
    db.from('cleaners').select('id').eq('user_id', uid).maybeSingle(),
    db.from('washers').select('id').eq('user_id', uid).maybeSingle(),
  ]);

  const driverId = estafeta.data?.id ?? null;
  const restauranteIds = (lojas.data ?? []).map((r: { id: string }) => r.id);
  const papeis = [
    'cliente', driverId ? 'estafeta' : null, restauranteIds.length ? 'parceiro' : null,
    prestador.data?.id ? 'prestador' : null, limpeza.data?.id ? 'limpezas' : null,
    lavagem.data?.id ? 'lavagem' : null,
  ].filter(Boolean) as string[];

  const emCurso = async (tabela: string, coluna: string, valor: string, finais: string[], etiqueta: string) => {
    const { data, error } = await db.from(tabela).select('id, status').eq(coluna, valor)
      .not('status', 'in', `(${finais.join(',')})`);
    if (error) { bloqueios.push(`nao_foi_possivel_verificar_${etiqueta}`); return; }
    if (data && data.length) bloqueios.push(`${etiqueta}_em_curso:${data.length}`);
  };

  await Promise.all([
    emCurso('orders', 'user_id', uid, FINAIS.orders, 'pedidos'),
    emCurso('reservations', 'client_user_id', uid, FINAIS.reservations, 'reservas'),
    emCurso('tvde_rides', 'client_id', uid, FINAIS.tvde_rides, 'viagens'),
    emCurso('appointments', 'client_user_id', uid, FINAIS.appointments, 'marcacoes'),
    emCurso('cleaning_bookings', 'client_user_id', uid, FINAIS.cleaning_bookings, 'limpezas'),
  ]);

  if (driverId) {
    await emCurso('orders', 'assigned_driver_id', driverId, FINAIS.orders, 'entregas');
    // driver_weekly_settlements.driver_id referencia drivers(user_id), nao drivers(id).
    const { data: acertos, error: e1 } = await db
      .from('driver_weekly_settlements').select('id, status')
      .eq('driver_id', uid).not('status', 'in', '(received,paid)');
    if (e1) bloqueios.push('nao_foi_possivel_verificar_acertos_estafeta');
    else if (acertos?.length) bloqueios.push(`acerto_estafeta_por_fechar:${acertos.length}`);
    const divida = estafeta.data?.debt_cents ?? 0;
    if (divida > 0) bloqueios.push(`divida_estafeta_cents:${divida}`);
  }

  for (const rid of restauranteIds) {
    const { data: acertos, error: e2 } = await db
      .from('partner_weekly_settlements').select('id, status')
      .eq('partner_id', rid).not('status', 'in', '(paid)');
    if (e2) bloqueios.push('nao_foi_possivel_verificar_acertos_parceiro');
    else if (acertos?.length) bloqueios.push(`acerto_parceiro_por_fechar:${acertos.length}`);
  }

  if (bloqueios.length) return json({ ok: false, blocked: bloqueios, papeis }, 409);

  const { data: carteira } = await db
    .from('client_wallets').select('free_balance_cents').eq('user_id', uid).maybeSingle();
  const saldoCents = carteira?.free_balance_cents ?? 0;
  const { data: tokens } = await db
    .from('bora_tokens').select('id, amount').eq('user_id', uid).eq('is_used', false);
  const tokensCount = tokens?.length ?? 0;
  const tokensSoma = (tokens ?? []).reduce((s: number, t: { amount: number }) => s + (t.amount ?? 0), 0);

  if (!corpo.confirm && (saldoCents > 0 || tokensCount > 0)) {
    return json({ ok: false, needs_confirmation: true, papeis,
      forfeit: { saldo_livre_cents: saldoCents, tokens_por_usar: tokensCount, tokens_valor: tokensSoma } });
  }

  const marca = 'Conta eliminada';
  const emailHash = await sha256((user.email ?? '').toLowerCase());
  const agora = new Date().toISOString();
  const emailMorto = `apagado-${emailHash.slice(0, 12)}@bora.invalid`;

  if (tokensCount) {
    const { error } = await db.from('bora_tokens')
      .update({ is_used: true, used_at: agora }).eq('user_id', uid).eq('is_used', false);
    prova.bora_tokens = error ? { accao: 'falhou', erro: error.message }
      : { accao: 'consumidos_nao_apagados', linhas: tokensCount, valor: tokensSoma };
  } else prova.bora_tokens = { accao: 'nada_a_fazer', linhas: 0 };

  if (saldoCents > 0) {
    // kind tem check constraint: 'account_closure' nao passa; 'adjustment' passa.
    const { error: eMov } = await db.from('wallet_transactions').insert({
      user_id: uid, amount_cents: -saldoCents, kind: 'adjustment',
      reason: 'Encerramento de conta a pedido do titular',
      balance_after_cents: 0, idempotency_key: `closure-${uid}`,
    });
    const { error: eSaldo } = await db.from('client_wallets')
      .update({ free_balance_cents: 0, updated_at: agora }).eq('user_id', uid);
    prova.client_wallets = (eMov || eSaldo)
      ? { accao: 'falhou', erro: (eMov ?? eSaldo)?.message }
      : { accao: 'saldo_a_zero_com_lancamento', cents_perdidos: saldoCents };
  } else prova.client_wallets = { accao: 'nada_a_fazer', cents_perdidos: 0 };

  {
    const { count, error } = await db.from('orders')
      .update({ customer_name: marca, client_phone: null }, { count: 'exact' }).eq('user_id', uid);
    prova.orders = error ? { accao: 'falhou', erro: error.message }
      : { accao: 'anonimizado', linhas: count ?? 0, mantido: 'valores, datas e referencias Stripe' };
  }

  for (const [tabela, coluna, extras] of [
    ['appointments', 'client_user_id', { client_name: marca, client_phone: null }],
    ['reservations', 'client_user_id', { client_name: marca, client_phone: null }],
    ['cleaning_bookings', 'client_user_id', {}],
  ] as [string, string, Record<string, unknown>][]) {
    const { count, error } = await db.from(tabela)
      .update({ [coluna]: MARCADOR, ...extras }, { count: 'exact' }).eq(coluna, uid);
    prova[tabela] = error ? { accao: 'falhou', erro: error.message }
      : { accao: 'reapontado_para_marcador', linhas: count ?? 0 };
  }

  // `messages` nao guarda o id de quem escreveu (so sender_type e order_id).
  prova.messages = { accao: 'nao_aplicavel', motivo: 'a tabela nao tem coluna de autor' };

  if (driverId) {
    // user_id NAO se anula: driver_weekly_settlements aponta para essa coluna.
    // phone e NOT NULL: marcador em vez de null.
    const { error } = await db.from('drivers').update({
      name: marca, phone: '000000000', email: null, nif: null, iban: null,
      mbway_phone: null, address: null, document_number: null, document_photo_url: null,
      vehicle_photo_url: null, registration_selfie_url: null, vehicle_doc_url: null,
      photo_url: null, fcm_token: null, is_online: false, license_plate: null,
      deleted_at: agora, deletion_reason: 'Encerramento a pedido do titular',
    }).eq('id', driverId);
    prova.drivers = error ? { accao: 'falhou', erro: error.message }
      : { accao: 'anonimizado', linhas: 1,
          campos: ['nome', 'telefone', 'email', 'NIF', 'IBAN', 'morada', 'documentos', 'fotos', 'matricula'],
          mantido: 'historico de acertos e transacoes, anonimizado' };
  }

  if (restauranteIds.length) {
    // O gatilho trg_restaurants_mirror_owner espelha user_ <-> user_id. Anular
    // so um faz o gatilho copiar o outro de volta (medido 2026-09-07: a loja
    // ficava desactivada mas com o dono ainda ligado). Anular OS DOIS.
    const { count, error } = await db.from('restaurants').update({
      user_id: null, user_: null, is_active_admin: false, is_online: false,
      nif: null, iban: null, owner_doc_url: null, activity_doc_url: null,
      mbway_phone: null, fcm_token: null,
    }, { count: 'exact' }).eq('user_id', uid);
    prova.restaurants = error ? { accao: 'falhou', erro: error.message }
      : { accao: 'dono_desligado_loja_desactivada', linhas: count ?? 0,
          mantido: 'nome, morada e historico de pedidos da loja' };
  }

  for (const [tabela, id] of [
    ['service_providers', prestador.data?.id], ['cleaners', limpeza.data?.id],
    ['washers', lavagem.data?.id],
  ] as [string, string | undefined][]) {
    if (!id) continue;
    const campos: Record<string, unknown> = { name: marca, phone: null, email: null, nif: null, photo_url: null };
    if (tabela === 'service_providers') { campos.iban = null; campos.is_active_admin = false; }
    else { campos.is_active = false; campos.docs = null; }
    const { error } = await db.from(tabela).update(campos).eq('id', id);
    prova[tabela] = error ? { accao: 'falhou', erro: error.message } : { accao: 'anonimizado', linhas: 1 };
  }

  {
    const apagados: Record<string, number | string> = {};
    // partner_push_tokens usa `partner_id`, nao `user_id`.
    for (const [t, col] of [['client_push_tokens', 'user_id'], ['driver_push_tokens', 'user_id'],
                            ['partner_push_tokens', 'partner_id'], ['provider_push_tokens', 'user_id'],
                            ['client_addresses', 'user_id'], ['client_favorites', 'user_id'],
                            ['client_search_history', 'user_id'], ['in_app_notifications', 'user_id'],
                            ['preferencias_papel', 'user_id']] as [string, string][]) {
      const { count, error } = await db.from(t).delete({ count: 'exact' }).eq(col, uid);
      apagados[t] = error ? `falhou: ${error.message}` : (count ?? 0);
    }
    prova.dados_de_conveniencia = { accao: 'apagado', detalhe: apagados };
  }

  {
    const removidos: Record<string, number | string> = {};
    for (const balde of ['driver-documents', 'avatars', 'restaurant-documents',
                         'cleaner-documents', 'washer-documents']) {
      const { data: lista, error: eL } = await db.storage.from(balde).list(uid, { limit: 200 });
      if (eL) { removidos[balde] = `falhou a listar: ${eL.message}`; continue; }
      const caminhos = (lista ?? []).map((o: { name: string }) => `${uid}/${o.name}`);
      if (!caminhos.length) { removidos[balde] = 0; continue; }
      const { error: eR } = await db.storage.from(balde).remove(caminhos);
      removidos[balde] = eR ? `falhou a remover: ${eR.message}` : caminhos.length;
    }
    prova.storage = { accao: 'apagado', detalhe: removidos };
  }

  {
    const { error } = await db.from('users').update({
      name: marca, phone: null, photo_url: null, fcm_token: null, email: emailMorto,
    }).eq('id', uid);
    prova.users = error ? { accao: 'falhou', erro: error.message }
      : { accao: 'anonimizado', linhas: 1, mantido: 'stripe_customer_id, para o rasto fiscal' };
  }

  {
    const { error } = await db.rpc('encerrar_conta_de_acesso', { p_user_id: uid, p_email_novo: emailMorto });
    prova.auth_users = error ? { accao: 'falhou', erro: error.message }
      : { accao: 'anonimizado_e_banido_para_sempre',
          detalhe: 'email trocado, palavra-passe invalidada, metadados limpos, identidades removidas, banned_until=infinity' };
  }

  const mantido = {
    rasto_fiscal: 'pedidos, ledger_entries, wallet_transactions, driver_transactions, payouts e acertos: anonimizados, nunca apagados (obrigacao legal de 10 anos)',
    loja: restauranteIds.length ? 'mantida e desactivada' : null,
  };

  // Nenhum passo pode falhar em silencio. Foi assim que a versao anterior desta
  // funcao deixou a app dizer "Conta apagada." sem apagar nada.
  const falhas = Object.entries(prova)
    .filter(([, v]) => JSON.stringify(v).includes('falhou'))
    .map(([k]) => k);
  if (falhas.length) {
    return json({ ok: false, error: 'encerramento_incompleto', falhas, papeis, prova }, 500);
  }

  await db.from('deleted_accounts').insert({
    original_user_id: uid, papel: papeis.join('+'), email_hash: emailHash,
    anonimizado: prova, mantido, motivo: corpo.motivo ?? null, origem: 'app',
  });
  await db.from('admin_audit_log').insert({
    admin_id: null, admin_email: 'sistema:delete-account',
    action: 'account_self_closure', entity_type: 'user', entity_id: uid,
    details: { papeis, prova, mantido },
  });

  return json({ ok: true, papeis, prova, mantido });
});
