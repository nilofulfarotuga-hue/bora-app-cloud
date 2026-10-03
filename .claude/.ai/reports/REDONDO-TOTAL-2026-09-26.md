# Redondo total — 26 e 27 de setembro de 2026

Contas usadas: Chrome do perfil Bora (boraappbora@gmail.com, deviceId d9e862e0), Supabase do Bora por MCP, GitHub pela credencial do git deste PC, Kaggle da conta Bora Bora app. Nada foi criado em contas de fora. Criado na base: as tabelas cascata_video e cascata_video_uso, e as cópias de segurança bkp_bk_precos_20260926, bkp_bk_fontes_20260926, bkp_products_categoria_20260927, bkp_products_fotos_20260927 e b12_plano_categoria_20260927, todas com RLS ligada.

## O que NÃO ficou feito, primeiro

O Em Dia não foi submetido à Apple. O CI do iPhone do Em Dia pára porque o GitHub do em-dia-app não tem as sete chaves da Apple (certificado de distribuição e a palavra-passe dele, perfil da loja para com.boraguarda.emdia, e a chave da API da Apple com o id, o issuer e o team). Pôr chaves e certificados no GitHub é um passo que não faço por regra de segurança: é teu. A lista exata está em em_dia/docs/SECRETS-IOS.md e há o script _segredos/em-dia/github_secrets.py. Assim que estiverem lá, o resto é um disparo do build-ios com enviar ligado, que sobe, cria a versão e submete sozinho. O rótulo de privacidade continua a ser só pelo portal.

Na cascata de vídeo, três degraus ficaram parados à espera de ti. O Meta AI no Chrome do Bora pede para aceitar os termos da Meta com o botão Continuar; deixei a página aberta, é só carregares. O ZSky e o Grok não têm conta no perfil Bora e criar contas é contigo. Também falta ligar o robô das redes e o Studio à cascata e fazer o ecrã dela no painel admin.

O radar das duas da manhã continua sem vídeos novos. O histórico certo do YouTube é o do teu perfil pessoal do Chrome, que não estava ligado à extensão do Claude nesta sessão; o do perfil Bora só tem desenhos das meninas. E o yt-dlp continua bloqueado pela encriptação do Chrome.

No Burger King faltou a segunda metade: juntar os produtos da Glovo que não temos, com os grupos de opções, e tirar os que só existem online.

A memória Córtex não aceitou escrita nesta sessão (o conector pede nova autorização no claude.ai). O resumo foi para a tabela claude_ai_memoria, que o Córtex espelha de hora a hora.

## O que ficou feito

B1. A skill dos navegadores passou a ter o 99Freelas, o Codester e o Meta AI no perfil Bora, e o mapa de contas ganhou seis sites. Commit 3dee71f3.

B2, B3 e B4 do crescimento foram feitos pelo Codex e eu verifiquei de novo. O decisor está na versão 7 desde 26/09 às 21:08 e não houve mais nenhuma decisão com erro depois disso. O agente torre fez seis rondas seguidas bem. O radar do crescimento apanhou 24 vídeos no dia 26. Pus no repositório o código que o Codex tinha deixado por gravar, commit 27563493.

B6, o site do Guarda FC, foi feito pelo Codex: resultado com o Desportivo de Chaves e classificação com duas fontes que concordam, e os workflows verdes.

B7, a app do motorista. A recusa que ninguém fez na corrida de 25/09 veio de um toque dentro da app, no cartão da oferta que apareceu por cima do ecrã logo a seguir à corrida cancelada; vi isso no registo do servidor, que distingue o botão da app do botão da notificação. Agora o Recusar não faz nada no primeiro segundo depois de a oferta aparecer e pede um segundo toque. Expirar nunca recusa. O token de notificações passa a registar-se sempre que a app abre, e a volta da ida-e-volta leva sempre o número da ida. No servidor, o GPS parado já não desliga o botão de ninguém, só tira das ofertas; e repus os limites de 15 e 30 minutos. O Ney continua online mas deixa de receber ofertas enquanto o telemóvel não mandar posição. Commit 1e76dbc5.

B8, o parceiro editar o pedido, já estava ligado desde 22/09, com o dinheiro aplicado nesse dia com o teu vai. O resumo que os outros motores liam dizia o contrário; corrigi-o.

B9, venda ao peso. O jiló mostra o Escolhe a quantidade e cada porção soma certo até ao carrinho, provado no ecrã verdadeiro com os dados reais. A abóbora deixou de ser vendida ao peso a 24/09 sem ninguém registar quem mudou; o preço por quilo é decisão tua ou da Sabores de Casa.

B10, o Burger King. Li os preços de balcão da loja da Guarda no site oficial e acertei 53 preços. Havia 48 produtos a vender abaixo do balcão, agora não há nenhum. Cuidado que aprendi: no site o preço de um menu é o tamanho grande, e os nossos menus são o médio.

B5, a cascata de vídeo. Ficou uma tabela única com a ordem e o contador de créditos por dia. O Veo do Gemini tem nota 40 em 45 e o Kaggle 27 em 45, medidos com o mesmo fiscal. Commit 27cf19e9.

B12, as sugestões do robô. 5695 produtos ganharam categoria, 5546 por regras e 149 pelo motor grátis da VPS; ficaram 5. 1505 saíram da lista de rever. Cinco fotos oficiais do Continente. As 78 sem foto não têm fonte legítima. O lento repor demo era só o arranque, cerca de meio segundo por hora.

## Para o Danilo

Pôr as sete chaves da Apple no GitHub do Em Dia. Carregar em Continuar no Meta AI aberto no Chrome do Bora. Ligar a extensão do Claude no teu perfil pessoal do Chrome, uma vez, para o radar ler o teu histórico. Decidir o preço por quilo da abóbora. Decidir se se corrige a ordem dos gatilhos das categorias ou se o lote corre todas as semanas.

## Publicação

Push de 5 commits no ramo autonomous-night-2026-04-29 (4885849c até 27cf19e9), e depois mais dois: a versão passou de 1.0.3 para 1.0.4, só no nome, porque a Apple já tinha aprovado a 1.0.3 e não aceita outra build com o mesmo número; e pus o inglês de quatro frases novas do favor que outra sessão tinha enviado sem tradução e que chumbavam os testes do iPhone.

No fim ficou tudo verde nas três plataformas, no commit 1f2c41ce. O Android passou o autoteste dos três perfis no emulador e subiu à Play; a app vai na versão 628. A web está na 1.0.4 e já tem a correção do Recusar. O iPhone passou os testes, subiu à Apple e a versão 1.0.4 ficou submetida para revisão com lançamento automático: quando a Apple aprovar, sai sozinha.

Pelo caminho encontrei três ficheiros de trava do git abandonados no repositório do PC, sem nenhum git a correr; alguma tarefa automática do PC abre o git e morre a meio. Tirei-os para poder gravar, e fica registado para se descobrir qual é.
