# Jyosmi Sushi: catálogo da app igual ao site da loja (08/11/2026)

Fonte da verdade: https://strangeroasis.com/encomendas/ (HTML lido a 08/11/2026, 116 artigos com código, uma só loja). Base: Supabase `ojykpzwqrtusfeakzrna`, loja `jyosmi-sushi-guarda` (não-parceira, encomenda por telefone, 75 produtos hoje). Nada foi escrito na base: só SELECT e EXPLAIN. O SQL para aplicar está em `supabase/dados/jyosmi_igual_ao_site_2026_11_08.sql` (só INSERT/UPDATE, com cópia de segurança no primeiro bloco).

## Resumo

Fiz isto: comparei os 116 artigos do site com os 75 da app, um a um (nome, preço de balcão, tamanhos, foto, +18, disponível), e preparei o SQL. Os preços que a app já tinha estão todos certos ao cêntimo (0 diferenças em 74 produtos). Os tamanhos dos combinados também já estavam certos desde 31/10. Faltavam: os tamanhos das entradas, 42 artigos do site (cervejas, vinhos, destilados, cafés e o Guaraná Antarctica), 3 nomes, 7 fotos, a regra da bebida grátis presa à Média/Grande, a ordem do menu e o tempo de preparação.

Contas: entram 42 produtos, sai 1 (San Pellegrino fica indisponível, não está no site), mudam 33 produtos (nome, foto, tamanhos ou opções). Os 74 que ficam mudam também a ordem no menu. Na loja, o tempo de preparação passa de 20 para 45 minutos.

## Como a app guarda isto (lido no código do `wt-m6-2026-11-08` e na base)

- **Preço**: `products.price` é o preço de BALCÃO. A app soma a margem de não-parceiro em tempo real (`PricingService.applyMarkup`, `_nonPartnerMarkupRate = 0.15`). O servidor (`order_line_options_extras`) soma o `price_add` das opções ao preço base antes da margem, casando pelo nome do grupo e pelo nome da opção. Página do livro `livro-areas-precos-catalogo-nao-parceiro`: guardar só o balcão, nunca pré-somar.
- **Tamanhos e extras**: `product_option_groups` + `product_option_items`. Um grupo obrigatório (`is_required` e `min_choices >= 1`) faz o "+" do cartão abrir a ficha do produto. É assim que os 12 combinados já têm "Tamanho" (Pequena/Média/Grande). Não foi preciso estrutura nova nem produtos separados por tamanho.
- **+18**: `products.age_restricted`. O gatilho `fn_products_maior_18_novo` só liga (nunca desliga) com o classificador `produto_e_maior_18`. No SQL vai explícito.
- **Tempo de preparação**: `restaurants.phone_prep_minutes` (o gatilho dos pedidos por telefone copia-o para `orders.prep_time_minutes`, o "fica pronta em X min" do cliente) e `restaurants.takeaway_default_prep_minutes` (levantar no restaurante). Os dois estavam em 20. A janela "X-Y min" do cabeçalho da loja NÃO vem da base: é `OrderEtaService.deliveryWindowMinutes` (distância + 8 minutos fixos), por isso o SQL não a muda.
- **Foto**: `products.photo_url` aceita URL externa. As 66 fotos que a app já tem apontam todas para strangeroasis.com. Testei as 86 imagens do site uma a uma: todas respondem 200 com imagem. Ver o problema da versão web nos achados.

## Os 8 pedidos, um a um

