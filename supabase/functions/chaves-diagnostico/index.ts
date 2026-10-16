// chaves-diagnostico — DESCARTÁVEL (missão chave-nova-16-10, 16/10/2026).
//
// Serve só para responder a uma pergunta que a documentação não fecha: que variáveis
// SUPABASE_* a plataforma injeta nas Edge Functions deste projeto (em especial
// SUPABASE_SECRET_KEYS / SUPABASE_PUBLISHABLE_KEYS / SUPABASE_JWKS) e com que nomes de
// chave. Devolve NOMES, tamanhos e um prefixo de 12 caracteres — nunca um valor inteiro.
// Protegida por um cabeçalho descartável; depois de usada é substituída por um 410.

const NONCE = '9b1e4c7d2a6f83e05c41b7a2d9e6f130-chave-nova-16-10';

Deno.serve((req: Request) => {
  if (req.headers.get('x-diag') !== NONCE) {
    return new Response('nao', { status: 404 });
  }
  const env = Deno.env.toObject();
  const nomes = Object.keys(env)
    .filter((k) => k.startsWith('SUPABASE_') || k.startsWith('SB_'))
    .sort();
  const resumo: Record<string, unknown> = {};
  for (const k of nomes) {
    const v = env[k] ?? '';
    if (k === 'SUPABASE_SECRET_KEYS' || k === 'SUPABASE_PUBLISHABLE_KEYS') {
      try {
        const o = JSON.parse(v) as Record<string, unknown>;
        resumo[k] = Object.fromEntries(
          Object.entries(o).map(([n, val]) => [n, String(val).slice(0, 12) + '… len=' + String(val).length]),
        );
      } catch {
        resumo[k] = 'nao-json len=' + v.length + ' inicio=' + v.slice(0, 12);
      }
    } else if (k === 'SUPABASE_JWKS') {
      try {
        const o = JSON.parse(v) as { keys?: Array<{ alg?: string; kty?: string; kid?: string }> };
        resumo[k] = 'keys=' + (o.keys?.length ?? '?') + ' ' +
          (o.keys ?? []).map((x) => `${x.alg}/${x.kty}/${String(x.kid ?? '').slice(0, 8)}`).join(',');
      } catch {
        resumo[k] = 'nao-json len=' + v.length;
      }
    } else {
      resumo[k] = (v.startsWith('eyJ') ? 'JWT' : v.slice(0, 12) + '…') + ' len=' + v.length;
    }
  }
  return new Response(JSON.stringify({ nomes, resumo }, null, 1), {
    headers: { 'content-type': 'application/json' },
  });
});
