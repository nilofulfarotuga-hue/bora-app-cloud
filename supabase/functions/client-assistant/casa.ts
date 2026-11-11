// CASA E MANUTENÇÃO NO AMIGO (11/11/2026, missão amigo-casa-2026-11-11, ordem do Danilo: "Conserta o amigo").
//
// O Amigo sabia que a Casa existia mas não dizia o preço, perguntava "quantas pessoas" (frase de reserva de
// mesa), sugeria um Favor para ir buscar material e só mostrava o botão "Pedir um Favor". Agora:
// - os serviços e os preços vêm da RPC casa_config (a mesma que a app usa; tabela casa_servicos), nunca de cor;
// - a regra do material, a garantia e o cancelamento vêm das definições (casa_garantia_dias, casa_cancel_free_hours);
// - a resposta acaba com a ligação "abrir a Casa e Manutenção", que vai como DEIXA (abrir_faixa → categoria casa):
//   as apps já publicadas abrem-na sem versão nova (tocarDeixa → abrirDestino → CasaCategoriaScreen).

type Json = any;

// Trabalhos em casa: montar/pendurar/reparar/pintar/canalização/eletricidade/jardim/mudanças.
const RE_CASA = new RegExp(
  [
    '\\bmont(ar|agem|e|em)\\b[^.?!]{0,40}\\b(m[oó]ve(l|is)|roupeiro|arm[aá]rio|cama|estante|cozinha|secret[aá]ria|c[oó]moda|beliche|mesa|ikea)',
    '\\bpendur(ar|e)\\b', '\\bfix(ar|e)\\b[^.?!]{0,30}\\b(televis|tv|parede|prateleira|quadro|espelho|varão|var[aã]o|cortin)',
    '\\b(televis[aã]o|tv)\\b[^.?!]{0,30}\\bparede\\b',
    '\\bpint(ar|ura|or)\\b[^.?!]{0,30}\\b(sala|quarto|parede|casa|tecto|teto|cozinha|apartamento)',
    '\\btorneira\\b', '\\bautoclismo\\b', '\\bsif[aã]o\\b', '\\bcanaliza', '\\bcanalizador', '\\bfuga de [aá]gua',
    '\\b(trocar|mudar|instalar|montar|p[oô]r) (o |um )?candeeiro\\b', '\\bdisjuntor', '\\beletricista', '\\beletricidade\\b',
    '\\bpladur\\b', '\\balvenaria\\b', '\\bsilicone\\b', '\\bfaz[- ]tudo\\b', '\\bbiscate', '\\breparar\\b', '\\breparaç',
    '\\bconsert(ar|o)\\b[^.?!]{0,30}\\b(porta|janela|estore|persiana|gaveta|arm[aá]rio|torneira|fechadura)',
    '\\bcortar (a )?relva\\b', '\\bjardin', '\\bpodar\\b', '\\bmato\\b', '\\bmudan[cç]a\\b', '\\bprateleiras?\\b',
    '\\bcortinad', '\\bcasa e manuten',
  ].join('|'),
  'i',
);

/** A mensagem fala de um trabalho em casa (montar, pendurar, canalização...)? */
export function eTrabalhoDeCasa(msg: string): boolean {
  return RE_CASA.test(String(msg ?? ''));
}

function euros(cents: number): string {
  return `${(cents / 100).toFixed(2).replace('.', ',')} €`;
}

/** O preço de um serviço como se diz ao cliente (só com o valor da tabela). */
export function precoCasa(s: Json): string {
  const modo = String(s?.modo ?? '');
  const c = typeof s?.preco_cents === 'number' ? s.preco_cents : null;
  if (modo === 'orcamento' || c == null) return 'por orçamento: o cliente manda fotos e os profissionais respondem com o preço';
  if (modo === 'hora') return `${euros(c)} por hora`;
  const un = String(s?.unidade ?? '');
  return un === 'movel' ? `${euros(c)} por móvel` : euros(c);
}