1. **Tamanhos nos combinados e entradas.** Combinados: já estavam na base desde 31/10 e batem com o site ao cêntimo (ex.: Combinado Tradicional 12 / 15 / 33 €, Combinado Vegan 10 / 12 / 25 €, Sushi Tradicional 11,50 / 14 / 30 €). O cliente só os vê ao abrir o produto; no cartão aparece o preço da Pequena. Entradas: faltavam. Entram 24 grupos "Tamanho" com Pequena e Média, com as peças quando o site as diz. No site as entradas NÃO têm Grande.
2. **Bebida grátis no Especial JYOSMI (Média e Grande).** Já existia, mas num grupo opcional separado: quem escolhia a Pequena também conseguia pedir a bebida grátis, e numa loja não-parceira quem paga essa bebida ao balcão é a Bora. Agora a bebida escolhe-se dentro do próprio Tamanho: Pequena; Média + Coca-Cola / Pepsi / Ice Tea / Água 500ml; Grande + as mesmas 4. São as 4 bebidas que o site diz. O grupo antigo fica vazio, com o título a explicar (ver o passo opcional mais abaixo).
3. **Fanta Guaraná, Guaraná Antártica e San Pellegrino.** O site tem DOIS artigos: "Fanta-Gurana -33cl" a 2,10 € (já na app, certo) e "Gurana Antartica-33cl" a 2,20 € (faltava, entra como "Guaraná Antarctica 33cl"). San Pellegrino já não está no site (o código BSA15 desapareceu da lista; a foto antiga ainda existe no servidor deles). Fica indisponível na app, não se apaga.
4. **Cerveja, vinho e sangria +18.** Na app não havia nenhuma bebida alcoólica. Entram 37, todas +18: 6 cervejas e sidra, 17 vinhos (incluindo o copo de vinho D. João), 14 destilados (incluindo o saké). Sangria não existe no site nem na app.
5. **Nomes iguais ao site.** Mudam 3: "Caixa Crocante" passa a "Caixa de Sushi Fritos"; "Ravioli Frito (Gyoza)" passa a "Gyoza Frio"; "Soja" passa a "Molho Soja". As outras diferenças são só erros de escrita do site e a app fica com a forma correta: Agua/Água, Gurana/Guaraná, Limon/Limão, Pessego/Pêssego, Ananac/Ananás, Limanada/Limonada, Gingiber/Gengibre, "Sweet chili" e "Teriyaki" (a app diz "Molho Sweet Chili" e "Molho Teriyaki"), "Cola Zero" (a app diz "Coca-Cola Zero"), "vanilla" (a app diz "baunilha"), "Arroz chau-chau" (só maiúsculas).
6. **Tempo de preparação 30-45 min.** A base só guarda um número por campo. Fica 45, o máximo do intervalo, para a app nunca prometer antes do que a loja cumpre (`phone_prep_minutes` e `takeaway_default_prep_minutes`, 20 para 45).
7. **Preços de balcão como no site.** Os 74 produtos que existem nos dois lados têm o preço igual ao cêntimo. Os tamanhos dos combinados também. Os 42 novos entram com o preço do site. As entradas ganham a Média com a diferença exata do site.
8. **Fotos reais do site.** Entram 7 que faltavam: Hossomaki Mix e os 6 molhos (Agridoce, Teriyaki, Sweet Chili, Soja, Wasabi, Gengibre). Ficam sem foto 7 produtos que o próprio site mostra só com o logótipo (Mochicream Manga, Mochicream Pistachio, Gelado Panado, Frutas Mistas, Pauzinhos, Sumo de Laranja Fresco, Limonada), e os 14 destilados novos pelo mesmo motivo (ficam `needs_photo = true`). Os 28 artigos novos com foto usam a do site.

## Lista do que muda

- **Entram 42 produtos**: Guaraná Antarctica 33cl; Cervejas e sidras (6); Vinhos (17); Destilados (14); Bebidas quentes (Café, Descafeinado, Chá Verde, Chá de Jasmim). Ids `jyosmi-<código do site>` (ex.: `jyosmi-bce01`).
- **Sai 1**: `jyosmi-bsa15` San Pellegrino fica `is_available = false` com o motivo escrito em `removal_reason`.
- **Mudam 33 produtos**: 3 nomes (TS04, TA07, E04); 7 fotos (TS05A, E01, E02, E03, E04, E05, E06); 24 entradas com tamanhos novos (TA03 a TA22, sem TA01 e TA02, que no site não têm tamanhos); Especial JYOSMI com a bebida presa ao tamanho. TA07 e E04 aparecem em duas listas e só contam uma vez.
- **Ordem do menu**: `sort_order` = posição no site (Entradas, Combinados, Poke, Bebidas, Cervejas, Vinhos, Destilados, Bebidas quentes, Sobremesas, Extras). Hoje todas as categorias começam em 1 e desempata o id, por isso as Bebidas aparecem primeiro.
- **Loja**: `phone_prep_minutes` e `takeaway_default_prep_minutes` de 20 para 45.
- **Cópias de segurança** (bloco 0): `bkp_jyosmi_products_20261108` (75 linhas), `bkp_jyosmi_opcoes_20261108` (41 linhas) e `bkp_jyosmi_restaurante_20261108` (1 linha), todas com RLS ligado. Nenhuma existe hoje.

