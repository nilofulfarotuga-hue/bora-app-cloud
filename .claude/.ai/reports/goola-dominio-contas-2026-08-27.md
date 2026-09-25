# Goola, domínio próprio, contas e grelha nova — 27 de agosto de 2026

---

## AS CREDENCIAIS, PRIMEIRO

Conta de parceiro da Goola Açaí, para entregares ao dono.

Endereço: goola@bora.app
Palavra-passe: GoolaiMYxMX11KR!7

Entra em bora-app-web.pages.dev, ou na app, pelo acesso de parceiro. A palavra-passe é temporária: diz-lhe para a trocar assim que entrar.

Testei o acesso a sério, não de olho. O login devolveu código 200 com sessão válida, o papel gravado no token é "partner", e com essa sessão ele vê a loja dele, vê os dois bowls no catálogo com os preços certos, e vê a caixa de pedidos, que está a zero porque ainda não houve nenhum. A conta ficou ligada à loja nas duas colunas de dono, `user_id` e `user_`, que é a lição que já tínhamos aprendido à força.

Conta de cliente de demonstração não criei nenhuma nova. Já existe a de sempre, cliente@bora.app com palavra-passe 123456, que funciona offline e serve para mostrar a app. Se quiseres uma conta de cliente própria para a Goola, digo e crio.

---

## OS CINCO ENDEREÇOS NOVOS, E A VERDADE SOBRE ELES

Isto é a parte que não fechou, e quero ser directo contigo antes de mais nada.

Fiz o passo zero que pediste antes de tocar em coisa nenhuma, e foi bom ter feito, porque encontrou o problema. Digo-te as três coisas por ordem.

Primeira: o domínio boraguarda.com existe e está registado. Confirmei-o por consulta directa aos servidores de nomes públicos: respondem dante.ns.cloudflare.com e elaine.ns.cloudflare.com, que são exactamente os mesmos do guardafcsad.com, um domínio teu que já funciona. Ou seja, está na Cloudflare, na tua conta, e como foi comprado lá dentro não há mudança de servidores de nomes para fazer.

Segunda: sobre a confirmação de email do registo, aquela do ICANN, não consigo responder-te com honestidade. O endereço da Cloudflare que mostra essa informação devolveu-me erro de autenticação, portanto não a consigo ler. O que posso dizer é o sinal indirecto: os servidores de nomes respondem normalmente e o domínio não está suspenso, o que costuma querer dizer que o contacto está em ordem. Mas isto é um sinal, não é prova, e não te quero dar por certo o que não vi.

Terceira, e é esta que trava tudo: o token que está no ficheiro do bora-site é um token só de Pages. Dá para criar e publicar sites, e usei-o para isso. Não dá para mexer em DNS. Quando lhe peço a lista de zonas do teu domínio devolve zero zonas sem sequer dar erro, que é como a Cloudflare diz "não tens permissão", e quando lhe peço as permissões responde que não há autenticação de utilizador válida.

O que isto significa na prática: eu consegui registar os cinco endereços nos projectos certos, e ficaram todos aceites do lado do Pages. Mas o registo de DNS que faz o endereço apontar para o site precisa de permissão de DNS, e essa não tenho. Por isso os cinco estão em estado pendente e ainda não abrem. Confirmei com pedido real a cada um: nenhum resolve ainda.

Os cinco ficaram assim, à espera só do DNS:

boraguarda.com e www.boraguarda.com apontados ao bora-site. goola.boraguarda.com apontado ao goola-guarda. ouroeprata.boraguarda.com apontado ao ouro-e-prata. saboresdobrasil.boraguarda.com apontado ao sabores-do-brasil. Não criei subdomínio para mais nenhuma loja, como mandaste.

Os endereços antigos continuam todos a funcionar e não lhes toquei. Confirmei com pedido real: bora-site.pages.dev devolve 200 e goola-guarda.pages.dev devolve 200 com o site inteiro. Ninguém fica sem o link que já recebeu.

### O que tens de fazer, e é uma coisa só

A via mais rápida, e depois eu termino tudo sozinho sem te chatear mais. São seis passos.

