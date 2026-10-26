# Missão geral de sábado (24/10 → 26/10/2026) — relatório para o Danilo

Publicação: tudo o que mexeu na app está nas 3 (Android 693, 694 e 696; iPhone enviado à Apple em cada
envio; site no commit d07af8d3). O Android dos blocos 3 e 5 falhou a 1.ª vez no teste do emulador (a
falha conhecida das 8h às 10h, com a loja de demonstração fechada) e passou ao ser relançado às 13:00.

Acessos usados: Supabase (MCP), VPS por SSH (IP público; o atalho bora-vps pela Tailscale dá recusa),
GitHub pelo PC, Gmail da Bora pelo canal do Emerson (API do carteiro), Chrome perfil Bora (só o agente
do reel). Registo passo a passo: tabela e2e_log, fluxo `geral-sabado-24-10`.

## O que NÃO ficou feito (e porquê)

- Publicar demos novas no bora-demos.pages.dev pelo Emerson: o projeto vive na conta Cloudflare da Bora
  e nem a VPS nem o PC lhe chegam por linha de comando. Falta um token do Cloudflare (ver PARA O DANILO).
  Hoje não trava nada: nenhum lead novo de obras tem e-mail publicado.
- Os 4 pontos de dinheiro da ordem ficaram de fora, como pedido (Stripe, as 3 funções de pagamento com a
  chave nova, desligar as chaves legadas).
- A sessão esteve parada muitas horas a 24 e 25/10 (o trabalho real foi feito a 25 e 26/10).

## Bloco 0 — Estado
Fiz o ponto de cada missão anterior no e2e_log (sinal fantasma parou no diagnóstico; documentos tinham
2 commits só no PC; omniroute parou no envio; livro comum feito até ao bloco 1; n3b à espera de envio;
agentes-email já estava no servidor).

## Bloco 1 — Motorista "ligado" sem sinal
Fiz isto: o servidor avisa por notificação quem tem o botão ligado e não manda sinal — aos 10 minutos,
depois de meia em meia hora até às 6 horas, depois de 6 em 6 horas. O Valdemir recebeu o primeiro aviso
a 25/10 às 22:40 e o seguinte às 04:40 (o Firebase aceitou os dois). A app religa sozinha o serviço de
fundo quando chega o aviso ou quando se abre com o botão ligado, e pede uma vez para tirar a Bora da
poupança de bateria, explicando o caminho conforme a marca (Samsung, Xiaomi, Huawei, Oppo, Vivo). No
iPhone o sinal passa a sair sempre da app com a sessão dele (antes não saía nunca pelo serviço, por isso
o segredo de 13/10 nunca foi usado). No painel, em vez de "Online", aparece "Ligado sem sinal desde 20/10
às 03:01" com o botão "Enviar aviso agora". Ninguém é posto offline: só o botão desliga.
Prova: captura do painel (pasta privada), SELECT dos avisos, versão Android 693, iPhone enviado à Apple,
site com as frases novas. Revisor: primeira ronda NÃO (duas correções), segunda SIM.
Falta isto: ver no telemóvel do Valdemir quando ele tiver a versão nova; o Ney quando ligar o iPhone.

## Bloco 2 — VPS: firewall e disco
Fiz isto: firewall ligada; da internet só entram SSH e os sites (80/443). O painel do Hermes, o trader,
a página do QR do WhatsApp e as impressoras deixaram de responder de fora (provado do PC). O painel do
Hermes abre pela Tailscale. Hermes, Emerson (Telegram), OmniRoute, carteiro, ponte do e-mail e WhatsApp
continuam vivos. Disco de 88% para 67%, sem apagar dados: caches, versões velhas de programas, logs
comprimidos, e 3,6 GB de ficheiros parados (medições antigas do trader e vídeos temporários) copiados
para a quarentena do PC com verificação, antes de saírem da VPS. Enviei o ramo da OmniRoute.
Erro meu pelo caminho: ao esvaziar o log do WhatsApp, o vigia dele achou que tinha caído e reiniciou-o
(25/10 23:46, mandou-te um alerta). Voltou a ligar num minuto. Esse log ficou fora da limpeza automática.

## Bloco 3 — Documentos de todos os papéis
O painel já tinha sido publicado por outra sessão a 25/10. Fiz isto: o prestador pendente (limpeza,
lavagem, motorista TVDE) vê na app o que falta e envia ali mesmo, como o estafeta. Para a limpeza criei
uma função nova no banco para o documento e os materiais. Capturas do painel do Valdemir (TVDE: carta,
operador, contrato, seguro, carro — tudo a vermelho "Falta", com "Pedir documentos em falta") e da Mayra
(limpeza: ficha completa com a foto do documento).
Erro encontrado (não corrigido, é regra de acesso): o lavador consegue mudar colunas da própria ficha
(aprovação, banimento, IBAN). Precisa de ser fechado numa missão de segurança.

