// 28/11/2026 (ordem do Danilo 09:38): entrar na app sem telemóvel e sem morada pode; fazer pedido não.
// Quando falta a morada ou o telemóvel, o Amigo diz exatamente o que falta e onde se põe, e mostra na
// mesma os produtos e os preços que escolheu (caso da Lena, conversa e0be9cf6: o carrinho falhou com
// SEM_MORADA e a resposta foi a frase genérica "Não consegui concluir...").

export interface FaltaContacto {
  morada: boolean;
  telefone: boolean;
}

export interface Escolhido {
  nome: string;
  loja: string;
  preco: number | null;
  quantidade: number;
}

/** As frases de recurso do fecho que nunca podem tapar a falta de morada ou de telemóvel. */
export function eRespostaGenerica(texto: string): boolean {
  const t = (texto ?? '').trim();
  if (!t) return true;
  return /^não consegui concluir/i.test(t) || /^encontrei opções, mas não consegui montar o carrinho/i.test(t);
}

function eur(v: number): string {
  return `${v.toFixed(2).replace('.', ',')} €`;
}

/** Junta o mesmo produto (mesma loja) e guarda no máximo [max] linhas. */
export function juntarEscolhidos(lista: Escolhido[], max = 6): Escolhido[] {
  const porChave = new Map<string, Escolhido>();
  for (const e of lista) {
    const nome = (e.nome ?? '').trim();
    if (!nome) continue;
    const chave = `${nome.toLowerCase()}|${(e.loja ?? '').toLowerCase()}`;
    const ja = porChave.get(chave);
    if (ja) {
      ja.quantidade = Math.max(ja.quantidade, e.quantidade);
    } else {
      porChave.set(chave, { ...e, nome, quantidade: Math.max(1, Math.round(e.quantidade || 1)) });
    }
  }
  return [...porChave.values()].slice(0, max);
}

/** O que falta, dito por extenso ("a tua morada e o teu telemóvel"). */
export function oQueFalta(f: FaltaContacto): string {
  if (f.morada && f.telefone) return 'a tua morada e o teu telemóvel';
  if (f.morada) return 'a tua morada';
  if (f.telefone) return 'o teu telemóvel';
  return '';
}

/** O texto de fecho quando falta morada ou telemóvel: o que falta, onde se põe e o que já escolheu. */
export function textoFaltaContacto(f: FaltaContacto, escolhidos: Escolhido[]): string {
  const falta = oQueFalta(f);
  if (!falta) return '';
  const partes: string[] = [];
  partes.push(`Para eu fechar o teu pedido só falta ${falta}. Toca em "Pôr os meus dados" aqui em baixo.`);
  if (f.morada) partes.push('Na morada põe a rua, o número da porta e o andar, e confirma no mapa onde é a tua porta.');
  if (f.telefone) partes.push('O estafeta usa o telemóvel para te contactar (chamada ou WhatsApp) se precisar.');
  const lista = juntarEscolhidos(escolhidos);
  if (lista.length > 0) {
    const linhas = lista.map((e) => {
      const qtd = e.quantidade > 1 ? `${e.quantidade}× ` : '';
      const loja = e.loja ? ` (${e.loja})` : '';
      const preco = typeof e.preco === 'number' && e.preco > 0 ? ` — ${eur(e.preco)}` : '';
      return `• ${qtd}${e.nome}${loja}${preco}`;
    });
    partes.push(`Entretanto já escolhi isto para ti:\n${linhas.join('\n')}`);
  }
  partes.push('Assim que puseres, diz-me "monta o carrinho" e eu trato do resto.');
  return partes.join('\n\n');
}

/** A nota que vai ao modelo no resultado da ferramenta (ele escreve a resposta com isto). */
export function notaFaltaContacto(f: FaltaContacto): string {
  const falta = oQueFalta(f);
  return `Para fazer pedido falta ${falta}. Diz à pessoa, numa frase simples, exatamente o que falta e que toca em "Pôr os meus dados"` +
    (f.morada ? ' (morada com rua, número da porta e andar)' : '') +
    (f.telefone ? ' (o estafeta usa o telemóvel para a contactar, por chamada ou WhatsApp)' : '') +
    '. Mostra NA MESMA os produtos que escolheste com os preços. Não digas "não consegui" nem peças para repetir a lista.';
}
