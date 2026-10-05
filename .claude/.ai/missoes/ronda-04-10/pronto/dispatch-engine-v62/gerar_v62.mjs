// Gera a PROPOSTA do dispatch-engine v62 a partir do ficheiro que está no repo
// (espelho do v61 que corre em produção), por âncoras exactas: cada âncora tem
// de existir UMA vez, senão aborta — nada é reescrito à mão.
//
// NÃO escreve na pasta protegida supabase/functions/dispatch-engine/ (a Trava
// não deixa, e é assim que deve ser). Escreve só aqui ao lado:
//   index.v62.PROPOSTA.ts   — o ficheiro inteiro, pronto a copiar
//   v61-para-v62.diff       — o que muda, linha a linha
//
// Uso:  node gerar_v62.mjs <raiz-do-repo>
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const raiz = process.argv[2] ?? '.';
const origem = path.join(raiz, 'supabase/functions/dispatch-engine/index.ts');
let s = fs.readFileSync(origem, 'utf8').replace(/\r\n/g, '\n');
const v61 = s;

function umaVez(ancora) {
  const n = s.split(ancora).length - 1;
  if (n !== 1) throw new Error(`âncora tem de existir 1 vez, existe ${n}: ${JSON.stringify(ancora.slice(0, 70))}`);
}
function trocar(ancora, novo) { umaVez(ancora); s = s.replace(ancora, () => novo); }
function trocarEntre(inicio, fim, novo, { incluiFim }) {
  umaVez(inicio); umaVez(fim);
  const a = s.indexOf(inicio);
  const b = s.indexOf(fim) + (incluiFim ? fim.length : 0);
  if (b <= a) throw new Error('âncoras fora de ordem');
  s = s.slice(0, a) + novo + s.slice(b);
}

// 1) Cabeçalho ---------------------------------------------------------------
trocar('// @ts-nocheck\n// dispatch-engine v59 (2026-08-16)', `// @ts-nocheck
// dispatch-engine v62 (ronda 04/10/2026) — duas mudanças, mais nada:
//   (1) QUEM PODE CHAMAR. Até aqui qualquer pessoa na internet podia acordar o
//       motor (verify_jwt=false e nenhuma verificação). Agora só passa: a chave
//       de serviço (a do ambiente ou a do cofre do banco, validada na Auth), um
//       admin, um estafeta aprovado, o dono do pedido ou o dono da loja do
//       pedido. É a mesma autenticação do notify-driver v42, mais os papéis com
//       que a app chama o motor. verify_jwt continua false.
//   (2) QUEM RECEBE A OFERTA. Os candidatos vêm TODOS de
//       public.dispatch_candidatos_entrega(order_id) — o matching das entregas
//       num sítio só: online + aprovado + não banido + batimento E GPS frescos
//       (dispatch_gps_fresh_seconds_entregas) + uma oferta viva de cada vez +
//       favor sozinho + máx. 3 ativos + raio (dispatch_raio_max_oferta_km),
//       já ordenados (mesma loja primeiro, depois o mais perto).
//   Ofertas, TTL, claim, redispatch e identidade (v59) ficam IGUAIS.
// dispatch-engine v59 (2026-08-16)`);

// 2) Constantes e ajudas que só serviam o matching antigo ---------------------
trocar(`const PREFERRED_RADIUS_KM = 10
const CAR_REQUIRED_SERVICES = ['carryGroceries']
const DISTANCE_WEIGHT = 5.0
const COST_WEIGHT = 1.0
const COST_PER_KM = 1.0
const AVG_SPEED_KMH = 30.0
`, '');
trocar(`function computeScore(d: number) { return (-d * DISTANCE_WEIGHT) + (-d * COST_PER_KM * COST_WEIGHT) }
function estimateEta(d: number) { return Math.round((d / AVG_SPEED_KMH) * 60) }
`, '');

