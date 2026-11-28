# Glovo, vista de fora — 26/10/2026, 05:45–06:15 (Lisboa)

Missão `paridade-rea-2026-10-26`. Chrome da missão com perfil novo e vazio (`_rea_perfil_paridade`),
sem login e sem conta. Morada: Praça Luís de Camões, Guarda (praça pública). Cookies: "Rejeitar".
Àquela hora as lojas estavam fechadas, por isso não há tempos de entrega reais. O que se vê é como a
Glovo trata uma loja fechada, e isso também conta como resultado.
Prints em `Desktop\Bora\paridade-rea-2026-10-26\glovo_*.png` (fora do repo). Observação passiva do
REA em `...\rea\glovo_05_inicio_inspect.json`: só a árvore de acessibilidade; valores de armazenamento
e cookies redigidos pelo próprio REA ("values_redacted": true), sem código de scripts.

## a) Início
- Sem morada: grande caixa "Qual é a tua morada?" + "Usar localização atual" (glovo_01). Por baixo,
  categorias (Envios, Comida, Farmácia e Beleza, Supermercados, Lojas, uma loja de conveniência em
  destaque) e "categorias mais populares" da cidade.
- A morada abre uma janela com sugestões. Depois de escolher, pergunta **que tipo de local é**
  (Casa, Apartamento, Escritório, Outro → Hospital, Escola, Personalizado) e mostra um mapa para
  afinar o ponto antes de confirmar (glovo_02 a 04).
- Pesquisa no topo: "De que precisas?" (glovo_23/24). O resultado são **lojas**, não pratos. Há
  separadores Tudo / Restaurantes / Mercearias / Lojas / Saúde. Cada loja traz a hora de agendar e a
  % de avaliações positivas. Nos mercados aparece o selo "Mesmos preços que na loja".
- Cartões de loja (glovo_06): foto grande, nome, estado ("Fechado", "Agendar para: 11:30",
  "Fechado até às 18:45"), % de gostos com o nº de avaliações, selo de promoção ("-40% em alguns
  artigos", "2x1 em alguns artigos"), selo "NOVO" e ícone de coroa (lojas Prime).

## b) Listas
- Comida: faixa de cozinhas com ícone (Promoções, Hambúrgueres, Sanduíches … Brasileira).
- Filtros: **Promoções** e **Tipo de comida**. **Ordenar por**: Recomendado, Perto de mim,
  Avaliações, Taxa de entrega (glovo_07). Atalho "Melhor avaliados".
- As lojas fechadas continuam na lista, todas com "Agendar para: <hora>".
- Supermercados: separadores Supermercado / Conveniência; na Guarda há 3 lojas (glovo_18).

## c) Uma loja (Burger King; mercado: Continente)
- Topo (glovo_09): capa, logótipo, selo de promoção, % de gostos, botão **Agendar**, taxa de entrega
  riscada com "GRÁTIS", "Agendar para: 11:00".
- **Loja fechada** (glovo_10): ao abrir, aparece "X está fechado até 11:00 — há estabelecimentos
  semelhantes abertos", com os botões **Ver estabelecimentos abertos** e **Agendar um pedido**.
- Botão (i) **Dados do estabelecimento** (glovo_11): morada e horário de cada dia da semana.
- Menu lateral com secções; no topo vêm **Promoções**, **Mais vendidos** e **Novidades**. Os
  produtos com desconto mostram o preço riscado.
- Nota legal fixa no cesto: "Os preços rasurados mostram o preço mais baixo dos 15 dias anteriores à
  redução" (glovo_14). Há também a ligação "Informações sobre as taxas".
- No mercado (glovo_19/20): árvore de categorias muito grande que se abre e fecha, "Mais vendidos"
  com "Mostrar tudo" e um "+" direto em cada produto.

## d) Um produto
- Janela com foto, nome, descrição, grupos **Obrigatório** ("Escolhe 1 artigo") com botões de
  escolha, quantidade −/+ e o botão "Adicionar 1 por 12,80 €" (glovo_12/13).
- Não vi campo de observação no produto. Não se viram alergénios nesta janela; podem estar mais
  abaixo, ou só depois de entrar na conta.

## e) Cesto
- Painel fixo à direita (glovo_14): "O teu pedido · N produtos", cada linha com as escolhas
  ("Cbk, Aros De Cebola X7"), **Editar**, −/1/+ (com 1, o "−" passa a caixote), o total no botão
  "Ir para o check-out · 12,80 €" e "Informações sobre as taxas".
- 1→2→1→0 (glovo_15/16): o total muda logo e, com 0, o cesto fica vazio.
- **Trocar de loja: não há aviso, porque há um cesto por loja.** Com o cesto do Burger King cheio,
  pôr água do Continente criou outro cesto. Ao voltar ao Burger King, o artigo continuava lá
  (glovo_20/21).
- "Leve também": aparece uma sugestão de bebida ligada ao cesto ("…para dar uma dose extra de
  energia ao teu pedido!").

## f) Finalizar
- "Ir para o check-out" sem conta leva logo ao **login** (glovo_17): telemóvel (com código por SMS
  ou **WhatsApp**), Google, Facebook ou email. **Parei aqui** (regra da missão), por isso não vi os
  meios de pagamento, a gorjeta, o cupão nem o agendamento dentro do checkout.
- Da ajuda pública (glovoapp.com/docs/pt/faq): o código promocional valida-se no perfil antes do
  pedido. No "Qualquer coisa", se o preço na loja diferir **menos de 30%**, a Glovo compra; **acima
  de 30%**, o estafeta liga ao cliente. O preço final vê-se quando o estafeta carrega o talão.

## g) Público: acompanhar, ajuda, parceiros, estafetas
- Glovo Prime (glovo_25, glovoapp.com/pt/pt/guarda/glovo-prime): **4,99 €/mês**, entregas grátis
  ilimitadas em lojas Prime, taxas mais baixas e promoções exclusivas, "poupa 2,20 € por pedido".
- Para parceiros (sell.glovoapp.com/pt/pt/services/pricing, glovo_27):
  - Comissão **30%** com entrega e **15%** na recolha na loja ("pode variar consoante a cidade").
  - Ferramentas vendidas à parte: Promoções, Anúncios (aparecer no topo), On-demand (entregas do
    canal próprio da loja) e Glovo Store (compras para a loja).
- Estafetas (riderhub.glovoapp.com/pt, glovo_28): centro de ajuda, G-Learning (cursos grátis),
  seguro e candidatura.
- Ajuda: FAQ pública e "Contacta-nos" dentro do site.

## O que levar daqui para o Bora (sem copiar marca, textos nem cores)
1. Loja fechada → janela com "ver lojas abertas parecidas" e "agendar".
2. Ficha "Dados da loja" (morada e horário) no topo da loja.
3. Faixas Promoções / Mais vendidos / Novidades no topo do menu.
4. Filtros (promoções, tipo de comida) e ordenar (perto, avaliação, taxa) na lista de restaurantes.
5. Tipo de local e ponto no mapa ao gravar a morada.
6. "Editar" uma linha do cesto (mudar extras) sem a apagar.
7. Um cesto por loja, em vez de apagar o cesto ao trocar.
8. Nota "preço riscado = mais baixo dos últimos 30 dias" (a Glovo escreve 15; a lei PT/UE diz 30,
   a confirmar com a advogada).
