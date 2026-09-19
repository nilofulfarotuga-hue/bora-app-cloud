// supabase/functions/delete-account/index.ts
//
// ENCERRAMENTO DE CONTA A PEDIDO DO PRÓPRIO (RGPD art. 17 · App Store 5.1.1(v))
// Reescrito a 2026-09-07, missão `ios-lancamento`.
//
// ─────────────────────────────────────────────────────────────────────────────
// PORQUE FOI REESCRITO
// A função que estava DEPLOYED com este nome era uma página HTML estática ("Como
// pedir a eliminação da sua conta", do tipo que a Google Play exige como URL de
// política). Devolvia HTTP 200 · text/html · 2171 bytes. A app só verificava
// `status >= 400`, por isso mostrava "Conta apagada." e fazia logout — sem nada
// ter sido apagado. Medido em produção a 2026-09-07.
//
// ─────────────────────────────────────────────────────────────────────────────
// PORQUE A CONTA É ANONIMIZADA NO LUGAR E NÃO APAGADA
// `client_wallets.user_id` e `wallet_transactions.user_id` são NOT NULL com
// ON DELETE CASCADE (medido em pg_constraint). Chamar `auth.admin.deleteUser`
// destruiria o livro da carteira — contra a regra da casa de nunca apagar linha
// financeira ou de ledger. Por isso:
//
//   • a linha `auth.users` é ESVAZIADA de dados pessoais (email trocado por um
//     endereço morto, telefone e metadados limpos, palavra-passe invalidada),
//   • `banned_until = infinity` e as linhas de `auth.identities` são removidas,
//   • nenhuma cascata dispara, e nem uma linha financeira desaparece.
//
// O efeito para a pessoa é o mesmo de uma eliminação: as credenciais antigas
// deixam de existir, não há recuperação de palavra-passe possível (o email já
// não é o dela) e nada seu fica identificável. É o padrão de anonimização em
// lugar que o RGPD aceita quando há retenção legal obrigatória — aqui, os 10
// anos de dados fiscais.
//
// ─────────────────────────────────────────────────────────────────────────────
// CONTRATO COM A APP (importante)
// Devolver 200 NÃO chega. O corpo tem de trazer `ok: true` e `prova`. Foi
// exactamente a ausência disto que deixou a app mentir durante meses.
//
//   200 { ok:true,  prova:{...} }                 → "Conta apagada."
//   200 { ok:false, needs_confirmation:true, … }  → ecrã de confirmação do saldo
//   409 { ok:false, blocked:[…] }                 → motivo real no ecrã
//   500 { ok:false, error:… }                     → erro no ecrã
//
// NÃO TOCA: pricing, dispatch, finalizePurchase, webhook Stripe, RLS de orders,
// wallets e ledger. Não apaga nenhuma linha de orders, ledger_entries,
// wallet_transactions, driver_transactions, payouts ou settlements.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// corsHeaders inline de proposito: o upload da funcao leva um ficheiro so,
// e assim nao depende de resolucao de caminho relativo no deploy.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MARCADOR = '00000000-0000-4000-8000-000000000001'; // utilizador "Conta eliminada"

