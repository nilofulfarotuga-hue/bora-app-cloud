// tools/varrer_chaves_funcoes.ts — varredura das chaves em TODAS as Edge Functions.
// Missão chaves-varredura-2026-10-31 (bloco A9). Regra da casa: docs/SEGURANCA-CHAVES.md + _shared/chaves.ts.
//
//   deno run --allow-read tools/varrer_chaves_funcoes.ts            # só o código (sem rede)
//   deno run --allow-read --allow-env --allow-net tools/varrer_chaves_funcoes.ts --vivo
//     (no --vivo, o ambiente traz SUPABASE_URL e a chave secreta nova em SUPABASE_SECRET_KEY)
//
// (a) CÓDIGO — em cada pasta de supabase/functions/ (menos _shared e _arquivo) procura os padrões que
//     partiram produção depois da troca de chaves de 16/10:
//       • comparar o token com a variável de ambiente (igualdade com SUPABASE_SERVICE_ROLE_KEY,
//         serviceKey, SERVICE_KEY…) — a variável é a sb_secret "default" e o banco manda outra;
//       • ler o papel/sub do JWT à mão (jwtRole, split('.')[1], atob sobre partes do token) —
//         com verify_jwt=false qualquer pessoa forja o payload; com =true recusa a chave nova.
//     Só _shared/chaves.ts pode fazer isto (e faz com confirmação no Auth).
// (b) NO AR (--vivo) — chama, com a chave secreta em `apikey` E em `Authorization: Bearer`, cada função
//     que tem o ramo `respostaAoPing` (o vigia diário), com {"ping":true}. Tem de responder 200 {"pong":true};
//     401/403 = a chave do servidor deixou de passar a porta dessa função. Só se chamam funções com ping:
//     as outras podiam fazer trabalho a sério com um corpo qualquer.
//
// Sai com código 1 se houver achados no código fora das exceções, ou falhas no ar.

const RAIZ = new URL('../supabase/functions/', import.meta.url);

/** Exceções explícitas — cada uma com o porquê. Acrescentar aqui só com razão escrita. */
export const EXCECOES: Record<string, string> = {
  'places-proxy':
    'lê o `sub` do JWT só para a chave do limite de pedidos por minuto (não decide acesso); verify_jwt=true valida a assinatura',
};

export type Achado = { funcao: string; ficheiro: string; linha: number; padrao: string; texto: string };

