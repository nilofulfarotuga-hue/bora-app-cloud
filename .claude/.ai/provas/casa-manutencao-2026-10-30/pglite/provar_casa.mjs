// Prova local (PGlite) das partes 01..05 da Casa: carrega a base imitada, as 5 migrações já no ar,
// as 2 pendentes e corre um cenário completo como cliente, profissional e admin. Nada vai a produção.
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import path from 'node:path';

const W = process.argv[2];
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const db = new PGlite();
const out = [];
const log = (...a) => { const s = a.join(' '); out.push(s); console.log(s); };
let falhas = 0;

async function carregar(nome, sql) {
  try { await db.exec(sql); log('CARREGOU', nome); }
  catch (e) { falhas++; log('FALHOU_CARREGAR', nome, '::', e.message); }
}

const uid = { admin: '00000000-0000-4000-8000-0000000000a1', cli: '00000000-0000-4000-8000-0000000000c1',
              p1: '00000000-0000-4000-8000-0000000000b1', p2: '00000000-0000-4000-8000-0000000000b2' };

async function como(quem, sql, params = []) {
  await db.query(`select set_config('test.uid', $1, false), set_config('test.jwt', $2, false)`,
                 [quem ? uid[quem] : '', JSON.stringify({ email: quem + '@exemplo.pt' })]);
  try { const r = await db.query(sql, params); return { ok: true, v: r.rows.length ? Object.values(r.rows[0])[0] : null }; }
  catch (e) { return { ok: false, e: e.message }; }
}
function espera(nome, r, cond) {
  const bom = cond(r);
  if (!bom) falhas++;
  log(bom ? 'OK  ' : 'FALHA', nome, '=>', r.ok ? JSON.stringify(r.v)?.slice(0, 220) : 'ERRO ' + r.e);
  return r;
}
const erro = (cod) => (r) => !r.ok && r.e.includes(cod);
const ok = (r) => r.ok;

await carregar('stubs', fs.readFileSync(path.join(here, 'stubs.sql'), 'utf8'));
try { await db.exec('CREATE PUBLICATION supabase_realtime;'); } catch (e) { log('aviso publicacao:', e.message); }
const mig = path.join(W, 'supabase', 'migrations');
for (const f of fs.readdirSync(mig).filter((f) => /^202610310\d+_casa_/.test(f)).sort()) {
  await carregar(f, fs.readFileSync(path.join(mig, f), 'utf8'));
}
await carregar('casa_04 (pendente)', fs.readFileSync(path.join(W, 'supabase/migrations_pendentes/casa_04_profissional_e_tarefas.sql'), 'utf8'));
await carregar('casa_05 (pendente)', fs.readFileSync(path.join(W, 'supabase/migrations_pendentes/casa_05_admin.sql'), 'utf8'));

// Pessoas
await db.exec(`
  INSERT INTO auth.users (id, email, raw_app_meta_data) VALUES ('${uid.admin}', 'admin@exemplo.pt', '{"role":"admin"}'), ('${uid.cli}', 'cliente@exemplo.pt', '{}'),
    ('${uid.p1}', 'pro1@exemplo.pt', '{}'), ('${uid.p2}', 'pro2@exemplo.pt', '{}');
  INSERT INTO public.users (id, name, email, phone) VALUES ('${uid.cli}', 'Cliente Teste', 'cliente@exemplo.pt', '+351910000001'),
    ('${uid.p1}', 'Pro Um', 'pro1@exemplo.pt', '+351910000002'), ('${uid.p2}', 'Pro Dois', 'pro2@exemplo.pt', '+351910000003');
  INSERT INTO public.provider_push_tokens (user_id, role, fcm_token, platform) VALUES ('${uid.p1}', 'handyman', 't1', 'android');`);

const n = await db.query(`select (select count(*) from cron.job where jobname like 'casa%') crons,
  (select count(*) from storage.buckets where id in ('handyman-documents','casa-fotos')) baldes,
  (select count(*) from pg_proc where proname like 'admin_casa%') admin_fns,
  (select string_agg(codigo||':'||fase||':'||ativo, ',' order by ordem) from casa_oficios) oficios`);
log('ESTRUTURA', JSON.stringify(n.rows[0]));