// 3) Porta de entrada: autenticação -----------------------------------------
trocar(`  try { const b = await req.json(); orderId = b?.orderId ?? null } catch (_) {}
  console.log(\`[dispatch-engine] v59 INVOKED orderId=\${orderId ?? 'ALL'}\`)
`, `  try { const b = await req.json(); orderId = b?.orderId ?? null } catch (_) {}
  const autorizado = await autorizar(req, supabase, supabaseUrl, serviceKey, orderId)
  if (!autorizado.ok) {
    console.warn(\`[dispatch-engine] v62 403 motivo=\${autorizado.reason} orderId=\${orderId ?? 'ALL'}\`)
    return new Response(JSON.stringify({ ok: false, error: 'forbidden' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  console.log(\`[dispatch-engine] v62 INVOKED orderId=\${orderId ?? 'ALL'}\`)
`);

// 4) dispatchOrder: reinício do ciclo e escolha pelos candidatos do banco ------
trocarEntre(
  `  if (triedIds.length > 0) {
    const reqCar = order.requires_car === true || CAR_REQUIRED_SERVICES.includes(order.service_type)
`,
  `  const driver = await findNextDriver(supabase, order, triedIds)
`,
  `  // v62: o matching vive em dispatch_candidatos_entrega (banco). Um erro aqui
  // sobe — a cadeia volta a tentar; nunca se cai num matching antigo às escondidas.
  const candidatos = await carregarCandidatos(supabase, order.id)
  if (triedIds.length > 0 && candidatos.length > 0 &&
      candidatos.every((d: any) => driverKeys(d).some(k => triedIds.includes(k)))) {
    console.log(\`[dispatch] All \${candidatos.length} drivers tried — cycle reset\`)
    triedIds.length = 0
  }
  const driver = findNextDriver(candidatos, triedIds)
`,
  { incluiFim: true },
);

// 5) findNextDriver: o primeiro candidato ainda não tentado -------------------
trocarEntre(
  `async function findNextDriver(supabase: any, order: any, excludeIds: string[]) {
`,
  `async function assignDriver(`,
  `async function carregarCandidatos(supabase: any, orderId: string): Promise<any[]> {
  const { data, error } = await supabase.rpc('dispatch_candidatos_entrega', { p_order_id: orderId })
  if (error) { console.error('[dispatch] dispatch_candidatos_entrega error:', JSON.stringify(error)); throw error }
  return (data ?? []).map((c: any) => ({
    id: c.driver_id, user_id: c.user_id, lat: c.lat, lng: c.lng, vehicle_type: c.vehicle_type, dist: c.dist_km,
  }))
}

function findNextDriver(candidatos: any[], excludeIds: string[]) {
  // A ordem já vem do banco: quem leva pedido da mesma loja primeiro, depois o mais perto.
  // v59: excludeIds pode conter drivers.id OU drivers.user_id (legado).
  const livres = candidatos.filter((d: any) => !driverKeys(d).some(k => excludeIds.includes(k)))
  console.log(\`[dispatch] \${livres.length} candidatos (de \${candidatos.length}, excl \${excludeIds.length})\`)
  const best = livres[0] ?? null
  if (best) console.log(\`[dispatch] Best driver=\${best.id} dist=\${best.dist != null ? Number(best.dist).toFixed(2) : '?'}km\`)
  return best
}

`,
  { incluiFim: false },
);