// Estados FINAIS. Tudo o que não estiver aqui conta como em curso e bloqueia.
// Lista de permissões de propósito: um estado novo que ninguém se lembre de
// acrescentar passa a bloquear, em vez de deixar encerrar uma conta com trabalho
// a meio.
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
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
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
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ ok: false, error: 'server_misconfigured' }, 500);
  }

  // ── Quem está a pedir ─────────────────────────────────────────────────────
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
  try { corpo = await req.json(); } catch { /* corpo vazio é aceitável */ }

  const prova: Record<string, unknown> = {};
  const bloqueios: string[] = [];

  // ── 1. Que papéis esta pessoa tem ─────────────────────────────────────────
  const [estafeta, lojas, prestador, limpeza, lavagem] = await Promise.all([
    db.from('drivers').select('id, debt_cents, blocked_for_debt').eq('user_id', uid).maybeSingle(),
    db.from('restaurants').select('id, name').eq('user_id', uid),
    db.from('service_providers').select('id').eq('user_id', uid),
    db.from('cleaners').select('id').eq('user_id', uid),
    db.from('washers').select('id').eq('user_id', uid),
  ]);

  const driverId = estafeta.data?.id ?? null;
  const restauranteIds = (lojas.data ?? []).map((r: { id: string }) => r.id);
  const papeis = [
    'cliente',
    driverId ? 'estafeta' : null,
    restauranteIds.length ? 'parceiro' : null,
    prestador.data?.id ? 'prestador' : null,
    limpeza.data?.id ? 'limpezas' : null,
    lavagem.data?.id ? 'lavagem' : null,
  ].filter(Boolean) as string[];

  // ── 2. Travões: trabalho em curso ─────────────────────────────────────────
  const emCurso = async (
    tabela: string, coluna: string, valor: string, finais: string[], etiqueta: string,
  ) => {
    const { data, error } = await db
      .from(tabela).select('id, status').eq(coluna, valor).not('status', 'in', `(${finais.join(',')})`);
    // Um erro aqui NÃO pode passar em silêncio: seria encerrar uma conta com
    // trabalho a meio por causa de uma consulta partida.
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
    const { data: acertos, error: e1 } = await db
      .from('driver_weekly_settlements').select('id, net_balance, status')
      .eq('driver_id', uid).not('status', 'in', '(received,paid)');
    // driver_weekly_settlements.driver_id referencia drivers(user_id), nao
    // drivers(id) — medido em pg_constraint 2026-09-07. Usar driverId aqui
    // nunca encontrava nada e deixava passar um acerto por fechar.
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

  if (bloqueios.length) {
    return json({ ok: false, blocked: bloqueios, papeis }, 409);
  }

  // ── 3. O que se perde: saldo livre e tokens ───────────────────────────────
  const { data: carteira } = await db
    .from('client_wallets').select('free_balance_cents').eq('user_id', uid).maybeSingle();
  const saldoCents = carteira?.free_balance_cents ?? 0;

  const { data: tokens } = await db
    .from('bora_tokens').select('id, amount').eq('user_id', uid).eq('is_used', false);
  const tokensCount = tokens?.length ?? 0;
  const tokensSoma = (tokens ?? []).reduce(
    (s: number, t: { amount: number }) => s + (t.amount ?? 0), 0);

  // Sem `confirm`, e havendo algo a perder, devolve-se o valor para o ecrã.
  if (!corpo.confirm && (saldoCents > 0 || tokensCount > 0)) {
    return json({
      ok: false,
      needs_confirmation: true,
      papeis,
      forfeit: {
        saldo_livre_cents: saldoCents,
        tokens_por_usar: tokensCount,
        tokens_valor: tokensSoma,
      },
    });
  }

  // ── 4. Encerrar, passo a passo, guardando prova ───────────────────────────
  const marca = `Conta eliminada`;
  const emailHash = await sha256((user.email ?? '').toLowerCase());
  const agora = new Date().toISOString();

  // 4.1 tokens: NÃO se apagam. Ficam consumidos, com data.
  if (tokensCount) {
    const { error } = await db.from('bora_tokens')
      .update({ is_used: true, used_at: agora }).eq('user_id', uid).eq('is_used', false);
    prova.bora_tokens = error
      ? { accao: 'falhou', erro: error.message }
      : { accao: 'consumidos_nao_apagados', linhas: tokensCount, valor: tokensSoma };
  } else {
    prova.bora_tokens = { accao: 'nada_a_fazer', linhas: 0 };
  }

  // 4.2 carteira: lançamento de encerramento (append-only) e saldo a zero.
  if (saldoCents > 0) {
    const { error: eMov } = await db.from('wallet_transactions').insert({
      user_id: uid,
      amount_cents: -saldoCents,
      kind: 'adjustment', // 'account_closure' nao passa na check constraint
      reason: 'Encerramento de conta a pedido do titular',
      balance_after_cents: 0,
      idempotency_key: `closure-${uid}`,
    });
    const { error: eSaldo } = await db.from('client_wallets')
      .update({ free_balance_cents: 0, updated_at: agora }).eq('user_id', uid);
    prova.client_wallets = (eMov || eSaldo)
      ? { accao: 'falhou', erro: (eMov ?? eSaldo)?.message }
      : { accao: 'saldo_a_zero_com_lancamento', cents_perdidos: saldoCents };
  } else {
    prova.client_wallets = { accao: 'nada_a_fazer', cents_perdidos: 0 };
  }

  // 4.3 pedidos: anonimizar o cliente. As linhas e os valores ficam (fiscal).
  {
    const { count, error } = await db.from('orders')
      .update({ customer_name: marca, client_phone: null }, { count: 'exact' })
      .eq('user_id', uid);
    prova.orders = error
      ? { accao: 'falhou', erro: error.message }
      : { accao: 'anonimizado', linhas: count ?? 0, campos: ['customer_name', 'client_phone'], mantido: 'valores, datas e referências Stripe' };
  }

  // 4.4 marcações, reservas e limpezas: passam para o marcador. Não se apagam.
  for (const [tabela, coluna, extras] of [
    ['appointments', 'client_user_id', { client_name: marca, client_phone: null }],
    ['reservations', 'client_user_id', { client_name: marca, client_phone: null }],
    ['cleaning_bookings', 'client_user_id', {}],
  ] as [string, string, Record<string, unknown>][]) {
    const { count, error } = await db.from(tabela)
      .update({ [coluna]: MARCADOR, ...extras }, { count: 'exact' })
      .eq(coluna, uid);
    prova[tabela] = error
      ? { accao: 'falhou', erro: error.message }
      : { accao: 'reapontado_para_marcador', linhas: count ?? 0 };
  }

  // 4.5 conversas — `messages` nao guarda o id de quem escreveu (so sender_type
  // e order_id, medido 2026-09-07), por isso nao ha nada a apagar por
  // utilizador. Fica registado para nao voltar a parecer um passo esquecido.
  prova.messages = { accao: 'nao_aplicavel', motivo: 'a tabela nao tem coluna de autor' };

  // 4.6 estafeta: nada de linha órfã. Anonimiza e desliga do utilizador.
  if (driverId) {
    const { error } = await db.from('drivers').update({
      // user_id NAO se anula: driver_weekly_settlements aponta para esta
      // coluna. Anular partia a chave e levava o historico de acertos. A
      // linha de acesso ja fica anonima, por isso isto nao e' um elo pessoal.
      // phone e NOT NULL em drivers: marcador em vez de null.
      name: marca, phone: '000000000', email: null, nif: null, iban: null,
      mbway_phone: null, address: null, document_number: null, document_photo_url: null,
      vehicle_photo_url: null, registration_selfie_url: null, vehicle_doc_url: null,
      photo_url: null, fcm_token: null, is_online: false, license_plate: null,
      deleted_at: agora, deletion_reason: 'Encerramento a pedido do titular',
    }).eq('id', driverId);
    prova.drivers = error
      ? { accao: 'falhou', erro: error.message }
      : {
          accao: 'anonimizado_e_desligado', linhas: 1,
          campos: ['nome', 'telefone', 'email', 'NIF', 'IBAN', 'morada', 'documentos', 'fotos', 'matrícula'],
          mantido: 'histórico de acertos e transações, anonimizado',
        };
  }

  // 4.7 parceiro: a ligação ao dono é cortada ANTES de mexer no utilizador, e a
  //     loja fica desactivada. A loja e o histórico de pedidos ficam.
  if (restauranteIds.length) {
    const { count, error } = await db.from('restaurants').update({
      // O gatilho trg_restaurants_mirror_owner espelha user_ <-> user_id.
      // Anular so um faz o gatilho copiar o outro de volta (medido 2026-09-07).
      user_id: null, user_: null, is_active_admin: false, is_online: false,
      nif: null, iban: null, owner_doc_url: null, activity_doc_url: null,
      mbway_phone: null, fcm_token: null,
    }, { count: 'exact' }).eq('user_id', uid);
    prova.restaurants = error
      ? { accao: 'falhou', erro: error.message }
      : {
          accao: 'dono_desligado_loja_desactivada', linhas: count ?? 0,
          campos_limpos: ['NIF', 'IBAN', 'documentos do dono'],
          mantido: 'nome, morada e histórico de pedidos da loja',
        };
  }

  // 4.8 prestadores de serviços, limpezas e lavagem
  for (const [tabela, id] of [
    ['service_providers', prestador.data?.id],
    ['cleaners', limpeza.data?.id],
    ['washers', lavagem.data?.id],
  ] as [string, string | undefined][]) {
    if (!id) continue;
    const campos: Record<string, unknown> = {
      name: marca, phone: null, email: null, nif: null,
      photo_url: null, is_active_admin: false,
    };
    if (tabela !== 'service_providers') { delete campos.is_active_admin; campos.is_active = false; campos.docs = null; }
    else campos.iban = null;
    const { error } = await db.from(tabela).update(campos).eq('id', id);
    prova[tabela] = error
      ? { accao: 'falhou', erro: error.message }
      : { accao: 'anonimizado', linhas: 1 };
  }

  // 4.9 tokens de notificação e dados de conveniência
  {
    const apagados: Record<string, number | string> = {};
    // partner_push_tokens usa `partner_id`, nao `user_id` (medido 2026-09-07).
    for (const [t, col] of [['client_push_tokens','user_id'], ['driver_push_tokens','user_id'],
                     ['partner_push_tokens','partner_id'], ['provider_push_tokens','user_id'],
                     ['client_addresses','user_id'], ['client_favorites','user_id'],
                     ['client_search_history','user_id'], ['in_app_notifications','user_id'],
                     ['preferencias_papel','user_id']] as [string,string][]) {
      const { count, error } = await db.from(t).delete({ count: 'exact' }).eq(col, uid);
      apagados[t] = error ? `falhou: ${error.message}` : (count ?? 0);
    }
    prova.dados_de_conveniencia = { accao: 'apagado', detalhe: apagados };
  }

  // 4.10 ficheiros pessoais no Storage
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

  // 4.11 perfil público
  {
    const { error } = await db.from('users').update({
      name: marca, phone: null, photo_url: null, fcm_token: null,
      email: `apagado-${emailHash.slice(0, 12)}@bora.invalid`,
    }).eq('id', uid);
    prova.users = error
      ? { accao: 'falhou', erro: error.message }
      : { accao: 'anonimizado', linhas: 1, mantido: 'stripe_customer_id, para o rasto fiscal' };
  }

  // 4.12 a conta de acesso: esvaziada, sem identidades e banida para sempre.
  //      Não se chama deleteUser — ver o cabeçalho.
  {
    const { error } = await db.rpc('encerrar_conta_de_acesso', {
      p_user_id: uid,
      p_email_novo: `apagado-${emailHash.slice(0, 12)}@bora.invalid`,
    });
    if (error) {
      prova.auth_users = { accao: 'falhou', erro: error.message };
      return json({ ok: false, error: 'encerramento_incompleto', prova }, 500);
    }
    prova.auth_users = {
      accao: 'anonimizado_e_banido_para_sempre',
      detalhe: 'email trocado, palavra-passe invalidada, metadados limpos, identidades removidas, banned_until=infinity',
    };
  }

  // ── 5. Registo ────────────────────────────────────────────────────────────
  const mantido = {
    rasto_fiscal: 'pedidos, ledger_entries, wallet_transactions, driver_transactions, payouts e acertos — anonimizados, nunca apagados (obrigação legal de 10 anos)',
    loja: restauranteIds.length ? 'mantida e desactivada' : null,
  };

  await db.from('deleted_accounts').insert({
    original_user_id: uid,
    papel: papeis.join('+'),
    email_hash: emailHash,
    anonimizado: prova,
    mantido,
    motivo: corpo.motivo ?? null,
    origem: 'app',
  });

  await db.from('admin_audit_log').insert({
    admin_id: null,
    admin_email: 'sistema:delete-account',
    action: 'account_self_closure',
    entity_type: 'user',
    entity_id: uid,
    details: { papeis, prova, mantido },
  });

  // Nenhum passo pode falhar em silencio. Foi exactamente assim que a versao
  // anterior desta funcao deixou a app dizer "Conta apagada." sem apagar nada.
  const falhas = Object.entries(prova)
    .filter(([, v]) => JSON.stringify(v).includes('falhou'))
    .map(([k]) => k);
  if (falhas.length) {
    return json({ ok: false, error: 'encerramento_incompleto', falhas, papeis, prova }, 500);
  }

  return json({ ok: true, papeis, prova, mantido });
});