## Bloco 4 — Restos
Enviei o ramo n3b (as guardas já estavam no banco). As lavagens: o cliente deixou de ler quanto o lavador
ganha e quanto fica para a Bora; o lavador deixou de ler a parte da Bora (nenhum valor mudou). "Não
compareceu" aparece certo, com cor própria, no painel e na app — e o cliente já não vê o botão Cancelar
nessa reserva (estava a aparecer). O robô do GitHub "olho-testlab-robo" foi desligado: testava o ramo
antigo main, parado desde 28/09, e falhava todos os dias por falta de memória. O ramo do e-mail dos
agentes já estava no servidor.

## Bloco 5 — Continente igual ao Glovo, só a subir
Fiz isto: o robô do PC leu os preços de hoje no Glovo da Guarda (3.714 produtos). 1.888 produtos do
Continente subiram para o preço do Glovo, subida média de 3,68% (cerca de 24 cêntimos ao cliente).
Nenhum desceu, nenhum ficou acima do Glovo, fotos intocadas, cópia de segurança feita. Erro meu e de
23/10: a conta do arredondamento deixava alguns 1 cêntimo acima do Glovo (118 do Continente e 1 do
McDonald's/BK) — corrigido. McDonald's: 30 produtos que já não existem no Glovo foram desativados (não
apagados). A ordem falava em 34; a sessão de 23/10 não deixou a lista, por isso usei a lista do Glovo
desse dia (os 30 nomes estão no e2e_log). Alguns são versões com nome novo no Glovo (ex.: McRoyal Bacon
virou Single/Double).

## Bloco 6 — Hermes a caçar clientes + Propostas diárias para o Emerson
O caçador já corre todos os dias úteis às 07:30 (sessão de 25/10): hoje encontrou 5 negócios novos com
e-mail verificado e o Emerson enviou o primeiro às 09:40 (clínica em Coimbra), e-mail limpo, com linha de
saída. A tarefa "Propostas diárias" foi desligada e tudo passou para o Emerson: 29 empresas contactadas e
18 leads na fila, sem repetidos; a MOYO nunca mais recebe nada; 23 empresas recebem hoje só o último
seguimento, na língua delas, com o link direto da demo, e depois pára. Se alguém responder, o Emerson
responde ao simples na língua do cliente e manda-te pelo Telegram o que for preço — só sai com o teu
"manda". WhatsApp ficou só em esqueleto (desligado).

## Bloco 7 — Reel do carro voador
Fiz isto: duas versões verticais, 15 s e 8 s, com uma carrinha de entregas a voar por cima da Sé da
Guarda, o logo real da Bora colado na lateral, a legenda "Na Guarda, as entregas já voam.", o aviso
"Imagens criadas com IA", um ecrã real da app parado 2,6 s e o fecho "Pede na app, recebe à porta" com
www.boraguarda.com/baixar. Revisto fotograma a fotograma em 3 voltas: nota final 85 (15 s) e 87 (8 s),
sem defeitos graves. Foram 3 vídeos no Flow (60 créditos). Mandei os dois ao teu Telegram; não publiquei.
Falta isto: o teu "ok". Repara na Sé: foi desenhada pela IA e pode não ser igual à verdadeira — se não a
reconheceres, refaz-se a partir de uma foto real.

## PARA O DANILO
1. Para o Emerson publicar demos novas no bora-demos: criar no Cloudflare da conta boraappbora um token
   com permissão "Cloudflare Pages: Edit" (dash.cloudflare.com → Perfil → API Tokens). Um passo.
2. O "Pedir documentos em falta" do painel para os motoristas TVDE (Valdemir e os outros) — um toque por
   motorista, quando quiseres que eles mandem a carta, contrato e seguro.
3. Para meter a própria VPS na Tailscale (para o trader e o QR do WhatsApp abrirem sem túnel) é preciso o
   teu login na Tailscale.

## Erros encontrados pelo caminho (reportados)
- Regra de acesso larga nos lavadores (bloco 3).
- 1 cêntimo acima do Glovo na paridade de 23/10 (corrigido no bloco 5).
- Reserva "não compareceu" com botão Cancelar visível ao cliente (corrigido no bloco 4).
- Carteiro podia mandar e-mails em dobro se dois envios corressem ao mesmo tempo (trava posta no bloco 6).
- A mensagem automática do WhatsApp ainda manda abrir o QR pela internet (já não abre: só por túnel).