// Permissões
const g = await db.query(`select bool_or(has_function_privilege('anon', p.oid, 'execute')) anon_pode,
  bool_and(has_function_privilege('authenticated', p.oid, 'execute')) auth_pode, count(*) n
  from pg_proc p where p.proname like 'admin_casa%'`);
espera('grants admin_casa_* (anon nao, authenticated sim)', { ok: true, v: g.rows[0] }, (r) => r.v.anon_pode === false && r.v.auth_pode === true);

const svc = (await db.query(`select s.id, s.oficio, s.preco_cents from casa_servicos s join casa_oficios o on o.codigo = s.oficio
  where s.modo = 'fixo' and o.fase = 1 order by o.ordem, s.ordem limit 1`)).rows[0];
const svcOrc = (await db.query(`select s.id, s.oficio from casa_servicos s join casa_oficios o on o.codigo = s.oficio
  where s.modo = 'orcamento' and o.fase = 1 and s.oficio = $1 limit 1`, [svc.oficio])).rows[0]
  ?? (await db.query(`select s.id, s.oficio from casa_servicos s join casa_oficios o on o.codigo = s.oficio where s.modo = 'orcamento' and o.fase = 1 limit 1`)).rows[0];
log('SERVICOS fixo', JSON.stringify(svc), 'orcamento', JSON.stringify(svcOrc));

// 1) Sem ser admin
espera('cliente chama admin_casa_resumo', await como('cli', 'select public.admin_casa_resumo()'), erro('sem_permissao'));
espera('admin_casa_resumo', await como('admin', 'select public.admin_casa_resumo()'), (r) => r.ok && r.v.enabled === false && r.v.valores_autorizados.autorizado === false);

// 2) Candidaturas
const disp = JSON.stringify([0, 1, 2, 3, 4, 5, 6].map((d) => ({ weekday: d, start: '07:00', end: '22:00' })));
const ofs = [...new Set([svc.oficio, svcOrc.oficio])];
for (const p of ['p1', 'p2']) {
  espera('candidatura ' + p, await como(p, `select public.casa_candidatura($1,'+35191','${p}@exemplo.pt','','bio','123456789','Guarda',40.537,-7.267,20,true,true,$2::text[],$3::jsonb)`,
    ['Pro ' + p, ofs, disp]), ok);
}
const prof = Object.fromEntries((await db.query('select user_id, id from casa_profissionais')).rows.map((r) => [r.user_id, r.id]));
const P1 = prof[uid.p1], P2 = prof[uid.p2];
const doc = await como('p1', `select public.casa_registar_documento('cartao_cidadao', null, '${uid.p1}/cc_1.jpg', '12345', '2030-01-01')`);
espera('documento p1', doc, ok);
espera('admin_casa_profissionais(pending)', await como('admin', `select public.admin_casa_profissionais('pending')`), (r) => r.ok && r.v.length === 2 && 'docs_pendentes' in r.v[0]);
espera('admin_casa_profissional(p1)', await como('admin', 'select public.admin_casa_profissional($1)', [P1]),
  (r) => r.ok && r.v.perfil && Array.isArray(r.v.oficios) && Array.isArray(r.v.documentos) && Array.isArray(r.v.conformidade_em_falta));
espera('recusar sem motivo', await como('admin', `select public.admin_casa_decidir_profissional($1,'recusar','')`, [P1]), erro('motivo_obrigatorio'));
for (const [p, id] of [['p1', P1], ['p2', P2]]) {
  espera('aprovar ' + p, await como('admin', `select public.admin_casa_decidir_profissional($1,'aprovar',null)`, [id]), (r) => r.ok && r.v.depois === 'approved' && r.v.sem_comissao_ate);
  for (const o of ofs) espera(`aprovar oficio ${o} ${p}`, await como('admin', `select public.admin_casa_decidir_oficio($1,$2,'aprovar',null)`, [id, o]), ok);
}
espera('aprovar documento', await como('admin', `select public.admin_casa_decidir_documento($1,'aprovar',null,'2030-06-30')`, [doc.v.id]), ok);
espera('documento validade passada', await como('admin', `select public.admin_casa_decidir_documento($1,'aprovar',null,'2020-01-01')`, [doc.v.id]), erro('validade_passada'));
espera('editar profissional', await como('admin', `select public.admin_casa_editar_profissional($1,'{"service_radius_km":25,"has_van":false}'::jsonb)`, [P1]), ok);
espera('editar profissional raio invalido', await como('admin', `select public.admin_casa_editar_profissional($1,'{"service_radius_km":"abc"}'::jsonb)`, [P1]), erro('valor_invalido'));
const sfase2 = (await db.query(`select codigo from casa_oficios where documento_exigido is not null limit 1`)).rows[0];
if (sfase2) {
  await como('admin', `insert into casa_profissional_oficios (profissional_id, oficio) values ($1,$2)`, [P1, sfase2.codigo]);
  espera('aprovar oficio fase 2 sem documento', await como('admin', `select public.admin_casa_decidir_oficio($1,$2,'aprovar',null)`, [P1, sfase2.codigo]), erro('documento_em_falta'));
}