/** O que a ferramenta casa_servicos devolve ao modelo, a partir da casa_config. */
export function casaParaModelo(cfg: Json): Json {
  const visivel = cfg?.visivel === true;
  if (!visivel) {
    return { disponivel: false, nota: 'A Casa e Manutenção ainda não está disponível. Diz isso numa frase; não ofereças Favor para o trabalho.' };
  }
  const oficios = new Map<string, string>();
  const desligados: string[] = [];
  for (const o of (Array.isArray(cfg?.oficios) ? cfg.oficios : [])) {
    oficios.set(String(o?.codigo), String(o?.nome ?? o?.codigo));
    if (o?.ativo === false) desligados.push(String(o?.nome ?? o?.codigo));
  }
  const servicos = (Array.isArray(cfg?.servicos) ? cfg.servicos : []).map((s: Json) => ({
    servico: String(s?.nome ?? ''),
    area: oficios.get(String(s?.oficio)) ?? String(s?.oficio ?? ''),
    preco: precoCasa(s),
    ...(s?.descricao ? { descricao: String(s.descricao).slice(0, 160) } : {}),
  }));
  const garantia = Number.isFinite(Number(cfg?.garantia_dias)) ? Number(cfg.garantia_dias) : 7;
  const cancelar = Number.isFinite(Number(cfg?.cancel_free_hours)) ? Number(cfg.cancel_free_hours) : 12;
  return {
    disponivel: true,
    servicos,
    // 11/11/2026: a casa_config só traz serviços de ofícios ligados; os desligados (ex.: Pintura, Eletricidade,
    // fase 2 com certificado) dizem-se como "ainda não disponível", nunca se metem noutro serviço.
    ainda_nao_disponivel: desligados,
    regras: {
      material: 'O profissional leva as ferramentas; o material (o móvel, a torneira, a tinta, os parafusos especiais...) é do cliente e tem de estar em casa no dia.',
      garantia: `Garantia de ${garantia} dias: se algo ficar mal, o profissional volta sem custo.`,
      cancelamento: `Cancelar é grátis até ${cancelar} horas antes.`,
      marcar: 'Marca-se na app, em Casa e Manutenção: escolhe o serviço, o dia e a hora. O botão para abrir aparece por baixo da tua resposta.',
    },
    instrucao: 'Escolhe o serviço que bate com o pedido e diz o preço tal como está aqui (uma frase), a regra do material numa frase curta, e que pode marcar no botão. Garantia e cancelamento: diz se ajudar ou se perguntarem. Trabalhos "por orçamento": diz que se pede orçamento com fotos e os profissionais respondem com o preço. Se o trabalho é de uma área em ainda_nao_disponivel (ex.: pintura), diz com simpatia que essa área ainda não está disponível na Casa e Manutenção e não o metas noutro serviço. Nunca perguntes quantas pessoas, nem ofereças um Favor para ir buscar material.',
  };
}

/** A ligação que abre a Casa e Manutenção (deixa abrir_faixa → categoria casa; funciona nas apps já publicadas). */
export function deixaCasa(hoje: string): { chave: string; tipo: string; texto: string; acao: Json } {
  return {
    chave: `casa:${hoje}`,
    tipo: 'casa',
    texto: 'Abrir a Casa e Manutenção para marcar',
    acao: { tipo: 'abrir_faixa', destino: JSON.stringify({ tipo_destino: 'categoria', destino: 'casa' }) },
  };
}

// Frases de reserva de mesa que não podem aparecer fora das reservas.
const RE_FRASE_MESA = /\b(para )?quantas pessoas\b|\bmesa para quantos\b|\bquantos (s[aã]o|v[aã]o ser)\b/i;

/** A resposta tem uma pergunta de reserva de mesa (fora de uma reserva de mesa)? */
export function temFraseDeMesa(texto: string): boolean {
  return RE_FRASE_MESA.test(String(texto ?? ''));
}

/** Tira as frases de reserva de mesa de uma resposta sobre a Casa (fica o resto, igual). */
export function semFraseDeMesa(texto: string): string {
  const t = String(texto ?? '');
  if (!temFraseDeMesa(t)) return t;
  const frases = t.match(/[^.?!]+[.?!]*\s*/g) ?? [t];
  const fica = frases.filter((f) => !temFraseDeMesa(f)).join('').trim();
  return fica || t;
}