Abre o endereço dash.cloudflare.com/profile/api-tokens no navegador. Carrega no botão azul que diz "Create Token". Na lista de modelos, procura a linha "Edit zone DNS" e carrega no botão "Use template" dessa linha. No quadro "Zone Resources", deixa o primeiro campo em "Include", muda o segundo de "Specific zone" para o teu domínio boraguarda.com. Desce e carrega em "Continue to summary" e depois em "Create Token". No fim aparece o token escrito uma única vez: carrega no botão "Copy" e cola-o aqui na conversa, ou grava-o no ficheiro do bora-site numa linha nova a dizer CLOUDFLARE_DNS_TOKEN igual ao token.

Assim que tiver isso, crio os cinco registos e confirmo-te os certificados um a um.

A outra via, se preferires fazer tu à mão, são cinco vezes o mesmo caminho. Abres dash.cloudflare.com, escolhes a conta, carregas em "Websites" no menu da esquerda e depois em boraguarda.com. No menu da esquerda carregas em "DNS" e depois em "Records". Carregas no botão azul "Add record". No campo "Type" escolhes CNAME. No campo "Name" escreves goola. No campo "Target" escreves goola-guarda.pages.dev. Deixas o "Proxy status" ligado, a nuvem laranja. Carregas em "Save". Repetes o mesmo para ouroeprata com destino ouro-e-prata.pages.dev, para saboresdobrasil com destino sabores-do-brasil.pages.dev, para www com destino bora-site.pages.dev, e para a raiz escreves arroba no nome com destino bora-site.pages.dev.

Não te abri a página no navegador porque a ligação ao Chrome não está activa nesta sessão, e não a consegui iniciar.

Já deixei o resto todo pronto para o momento em que o DNS acender: o endereço canónico do mini-site da Goola, o og:url e o sitemap já apontam para goola.boraguarda.com, e voltei a publicar o site com isso lá dentro. Confirmei no site já publicado que o canónico está mesmo lá.

---

## A GRELHA DAS CATEGORIAS PASSOU A QUATRO POR LINHA

Estava a três e obrigava a rolar muito. Agora são quatro, e as treze categorias cabem em quatro linhas.

O desenho é o mesmo, só menor: as cores, os cantos redondos e a sombra ficaram como estavam. As imagens continuam quadradas e a preencher o ladrilho todo, sem esticar e sem barra branca.

O nome tinha um problema que só se via depois de encolher. Nomes de duas palavras, como Enviar Encomenda e Bora Motorista, ficavam em letra muito mais pequena que os curtos como Lojas, porque o texto encolhia em vez de partir. Agora partem na segunda linha e ficam todos do mesmo tamanho. A caixa do nome tem altura fixa de duas linhas mesmo quando o nome só tem uma, e é isso que faz os ladrilhos ficarem exactamente iguais.

Provei nas três larguras que pediste. A 360, a 390 e a 430 não há corte lateral, não há estouro, e nenhum nome aparece cortado nem com reticências. Isto não é opinião minha: o teste falha sozinho se houver estouro, e tem uma verificação que lê cada nome e rebenta se algum estiver truncado. Aliás, apanhou mesmo o Enviar Encomenda a cortar numa versão intermédia, e foi por isso que mudei a abordagem.

As fotografias das três larguras ficaram guardadas em test barra golden barra underscore fotos, com nome grelha underscore categorias underscore 4col seguido da largura.

O botão redondo de ajuda deixou de tapar o último ladrilho: acrescentei espaço no fim da grelha à medida dele.

---

## OS DOIS LADRILHOS QUE GERASTE

Fui à pasta Downloads e identifiquei os dois pelo conteúdo, não pelo nome, que vem com aquele nome automático do Gemini.

O ficheiro Gemini underscore Generated underscore Image underscore vjqab1vjqab1vjqa ponto jpg é a taça de açaí roxo com banana, morango e granola em fundo roxo. É o de Sobremesas. Ficou instalado e já é o ladrilho da categoria nova. O caminho completo é assets barra categories barra cat underscore sobremesas ponto png, dentro do repositório da app. Passei-o para quinhentos e doze por quinhentos e doze, que é o formato de metade dos ladrilhos que já lá estão, porque em bruto pesava um megabyte contra os quinze a sessenta kilobytes dos irmãos.

O ficheiro Gemini underscore Generated underscore Image underscore xqhq27xqhq27xqhq ponto jpg é o carro coberto de espuma com bolhas em fundo azul. É o da Lavagem Auto. E aqui parei, como me mandaste.

