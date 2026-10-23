---
id: memoria-claude-ai-livro-areas-mister-kebab
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Mr Kebab & Restaurant (Guarda) — novo parceiro de Restaurantes fechado por Danilo; montar loja no app (catálogo via Glovo/Uber) + mini-site de presente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-mister-kebab`, origem `claude-ai`, atualizada em 2026-10-23T05:35:27.014842+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas mister kebab · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/mister-kebab.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: mister-kebab
description: Mr Kebab & Restaurant (Guarda) — novo parceiro de Restaurantes fechado por Danilo; montar loja no app (catálogo via Glovo/Uber) + mini-site de presente
sources: [chat]
aliases: [Mister Kebab, Mr Kebab, Mr. Kebab, Mr Kebab & Restaurant, mr-kebab-grd1]
---
- [stated] 2026-08-05: Danilo FECHOU com o dono — vai entrar na secção de Restaurantes do [[bora-app]] como PARCEIRO. Danilo monta a loja e oferece também um mini-site, mesmo esquema de [[ouro-e-prata]] / [[sabores-de-casa]] / [[beunique]].
- [stated] Combinado com o dono: é uma DEMONSTRAÇÃO — Danilo faz tudo, não quer pedir quase nada ao dono.
- [stated] Catálogo sai da Glovo e do Uber Eats (a loja está nas duas), mesmo caminho já usado em McDonald's/BK/KFC e nos mercados.
- [stated] REGRA DE PREÇO desta loja (decidida por Danilo): o preço-base gravado NÃO é o da Glovo nem o do Uber — é o PREÇO DA LOJA (balcão), que ele vai mandar por fotos.
- [stated] DECISÃO FINAL DE PREÇO (Danilo, corrigida por ele em 2026-08-05 com calculadora na mão): NÃO cobra os 10% de comissão a esta loja. A fórmula é simples e é a dele: **preço no app = preço de balcão + 15%** (10% da comissão + 5% do markup oculto). Exemplo que ele deu: Menu Doner Kebab balcão 6,90 → 7,94. Eu tinha usado ÷0,90 ×1,05 (=16,67%, dava 8,05) para a loja receber o balcão ao cêntimo — ELE NÃO QUER ISSO, quer os 15% redondos. Consequência assumida: pela fórmula de repasse do sistema a loja fica a ~1,3% do balcão (6,81 em vez de 6,90 no menu de 6,90). Aplicado por MCP em todos os produtos e extras.
- [stated] Coluna nova `products.partner_shelf_price` guarda o preço de balcão de cada produto, para recalcular sempre a partir da fonte sem arrastar arredondamentos.
- [stated] Para os produtos sem foto de preço de balcão: comparar os que TÊM preço de loja com o preço na Glovo, tirar a percentagem média que a Glovo cobra a mais, e usar essa média para descer o preço Glovo dos que faltam.
- [stated] Danilo pediu: primeiro pesquisa total (redes sociais, links, Glovo, Uber), depois o PLANO, e só depois montar loja + site — tudo por prompt, sem trabalho manual dele.

Preços de BALCÃO (fotos dos quadros da loja enviadas por Danilo, 2026-08-05) — fonte de verdade dos preços
- [stated] Quadro principal (prato/sandes | menu com bebida+batata): Doner Kebab 3,90|6,90 · Durum Kebab 4,50|7,20 · Kebab Prato 6,70|7,90 · Doner Box 4,00|5,50 · Falafel 5un 6,50|7,50 · Crispy 3un 6,70|7,90 · Nuggets 6un 6,70|7,90 · Doner Special 7,00|8,50 · Fish Finger 6un 6,70|7,90
- [stated] Quadro 2 (simples|menu): Taco Kebab (NOVO) 8,60|10,00 · Chicken Burguer 6,50|7,00 · Cheese Burguer 6,20|8,00 · Burguer Vegetariano 5,00|7,50
- [stated] Bebidas: lata 33cl 1,60 (Coca, Coca Zero, Nestea manga-ananás/pêssego/limão, Fanta laranja/ananás/maracujá, Sprite) · garrafa 1L 2,60 (Coca, Coca Zero, Sprite, Fanta Laranja) · água 33cl 0,80 / 50cl 1,00 / 1,5L 1,50 · café 0,90 · Super Bock 33cl 1,50 · Água Pedras e Pedras Limão 1,40 · Compal 1,60
- [stated] Extras: Extra Carne 2,00 · Batata Peq 2,00 · Batata Grd 4,00 · Salada Prato 5,00 · Pão 1,00 · Falafel un 1,00 · Crispy Chicken un 1,00 · Nuggets 0,80 · Extra Molho 0,50 · Extra Arroz 1,60 · Saco 0,10 (alguns destes ficaram tremidos na foto — confirmar)
- [stated] REGRA DE FONTE (Danilo, 2026-08-05): a LISTA de produtos vem do Uber Eats (todos os 21); NADA de site nem Facebook (desatualizados); Glovo/Uber servem só para comparar e para as fotos. O PREÇO real é o do balcão.

Loja montada no app (2026-08-05, Claude.ai via MCP)
- [stated] restaurant_id `mrkebab-guarda`, is_partner=true, category='restaurant', approved, `coming_soon=true` (sai do "Em breve" quando o dono confirmar), `partner_commission_billing='client'`. Morada R. 31 de Janeiro nº 1, 6300-769 Guarda; tel +351 271 211 317; lat/lng 40.5390589/-7.2697393; avaliação de vitrine 4,3/182.
- [stated] 47 produtos em 4 categorias PT-PT: Menus (10), Pratos e Sandes (10), Hambúrgueres (6), Bebidas (21). Preço = ROUND(balcão ÷ 0,90 × 1,05, 2). Fonte gravada em products.source = 'balcao_foto_2026_08_05'.
- [stated] 39 grupos de opções / 390 itens: "Bebida à escolha" (obrigatório, 1 de 10) em todos os menus; "Extras" (opcional, até 10) em toda a comida, com os preços do quadro também convertidos pela mesma fórmula.
- [stated] 8 produtos ficaram com foto da Glovo (vendor 471735); 39 ficaram com needs_photo=true — faltam fotos.
- [stated] PENDENTE: fotos dos 39 produtos; conta de parceiro para o dono (falta email); NIF/IBAN; confirmar Batata Grande (4,00) e Salada no Prato (5,00), que estavam tremidos na foto; mini-site; horário tem pausa de almoço a meio (11-15:30 e 17:30-00h) que o business_hours só com um par abre/fecha não representa — ficou 11:00-23:59, sáb 18:00-23:59.

Sessão executor 2026-08-05 (crawler Uber pelo Chrome real) — verificado por MCP
- [stated] O Uber desta loja só tem 26 produtos (não 47): não há lá hambúrgueres, taco kebab nem pizzas. As 8 bebidas que o Uber tem vêm SEM imagem. Conclusão provada: as fotos dos 29 produtos em falta NÃO existem em fonte nenhuma online — só fotografando no balcão. Não gastar mais sessões a tentar.
- [stated] Para restaurantes o endpoint certo é `getStoreV1` + `getMenuItemV1`; o `getCatalogPresentationV2` (usado pela skill market-data-sync) só serve mercearias.
- [stated] Estado verificado por MCP: 47 produtos, 18 com foto (todas no nosso Storage, 0 links de terceiros), 29 com needs_photo, 429 itens de opção, coming_soon ainda true, logo e capa no nosso Storage.
- [stated] Acrescentadas 3 bebidas às opções de menu que o Uber oferece e nós não tínhamos (Super Bock, Água das Pedras, Pedras Limão), todas a +0,00.
- [stated] Logo obtido do Facebook mas só 169px (avatar desenhado com máscara SVG) — serve para miniatura, precisa de um logo em condições vindo do dono.
- [stated] ACHADO POR CONFIRMAR NA LOJA: uma publicação do Facebook mostra um quadro de menu com 9 PIZZAS que não estão nem no nosso catálogo nem no Uber. Não foram inseridas.
- [stated] Divergência de preço: o mesmo quadro do Facebook diz Donner Box 3,20 €, enquanto a foto do balcão tirada por Danilo em 2026-08-05 diz 4,00 €. Decisão tomada: mantém-se a foto do balcão (é a atual); o quadro do Facebook é de outra época. Nada foi alterado.

Correção de preço e opções (2026-08-05, 2ª rodada, Danilo com calculadora)
- [stated] Danilo REJEITOU a fórmula ÷0,90 ×1,05. A regra dele é literal: **balcão + 15%** (10% + 5%). Menu Doner Kebab 6,90 → 7,94, não 8,05. Aplicado por MCP a todos os 47 produtos e a todos os extras (migration `mrkebab_preco_balcao_mais_15_2026_08_05`, backups em `bkp_mrkebab_precos_20260805` e `bkp_mrkebab_opcoes_20260805`).
- [stated] REGRA DAS OPÇÕES: copiar EXATAMENTE o Uber Eats, produto a produto — não a Glovo. Na Glovo as bebidas do menu são +1,50 €; no Uber vêm incluídas a +0,00. É o Uber que manda. As nossas opções foram montadas do quadro da loja e estão incompletas — é preciso abrir cada produto no Uber e refazer.
- [stated] FOTOS DAS BEBIDAS: Danilo autorizou ir buscar a qualquer fonte, porque são marcas conhecidas (Coca-Cola lata 33cl, Fanta, Nestea, Super Bock, Compal, Água das Pedras). Isso resolve 21 dos 29 sem foto; sobram só os 6 hambúrgueres e os 2 taco kebab, que têm mesmo de ser fotografados na loja.

Sessão executor 2026-08-05 (3ª rodada — opções Uber + fotos bebidas) — verificado por MCP
- [stated] Opções: os 26 produtos do Uber foram abertos um a um. Os NOSSOS grupos já eram mais completos que os do Uber (13 opções de bebida vs 10; 10 extras vs 4) — cobertura já estava certa. Só faltava 1 opção: "Batata Frita com Molho" +3,00€, acrescentada aos produtos não-bebida (429→455 itens de opção, confirmado por MCP).
- [stated] DECISÃO (Claude.ai, sem precisar perguntar — já resolvido pela regra desta loja): Extra Arroz/Carne/Molho ficam nos preços actuais (1,84/2,30/0,58 = balcão×1,15), NÃO alinhados ao Uber (2,50/2,50/0,80). O preço do Uber já traz a margem do Uber, não é preço de balcão — alinhar quebraria a regra balcão+15% que acabou de ser fixada. Nada foi alterado nestes 3 itens.
- [stated] Fotos: 25 de 47 produtos com foto (eram 18). 7 bebidas novas (fonte Continente, fundo branco). 6 chumbadas por enganar o cliente (Super Bock veio em pack de 24, Águas das Pedras em pack, Fanta Maracujá/Laranja e Sprite em garrafa de 2L em vez do tamanho certo) — ficaram sem foto de propósito. Também sem foto por decisão consciente: 3 águas simples (catálogo não diz a marca), 3 Nestea (Continente não vende Nestea) e o Café (não é produto de prateleira).
- [stated] FALTAM FOTOS (22): Hambúrgueres (6: Chicken Burguer + Menu, Cheese Burguer + Menu, Burguer Vegetariano + Menu), Taco Kebab + Menu Taco Kebab (2), e 14 bebidas (Fanta Ananás/Maracujá/Laranja 1L, Nestea×3, Sprite 1L, Águas×3, Água das Pedras×2, Super Bock, Café) — estas últimas 14 só resolvem fotografando na loja ou o dono mandando foto real do rótulo.
- [stated] Site republicado com as 25 fotos: mr-kebab.pages.dev, 200 OK.
- [stated] LIÇÃO: o executor apanhou o próprio erro — 1ª leitura das opções por REST sem filtro trouxe a 1ª página de TODAS as lojas (11/0) em vez das do Mister Kebab (39/429); notou porque não batia com o SQL de minutos antes, corrigiu e só então escreveu. Vale exigir sempre esse tipo de conferência cruzada antes de qualquer escrita em massa.

Conta de parceiro, redes e takeaway (2026-08-05, Claude.ai via MCP)
- [stated] CONTA DE PARCEIRO CRIADA: `mr.kebab@bora.app` (mesmo padrão de saboresde.casa@bora.app / ouro.prata@bora.app). Ligada a `restaurants.user_id` e a `public.users.role='partner'`. Senha temporária entregue ao Danilo no chat — não fica guardada aqui; ele deve mandar o dono trocá-la ao primeiro acesso. Isto desbloqueia o pendente "falta email do dono" — já não é preciso o email pessoal dele.
- [stated] WhatsApp do dono: +351 920 101 026 (contacto guardado como "Mtr Kebab"). Gravado em `restaurants.whatsapp`. Danilo decidiu que vai no site.
- [stated] Facebook oficial: facebook.com/mrkebabandrestaurant — gravado em `restaurants.social_facebook`.
- [stated] Migration `restaurants_sobre_e_redes_2026_08_05`: colunas novas em restaurants — `about_text`, `social_facebook`, `social_instagram`, `whatsapp` (mesma convenção já usada em service_providers).
- [stated] DECISÃO DO DONO: aceita tudo MENOS reserva de mesa. Gravado: `takeaway_enabled=true`, `reservations_enabled=false`, `curbside_enabled=false`.
- [stated] LOGO: Danilo fotografou a embalagem de molhos da casa (logo "mr.kebab" branco sobre vermelho, com kebab em pão) e depois GEROU ELE PRÓPRIO no ChatGPT uma versão 3D cartoon, 1254×1254, que aprovou e quer usar. Já não é preciso o executor gerar logo nenhum — é só aplicar o ficheiro dele.
- [stated] LIMITAÇÃO OPERACIONAL DESCOBERTA (2026-08-05): a Claude.ai NÃO consegue subir ficheiros para o Storage do Supabase — o contentor de bash só tem rede para api.anthropic.com, github, npm e pypi; `*.supabase.co` devolve 403 no proxy. Imagens que o Danilo manda no chat têm de chegar ao PC dele (pasta do repo ou Desktop\Bora) para o Claude Code as subir. Ficheiros entregues por `present_files` resolvem, mas obrigam-no a guardar.
- [stated] PEDIDO DE ACESSO (Danilo, 2026-08-05): quer soltar mais a loja mesmo em `coming_soon` — cliente navega, mete no carrinho, avança tudo, e só é travado NO ECRÃ DE PAGAMENTO. Hoje a guarda de servidor já é no pagamento (`trg_payment_draft_coming_soon`), falta confirmar que a UI do Flutter não bloqueia antes disso.
- [stated] O logo 3D e as fotos que Danilo tirou estão TODOS na pasta Downloads do PC dele (`C:\Users\danil\Downloads`) — o executor procura lá, ele não move nada à mão.
- [stated] PEDIDO DO SITE (Danilo, 2026-08-05): quer o site MUITO bonito, "capricha". Vasculhar o Facebook e TODOS os meios de comunicação do dono para tirar o máximo de imagens; usar também as fotos da própria loja que ele tirou; e as fotos cruas devem ser tratadas/embelezadas antes de entrar no site (ele referiu pedir ajuda a um gerador de imagem para melhorar), em vez de entrarem como estão.
- [stated] MESMO LOGIN PARA OS DOIS PAPÉIS (Danilo, 2026-08-05): `mr.kebab@bora.app` tem de servir para entrar como PARCEIRO e como CLIENTE, com a mesma senha. FEITO por MCP: linhas `partner` e `client` em `public.user_roles`. Descoberta importante — o sistema multi-papel JÁ EXISTE e está vivo no banco (tabela `user_roles`, RPC `my_roles()`, `add_client_role_to_me()`, `admin_list_user_roles()`, trigger `_grant_role_from_profile`); `public.users.role` ficou só como papel principal. Aproveitou-se para dar também papel `client` aos outros parceiros (sabores, ouro.prata, beunique) — todos podem agora encomendar como clientes.
- [stated] POR CONFIRMAR no Flutter: se a app oferece mesmo o seletor de papel a quem tem mais que um (o banco já devolve os dois por `my_roles()`); sem isso o dono entra e cai direto no painel do parceiro sem forma de ir ao lado do cliente.
- [stated] Danilo mandou print do estado actual (2026-08-05): a mensagem "Esta loja ainda não está a aceitar pedidos" aparece por cima da própria grelha de produtos (Pratos e Sandes), travando o browse — não só o pagamento. Confirma que o Bloco 5 do prompt do site ainda não correu (a 1ª tentativa caiu no Claude Code da nuvem em vez do PC e parou sozinha — ver [[bora-app]]).

Flyer "PEÇA O SEU MR. KEBAB PELO BORA APP" com QR reais (2026-08-05, Claude.ai)
- [stated] Danilo mandou o flyer do Mr Kebab gerado por IA (1024×1536) e pediu o mesmo esquema do flyer de [[ouro-e-prata]]: substituir os 2 QR falsos por QR reais nos lugares certos.
- [stated] FEITO: flyer subido a 3× (3072×4608, LANCZOS) e os 2 QR colados por cima das molduras originais. Esquerdo (iPhone/WEB, moldura laranja) → https://bora-app-web.pages.dev/#/registo-cliente; direito (ANDROID, moldura verde) → https://play.google.com/store/apps/details?id=pt.boraapp.bora (link da LOJA, já vale porque a app foi publicada em 31/07 — ver [[play-store-release]]; deixou de ser preciso o apps/testing).
- [stated] LIÇÃO DE QR (vale para todos os cartazes seguintes): usar correção de erro **M**, não H. Com H o QR do Play Store dava 49 módulos e só se lia com o cartaz acima de 1536px; com M dá 37 módulos, módulos maiores, e lê-se com o cartaz reduzido a 700px e mesmo com foto tremida (blur). Testado com cv2.QRCodeDetector em várias escalas antes de entregar.
- [stated] Ficheiros entregues: mr-kebab-bora-QR.jpg (3 MB, para WhatsApp/redes), mr-kebab-bora-QR.png (9 MB, sem perdas, para gráfica), qr-mrkebab-web-registo-cliente.png e qr-mrkebab-android-playstore.png (QR soltos, para reutilizar noutros materiais).
- [stated] MÉTODO: feito por Python (segno + PIL) no contentor, não pelo Canva — é o mesmo caminho que funcionou no cartaz da Ouro e Prata e permite medir as molduras ao pixel e provar a leitura antes de entregar.

Site v2 e carrinho liberado (2026-08-05, Claude Code no PC, verificado por MCP)
- [stated] Site reconstruído do zero, no ar: mr-kebab.pages.dev. Confirmado ao vivo: 47 produtos, 4 categorias, preços batem com a DB. Logo 3D do Danilo aplicado (recortado o fundo vermelho) — restaurants.photo_url actualizado. Material visual: só 5 fotos do Facebook da loja (tratadas: exposição, tirar amarelado, saturação leve, nitidez) + o logo — SEM fotos do Uber nem da Glovo, por instrução directa do Danilo ao Claude Code nesta sessão. coming_soon continua true, confirmado. social_instagram continua vazio (não encontrado).
- [stated] CARRINHO LIBERADO até ao pagamento (Bloco 5 fechado): CartStore ganhou o getter vendorBlocksAddToCart; os 6 sítios que travavam passaram a lê-lo. Cliente já escolhe produto, opções, enche carrinho, chega ao checkout — só para na tela de pagamento com aviso PT-PT. Trigger trg_payment_draft_coming_soon (guarda de servidor) não foi tocado. flutter analyze 0 erros. Resolve o print que o Danilo tinha mandado (loja bloqueada na grelha de produtos).
- [stated] BLOCOS 6 E 7 FICARAM POR FAZER — o executor foi directo, não inventou: não testou o login mr.kebab@bora.app nos dois papéis (parceiro+cliente) nem tocou no painel admin (whatsapp/redes/about/takeaway/reservas editáveis, papéis de utilizador). Falta uma sessão só para isto.
- [stated] NÃO HÁ NENHUMA FOTO REAL DA LOJA NO PC do Danilo — nem Downloads, nem Pictures, nem Desktop; as 3 que lá estavam eram screenshots do próprio Bora App. As fotos que faltam (hambúrgueres, taco, 14 bebidas) só resolvem com o Danilo a fotografar de propósito no balcão.
- [stated] VERIFICAÇÃO DO LOGIN por MCP (2026-08-05): tudo confere do lado do banco — hash da senha bate com `[REMOVIDO]`, email confirmado, conta não banida, papel principal `partner`, `user_roles` = [client, partner], e `mrkebab-guarda` ligada à conta. O único ponto por provar é a UI do Flutter (seletor de papel).
- [stated] ORDEM CRIADA no Córtex para fechar os Blocos 6 e 7 (login duplo + painel admin): `prop-a2e5282f`. O Córtex classificou-a como ZONA VERMELHA automaticamente (apanhou palavras de zona protegida no texto das proibições) e mandou-a para a fila de aprovação da Central — não entrou no loop automático. Danilo tem de aprovar à mão.
- [stated] NOTA DE MÉTODO: as proibições escritas no corpo da ordem (ex.: "não tocar em post_order_to_ledger, platform_settings, partner_shelf_price") fazem o detetor de zona do carteiro marcar a ordem como vermelha, mesmo quando a tarefa é só UI. Nas próximas ordens, referir as zonas protegidas de forma genérica ("respeitar as zonas protegidas do CEO-AI") em vez de listar os nomes, se se quiser que entre no loop verde.
