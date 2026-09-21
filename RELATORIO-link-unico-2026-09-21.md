# Relatório — link único para o iPhone (21 de setembro de 2026)

Missão `link-unico-iphone`, run `link-unico-20260921`. Claude Code, motor Opus, no PC.
Linhas do `e2e_log`: 2137 (E0), 2138 (E1), 2139 (E2), 2140 (E3), 2141 (E4), 2142 (E5); a do E6 vai no fim.

## Acessos usados nesta sessão

Chrome do PC no perfil Bora (boraappbora@gmail.com, Gemini com plano Google AI Plus, confirmado no ecrã como "Bora Bora bora · Plus") para gerar e julgar a arte. API do App Store Connect com a chave de equipa "Bora iOS CI" (chave no cofre local, nunca no repo). Base de dados Supabase pelo MCP. VPS das redes por SSH (chave do PC). Cloudflare Pages pelo script oficial de publicação do site. Nada foi criado de novo em contas externas; não houve logins.

## O que NÃO ficou feito, dito primeiro

A ficha da App Store não muda sozinha como o prompt pedia. O idioma "Inglês" que aparece na loja vem de dentro da própria app, não dos textos da ficha, que já estavam em português desde o início. E a categoria, a Apple não deixa mudar na versão que está no ar: a API respondeu com recusa (código 409, "estado inválido") e a página da própria Apple sobre propriedades editáveis diz o mesmo. As duas coisas ficam prontas para a próxima versão, a 1.0.1, que já criei no App Store Connect, mas essa versão ainda não tem build nem foi submetida. Para isso falta a build do iOS pelo CI (dispara-se à mão no GitHub, no ramo ios-lancamento, e paga minutos de Mac) e depois submeter a versão. Não o fiz nesta sessão porque o autoteste dos três perfis tem de passar primeiro e a sessão já ia longa; está tudo explicado mais abaixo.

O fiscal automático da VPS não conseguiu dar nota à peça nova: a sessão viva do Chrome que ele usa está morta há 13 dias e a API grátis do Gemini estava no limite. A nota foi dada pela sessão paga do Gemini, como a regra manda, e ficou registada.

O Mr Kebab continua fechado, como mandaste. Não toquei na bandeira.

## O que estava mesmo no ar quando comecei (Bloco E0)

O prompt dizia que a página boraguarda.com/baixar mandava o iPhone para o site em vez da App Store. Não era bem assim: desde 13 de setembro a página já tinha o botão da App Store escondido no código, e o JavaScript mostrava-o no iPhone. Quem leu a página sem correr o JavaScript, como faz a Claude.ai, viu o botão do site em cima e concluiu mal. O que faltava de verdade era outra coisa: o botão "pedir pelo site" continuava do mesmo tamanho que o da loja, no computador saíam dois QR pequenos e os botões empilhados, e sem JavaScript o botão da App Store nem existia. Escrevi tudo em `docs/ESTADO-DIVULGACAO-2026-09-21.md`.

A arte impressa toda tinha QR velho: li os QR das 30 imagens de flyers, cartazes e autocolantes com o leitor da casa e nenhuma apontava para o baixar. Todas apontavam para a Play Store e para o registo no site. Na VPS, o carrossel escrevia "Android: link" e "iPhone ou computador: site", o reel de recurso escrevia "play.google.com/store" no fecho, e o Sabores de Casa Açaí não estava na rotação nem tinha fotos para o portão do parceiro.

Um número que vale a pena ouvir: desde 7 de setembro a página baixar teve 325 visitas de Android, 126 de iPhone e 47 de computador, tirando robôs. Um quarto das pessoas vinha de iPhone.

## Um link só (Bloco E1)

A página `boraguarda.com/baixar` foi reescrita e está no ar. No iPhone e no iPad aparece só o botão grande da App Store, com o link real da ficha. No Android aparece só o da Google Play, com a marcação de origem no referrer da instalação. No computador aparecem os dois botões lado a lado e um QR grande único que aponta para a própria página, para o telemóvel decidir. O "pedir pelo site" passou a ser uma linha pequena por baixo. O código BEMVINDO continua lá com os mesmos valores da base (1000 tokens, 5 euros, uma vez por pessoa, confirmado por SELECT) e a marcação de origem por peça continua a funcionar: as visitas de teste ficaram registadas com a origem qr-flyer.