// 3) Catálogo, definições e autorizo
espera('catalogo', await como('admin', 'select public.admin_casa_catalogo()'), (r) => r.ok && r.v.oficios.length > 0 && r.v.servicos.length > 0);
for (const o of ofs) await como('admin', `select public.admin_casa_guardar_oficio($1, true)`, [o]);
espera('definicoes', await como('admin', 'select public.admin_casa_definicoes()'), (r) => r.ok && r.v.some((d) => d.key === 'casa_enabled'));
espera('guardar casa_enabled pela definicao', await como('admin', `select public.admin_casa_guardar_definicao('casa_enabled','true'::jsonb)`), erro('usar_interruptor'));
espera('guardar tipo errado', await como('admin', `select public.admin_casa_guardar_definicao('casa_max_fotos','"x"'::jsonb)`), erro('valor_invalido'));
espera('testadores', await como('admin', `select public.admin_casa_guardar_definicao('casa_testadores', $1::jsonb)`, [JSON.stringify([uid.cli])]), ok);
const amanha = new Date(Date.now() + 26 * 3600e3).toISOString();
const criar = (sid, metodo = 'cash', chave = null) => como('cli',
  `select public.casa_criar_pedido($1, 1, 'montar', '{}'::jsonb, 'Rua A 1', 'Guarda', '6300-000', 40.54, -7.27, $2::timestamptz, $3, $4)`,
  [sid, amanha, metodo, chave]);
espera('testador: pedido de teste corre antes do autorizo', await criar(svc.id, 'cash', 'k0'), (r) => r.ok && r.v.is_test === true);
await como('admin', `select public.admin_casa_guardar_definicao('casa_testadores', '[]'::jsonb)`);
espera('cliente normal com a Casa desligada', await criar(svc.id, 'cash', 'kx'), erro('casa_desligada'));
espera('interruptor ligar (provas)', await como('admin', 'select public.admin_casa_interruptor(true)'), (r) => r.ok && r.v.enabled === true);
espera('pedido real antes do autorizo', await criar(svc.id, 'cash', 'ky'), erro('valores_por_autorizar'));
espera('autorizo sem a palavra', await como('admin', `select public.admin_casa_autorizar_valores('sim pode')`), erro('texto_sem_autorizo'));
espera('autorizo', await como('admin', `select public.admin_casa_autorizar_valores('Eu autorizo os valores da Casa 31/10/2026')`), ok);

// 4) Pedido de preço fixo até confirmado
const ped = espera('pedido fixo real', await criar(svc.id, 'cash', 'k1'), (r) => r.ok && r.v.estado === 'procura' && r.v.is_test === false);
const PID = ped.v?.id;
espera('ofertas p1 (meu_orcamento_id presente)', await como('p1', 'select public.casa_minhas_ofertas()'),
  (r) => r.ok && r.v.some((o) => o.pedido_id === PID) && r.v.every((o) => 'meu_orcamento_id' in o));