const PADROES: { nome: string; re: RegExp }[] = [
  {
    nome: 'compara o token com a variável de ambiente',
    re: /(token|bearer|auth\w*|h)\s*===?\s*(Deno\.env\.get\(\s*['"]SUPABASE_SERVICE_ROLE_KEY['"]\s*\)|(serviceKey|SERVICE_KEY|SUPABASE_SERVICE_ROLE_KEY|serviceRoleKey)\b)/,
  },
  {
    nome: 'compara com a variável de ambiente (ao contrário)',
    re: /(Deno\.env\.get\(\s*['"]SUPABASE_SERVICE_ROLE_KEY['"]\s*\)|serviceKey|SERVICE_KEY|SUPABASE_SERVICE_ROLE_KEY|serviceRoleKey)\s*===?\s*(token|bearer)\b/,
  },
  { nome: 'lê o papel do JWT à mão', re: /\b(jwtRole|decodeJwtRole|roleFromJwt|lerPayload|jwtServiceRoleVerificadoPelaPorta)\s*\(/ },
  { nome: 'parte o JWT à mão', re: /\.split\(\s*['"]\.['"]\s*\)\s*\[\s*1\s*\]/ },
  { nome: 'descodifica parte do JWT', re: /atob\([^)]*\b(parts|partes)\s*\[\s*1\s*\]/ },
];

async function* ficheirosTs(dir: URL): AsyncGenerator<URL> {
  for await (const e of Deno.readDir(dir)) {
    const u = new URL(e.name + (e.isDirectory ? '/' : ''), dir);
    if (e.isDirectory) yield* ficheirosTs(u);
    else if (e.name.endsWith('.ts') && !e.name.endsWith('_test.ts')) yield u;
  }
}

/** Varre o texto de um ficheiro. Linhas de comentário puro não contam. */
export function varrerTexto(funcao: string, ficheiro: string, texto: string): Achado[] {
  const achados: Achado[] = [];
  texto.split(/\r?\n/).forEach((linha, i) => {
    const t = linha.trim();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return;
    for (const p of PADROES) {
      if (p.re.test(linha)) achados.push({ funcao, ficheiro, linha: i + 1, padrao: p.nome, texto: t.slice(0, 140) });
    }
  });
  return achados;
}

export async function varrerCodigo(raiz: URL = RAIZ): Promise<{ achados: Achado[]; comPing: string[]; total: number }> {
  const achados: Achado[] = [];
  const comPing: string[] = [];
  let total = 0;
  const pastas: string[] = [];
  for await (const e of Deno.readDir(raiz)) {
    if (e.isDirectory && !e.name.startsWith('_')) pastas.push(e.name);
  }
  pastas.sort();
  for (const funcao of pastas) {
    total++;
    let temPing = false;
    for await (const f of ficheirosTs(new URL(funcao + '/', raiz))) {
      const texto = await Deno.readTextFile(f);
      if (/respostaAoPing\s*\(|body\?\.ping === true/.test(texto)) temPing = true;
      achados.push(...varrerTexto(funcao, f.pathname.split('/supabase/functions/')[1] ?? f.pathname, texto));
    }
    if (temPing) comPing.push(funcao);
  }
  return { achados, comPing, total };
}

async function varrerNoAr(funcoes: string[]): Promise<{ funcao: string; status: number; ok: boolean; corpo: string }[]> {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const chave = Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !chave.startsWith('sb_secret_')) {
    throw new Error('--vivo precisa de SUPABASE_URL e da chave secreta nova (sb_secret) em SUPABASE_SECRET_KEY');
  }
  const out = [];
  for (const funcao of funcoes) {
    let status = 0;
    let corpo = '';
    try {
      const r = await fetch(`${url}/functions/v1/${funcao}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: chave, Authorization: `Bearer ${chave}` },
        body: '{"ping":true}',
      });
      status = r.status;
      corpo = (await r.text()).slice(0, 120);
    } catch (e) {
      corpo = String(e).slice(0, 120);
    }
    out.push({ funcao, status, ok: status === 200 && corpo.includes('"pong":true'), corpo });
  }
  return out;
}

if (import.meta.main) {
  const vivo = Deno.args.includes('--vivo');
  const { achados, comPing, total } = await varrerCodigo();
  const fora = achados.filter((a) => !(a.funcao in EXCECOES));
  const porFuncao = new Map<string, Achado[]>();
  for (const a of fora) porFuncao.set(a.funcao, [...(porFuncao.get(a.funcao) ?? []), a]);

  console.log(`Código: ${total} funções varridas · ${comPing.length} com ramo ping · ${porFuncao.size} com padrão proibido`);
  for (const [f, lista] of porFuncao) {
    console.log(`  ✗ ${f}`);
    for (const a of lista) console.log(`      ${a.ficheiro}:${a.linha}  ${a.padrao}  →  ${a.texto}`);
  }
  for (const [f, porque] of Object.entries(EXCECOES)) {
    if (achados.some((a) => a.funcao === f)) console.log(`  ~ ${f} (exceção: ${porque})`);
  }

  let falhasNoAr = 0;
  if (vivo) {
    const r = await varrerNoAr(comPing);
    falhasNoAr = r.filter((x) => !x.ok).length;
    console.log(`No ar: ${r.length} funções com ping chamadas com a chave secreta (apikey + Bearer) · ${falhasNoAr} falharam`);
    for (const x of r) console.log(`  ${x.ok ? '✓' : '✗'} ${x.funcao}  ${x.status}  ${x.ok ? '' : x.corpo}`);
  }

  if (porFuncao.size > 0 || falhasNoAr > 0) Deno.exit(1);
  console.log('Tudo verde.');
}