## Prova para depois de aplicar

O último SELECT do ficheiro devolve estes números. Antes (lido a 08/11): produtos 75, disponíveis 75, +18 0, grupos Tamanho 12, opções no Tamanho do Especial 3, linhas no grupo antigo da bebida 4, prep 20/20. Depois deve dar: 117, 116, 37, 36, 9, 0, 45/45. Os comandos de escrita foram validados com EXPLAIN (sem executar), contra a base real.

## Dúvidas que o site não resolve

1. **"Gyoza Frio"**: no site está assim, mas a descrição diz "dumplings dourados" e o inglês diz "Fried". Parece um erro do site ("Frito"). O SQL segue a ordem do Danilo ("Gyoza Frio"). Se for erro, basta trocar o nome no bloco 1.
2. **Guaraná**: li o pedido como dois artigos, como no site (Fanta Guaraná 2,10 € fica, Guaraná Antarctica 2,20 € entra). Se o Danilo quis dizer um só produto, falta saber qual sai.
3. **San Pellegrino**: tirei porque já não está no site. Pode ser só falta de stock deles; confirmar com a loja se volta.
4. **Sangria**: não existe no site nem na app. Não há nada para marcar.
5. **Super Bock Zero**: marquei +18 porque o pedido diz "cerveja". O classificador da base diria que não (0,0% de álcool). Decidir.
6. **Estafeta chamado cedo demais**: a loja chama o estafeta 15 minutos depois do pedido (`dispatch_delay_minutes = 15`). Com a comida pronta só aos 30-45, o estafeta fica à espera 15 a 30 minutos. Não mexi (não foi pedido); proposta: 25 ou 30.
7. **45 ou outro número**: usei 45 (o máximo). Se preferirem o meio, 40.
8. **Dúvidas pequenas de nome**: "J Walker Double Black - 50 cl" a 5,50 € tratado como dose de 50 ml; os chás dizem "70cl" no site (copiei); "MarquesD'Almedia" ficou "Marquês d'Almeida"; "Famous" ficou "Famous Grouse"; "Sappro Japones" ficou "Sapporo Japonesa".
9. **Café e chá na entrega**: entram porque o site os vende; se não fizer sentido levar café quente ao domicílio, basta pôr indisponível.

## Passo opcional (fora do SQL, porque precisa de DELETE)

Depois do bloco 6, o grupo antigo `jyosmi-ts09-g1` fica sem opções. Na ficha do Especial aparece um cartão vazio "Bebida grátis: escolhe-a no Tamanho, acima · Opcional". Não estraga o pedido, mas fica feio. Para o tirar (só apaga se estiver mesmo vazio):

```sql
delete from public.product_option_groups g
 where g.id = 'jyosmi-ts09-g1'
   and not exists (select 1 from public.product_option_items i where i.group_id = g.id);
```

## Achados pelo caminho (reportados, não corrigidos aqui)

1. **Fotos desta loja na versão web**: o servidor strangeroasis.com não manda `access-control-allow-origin` (testado com e sem Origin) e o domínio não está na lista do proxy de imagens (`lib/utils/image_proxy.dart` e `web/functions/img.js`). Na web, as fotos da Jyosmi (as 66 de hoje e as novas) devem ficar cinzentas; no Android e no iPhone nativos não acontece. Conserto: acrescentar `strangeroasis.com` às duas listas, ou copiar as fotos para o nosso Storage.
2. **Preço das opções na ficha**: a linha da opção mostra o acréscimo seco de balcão (ex.: "+3,00 €" na Média), mas o botão e o total somam a margem de 15% (+3,45 €). Está em `lib/screens/product_detail_screen.dart` (~linha 705, sem `applyMarkup`). O `premio_opcoes_sheet.dart` já faz certo. Não muda o que se cobra, só o que se lê.
3. **Janela "X-Y min" da loja**: é fixa no código (distância + 8 min) para todas as lojas. Para mostrar 30-45 nesta loja é preciso código (por exemplo, usar `phone_prep_minutes` nas lojas por telefone).
4. **Carrinhos abertos na hora da troca**: o servidor casa as opções pelo nome. Um carrinho montado antes, com "Média (18 peças) + bebida grátis", passa a valer +0 € depois do SQL. O risco é pequeno e só dura uns minutos.
5. **Rótulo de destaque solto**: `restaurants.produto_destaque_rotulo = 'Hambúrguer do mês'` com `produto_destaque_id` vazio nesta loja de sushi. Parece um valor por defeito; não aparece enquanto não houver produto escolhido.