Prova: o Playwright abriu o endereço público a fingir um iPhone 14, um Pixel 7 e um computador, tirou as três capturas e leu da própria página o que estava visível. Os três casos passaram em todos os pontos, e a frase antiga "iPhone ou computador · sem instalar nada" tem zero ocorrências no ar. Capturas em `provas/link-unico-20260921/E1-publico/`. A página principal do site também tinha um bloco de descarga só com a Play Store e a frase "iOS brevemente"; passou a ter o QR único e os botões das duas lojas. Commits no repo do site: 4e9ff81 e 25fd0f5, publicados pelo script oficial.

## Um QR só em toda a arte (Bloco E2)

Refiz tudo com o gerador único da casa, que aponta para `boraguarda.com/baixar?de=qr-flyer`. O flyer A4 e a versão de WhatsApp (em Downloads e em `Desktop\Bora\Projetos\flyer-bora-app-2026-09-21`), com o rodapé a dizer "na App Store e na Google Play" e a morada curta. Os autocolantes genéricos, dez peças nas duas famílias mais os quatro A4 de pré-visualização e os dois PDFs de gráfica, com um painel único a tapar as duas molduras antigas. O cartaz grande A3 do Bora, com um painel único no lugar das duas molduras rotuladas e a linha "Em breve" reescrita, porque o Sabores de Casa já está na app. Os dois cartazes do Goola, vertical e horizontal, com a moldura da esquerda a virar o cartão do QR único e a da direita o cartão das duas lojas com o ícone real da app. Os autocolantes antigos da pasta do Goola eram o desenho reprovado a 4 de setembro e foram para uma pasta de antigo com aviso para não irem à gráfica.

Os verificadores mecânicos de cada peça passaram a exigir o QR único e a chumbar qualquer QR velho, e correram todos verdes: flyer tudo verde, autocolantes tudo verde, cartaz 42 pontos certos, Goola 23 pontos certos. Leitura final por OpenCV de 28 imagens: 26 apontam para o baixar e nenhuma tem QR velho; as duas restantes são imagens de comparação sem QR legível, uma refeita e outra arquivada. Lista completa em `provas/link-unico-20260921/E2-qr-lidos-depois.txt`.

## A ficha da App Store (Bloco E3)

Lido da API: a ficha viva tem o idioma principal pt-PT e o nome "Bora — entregas e serviços". O "Inglês" da loja vem do binário, confirmado pelo lookup público da Apple. Acrescentei ao Info.plist do iOS a declaração de idiomas pt-PT e inglês; o teste do Info.plist passou sete em sete. Isto entra em vigor na próxima build.

Categoria: criei a versão iOS 1.0.1 no App Store Connect, com lançamento manual como a anterior, e nas fichas pendentes ficou Estilo de vida como categoria principal e Gastronomia e bebidas como secundária, lido de volta pela API. Escolhi Estilo de vida porque é a categoria que a Apple define para "serviços de interesse geral", onde vivem as apps de limpeza ao domicílio, marcações de barbearia e afins; a Gastronomia fica em segundo para as pessoas que procuram entregas de comida continuarem a encontrar a Bora. Escrevi também o texto das novidades da versão em português. A ficha viva fica igual até a 1.0.1 ser submetida e aprovada.

O que falta para fechar isto: disparar a build iOS no GitHub (ramo ios-lancamento, que é antepassado da produção, por isso é um avanço limpo), ligar a build à versão 1.0.1 e submeter. Fica para a próxima sessão, depois do autoteste.

Fora do scope mas visto: alguém criou a 15 de setembro versões da app para Mac, Apple TV e Vision Pro no App Store Connect, todas em rascunho. Não mexi.

## A propaganda a sério (Bloco E4)