espera('aceitar oferta p1', await como('p1', 'select public.casa_aceitar_oferta($1)', [PID]), (r) => r.ok && r.v.estado === 'aceite');
espera('reatribuir a p2', await como('admin', 'select public.admin_casa_reatribuir($1,$2)', [PID, P2]), (r) => r.ok && r.v.estado === 'aceite' && r.v.profissional.id === P2);
espera('suspender p2 com trabalho', await como('admin', `select public.admin_casa_decidir_profissional($1,'suspender','teste de suspensao')`, [P2]), erro('tem_trabalhos_ativos'));
espera('reatribuir de volta a p1', await como('admin', 'select public.admin_casa_reatribuir($1,$2)', [PID, P1]), (r) => r.ok && r.v.profissional.id === P1);
for (const e of ['a_caminho', 'chegou', 'em_curso']) espera('avancar ' + e, await como('p1', 'select public.casa_avancar($1,$2)', [PID, e]), (r) => r.ok && r.v.estado === e);
espera('concluir sem foto', await como('p1', `select public.casa_avancar($1,'concluido')`, [PID]), erro('foto_depois_em_falta'));
espera('foto depois', await como('p1', `select public.casa_adicionar_foto($1,'depois',$2)`, [PID, `${uid.p1}/${PID}/depois_1.jpg`]), ok);
espera('concluir', await como('p1', `select public.casa_avancar($1,'concluido')`, [PID]), (r) => r.ok && r.v.estado === 'concluido');
espera('foto visivel ao cliente', await como('cli', 'select public._casa_foto_visivel($1)', [`${uid.p1}/${PID}/depois_1.jpg`]), (r) => r.ok && r.v === true);
espera('foto invisivel a estranho', await como('p2', 'select public._casa_foto_visivel($1)', [`${uid.p1}/${PID}/depois_1.jpg`]), (r) => r.ok && r.v === false);
espera('pedir refazer', await como('cli', `select public.casa_pedir_refazer($1,'ficou torto')`, [PID]), (r) => r.ok && r.v.estado === 'disputa');
espera('resumo com disputa', await como('admin', 'select public.admin_casa_resumo()'), (r) => r.ok && r.v.disputas === 1);
espera('resolver disputa', await como('admin', `select public.admin_casa_resolver_disputa($1,'sem_razao','ficou bem')`, [PID]), ok);
espera('pedido confirmado', await como('admin', 'select public.admin_casa_pedido($1)', [PID]),
  (r) => r.ok && r.v.estado === 'confirmado' && r.v.eventos.length >= 8 && r.v.ofertas.length >= 1 && r.v.cliente.email === 'cliente@exemplo.pt');
espera('pedidos lista', await como('admin', `select public.admin_casa_pedidos(null, 200)`), (r) => r.ok && r.v[0].cliente_nome === 'Cliente Teste');

// 5) Orçamento
const po = espera('pedido orcamento', await criar(svcOrc.id, 'cash', 'k2'), (r) => r.ok && r.v.estado === 'orcamentos');
const OID = po.v?.id;
const orc = espera('enviar orcamento p2', await como('p2', `select public.casa_enviar_orcamento($1, 3500, 'tudo', 'nada', false, '2 dias', 120)`, [OID]), ok);
espera('ofertas p2 com meu_orcamento_id', await como('p2', 'select public.casa_minhas_ofertas()'),
  (r) => r.ok && r.v.some((o) => o.pedido_id === OID && o.meu_orcamento_id === orc.v?.id));
espera('admin orcamentos', await como('admin', `select public.admin_casa_orcamentos(null)`), (r) => r.ok && r.v.length === 1 && r.v[0].tempo_resposta_min !== undefined && r.v[0].ganhou === false);
espera('aceitar orcamento', await como('cli', `select public.casa_aceitar_orcamento($1,'cash')`, [orc.v?.id]), (r) => r.ok && r.v.estado === 'aceite');
espera('marcar teste', await como('admin', 'select public.admin_casa_marcar_teste($1,true)', [OID]), (r) => r.ok && r.v.is_test === true);
espera('forcar conclusao', await como('admin', `select public.admin_casa_forcar_conclusao($1,'combinado por telefone')`, [OID]), (r) => r.ok && r.v.estado === 'confirmado');
espera('cancelar confirmado', await como('admin', `select public.admin_casa_cancelar($1,'tarde demais')`, [OID]), erro('estado_invalido'));
const pc = await criar(svc.id, 'cash', 'k3');
espera('cancelar pelo admin', await como('admin', `select public.admin_casa_cancelar($1,'cliente ligou a cancelar')`, [pc.v?.id]), (r) => r.ok && r.v.ok);
espera('ofertas admin', await como('admin', 'select public.admin_casa_ofertas(null)'), (r) => r.ok && r.v.length >= 2);
const logCasa = (await db.query(`select count(*)::int n from ofertas_prestador_log where categoria = 'casa'`)).rows[0].n;
espera('registo de ofertas com casa', { ok: true, v: logCasa }, (r) => r.v >= 1);