## Tabela produto a produto (site contra app)

Preços em euros de balcão. Tamanhos: P = Pequena, M = Média, G = Grande; entre parênteses, as peças. Nos combinados, "tamanhos = site" quer dizer que a app já tem os mesmos tamanhos e acréscimos.

| Código | Site: nome · preço balcão · tamanhos | App hoje: nome · preço balcão · tamanhos | Foto | +18 | Disponível | O que muda |
|---|---|---|---|---|---|---|
| TA01 | Sopa Miso · 3,50 € | Sopa Miso · 3,50 € | igual ao site | não | sim | nada (só ordem do menu) |
| TA02 | Ceviche de Salmão · 10,00 € | Ceviche de Salmão · 10,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| TA03 | Camarão Panado · 9,00 € · P 9,00 (10) / M 10,00 (12) | Camarão Panado · 9,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA04 | Crepe de Camarão · 9,00 € · P 9,00 (10) / M 10,00 (12) | Crepe de Camarão · 9,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA04A | Camarão com Amêndoas · 10,00 € · P 10,00 (10) / M 11,00 (12) | Camarão com Amêndoas · 10,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA05 | Crepe de Legumes · 7,00 € · P 7,00 (7) / M 8,00 (9) | Crepe de Legumes · 7,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA06 | Frango Panado · 7,00 € · P 7,00 / M 8,00 | Frango Panado · 7,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA06A | Mix de Fritos · 9,00 € · P 9,00 (10) / M 11,00 (15) | Mix de Fritos · 9,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA07 | Gyoza Frio · 8,00 € · P 8,00 (8) / M 9,00 (10) | Ravioli Frito (Gyoza) · 8,00 € | igual ao site | não | sim | nome → "Gyoza Frio"; entram tamanhos P/M |
| TA07A | Lula Frita · 9,00 € · P 9,00 (10) / M 10,00 (12) | Lula Frita · 9,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA07B | Queijo Frito · 6,00 € · P 6,00 (6) / M 8,00 (10) | Queijo Frito · 6,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA08 | Algas com Oyster · 8,00 € · P 8,00 / M 10,00 | Algas com Oyster · 8,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA09 | Porco com Oyster · 9,00 € · P 9,00 / M 11,00 | Porco com Oyster · 9,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA10 | Frango Agridoce e Mel · 7,00 € · P 7,00 / M 8,00 | Frango Agridoce e Mel · 7,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA11 | Legumes e Cogumelos · 5,50 € · P 5,50 / M 7,00 | Legumes e Cogumelos · 5,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA12 | Cogumelos Salteados · 6,50 € · P 6,50 / M 7,50 | Cogumelos Salteados · 6,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA13 | Vitela Salteada · 7,50 € · P 7,50 / M 8,50 | Vitela Salteada · 7,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA14 | Camarão Salteado · 8,50 € · P 8,50 / M 9,50 | Camarão Salteado · 8,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA15 | Arroz Branco · 3,50 € · P 3,50 / M 4,50 | Arroz Branco · 3,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA16 | Arroz chau-chau · 4,00 € · P 4,00 / M 5,00 | Arroz Chau-Chau · 4,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA17 | Massa com Legumes · 5,50 € · P 5,50 / M 6,50 | Massa com Legumes · 5,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA18 | Massa Salteada com Frango · 6,50 € · P 6,50 / M 7,50 | Massa Salteada com Frango · 6,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA19 | Massa Salteada com Porco · 7,00 € · P 7,00 / M 8,00 | Massa Salteada com Porco · 7,00 € | igual ao site | não | sim | entram tamanhos P/M |
| TA20 | Massa com Camarão · 7,50 € · P 7,50 / M 8,50 | Massa com Camarão · 7,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA21 | Massa com Vitela · 7,50 € · P 7,50 / M 8,50 | Massa com Vitela · 7,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TA22 | Massa Fina · 5,50 € · P 5,50 / M 6,50 | Massa Fina · 5,50 € | igual ao site | não | sim | entram tamanhos P/M |
| TS00 | Dragon Roll · 10,00 € | Dragon Roll · 10,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| TS01 | Sushi Tradicional · 11,50 € · P 11,50 (12) / M 14,00 (18) / G 30,00 (44) | Sushi Tradicional · 11,50 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS02 | Caixa Premium com Sushi Fritos · 11,00 € · P 11,00 (12) / M 12,50 (18) / G 27,00 (44) | Caixa Premium com Sushi Fritos · 11,00 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS03 | Caixa Premium sem Sushi Fritos · 11,50 € · P 11,50 (12) / M 13,00 (18) / G 28,00 (44) | Caixa Premium sem Sushi Fritos · 11,50 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS04 | Caixa de Sushi Fritos · 11,00 € · P 11,00 (12) / M 13,00 (18) / G 28,00 (44) | Caixa Crocante · 11,00 € · tamanhos = site | igual ao site | não | sim | nome → "Caixa de Sushi Fritos" |
| TS05 | Sushi Braseado · 11,50 € · P 11,50 (12) / M 14,00 (18) / G 30,00 (44) | Sushi Braseado · 11,50 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS05A | Hossomaki Mix · 10,00 € · P 10,00 (20) / M 11,00 (24) | Hossomaki Mix · 10,00 € · tamanhos = site | entra foto do site | não | sim | foto |
| TS06 | Nigiri Misto · 11,50 € · P 11,50 (12) / M 14,00 (18) | Nigiri Misto · 11,50 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS07 | Sashimi Mix · 12,00 € · P 12,00 (12) / M 14,00 (18) | Sashimi Mix · 12,00 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS08 | Temaki · 5,50 € | Temaki · 5,50 € | igual ao site | não | sim | nada (só ordem do menu) |
| TS09 | Especial JYOSMI · 12,00 € · P 12,00 (12) / M 15,00 (18) / G 33,00 (44) | Especial JYOSMI · 12,00 € · tamanhos = site | igual ao site | não | sim | bebida grátis presa à Média/Grande |
| TS10 | Combinado Tradicional · 12,00 € · P 12,00 (12) / M 15,00 (18) / G 33,00 (44) | Combinado Tradicional · 12,00 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS11 | Combinado de Fusão · 12,00 € · P 12,00 (12) / M 15,00 (18) / G 33,00 (44) | Combinado de Fusão · 12,00 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TS12 | Combinado Vegan · 10,00 € · P 10,00 (12) / M 12,00 (18) / G 25,00 (44) | Combinado Vegan · 10,00 € · tamanhos = site | igual ao site | não | sim | nada (só ordem do menu) |
| TSP01 | Poke Misto · 11,00 € | Poke Misto · 11,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| TSP02 | Poke de Salmão · 11,00 € | Poke de Salmão · 11,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| TSP03 | Poke de Atum · 11,00 € | Poke de Atum · 11,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA01 | Agua Fastio-500ml · 2,00 € | Água Fastio 500ml · 2,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA02 | Agua Fastio-1Lt · 3,00 € | Água Fastio 1L · 3,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA03 | Coca-Cola Original -33cl · 2,10 € | Coca-Cola Original 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA04 | Cola Zero -33cl · 2,10 € | Coca-Cola Zero 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA05 | Pepsi -33cl · 2,10 € | Pepsi 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA05A | Sprite - 33cl · 2,10 € | Sprite 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA06 | Ice-Tea Limão -33cl · 2,10 € | Ice Tea Limão 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA07 | Ice-Tea Manga -33cl · 2,10 € | Ice Tea Manga 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA08 | Fanta-Laranja -33cl · 2,10 € | Fanta Laranja 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA09 | Fanta-Gurana -33cl · 2,10 € | Fanta Guaraná 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA09A | Gurana Antartica-33cl · 2,20 € | — | foto do site | não | entra | entra como "Guaraná Antarctica 33cl" |
| BSA10 | Fuze Limon-33cl · 2,10 € | Fuze Limão 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA11 | Fuze Pessego-33cl · 2,10 € | Fuze Pêssego 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA12 | Fuze Manga/Ananac-33cl · 2,10 € | Fuze Manga/Ananás 33cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA13 | Pedras Limão com Gas -25cl · 2,10 € | Pedras Limão com Gás 25cl · 2,10 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA14 | Pedras Salgada com Gas -25cl · 1,90 € | Pedras Salgada com Gás 25cl · 1,90 € | igual ao site | não | sim | nada (só ordem do menu) |
| BSA16 | Sumo de Laranja Fresco · 3,50 € | Sumo de Laranja Fresco · 3,50 € | sem foto (site só tem logótipo) | não | sim | nada (só ordem do menu) |
| BSA17 | Limanada · 3,00 € | Limonada · 3,00 € | sem foto (site só tem logótipo) | não | sim | nada (só ordem do menu) |
| BCE01 | Super Bock -33cl · 2,20 € | — | foto do site | sim | entra | entra como "Super Bock 33cl" |
| BCE02 | Super Bock Preta-33cl · 2,20 € | — | foto do site | sim | entra | entra como "Super Bock Preta 33cl" |
| BCE03 | Super Bock Zero-33cl · 2,20 € | — | foto do site | sim | entra | entra como "Super Bock Zero 33cl" |
| BCE04 | Sagres -33cl · 2,20 € | — | foto do site | sim | entra | entra como "Sagres 33cl" |
| BCE05 | Sappro Japones -33cl · 4,00 € | — | foto do site | sim | entra | entra como "Sapporo Japonesa 33cl" |
| BCE06 | Somersby · 3,00 € | — | foto do site | sim | entra | entra como "Somersby" |
| BV01 | Grao Vasco Tinto -37.5cl · 6,50 € | — | foto do site | sim | entra | entra como "Grão Vasco Tinto 37,5cl" |
| BV02 | Grao Vasco Tinto -75cl · 10,00 € | — | foto do site | sim | entra | entra como "Grão Vasco Tinto 75cl" |
| BV03 | MonteVelho Tinto-37.5cl · 7,00 € | — | foto do site | sim | entra | entra como "Monte Velho Tinto 37,5cl" |
| BV04 | MonteVelho Tinto-75cl · 11,00 € | — | foto do site | sim | entra | entra como "Monte Velho Tinto 75cl" |
| BV06 | Casal Garcia Branco-37.5cl · 6,50 € | — | foto do site | sim | entra | entra como "Casal Garcia Branco 37,5cl" |
| BV07 | Casal Garcia Branco-75cl · 11,00 € | — | foto do site | sim | entra | entra como "Casal Garcia Branco 75cl" |
| BV08 | Planalto Douro Branco-75cl · 12,00 € | — | foto do site | sim | entra | entra como "Planalto Douro Branco 75cl" |
| BV09 | Planalto Douro Branco-37.5cl · 7,00 € | — | foto do site | sim | entra | entra como "Planalto Douro Branco 37,5cl" |
| BV10 | MarquesD'Almedia Branco-75cl · 11,00 € | — | foto do site | sim | entra | entra como "Marquês d'Almeida Branco 75cl" |
| BV11 | MarquesD'Almedia Tinto-75cl · 11,00 € | — | foto do site | sim | entra | entra como "Marquês d'Almeida Tinto 75cl" |
| BV12 | Carm-Urze Brano-75cl · 11,50 € | — | foto do site | sim | entra | entra como "Carm Urze Branco 75cl" |
| BV13 | Carm-Urze Tinto-75cl · 11,50 € | — | foto do site | sim | entra | entra como "Carm Urze Tinto 75cl" |
| BV14 | Mateus Rose-37.5cl · 6,50 € | — | foto do site | sim | entra | entra como "Mateus Rosé 37,5cl" |
| BV15 | Mateus Rose-75cl · 11,00 € | — | foto do site | sim | entra | entra como "Mateus Rosé 75cl" |
| BV16 | Santero Doce-75cl · 10,00 € | — | foto do site | sim | entra | entra como "Santero Doce 75cl" |
| BV17 | D. Joao Tinto-Copo · 2,50 € | — | foto do site | sim | entra | entra como "D. João Tinto (copo)" |
| BV18 | D. Joao Branco-Copo · 2,50 € | — | foto do site | sim | entra | entra como "D. João Branco (copo)" |
| BCA01 | Vodka Rodanov -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Vodka Rodanov 50ml" |
| BCA02 | Macieira -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Macieira 50ml" |
| BCA03 | Gin Bombay -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Gin Bombay 50ml" |
| BCA04 | Bushmills -50ml · 4,50 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Bushmills 50ml" |
| BCA05 | Jameson -50ml · 4,50 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Jameson 50ml" |
| BCA06 | J&B -50ml · 4,50 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "J&B 50ml" |
| BCA07 | Jack Daniel's -50ml · 4,50 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Jack Daniel's 50ml" |
| BCA08 | Martini Branco -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Martini Branco 50ml" |
| BCA09 | Martini Rosso -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Martini Rosso 50ml" |
| BCA10 | Martini Dry -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Martini Dry 50ml" |
| BCA11 | J Walker Double Black - 50 cl · 5,50 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Johnnie Walker Double Black 50ml" |
| BCA12 | Famous -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Famous Grouse 50ml" |
| BCA13 | Grants -50ml · 4,00 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Grant's 50ml" |
| BCA14 | Sake Japones -150ml · 4,50 € | — | sem foto (site só tem logótipo) | sim | entra | entra como "Saké Japonês 150ml" |
| BSA18 | Café · 1,00 € | — | foto do site | não | entra | entra como "Café" |
| BSA19 | Descafeinado · 1,20 € | — | foto do site | não | entra | entra como "Descafeinado" |
| BSA20 | Chá Verde -70cl · 3,00 € | — | foto do site | não | entra | entra como "Chá Verde 70cl" |
| BSA21 | Chá Jasmine -70cl · 3,50 € | — | foto do site | não | entra | entra como "Chá de Jasmim 70cl" |
| SM01 | Mochicream Manga · 3,90 € | Mochicream Manga · 3,90 € | sem foto (site só tem logótipo) | não | sim | nada (só ordem do menu) |
| SM02 | Mochicream Morango · 3,90 € | Mochicream Morango · 3,90 € | igual ao site | não | sim | nada (só ordem do menu) |
| SM03 | Mochicream Pistachio · 3,90 € | Mochicream Pistachio · 3,90 € | sem foto (site só tem logótipo) | não | sim | nada (só ordem do menu) |
| SM04 | Petit Gâteau com Gelado · 4,00 € | Petit Gâteau com Gelado · 4,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| SM05 | Gelado Panado · 4,00 € | Gelado Panado · 4,00 € | sem foto (site só tem logótipo) | não | sim | nada (só ordem do menu) |
| SM06 | Gelado (vanilla,chocolate e Morango) · 3,00 € | Gelado (baunilha, chocolate ou morango) · 3,00 € | igual ao site | não | sim | nada (só ordem do menu) |
| SM07 | Frutas Mistas · 3,00 € | Frutas Mistas · 3,00 € | sem foto (site só tem logótipo) | não | sim | nada (só ordem do menu) |
| E01 | Molho Agridoce · 1,00 € | Molho Agridoce · 1,00 € | entra foto do site | não | sim | foto |
| E02 | Sweet chili · 1,00 € | Molho Sweet Chili · 1,00 € | entra foto do site | não | sim | foto |
| E03 | Teriyaki · 1,00 € | Molho Teriyaki · 1,00 € | entra foto do site | não | sim | foto |
| E04 | Molho Soja · 0,50 € | Soja · 0,50 € | entra foto do site | não | sim | nome → "Molho Soja"; foto |
| E05 | Wasabi · 0,50 € | Wasabi · 0,50 € | entra foto do site | não | sim | foto |
| E06 | Gingiber · 0,50 € | Gengibre · 0,50 € | entra foto do site | não | sim | foto |
| E07 | Pauzinhos · 0,50 € | Pauzinhos · 0,50 € | sem foto (site só tem logótipo) | não | sim | nada (só ordem do menu) |
| (BSA15) | não existe no site | Água com Gás San Pellegrino 50cl · 3,50 € | igual à antiga do site | não | sim → **indisponível** | sai (fica indisponível, não se apaga) |

URLs das fotos novas (todas testadas com resposta 200): estão por extenso no SQL, blocos 1 e 3. Exemplos: Hossomaki Mix `https://strangeroasis.com/wp-content/uploads/2026/06/Hossomaki-Mix.png`; Molho Soja `https://strangeroasis.com/wp-content/uploads/2026/07/Soja-souce.png`; Guaraná Antarctica `https://strangeroasis.com/wp-content/uploads/2026/10/Guarana-Antartica.jpg`.