// 6) Fim do ficheiro: sai o haversine, entra a autenticação --------------------
{
  const inicio = 'function haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {\n';
  umaVez(inicio);
  s = s.slice(0, s.indexOf(inicio)) + `// ── Autenticação (v62) — a do notify-driver v42, mais os papéis da app ────────
const servicoOk = new Set<string>()
const ADMIN_EMAILS = ['nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com']
function lerPayload(token: string): any {
  try {
    let b = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    while (b.length % 4) b += '='
    return JSON.parse(atob(b))
  } catch (_) { return null }
}
async function autorizar(req: Request, supabase: any, supabaseUrl: string, serviceKey: string, orderId: string | null): Promise<{ ok: boolean, reason?: string }> {
  const h = req.headers.get('authorization') ?? ''
  if (!h.toLowerCase().startsWith('bearer ')) return { ok: false, reason: 'sem_token' }
  const token = h.slice(7).trim()
  if (!token) return { ok: false, reason: 'sem_token' }
  // Gatilhos, cron, webhooks e o próprio motor (redispatch) mandam a chave de serviço.
  if (token === serviceKey || servicoOk.has(token)) return { ok: true }
  const p = lerPayload(token)
  if (p?.role === 'service_role') {
    // Chave de serviço do cofre do banco (pode não ser igual à do ambiente):
    // só passa se a Auth a aceitar como admin.
    try {
      const r = await fetch(\`\${supabaseUrl}/auth/v1/admin/users?per_page=1\`, { headers: { apikey: token, Authorization: \`Bearer \${token}\` } })
      if (r.ok) { servicoOk.add(token); return { ok: true } }
    } catch (_) {}
    return { ok: false, reason: 'service_invalido' }
  }
  if (p?.role !== 'authenticated') return { ok: false, reason: \`papel_\${p?.role ?? 'desconhecido'}\` }
  const { data: u, error } = await supabase.auth.getUser(token)
  if (error || !u?.user) return { ok: false, reason: 'jwt_invalido' }
  const uid = String(u.user.id)
  if (u.user.app_metadata?.role === 'admin' || ADMIN_EMAILS.includes(String(u.user.email ?? '').toLowerCase())) return { ok: true }
  // Estafeta aprovado: a app dele acorda o motor ao ficar online (por pedido pendente).
  const { data: d } = await supabase.from('drivers').select('id').eq('user_id', uid).eq('approval_status', 'approved').limit(1)
  if (d?.length) return { ok: true }
  if (!orderId) return { ok: false, reason: 'sem_pedido' }
  // Dono do pedido (cliente) ou dono da loja do pedido (parceiro).
  const { data: o } = await supabase.from('orders').select('user_id,restaurant_id').eq('id', orderId).maybeSingle()
  if (!o) return { ok: false, reason: 'pedido_desconhecido' }
  if (o.user_id && String(o.user_id) === uid) return { ok: true }
  if (o.restaurant_id) {
    const { data: r } = await supabase.from('restaurants').select('user_id,user_').eq('id', o.restaurant_id).maybeSingle()
    if (r && (String(r.user_id ?? '') === uid || String(r.user_ ?? '') === uid)) return { ok: true }
  }
  return { ok: false, reason: 'papel_sem_permissao' }
}
`;
}

// Verificações finais: o que tem de ter saído e o que tem de ter entrado -------
const contar = (t) => s.split(t).length - 1;
for (const morto of ['PREFERRED_RADIUS_KM', 'CAR_REQUIRED_SERVICES', 'haversine', 'computeScore',
  'estimateEta', "from('tvde_rides')", "select('id,user_id,lat,lng,vehicle_type')", 'v59 INVOKED']) {
  if (contar(morto) !== 0) throw new Error(`ainda aparece: ${morto}`);
}
const esperado = { "rpc('dispatch_candidatos_entrega'": 1, 'await autorizar(': 1, 'async function autorizar(': 1,
  'v62 INVOKED': 1, 'async function assignDriver(': 1, 'async function decideRedispatch(': 1,
  'async function scheduleRedispatch(': 1, 'async function processDispatch(': 1 };
for (const [t, n] of Object.entries(esperado)) {
  if (contar(t) !== n) throw new Error(`esperava ${n}× ${t}, há ${contar(t)}`);
}

const saida = path.join(aqui, 'index.v62.PROPOSTA.ts');
fs.writeFileSync(saida, s);
const base = path.join(aqui, '.v61.tmp.ts');
fs.writeFileSync(base, v61);
let diff = '';
try {
  execFileSync('git', ['diff', '--no-index', '--no-color', '--', base, saida], { encoding: 'utf8' });
} catch (e) { diff = String(e.stdout ?? ''); }
fs.rmSync(base);
diff = diff.replace(/^(diff --git|index |---|\+\+\+) .*$/gm, (l) =>
  l.startsWith('---') ? '--- a/supabase/functions/dispatch-engine/index.ts'
  : l.startsWith('+++') ? '+++ b/supabase/functions/dispatch-engine/index.ts'
  : l.startsWith('diff') ? 'diff --git a/supabase/functions/dispatch-engine/index.ts b/supabase/functions/dispatch-engine/index.ts'
  : l);
fs.writeFileSync(path.join(aqui, 'v61-para-v62.diff'), diff);
console.log(`v61: ${v61.split('\n').length} linhas  ->  v62: ${s.split('\n').length} linhas`);
console.log(`escrito: ${path.relative(raiz, saida)} e v61-para-v62.diff (${diff.split('\n').length} linhas de diff)`);