A cena de cinema do Sabores de Casa Açaí foi desenhada pelo Gemini pago, modo imagem, formato vertical, com a foto real do copo da felicidade e o logo real anexados como referência: um copo de açaí a transbordar, no balcão de uma mercearia brasileira, com a rua de granito da Guarda pela montra. O script da VPS colou o logo do Bora, o logo real do parceiro, o QR único e o rodapé "App Store · Google Play · boraguarda.com/baixar". O portão do QR leu o destino certo nos dois formatos. O juízo pela sessão paga do Gemini, com o cartaz aprovado do Goola ao lado, deu 92 em 100; só perdeu no título com nove palavras, e por isso o gerador de títulos passou a encurtar quando o nome da loja é comprido.

Descobri e corrigi pelo caminho um defeito antigo: desde 5 de setembro o cartão do QR tapava o disco do logo do parceiro em todas as peças de loja do dia, e por isso a peça do Goola de hoje saiu sem logo. Agora o disco desce para baixo do QR.

O robô das redes passou a dizer as duas lojas em tudo o que sai: legenda da loja do dia, carrossel, reel, formato extra, story e grelha da semana, e o carrossel deixou de mandar o iPhone para o site. Cada ficheiro mudado na VPS tem cópia com o sufixo bak-link-unico-2026-09-21 e a sintaxe foi verificada.

## As duas lojas paradas (Bloco E5)

Sabores de Casa Açaí: já estava aberta na base e o dono tem um aparelho registado para receber pedidos. Pus as fotos reais e o logo na pasta de parceiros da VPS, o portão do parceiro passa, a cena de cinema está guardada com o nome da loja, e a loja entrou na rotação para quinta-feira 24 ao meio-dia. Fiz o ensaio completo do robô da loja do dia em modo de ensaio: foi buscar os dados à base, usou a cena guardada porque a API estava no limite, passou o portão do parceiro, montou os cartazes, o juiz de visão aprovou, e não publicou. As peças de ensaio estão em `provas/link-unico-20260921/E4-sabores-de-casa-*`.

Mr Kebab & Restaurant: continua em breve, não mexi. Tem logo, capa, morada, telefone, horário, coordenadas e 47 produtos, 25 com foto. O que falta para abrir é o dono entrar uma vez na app de parceiro no telemóvel, porque nunca entrou e não há aparelho registado, logo nenhum pedido lhe tocaria; pôr foto nos 22 produtos que não têm; e o teu "vai". A pergunta foi pela ponte do Telegram.

## Provas, publicação e fecho (Bloco E6)

O autoteste dos três perfis corre no CI antes de qualquer publicação, por desenho do build_android.yml: sem verde, o build não sai. Neste PC o arnês não se liga ao emulador, é uma armadilha conhecida, por isso a prova é a do CI. O push da produção leva só os ficheiros desta missão, caminho a caminho: o Info.plist, o documento de estado, este relatório e as provas. As alterações de outras sessões que estão por commitar na árvore ficaram onde estavam. O CI correu verde de ponta a ponta: o autoteste dos três perfis passou (das 16:24 às 16:53), o build Android subiu para a Play em alpha e o CI empurrou o versionCode 614; o web também ficou verde. Linhas 2143 e 2144 do e2e_log.

Cópia deste relatório em `C:\Users\danil\Desktop\Bora\Projetos`. Digest em `claude_ai_memoria`. O Córtex não estava autorizado nesta sessão (o conector pede autorização nova), por isso o digest foi para a tabela e a ordem de continuação foi para a caixa de entrada do repo.

## O que encontrei fora do scope

A função de visitas do site e a pasta functions do repo do site estão no ar mas por committar de outra sessão, juntamente com a política de privacidade e os termos; publiquei a cópia de trabalho tal como estava, que já era o que estava no ar. Os mini-sites de parceiros e a página de viagens do site ainda têm botões para a Play Store e para o registo no site em vez do link único. O fiscal da VPS depende de uma sessão viva do Chrome que está morta há 13 dias. A ordem de rotação das lojas grandes (proxima_loja.py) continua com o bug conhecido de ordenar ao contrário. No App Store Connect há versões para Mac, TV e Vision Pro criadas a 15 de setembro em rascunho. E a peça do Goola publicada hoje ao meio-dia saiu sem o logo do parceiro, pelo defeito que agora está corrigido.