// 6) Preço muda -> volta a proposta
espera('mudar preco', await como('admin', `select public.admin_casa_guardar_servico($1, $2::jsonb)`, [svc.id, JSON.stringify({ preco_cents: svc.preco_cents + 100 })]), (r) => r.ok && r.v.valores_reabertos === true);
espera('valores reabertos', await como('admin', 'select public.admin_casa_resumo()'), (r) => r.ok && r.v.valores_autorizados.autorizado === false);
espera('servico novo', await como('admin', `select public.admin_casa_guardar_servico(null, $1::jsonb)`, [JSON.stringify({ oficio: svc.oficio, nome: 'Teste novo', modo: 'orcamento', preco_cents: null })]), ok);
espera('servico invalido', await como('admin', `select public.admin_casa_guardar_servico(null, $1::jsonb)`, [JSON.stringify({ oficio: svc.oficio, nome: 'X', modo: 'fixo', preco_cents: null })]), erro('valor_invalido'));
espera('calcular acertos sem autorizo', await como('admin', `select public.admin_casa_calcular_acertos(current_date)`), erro('valores_por_autorizar'));
await como('admin', `select public.admin_casa_autorizar_valores('autorizo de novo')`);

// 7) Acertos e exportar
const seg = (await db.query(`select (date_trunc('week', now() at time zone 'Europe/Lisbon'))::date d`)).rows[0].d;
const segIso = new Date(seg).toISOString().slice(0, 10);
espera('calcular acertos', await como('admin', `select public.admin_casa_calcular_acertos($1::date)`, [segIso]), (r) => r.ok && r.v.criados === 1);
const ac = espera('listar acertos', await como('admin', `select public.admin_casa_acertos($1::date)`, [segIso]), (r) => r.ok && r.v.length === 1 && r.v[0].profissional_nome);
espera('marcar acerto pago', await como('admin', `select public.admin_casa_acerto_marcar($1,'paid','transferencia','REF1')`, [ac.v?.[0]?.id]), ok);
espera('marcar estado invalido', await como('admin', `select public.admin_casa_acerto_marcar($1,'pago',null,null)`, [ac.v?.[0]?.id]), erro('acao_invalida'));
for (const t of ['pedidos', 'ganhos', 'profissionais']) {
  espera('exportar ' + t, await como('admin', `select public.admin_casa_exportar($1, current_date - 1, current_date)`, [t]),
    (r) => r.ok && Array.isArray(r.v) && r.v.length >= 1 && !JSON.stringify(r.v).includes('"iban"'));
}
espera('exportar tipo errado', await como('admin', `select public.admin_casa_exportar('x', null, null)`), erro('acao_invalida'));
espera('interruptor ligar', await como('admin', 'select public.admin_casa_interruptor(true)'), (r) => r.ok && r.v.enabled === true);
espera('interruptor desligar', await como('admin', 'select public.admin_casa_interruptor(false)'), (r) => r.ok && r.v.enabled === false);
espera('suspender p2 sem trabalho', await como('admin', `select public.admin_casa_decidir_profissional($1,'suspender','teste de suspensao')`, [P2]), (r) => r.ok && r.v.depois === 'suspended');
espera('reativar p2', await como('admin', `select public.admin_casa_decidir_profissional($1,'reativar',null)`, [P2]), (r) => r.ok && r.v.depois === 'approved');
espera('casa_tick', await como(null, 'select public.casa_tick()'), (r) => r.ok && !Object.keys(r.v).some((k) => k.startsWith('erro')));
espera('meus ganhos p1', await como('p1', 'select public.casa_meus_ganhos()'), (r) => r.ok && r.v.semana);
const aud = (await db.query(`select count(*)::int n, count(distinct action)::int a from admin_audit_log`)).rows[0];
log('AUDITORIA linhas', aud.n, 'acoes distintas', aud.a);
const avisos = (await db.query(`select count(*)::int n from net.calls`)).rows[0].n;
log('AVISOS (net.http_post) registados', avisos);

log('RESULTADO', falhas === 0 ? 'TUDO VERDE' : falhas + ' FALHA(S)');
fs.writeFileSync(path.join(here, 'provar_casa.saida.txt'), out.join('\n'));
process.exit(falhas === 0 ? 0 : 1);