A metade de cima dessa imagem tem o xadrez do fundo transparente desenhado por dentro do ficheiro. Não é transparência a sério, é o padrão aos quadrados pintado na imagem. Medi para ter a certeza antes de te dizer: as quarenta e quatro linhas que analisei no terço superior têm o padrão alternado, e cada linha tem noventa cores diferentes contra doze na parte de baixo, que é fundo liso a sério. Não a remendei nem a instalei. Se a voltares a gerar, pede fundo azul cheio até às bordas, sem transparência.

A categoria de Lavagem Auto em si não construí, como mandaste. Fica para missão própria.

---

## A LOJA FECHADA PASSOU A SER VISITÁVEL

Antes, com a loja fora de horas, o cliente carregava no cartão e não acontecia nada de útil. Agora entra e vê tudo.

Na lista, a loja fechada continua a aparecer, agora com o selo a dizer Fechada seguido da hora a que abre, lido do horário verdadeiro. O cartão passou a ser clicável. Lá dentro vê capa, logo, categorias, produtos, preços e opções, sem nada bloqueado nem esbatido.

O travão passou para o momento de meter no carrinho. Ao carregar no mais, ou no botão de adicionar, aparece uma mensagem só, simples, a dizer que a loja está fechada e a que horas abre. O botão principal fica desactivado em vez de convidar a pedir. Não prometi agendamento nem aviso de reabertura em lado nenhum, e tenho um teste que lê a mensagem e rebenta se lá aparecer alguma dessas palavras.

A verdade do horário vem toda da função is_partner_open, que já existia e já sabe de feriados e do override manual. Não escrevi lógica de horas nova no Flutter e não cravei horas nenhumas. Não toquei nos horários nem nas moradas que corrigiste hoje.

Do lado do servidor pus a mesma guarda, para não se conseguir forçar um pedido por fora da app. Chama-se STORE_CLOSED e segue o padrão do STORE_COMING_SOON que já existia.

Testei os três casos de uma vez, às vinte e duas e cinquenta e quatro de Lisboa, e desfiz tudo no fim para não deixar lixo. O Burger King, que estava aberto, deixou criar o pedido normalmente, ou seja a guarda não parte o fluxo normal, que era o que te preocupava. O Continente, fechado, foi recusado com a mensagem a dizer que está fechado e que abre às oito. E a Goola, que está fechada e em Em breve ao mesmo tempo, foi recusada com a mensagem de Em breve, que é o que mandaste ter prioridade. Confirmei a seguir que nenhum desses pedidos de teste ficou gravado.

Fechada e Em breve são coisas diferentes no código e nas mensagens, como pediste.

No painel de administração já dá para ver e mexer nisto tudo. O horário por dia, os feriados e o override manual estão na ficha da loja, e a lista de parceiros mostra o estado. Não precisei de acrescentar nada.

### Um defeito que encontrei pelo caminho

Ao mexer nisto dei com uma coisa que estava mal e que te afectava a Goola directamente. O código que mete produtos no carrinho estava a recusar em silêncio quando a loja está em Em breve. Recusar sem dizer nada. Ou seja, na Goola o botão de adicionar não fazia rigorosamente nada, e isso contradizia o que a própria app diz noutro sítio, que é que a loja em Em breve deixa encher o carrinho e só trava no pagamento. Corrigi e pus um teste a segurar. Agora enche o carrinho, e quem trava é o ecrã de pagamento e o servidor.

---

## A TAXA DE PEDIDO PEQUENO, DO LADO DA APP

Confirmei o que pediste. O valor que a app mostra passou a vir do campo small_order_fee que o servidor devolve no quote, e não de um cálculo local. Quando há quote fresco, é o número do servidor que manda, que é exactamente o mesmo que entra no total, no valor a cobrar e no valor que vai ao Stripe. O cálculo local só entra quando ainda não há quote nenhum, que é no carrinho antes de haver morada de recolha e de entrega, altura em que a chamada ao servidor nem é possível. E mesmo nesse caso os valores vêm todos das definições da plataforma, nunca do código.

A linha aparece no carrinho, no pagamento e no detalhe do pedido, com o aviso de quanto falta para a evitar. Não toquei no quote_order_pricing nem no interruptor, como mandaste.

---

## A GOOLA NAS DUAS CATEGORIAS

A consulta que fiz à base foi esta: contar as lojas cujo campo de categoria ou cuja lista de categorias extra contenha restaurant, filtrando pela Goola, e depois o mesmo para sobremesa.

O resultado foi um em Restaurantes e um em Sobremesas. Aparece nas duas, que era o que querias.

