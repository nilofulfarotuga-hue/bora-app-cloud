---
id: memoria-claude-ai-livro-areas-precos-catalogo-nao-parceiro
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regras que o Danilo fixou para o preço base dos produtos de lojas não-parceiras do [[bora-app]] (robot do talão + qual a fonte de preço válida)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-precos-catalogo-nao-parceiro`, origem `claude-ai`, atualizada em 2026-10-23T22:13:56.674853+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas precos catalogo nao parceiro · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/precos-catalogo-nao-parceiro.md), copiada a 2026-10-23 23:13 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: precos-catalogo-nao-parceiro
description: Regras que o Danilo fixou para o preço base dos produtos de lojas não-parceiras do [[bora-app]] (robot do talão + qual a fonte de preço válida)
sources: [chat]
aliases: [preço de balcão, robot do talão, correção de preço, catalog_price_updates, preço não-parceiro]
---

- [stated] 05/09: autorizou ("vai") a regra do robot que corrige preços a partir do talão — talão MAIS CARO que o nosso preço, corrige sozinho; talão MAIS BARATO, nunca aplica, fica pendente à espera da decisão dele
- [stated] O preço base de produto de loja não-parceira tem de ser o preço de BALCÃO (ir lá e comprar / levantar no restaurante), NÃO o preço de entrega das plataformas; mandou ir a fundo e comparar todas as fontes possíveis antes de mexer em preços
- [stated] 05/09: mandou pôr TODOS os produtos cujo preço final ficasse acima da Glovo a 20 cêntimos ABAIXO da Glovo (regra comercial: nunca ficar mais caro que a Glovo na prateleira)
- [stated] Não quer vender abaixo do custo: onde a Glovo vende ao preço ou abaixo do que ele paga ao balcão, prefere ficar no custo (sem ganho, sem perda) a bater a Glovo com prejuízo
- [stated] 08/09, decisão dele: taxa de serviço fixa de 0,99 € para TUDO o que é não-parceiro (mercados, lojas, farmácia e restaurantes sem contrato), em vez dos 2,50 € de antes, MAIS 6% no preço de todos os produtos não-parceiros. Só a taxa de 2,50 € é substituída — os 15% de margem sobre o balcão FICAM e os 6% entram por cima (total 21% sobre o balcão); ele confirmou isto no mesmo dia ("tem que estar do jeito que estava, 15 mais 6 dá 21") e não é bug
- [stated] 08/09, DECISÃO FINAL que substitui os 6%: margem passa a 15% + 3% = 18% sobre o balcão ("é isso que vai ficar"), mantendo a taxa de 0,99 €. Motivo dado por ele: com 21% ficava mais caro que a Glovo em quase tudo; com 18% fica abaixo dela na maioria. Aplicado a todas as lojas não-parceiras
- [stated] 08/09: mandou que no CONTINENTE (só nessa loja) todo o produto cujo preço final ficasse acima da Glovo passe a ficar IGUAL à Glovo — "tem que ficar igual", nem acima nem abaixo. Afina a regra de 05/09 dos 20 cêntimos abaixo; o piso no custo de balcão continua a valer
- [stated] Escolheu esta combinação sabendo que no pedido mínimo (12 €) fica a perder ~47 cêntimos e que só empata a partir de ~20 € de carrinho — aceita a perda nos pedidos pequenos como desconto de lançamento para atrair cliente novo
- [stated] 09/09: mandou subir a taxa mínima de 12 € para 15 € — pedido de mercado/restaurante abaixo de 15 € de compras paga a taxa de pedido pequeno (1,39 €). Substitui o pedido mínimo de 12 € referido acima
- [stated] 14/09: mandou fazer vistoria geral aos preços de TODOS os mercados/lojas não-parceiras no Supabase, depois de um pedido da Wells ter saído com margem zero — "tem que ter a matemática certa, é dinheiro, tem que ser no mínimo detalhe" e "pra não se repetir isso". Prompt de correção entregue em ficheiro (prompt-vistoria-precos-14-09.md), por rodar em sessão nova do Claude Code no projeto bora-app-cloud
- [stated] 14/09: LIDL e MERCADONA estão FORA — não trabalha com eles, estão desligados e não aparecem a cliente nenhum ("já está fora"). Não contar com essas duas lojas em análises, vistorias ou trabalho de catálogo; as lojas não-parceiras vivas são Continente, Auchan, Intermarché, Pingo Doce, Wells, Leroy Merlin, Kiwoko, Zippy, Worten e as cadeias de comida
- [stated] 28/09, regra para cobrar o CLIENTE num pedido não-parceiro depois do talão: produto que no talão saiu MAIS BARATO que na app fica ao preço da app; produto que saiu MAIS CARO (incluindo substituições) passa a preço do talão + a margem dele (15% + a regra toda), nunca ao preço seco do balcão. Irritou-se quando o valor a cobrar foi baixado em vez de subido
- [stated] 04/10: preço de balcão só se tira dos canais do PRÓPRIO restaurante (Facebook, Instagram, site, cartaz/talão); o Vamos Já NÃO é preço de balcão nem serve de comparação, tal como Glovo/Uber
- [stated] 05/10: o cliente paga o preço que vê na app — se a compra real sair mais barata, a diferença fica com a Bora (NÃO se devolve excedente da pré-autorização ao cliente; "já assumi isso"); se sair mais cara, ele fica com o prejuízo e o sistema corrige o preço para não voltar a acontecer
- [stated] 05/10: no catálogo de loja não-parceira guarda-se SÓ o preço normal de balcão (ex.: 9,90) — o sistema soma a margem sozinho; nunca pré-somar os 15% no preço guardado (ficava cobrado duas vezes, 9,90 aparecia 13,09 em vez de ~11,39). Mandou verificar todas as lojas novas por esta regra
FINAL WRITE
- [stated] 11/10/2026: disse que hoje cobra 15% sobre o produto não-parceiro (+ 0,99 € de serviço + 2,50 € de entrega); quer pôr taxa de entrega e de serviço GRÁTIS nos mercados (embutindo no preço) para concorrer com Glovo/Uber e divulgar os mercados, sem ter prejuízo — ainda a decidir a combinação (percentagem, taxa mínima, valor mínimo)
- [stated] 23/10/2026: decidiu igualar os preços de McDonald's, Burger King e Continente ao Glovo da Guarda — SÓ SUBIR o que estiver abaixo, nunca baixar nenhum preço; autorizou entrega grátis (McDonald's a partir de 20 €, Continente e Burger King a partir de 30 €; abaixo disso entrega normal e sem taxa de pedido pequeno), taxa de serviço 0,99 € mantém-se; Auchan, Intermarché e Pingo Doce ficam como estão
