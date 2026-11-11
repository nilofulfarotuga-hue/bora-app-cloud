---
id: memoria-claude-ai-entrega-amigo-casa-2026-11-11-patch
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Remendo do client-assistant (Amigo + Casa e Manutenção) 11/11 — git apply sobre origin/autonomous-night-2026-04-29 b8af9bc9

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `entrega-amigo-casa-2026-11-11-patch`, origem `claude-code`, atualizada em 2026-11-11T17:06:36.927119+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: entrega amigo casa 2026 11 11 patch · memoria claude.ai · claude_ai_memoria

diff --git a/supabase/functions/client-assistant/amigo.ts b/supabase/functions/client-assistant/amigo.ts
index 2eb3c9b2..f856a957 100644
--- a/supabase/functions/client-assistant/amigo.ts
+++ b/supabase/functions/client-assistant/amigo.ts
@@ -139,7 +139,7 @@ export function emocaoPorDefeito(o: { erro: boolean; handoff: boolean; temCarrin
  * ligada, esta é a frase de identidade (substitui a do "assistente de compras").
  */
 export const IDENTIDADE_AMIGO =
-  'És o Amigo Bora, o amigo do cliente na Guarda, Portugal, para o que ele quiser: conversar, comida (restaurantes), mercado e supermercados, lojas e farmácias, Favores, Limpeza, Reservas de mesa, Serviços, dúvidas sobre a Guarda e sobre a app Bora. NUNCA te apresentas nem te descreves como "assistente de compras" nem "amigo de compras": és o Amigo, para tudo.';
+  'És o Amigo Bora, o amigo do cliente na Guarda, Portugal, para o que ele quiser: conversar, comida (restaurantes), mercado e supermercados, lojas e farmácias, Favores, Limpeza, Casa e Manutenção, Reservas de mesa, Serviços, dúvidas sobre a Guarda e sobre a app Bora. NUNCA te apresentas nem te descreves como "assistente de compras" nem "amigo de compras": és o Amigo, para tudo.';
 
 // ─── Que tipo de mensagem é ───────────────────────────────────────────────────
 
@@ -332,7 +332,7 @@ export function blocoAmigo(pesquisa = false): string {
     'Nunca falas de política, religião, saúde ou medicina (além do que as regras da farmácia já dizem), nem de outras pessoas. Nunca prometes prazos nem preços fora das ferramentas.',
     'Quando não sabes: dizes "Isso não sei, mas posso perguntar à equipa" e chamas report_gap.',
     'O PERFIL (abaixo) é o que sabes do cliente: lojas favoritas, hábitos, artigos que repete. Usa-o com naturalidade quando a conversa é sobre comida ou compras ("o do costume", "aquele sushi de sexta"), nunca na conversa solta, e sem recitar listas e sem dizer números do perfil (contagens, orçamento). Nunca dizes "o teu perfil diz" nem "segundo os teus dados".',
-    'COMPRAS E MARCAÇÕES ACABAM SEMPRE NUMA AÇÃO: quando o cliente quer alguma coisa (comida, compras, uma faxina/limpeza, um Favor), a resposta acaba com o carrinho criado (propose_cart ou basket_quote), ou com suggest_action pedir_favor (destino = o que o estafeta compra/faz) ou suggest_action marcar_limpeza (destino = o dia e a hora que o cliente disse). Uma confirmação do cliente só; nunca acabas em texto solto.',
+    'COMPRAS E MARCAÇÕES ACABAM SEMPRE NUMA AÇÃO: quando o cliente quer alguma coisa (comida, compras, uma faxina/limpeza, um Favor), a resposta acaba com o carrinho criado (propose_cart ou basket_quote), ou com suggest_action pedir_favor (destino = o que o estafeta compra/faz) ou suggest_action marcar_limpeza (destino = o dia e a hora que o cliente disse). Uma confirmação do cliente só; nunca acabas em texto solto. Trabalho em casa (montar, pendurar, reparar, pintar...) é a Casa e Manutenção: casa_servicos, o preço que vem, e a ligação para abrir a Casa aparece sozinha (sem Favor).',
     'Comparar com a Glovo/Uber: só com o que o cliente MOSTROU (print) ou ESCREVEU (preços). Se só disse "compara com a Glovo", pede-lhe o print do carrinho. Se escreveu os artigos com preços, chama comparar_outra_app. NUNCA dizes um preço da outra app que o cliente não deu.',
     'A "deixa" do fim (promoção, parceiro novo, tokens, check-in) é posta pelo sistema por baixo da tua resposta: tu NÃO escreves promoções nem deixas por tua conta.',
     'A TUA CARA (a app mostra-te como um rosto que fala): começa SEMPRE a resposta com UMA etiqueta: [cara:alegre] (encontraste o que ele quer, boa notícia, cumprimento), [cara:triste] (não há, está fechado, esgotado), [cara:surpreso] (novidade, coisa inesperada), [cara:pensativo] (precisas de uma informação ou estás a considerar opções), [cara:confuso] (não percebeste o pedido) ou [cara:a_falar] (o resto). O sistema tira a etiqueta antes de o cliente ler; nunca a expliques.',
diff --git a/supabase/functions/client-assistant/casa.ts b/supabase/functions/client-assistant/casa.ts
new file mode 100644
index 00000000..ae122ad2
--- /dev/null
+++ b/supabase/functions/client-assistant/casa.ts
@@ -0,0 +1,109 @@
+// CASA E MANUTENÇÃO NO AMIGO (11/11/2026, missão amigo-casa-2026-11-11, ordem do Danilo: "Conserta o amigo").
+//
+// O Amigo sabia que a Casa existia mas não dizia o preço, perguntava "quantas pessoas" (frase de reserva de
+// mesa), sugeria um Favor para ir buscar material e só mostrava o botão "Pedir um Favor". Agora:
+// - os serviços e os preços vêm da RPC casa_config (a mesma que a app usa; tabela casa_servicos), nunca de cor;
+// - a regra do material, a garantia e o cancelamento vêm das definições (casa_garantia_dias, casa_cancel_free_hours);
+// - a resposta acaba com a ligação "abrir a Casa e Manutenção", que vai como DEIXA (abrir_faixa → categoria casa):
+//   as apps já publicadas abrem-na sem versão nova (tocarDeixa → abrirDestino → CasaCategoriaScreen).
+
+type Json = any;
+
+// Trabalhos em casa: montar/pendurar/reparar/pintar/canalização/eletricidade/jardim/mudanças.
+const RE_CASA = new RegExp(
+  [
+    '\\bmont(ar|agem|e|em)\\b[^.?!]{0,40}\\b(m[oó]ve(l|is)|roupeiro|arm[aá]rio|cama|estante|cozinha|secret[aá]ria|c[oó]moda|beliche|mesa|ikea)',
+    '\\bpendur(ar|e)\\b', '\\bfix(ar|e)\\b[^.?!]{0,30}\\b(televis|tv|parede|prateleira|quadro|espelho|varão|var[aã]o|cortin)',
+    '\\b(televis[aã]o|tv)\\b[^.?!]{0,30}\\bparede\\b',
+    '\\bpint(ar|ura|or)\\b[^.?!]{0,30}\\b(sala|quarto|parede|casa|tecto|teto|cozinha|apartamento)',
+    '\\btorneira\\b', '\\bautoclismo\\b', '\\bsif[aã]o\\b', '\\bcanaliza', '\\bcanalizador', '\\bfuga de [aá]gua',
+    '\\b(trocar|mudar|instalar|montar|p[oô]r) (o |um )?candeeiro\\b', '\\bdisjuntor', '\\beletricista', '\\beletricidade\\b',
+    '\\bpladur\\b', '\\balvenaria\\b', '\\bsilicone\\b', '\\bfaz[- ]tudo\\b', '\\bbiscate', '\\breparar\\b', '\\breparaç',
+    '\\bconsert(ar|o)\\b[^.?!]{0,30}\\b(porta|janela|estore|persiana|gaveta|arm[aá]rio|torneira|fechadura)',
+    '\\bcortar (a )?relva\\b', '\\bjardin', '\\bpodar\\b', '\\bmato\\b', '\\bmudan[cç]a\\b', '\\bprateleiras?\\b',
+    '\\bcortinad', '\\bcasa e manuten',
+  ].join('|'),
+  'i',
+);
+
+/** A mensagem fala de um trabalho em casa (montar, pendurar, canalização...)? */
+export function eTrabalhoDeCasa(msg: string): boolean {
+  return RE_CASA.test(String(msg ?? ''));
+}
+
+function euros(cents: number): string {
+  return `${(cents / 100).toFixed(2).replace('.', ',')} €`;
+}
+
+/** O preço de um serviço como se diz ao cliente (só com o valor da tabela). */
+export function precoCasa(s: Json): string {
+  const modo = String(s?.modo ?? '');
+  const c = typeof s?.preco_cents === 'number' ? s.preco_cents : null;
+  if (modo === 'orcamento' || c == null) return 'por orçamento: o cliente manda fotos e os profissionais respondem com o preço';
+  if (modo === 'hora') return `${euros(c)} por hora`;
+  const un = String(s?.unidade ?? '');
+  return un === 'movel' ? `${euros(c)} por móvel` : euros(c);
+}
+
+/** O que a ferramenta casa_servicos devolve ao modelo, a partir da casa_config. */
+export function casaParaModelo(cfg: Json): Json {
+  const visivel = cfg?.visivel === true;
+  if (!visivel) {
+    return { disponivel: false, nota: 'A Casa e Manutenção ainda não está disponível. Diz isso numa frase; não ofereças Favor para o trabalho.' };
+  }
+  const oficios = new Map<string, string>();
+  const desligados: string[] = [];
+  for (const o of (Array.isArray(cfg?.oficios) ? cfg.oficios : [])) {
+    oficios.set(String(o?.codigo), String(o?.nome ?? o?.codigo));
+    if (o?.ativo === false) desligados.push(String(o?.nome ?? o?.codigo));
+  }
+  const servicos = (Array.isArray(cfg?.servicos) ? cfg.servicos : []).map((s: Json) => ({
+    servico: String(s?.nome ?? ''),
+    area: oficios.get(String(s?.oficio)) ?? String(s?.oficio ?? ''),
+    preco: precoCasa(s),
+    ...(s?.descricao ? { descricao: String(s.descricao).slice(0, 160) } : {}),
+  }));
+  const garantia = Number.isFinite(Number(cfg?.garantia_dias)) ? Number(cfg.garantia_dias) : 7;
+  const cancelar = Number.isFinite(Number(cfg?.cancel_free_hours)) ? Number(cfg.cancel_free_hours) : 12;
+  return {
+    disponivel: true,
+    servicos,
+    // 11/11/2026: a casa_config só traz serviços de ofícios ligados; os desligados (ex.: Pintura, Eletricidade,
+    // fase 2 com certificado) dizem-se como "ainda não disponível", nunca se metem noutro serviço.
+    ainda_nao_disponivel: desligados,
+    regras: {
+      material: 'O profissional leva as ferramentas; o material (o móvel, a torneira, a tinta, os parafusos especiais...) é do cliente e tem de estar em casa no dia.',
+      garantia: `Garantia de ${garantia} dias: se algo ficar mal, o profissional volta sem custo.`,
+      cancelamento: `Cancelar é grátis até ${cancelar} horas antes.`,
+      marcar: 'Marca-se na app, em Casa e Manutenção: escolhe o serviço, o dia e a hora. O botão para abrir aparece por baixo da tua resposta.',
+    },
+    instrucao: 'Escolhe o serviço que bate com o pedido e diz o preço tal como está aqui (uma frase), a regra do material numa frase curta, e que pode marcar no botão. Garantia e cancelamento: diz se ajudar ou se perguntarem. Trabalhos "por orçamento": diz que se pede orçamento com fotos e os profissionais respondem com o preço. Se o trabalho é de uma área em ainda_nao_disponivel (ex.: pintura), diz com simpatia que essa área ainda não está disponível na Casa e Manutenção e não o metas noutro serviço. Nunca perguntes quantas pessoas, nem ofereças um Favor para ir buscar material.',
+  };
+}
+
+/** A ligação que abre a Casa e Manutenção (deixa abrir_faixa → categoria casa; funciona nas apps já publicadas). */
+export function deixaCasa(hoje: string): { chave: string; tipo: string; texto: string; acao: Json } {
+  return {
+    chave: `casa:${hoje}`,
+    tipo: 'casa',
+    texto: 'Abrir a Casa e Manutenção para marcar',
+    acao: { tipo: 'abrir_faixa', destino: JSON.stringify({ tipo_destino: 'categoria', destino: 'casa' }) },
+  };
+}
+
+// Frases de reserva de mesa que não podem aparecer fora das reservas.
+const RE_FRASE_MESA = /\b(para )?quantas pessoas\b|\bmesa para quantos\b|\bquantos (s[aã]o|v[aã]o ser)\b/i;
+
+/** A resposta tem uma pergunta de reserva de mesa (fora de uma reserva de mesa)? */
+export function temFraseDeMesa(texto: string): boolean {
+  return RE_FRASE_MESA.test(String(texto ?? ''));
+}
+
+/** Tira as frases de reserva de mesa de uma resposta sobre a Casa (fica o resto, igual). */
+export function semFraseDeMesa(texto: string): string {
+  const t = String(texto ?? '');
+  if (!temFraseDeMesa(t)) return t;
+  const frases = t.match(/[^.?!]+[.?!]*\s*/g) ?? [t];
+  const fica = frases.filter((f) => !temFraseDeMesa(f)).join('').trim();
+  return fica || t;
+}
diff --git a/supabase/functions/client-assistant/casa_test.ts b/supabase/functions/client-assistant/casa_test.ts
new file mode 100644
index 00000000..4cb16c6f
--- /dev/null
+++ b/supabase/functions/client-assistant/casa_test.ts
@@ -0,0 +1,92 @@
+// Testes da Casa e Manutenção no Amigo (11/11/2026, missão amigo-casa-2026-11-11).
+import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
+import { casaParaModelo, deixaCasa, eTrabalhoDeCasa, precoCasa, semFraseDeMesa, temFraseDeMesa } from './casa.ts';
+
+// Forma da casa_config no ar (11/11/2026), cortada a 4 serviços.
+const CFG = {
+  visivel: true,
+  garantia_dias: 7,
+  cancel_free_hours: 12,
+  oficios: [
+    { codigo: 'montagem', nome: 'Montagem de móveis' },
+    { codigo: 'fixacao', nome: 'Pendurar e fixar' },
+    { codigo: 'canalizacao', nome: 'Canalização' },
+    { codigo: 'pintura', nome: 'Pintura' },
+  ],
+  servicos: [
+    { oficio: 'montagem', nome: 'Montar roupeiro', modo: 'fixo', preco_cents: 8000, unidade: 'movel' },
+    { oficio: 'fixacao', nome: 'Pendurar televisão', modo: 'fixo', preco_cents: 4500, unidade: 'tarefa' },
+    { oficio: 'canalizacao', nome: 'Trocar torneira', modo: 'fixo', preco_cents: 4000, unidade: 'tarefa' },
+    { oficio: 'canalizacao', nome: 'Autoclismo ou sifão', modo: 'hora', preco_cents: 2000, unidade: 'hora' },
+    { oficio: 'pintura', nome: 'Pintura', modo: 'orcamento', preco_cents: null, unidade: 'tarefa' },
+  ],
+};
+
+Deno.test('trabalhos de casa são reconhecidos', () => {
+  for (const m of [
+    'preciso de montar um roupeiro', 'quanto custa pendurar uma televisão?', 'quero pintar a sala',
+    'tenho a torneira a pingar', 'o autoclismo não para', 'preciso de alguém para cortar a relva',
+    'montar uma cama do IKEA', 'quero pôr a tv na parede',
+  ]) assert(eTrabalhoDeCasa(m), m);
+});
+
+Deno.test('compras e conversa não são trabalhos de casa', () => {
+  for (const m of [
+    'quero açaí', 'quero um cheeseburger', 'leite, pão e ovos', 'que restaurantes estão abertos?',
+    'reservar mesa para 4 no sábado', 'quero uma lâmpada LED', 'olá, tudo bem?',
+  ]) assert(!eTrabalhoDeCasa(m), m);
+});
+
+Deno.test('preços saem da tabela: fixo, por móvel, à hora e orçamento', () => {
+  assertEquals(precoCasa(CFG.servicos[0]), '80,00 € por móvel');
+  assertEquals(precoCasa(CFG.servicos[1]), '45,00 €');
+  assertEquals(precoCasa(CFG.servicos[2]), '40,00 €');
+  assertEquals(precoCasa(CFG.servicos[3]), '20,00 € por hora');
+  assertStringIncludes(precoCasa(CFG.servicos[4]), 'orçamento');
+  assertStringIncludes(precoCasa(CFG.servicos[4]), 'fotos');
+});
+
+Deno.test('o modelo recebe serviços, material, garantia e cancelamento das definições', () => {
+  const r = casaParaModelo({ ...CFG, garantia_dias: 9, cancel_free_hours: 24 });
+  assertEquals(r.disponivel, true);
+  assertEquals(r.servicos.length, 5);
+  assertEquals(r.servicos[0].servico, 'Montar roupeiro');
+  assertEquals(r.servicos[0].area, 'Montagem de móveis');
+  assertStringIncludes(r.regras.material, 'ferramentas');
+  assertStringIncludes(r.regras.material, 'material');
+  assertStringIncludes(r.regras.garantia, '9 dias');
+  assertStringIncludes(r.regras.cancelamento, '24 horas');
+  assertStringIncludes(r.instrucao, 'quantas pessoas');
+});
+
+Deno.test('ofícios desligados (ex.: Pintura, fase 2) vão em ainda_nao_disponivel', () => {
+  const cfg = {
+    ...CFG,
+    oficios: [...CFG.oficios.filter((o) => o.codigo !== 'pintura'), { codigo: 'pintura', nome: 'Pintura', ativo: false }],
+    servicos: CFG.servicos.filter((s) => s.oficio !== 'pintura'),
+  };
+  const r = casaParaModelo(cfg);
+  assertEquals(r.ainda_nao_disponivel, ['Pintura']);
+  assert(!r.servicos.some((s: { servico: string }) => s.servico === 'Pintura'));
+  assertStringIncludes(r.instrucao, 'ainda_nao_disponivel');
+});
+
+Deno.test('Casa desligada: o modelo diz que não está disponível, sem lista', () => {
+  const r = casaParaModelo({ ...CFG, visivel: false });
+  assertEquals(r.disponivel, false);
+  assertEquals(r.servicos, undefined);
+});
+
+Deno.test('a ligação abre a categoria casa pelo caminho das faixas (apps já publicadas)', () => {
+  const d = deixaCasa('2026-11-11');
+  assertEquals(d.acao.tipo, 'abrir_faixa');
+  assertEquals(JSON.parse(d.acao.destino), { tipo_destino: 'categoria', destino: 'casa' });
+  assertStringIncludes(d.texto, 'Casa e Manutenção');
+});
+
+Deno.test('frases de reserva de mesa saem da resposta da Casa; o resto fica', () => {
+  assert(temFraseDeMesa('Para quantas pessoas é?'));
+  const t = semFraseDeMesa('Montar um roupeiro fica 80,00 €. Para quantas pessoas é? O material é teu.');
+  assertEquals(t, 'Montar um roupeiro fica 80,00 €. O material é teu.');
+  assertEquals(semFraseDeMesa('Fica 45,00 €.'), 'Fica 45,00 €.');
+});
diff --git a/supabase/functions/client-assistant/index.ts b/supabase/functions/client-assistant/index.ts
index 81d4ebcd..05ad44ee 100644
--- a/supabase/functions/client-assistant/index.ts
+++ b/supabase/functions/client-assistant/index.ts
@@ -118,6 +118,8 @@ import {
 // 11/11/2026 (ordem do Danilo 10:54): fala mais humana — sem reapresentar, sem o nome a abrir, parabéns uma
 // vez, uma sugestão só, e o histórico das últimas mensagens da conversa.
 import { afinarFala, podeOutroCarrinho, textosDoAssistente, ultimasMensagens } from './estilo.ts';
+// 11/11/2026 (amigo-casa, "Conserta o amigo"): Casa e Manutenção com os preços da tabela e a ligação que a abre.
+import { casaParaModelo, deixaCasa, eTrabalhoDeCasa, semFraseDeMesa } from './casa.ts';
 
 const corsHeaders = {
   'Access-Control-Allow-Origin': '*',
@@ -447,6 +449,12 @@ function buildFunctionDeclarations() {
       description: 'Diz se uma loja está aberta agora e a que horas abre/fecha.',
       parameters: { type: 'object', properties: { restaurant_id: { type: 'string' } }, required: ['restaurant_id'] },
     },
+    {
+      // 11/11/2026 (amigo-casa): os preços da Casa e Manutenção vêm daqui, nunca de cor.
+      name: 'casa_servicos',
+      description: 'Casa e Manutenção da Bora: profissionais que vão a casa montar móveis (roupeiro, cama), pendurar televisão, quadros e prateleiras, trocar torneiras, autoclismos, candeeiros, eletricidade, gás, pintura, pladur, jardinagem e pequenas mudanças. Devolve TODOS os serviços com o preço real (fixo, à hora ou por orçamento com fotos), a regra do material, a garantia e o cancelamento. Chama SEMPRE que o cliente fala de um trabalho em casa, antes de responder.',
+      parameters: { type: 'object', properties: {} },
+    },
     {
       // v12 (11/11/2026): "que restaurantes estão abertos?" deixou de ter "não tenho a lista".
       name: 'lojas_abertas',
@@ -557,7 +565,7 @@ function buildSystemFixo(personalidade = false, pesquisa = false): string {
     // m11 / adendo 1-B (09/11/2026): com a personalidade ligada o Amigo é amigo para tudo, nunca "de compras".
     personalidade
       ? IDENTIDADE_AMIGO
-      : 'És o Bora Assistente, o assistente de compras da Bora App (entregas de restaurantes, supermercados, lojas e farmácias; Favores; Limpeza; Reservas de mesa; Serviços) na Guarda, Portugal.',
+      : 'És o Bora Assistente, o assistente de compras da Bora App (entregas de restaurantes, supermercados, lojas e farmácias; Favores; Limpeza; Casa e Manutenção; Reservas de mesa; Serviços) na Guarda, Portugal.',
     'Língua: português de Portugal, tom simpático e direto. Respostas CURTAS (1-3 frases): os cartões com lojas, artigos e totais aparecem sozinhos por baixo do teu texto — não repitas listas inteiras nem tabelas. O cliente pode escrever em português do Brasil, com erros ou por voz: percebe a intenção.',
     '',
     // 11/11/2026 (ordem do Danilo, 10:54): mais humano e mais esperto.
@@ -588,6 +596,7 @@ function buildSystemFixo(personalidade = false, pesquisa = false): string {
     '9b. Comparação com outras apps (Glovo, Uber Eats, iFood, Bolt Food): quando o cliente manda prints do carrinho de outra app ou pede "compara com a Glovo", o sistema já lê os artigos, corre basket_quote e calcula a diferença — o cartão de comparação aparece sozinho. Tu só comentas em 1-2 frases com os números que a ferramenta deu (nunca calcules nada). Se a outra app ficar mais barata, diz a verdade e sugere a loja mais barata do Bora na mesma. Se o cliente ESCREVEU os artigos e os preços da outra app, chama comparar_outra_app. Se só disse "compara com a Glovo" sem print nem preços, pede-lhe o print do carrinho. NUNCA dizes um preço da outra app que o cliente não deu.',
     '9c. Quando o cliente te corrige ou percebes que erraste → learn_lesson com a regra certa (curta, sem dinheiro) e continua a ajudar.',
     '9d. "Que restaurantes / lojas / farmácias estão abertos?", "o que há aberto agora?" → lojas_abertas (horário real de agora, parceiros primeiro). Responde com 3 a 5 nomes, parceiros primeiro, e a hora a que fecham; a morada e o link do mapa (vêm da ferramenta) quando a pessoa pergunta onde fica. NUNCA digas que não tens a lista.',
+    '9e. CASA E MANUTENÇÃO (montar móveis, pendurar televisão ou quadros, torneiras, autoclismos, candeeiros, eletricidade, gás, pintura, pladur, jardim, pequenas mudanças) → chama casa_servicos ANTES de responder e diz o preço do serviço que bate, tal como vem (ex.: "Montar um roupeiro fica 80,00 €"); à hora diz "20,00 € por hora"; os de orçamento pedem-se com fotos e os profissionais respondem com o preço; uma área em ainda_nao_disponivel (ex.: pintura) diz-se que ainda não está disponível, sem a meter noutro serviço. Diz numa frase curta que o profissional leva as ferramentas e o material é do cliente. Garantia e cancelamento grátis: com os números da ferramenta. A ligação para abrir a Casa e Manutenção aparece sozinha por baixo da tua resposta: diz só que pode marcar aí. NUNCA perguntas "quantas pessoas" nem nada de reservas de mesa (isso é só para reservar mesa num restaurante) e NUNCA ofereces um Favor para ir buscar material ou fazer o trabalho.',
     pesquisa
       ? '10. Fora do âmbito (trabalhos de casa, outras apps) → responde numa frase simpática que só tratas da Bora e volta ao assunto com uma sugestão. O tempo, a agenda e os eventos da Guarda, notícias e a farmácia de serviço NÃO estão fora: regra 20.'
       : '10. Fora do âmbito (futebol, notícias, trabalhos de casa, outras apps) → responde numa frase simpática que só tratas da Bora e volta ao assunto com uma sugestão.',
@@ -1013,6 +1022,9 @@ Deno.serve(async (req: Request) => {
   let favores: Json[] = [];
   let favorPreco: Json = null;
   const acoes: Json[] = [];
+  // 11/11/2026 (amigo-casa): a Casa está visível (casa_config.visivel)? null = ainda não se perguntou.
+  let casaVisivel: boolean | null = null;
+  const pedeCasa = eTrabalhoDeCasa(userMessage);
   let gapLogged = false;
   // v11: ferramentas corridas nesta volta (decidem se há deixa e se a compra acabou numa ação).
   const ferramentasUsadas = new Set<string>();
@@ -1208,6 +1220,13 @@ Deno.serve(async (req: Request) => {
           if (error) return { ok: false, error: error.message };
           return { ok: true, data: { loja: r?.name ?? rid, aberta_agora: open?.is_open, abre_as: open?.opens_at, fecha_em_minutos: open?.closes_in_minutes, horario: r?.business_hours ?? null } };
         }
+        case 'casa_servicos': {
+          // 11/11/2026 (amigo-casa): a mesma RPC que a app usa (casa_config: casa_servicos + definições).
+          const { data, error } = await adminClient.rpc('casa_config');
+          if (error) return { ok: false, error: error.message };
+          casaVisivel = data?.visivel === true;
+          return { ok: true, data: casaParaModelo(data) };
+        }
         case 'lojas_abertas': {
           // v12 (11/11/2026): quem está aberto AGORA (is_partner_open de cada loja visível, hora de Lisboa),
           // parceiros primeiro, com morada e link do Google Maps.
@@ -1469,7 +1488,9 @@ Deno.serve(async (req: Request) => {
   // não como mensagem do cliente; e a resposta anterior fica guardada para o caso de a nova falar "do cliente".
   let notaSistema = '';
   let textoAntesDaNota = '';
+  // 11/11/2026 (amigo-casa): um trabalho em casa acaba na ligação da Casa (posta no fecho), não num Favor.
   const precisaDeAcao = (): boolean => s.personality && !hasImage && pedeAcao(userMessage) &&
+    !pedeCasa && !ferramentasUsadas.has('casa_servicos') &&
     propostas.length === 0 && favores.length === 0 && !comparacao &&
     !acoes.some((a) => ACOES_DE_COMPRA.has(a.tipo)) && ![...ferramentasUsadas].some((n) => FERRAMENTAS_AJUDA.has(n));
   // Texto que o modelo escreve no MESMO turno em que chama só ferramentas "leves" (botão, memória,
@@ -1790,11 +1811,37 @@ Deno.serve(async (req: Request) => {
   }
   if (handoff && !acoes.some((a) => a.tipo === 'suporte_humano')) acoes.push({ tipo: 'suporte_humano', rotulo: 'Falar com o suporte', destino: null });
 
+  // ── 11/11/2026 (amigo-casa): trabalho em casa → sem frases de reserva de mesa, sem Favor para o material
+  // (só se a pessoa falou de Favor) e a ligação que abre a Casa e Manutenção. Vai como DEIXA abrir_faixa
+  // (categoria casa) porque as apps já publicadas a abrem sem versão nova. ──
+  let deixaDaCasa: Json = null;
+  const turnoDaCasa = ferramentasUsadas.has('casa_servicos') || pedeCasa;
+  if (turnoDaCasa && !geminiError && !handoff && !hasImage && propostas.length === 0 && !comparacao) {
+    if (casaVisivel === null) {
+      const { data: cfg } = await adminClient.rpc('casa_config');
+      casaVisivel = cfg?.visivel === true;
+    }
+    finalText = semFraseDeMesa(finalText);
+    if (!/\bfavor/i.test(userMessage)) {
+      for (let i = acoes.length - 1; i >= 0; i--) {
+        if (acoes[i].tipo === 'pedir_favor' || acoes[i].tipo === 'abrir_favores') acoes.splice(i, 1);
+      }
+    }
+    if (casaVisivel) {
+      const d = deixaCasa(new Date().toISOString().slice(0, 10));
+      const { data: lin, error: ie } = await adminClient.from('assistant_deixas').insert({
+        user_id: userId, conversation_id: conversationId, chave: d.chave, tipo: d.tipo, texto: d.texto, acao: d.acao,
+      }).select('id').single();
+      if (ie) console.warn('[AMIGO] deixa da casa:', ie.message);
+      else if (lin?.id) deixaDaCasa = { id: lin.id, tipo: d.tipo, texto: d.texto, acao: d.acao };
+    }
+  }
+
   // ── v11: a DEIXA — uma linha útil no fim de uma conversa livre (nunca em compras, comparações,
   // fotos, ajuda/suporte ou erro). Escolhida e escrita aqui com dados do banco; rotação de 24 h por
   // cliente (assistant_deixas). Sem a tabela (migração por aplicar) não há deixa. ──
-  let deixa: Json = null;
-  if (s.personality && s.deixaOn && !hasImage && !handoff && !geminiError && propostas.length === 0 && !divisao &&
+  let deixa: Json = deixaDaCasa;
+  if (!deixa && s.personality && s.deixaOn && !hasImage && !handoff && !geminiError && propostas.length === 0 && !divisao &&
       favores.length === 0 && !comparacao && !listaExtraida && !pedeAcao(userMessage) &&
       ![...ferramentasUsadas].some((n) => FERRAMENTAS_AJUDA.has(n))) {
     try {