Além da consulta, escrevi nove testes que seguram isto, incluindo um que distingue este caso do das Festas, que por ordem tua fica só numa categoria.

---

## OS DADOS REAIS DA GOOLA, E O QUE NÃO ENCONTREI

Procurei a sério e não encontrei quase nada. Digo-te o que procurei e onde, para saberes que não foi por falta de tentar.

Telefone da loja: não encontrei. Fui ao directório de lojas do centro comercial, que é guarda.lavieshopping.pt, e a Goola nem sequer aparece lá listada, provavelmente por ser loja nova. Tirei de lá telefones de outras lojas, mas nenhum da Goola. O número duzentos e setenta e um, dois um zero, sete três dois é do centro comercial, não da loja, e por isso não o gravei como sendo dela.

Email de contacto: não encontrei em fonte nenhuma.

Fotografias do quiosque da Guarda: não encontrei nenhuma. Encontrei uma notícia no SAPO sobre a abertura, que confirma o piso três e os atributos da marca, mas o artigo não traz fotografia do quiosque. O Instagram e o Facebook da marca exigem sessão iniciada para mostrar o conteúdo, portanto não consegui lá chegar. E a página do Facebook que consegui ver é da marca em Lisboa, não da unidade da Guarda.

Não inventei nada. Os campos ficaram vazios.

O que fiz foi deixar tudo pronto para o dia em que tiveres os dados. O telefone já era editável no painel. O email não era, e passou a ser: acrescentei o campo E-mail de contato da loja no cartão de perfil da ficha da loja, ao lado do WhatsApp e das redes.

Sobre as fotografias, o mini-site continua a usar as fotografias verdadeiras da marca, tiradas do site oficial e já tratadas. Nenhuma é de banco de imagens. Quando tiveres fotografias do quiosque da Guarda, substituem-se na pasta assets do goola-site e volta-se a publicar.

Sobre o pote de um litro, registei o que disseste: o dono confirmou que não vende. Não está no site nem no catálogo.

---

## O TESTE QUE FALHAVA HÁ MESES ERA UM DEFEITO A SÉRIO

Pediste para o arranjar ou dizer porquê não. Arranjei, e ainda bem, porque não era chatice de teste.

A biblioteca de mapas que calcula distâncias vinha configurada de fábrica para arredondar ao quilómetro inteiro. Na prática, um restaurante a trezentos e oitenta metros aparecia como zero quilómetros, e três lugares a dois vírgula zero três, dois vírgula doze e dois vírgula trinta e seis apareciam todos como dois quilómetros.

Isso não é só o tempo de entrega estimado. Essa distância também alimenta a taxa de entrega que aparece na lista de restaurantes e na ficha da loja. Não mexe no que é cobrado, porque quem manda no preço final é o servidor, mas o cliente estava a ver um número que podia não bater.

A correcção foi dizer à biblioteca para não arredondar. O teste que estava vermelho há meses ficou verde.

---

## OS NÚMEROS

A análise estática da app: zero erros.

Os testes: duzentos e cinquenta e dois, todos verdes, zero falhas. É a primeira vez que a suite fica inteiramente limpa, porque aquele teste da distância estava vermelho desde há muito.

Destes, vinte são novos e meus: cinco da grelha de quatro colunas, oito da loja fechada, e sete acrescentados aos da taxa.

---

## O QUE FICOU POR FAZER, E PORQUÊ

Os cinco endereços novos não abrem ainda. Falta o registo de DNS, e o token que tenho não pode criá-lo. Está tudo o resto feito e à espera desse passo. O caminho ecrã a ecrã está lá em cima.

Não sei dizer-te se a confirmação de email do registo do domínio está feita, porque o endereço que mostra isso recusou-me a autenticação. Se ao criares o token novo vires algum aviso da Cloudflare em cima, diz-me.

O telefone, o email e as fotografias próprias da Goola continuam por preencher, porque não existem em fonte pública nenhuma que eu consiga alcançar. Os campos estão prontos no painel.

A categoria de Lavagem Auto não foi construída, por ordem tua, e a imagem dela não foi instalada por vir com o xadrez.

Nenhuma outra loja levou subdomínio, como mandaste.

---

## AVISO SOBRE O ENVIO

O envio para o repositório é publicação. Vai código a sério neste envio, portanto vai disparar a compilação para Android e a actualização do site na web. O versionCode não foi tocado: quem o incrementa é o sistema de compilação, sozinho.
