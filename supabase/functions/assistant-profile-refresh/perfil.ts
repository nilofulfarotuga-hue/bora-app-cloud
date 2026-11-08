// Amigo Bora v1 (08/11/2026) — junta factos + memórias + conversa num perfil só (puro, testado em perfil_test.ts).

// deno-lint-ignore no-explicit-any
type Json = any;

function limpa(s: unknown, max: number): string {
  return String(s ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/<<<|>>>|⟦|⟧/g, '').replace(/\s+/g, ' ').trim().slice(0, max);
}

/** O que nunca entra no perfil: números longos (telefones, cartões), emails, moradas, pagamentos. */
export const PROIBIDO = /(\d{9,}|@|iban|cart[aã]o|visa|mastercard|mb ?way|\bnif\b|password|senha|\brua\b|avenida|\bav\.)/i;

function listaSegura(v: unknown, max = 5): string[] {
  if (!Array.isArray(v)) return [];
  return v.map((x) => limpa(x, 60)).filter((x) => x.length > 1 && !PROIBIDO.test(x)).slice(0, max);
}

export function montarPerfil(factos: Json, memorias: Json[], conversa: Json | null, anterior: Json): Json {
  const restricoes = new Set<string>(listaSegura(anterior?.restricoes));
  const gostos = new Set<string>(listaSegura(anterior?.gostos));
  for (const m of memorias ?? []) {
    const v = limpa(typeof m?.value === 'string' ? m.value : (m?.value?.text ?? ''), 60);
    if (!v || PROIBIDO.test(v)) continue;
    const k = limpa(m?.key, 30);
    if (m?.kind === 'restricao_alimentar') restricoes.add(v);
    else if (m?.kind === 'marca_preferida') gostos.add(k ? `${k}: ${v}` : v);
    else if (m?.kind === 'nunca_substituir') gostos.add(`nunca trocar ${k || v}`);
  }
  for (const r of listaSegura(conversa?.restricoes)) restricoes.add(r);
  for (const g of listaSegura(conversa?.gostos)) gostos.add(g);
  const nome = limpa(conversa?.nome_tratamento ?? anterior?.nome_tratamento ?? '', 30);
  const registo = conversa?.registo === 'formal' || conversa?.registo === 'informal' ? conversa.registo : (anterior?.registo ?? null);
  const notas = limpa(conversa?.notas ?? anterior?.notas ?? '', 160);
  const ticket = factos?.ticket_medio_eur === null || factos?.ticket_medio_eur === undefined ? null : Number(factos.ticket_medio_eur);
  return {
    versao: 1,
    nome_tratamento: nome && !PROIBIDO.test(nome) ? nome : null,
    registo,
    lojas_favoritas: factos?.lojas_favoritas ?? [],
    recorrentes: factos?.recorrentes ?? [],
    habitos: factos?.habitos ?? [],
    ticket_medio_eur: ticket !== null && Number.isFinite(ticket) ? ticket : null,
    categorias: factos?.categorias ?? {},
    pedidos_entregues: Number(factos?.pedidos_entregues ?? 0),
    ultimo_pedido_em: factos?.ultimo_pedido_em ?? null,
    restricoes: [...restricoes].slice(0, 5),
    gostos: [...gostos].slice(0, 5),
    notas: notas && !PROIBIDO.test(notas) ? notas : null,
  };
}
