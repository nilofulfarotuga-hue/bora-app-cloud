// deno test --allow-read tools/varrer_chaves_funcoes_test.ts
import { EXCECOES, varrerCodigo, varrerTexto } from './varrer_chaves_funcoes.ts';

Deno.test('apanha os padroes que partiram producao', () => {
  const casos = [
    "  if (token === Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) {",
    '  if (token === serviceKey || servicoOk.has(token)) return { ok: true }',
    '  if (!(SERVICE_KEY && token === SERVICE_KEY)) {',
    "  const role = jwtRole(req.headers.get('authorization') ?? '');",
    "    const payload = JSON.parse(atob(token.split('.')[1]))",
    '    Uint8Array.from(atob(parts[1].replace(/-/g, "+")), (c) => c.charCodeAt(0))',
  ];
  for (const c of casos) {
    if (varrerTexto('f', 'f/index.ts', c).length === 0) throw new Error('nao apanhou: ' + c);
  }
});

Deno.test('nao apanha o que e legitimo', () => {
  const casos = [
    '  if (await chamadaDoServidor(req)) return { ok: true }',
    '  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))',
    '    const raw = atob(body.fileBase64)',
    "  // antigo: token === Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') (comentario nao conta)",
    '    if (e.fcm_token && !alvos.some((a) => a.token === e.fcm_token)) {',
  ];
  for (const c of casos) {
    const a = varrerTexto('f', 'f/index.ts', c);
    if (a.length !== 0) throw new Error('falso positivo: ' + c);
  }
});

Deno.test('o repo de hoje: so as funcoes de zona vermelha por publicar ficam de fora', async () => {
  const { achados, comPing, total } = await varrerCodigo();
  const fora = new Set(achados.filter((a) => !(a.funcao in EXCECOES)).map((a) => a.funcao));
  const esperadas = new Set(['dispatch-engine', 'finalize-order-from-intent', 'refund']);
  for (const f of fora) if (!esperadas.has(f)) throw new Error('funcao nova com padrao proibido: ' + f);
  if (total < 90) throw new Error('varreu poucas funcoes: ' + total);
  for (const f of ['notify-client', 'notify-driver', 'tvde-payment', 'support-password-reset', 'settlement-receipt']) {
    if (!comPing.includes(f)) throw new Error('sem ramo ping: ' + f);
  }
});
