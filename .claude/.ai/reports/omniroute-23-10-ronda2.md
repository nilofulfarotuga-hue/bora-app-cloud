# Relatório da missão OmniRoute, segunda ronda — 23/10/2026

Acessos. Não criei nem usei conta nova nenhuma. Não mexi em dinheiro, preços nem comissões. Tirei a
chave do OpenCode Go de todo o lado onde estava a ser usada; as cópias de segurança dos ficheiros
mexidos ficaram na VPS em /root/backups e no PC ao lado de cada ficheiro.

O que não ficou feito, primeiro. Nada do que pediste ficou por fazer. Deixei de propósito, como
mandaste, os robôs do app que falam com o Gemini, o Motor Bora antigo (registei no Córtex o lembrete
para 30/10), o disco, a rede, a voz da Microsoft e o Cerebras; o estado de cada um está mais abaixo,
com prova. Há duas coisas que encontrei e não corrigi por não estarem na ordem: o Hermes principal ainda
tem na sua lista de recurso interna o OpenCode Go, que já não existe, e os modelos grátis do OpenCode
Zen chamados de fora do OpenCode; e a tua nota do Obsidian "Troca de motor em 1 minuto", de 30/08, já
não corresponde à realidade.

Fiz isto.

Primeiro, tirei o OpenCode Go do OmniRoute: apaguei a ligação, tirei-o de todos os grupos e das três
chaves das máquinas. A fila principal ficou pela ordem que pediste: Gemini, NVIDIA, OpenRouter, Groq,
Cloudflare e o Motor Bora no fim. O grupo da torre ficou igual, só com Cloudflare e Groq, que por
escrito não treinam com os dados. Testei cada nível sozinho, com uma ferramenta, e responderam todos.
Na prova de descida apanhei uma armadilha: com três níveis Gemini seguidos no topo, uma chave
estragada faz o Google responder com um erro que o OmniRoute toma por pedido mal feito, e ao terceiro
desiste em vez de descer. Corrigi pondo só dois Gemini seguidos. Depois estraguei de propósito as chaves
do Gemini e respondeu a NVIDIA; repus as chaves e o Gemini voltou.

Segundo, o OpenCode do PC. Tirei a chave Go do cofre dele e a ferramenta antiga que a tinha escrita no
ficheiro de configuração. Ficaram duas fontes. Uma são os modelos grátis do próprio OpenCode Zen, usados
dentro do OpenCode, como a OpenCode exige. A lista real, tirada hoje do próprio programa, tem nove: beam,
big-pickle, deepseek v4.1 flash, flint, glm 5.3 flash, mimo 2.6 flash e três nemotron; o hy3 já não
existe. Pus por defeito o glm 5.3 flash, que é dos que não treinam com o que recebem. A outra fonte é o
OmniRoute. O atalho SEM-LIMITE no Ambiente de Trabalho abre o OpenCode já com o modelo grátis, e o
OmniRoute escolhe-se lá dentro. Prova: o modelo grátis mudou uma linha num ficheiro de teste e eu desfiz;
o OmniRoute também respondeu.

Terceiro, o recurso do carteiro, para quando o Claude esgota. Antes ia ao portátil velho, que está
desligado há três dias, e punha o Claude Code a falar com o plano Go. Agora vai ao teu PC actual e corre
o OpenCode com ferramentas: primeiro pelo OmniRoute, depois pelo modelo grátis do Zen, e por fim o Hermes
na VPS. O Claude Code não foi tocado. Prova: simulei o Claude em baixo, o recurso assumiu e escreveu no
PC o ficheiro C:\BoraLocal\provas-cadeia-motores\PROVA-RECURSO-OMNIROUTE.txt com a palavra de controlo
VIVO-K7Q2-OMNIROUTE, que li depois no PC. O degrau do Zen respondeu sozinho também. O autoteste do
carteiro deu tudo certo.

Quarto, a ponte do Hermes ao PC. O nome bora-pc já apontava para o PC actual; o defeito era o script de
arranque correr o teste com o utilizador errado, que não vê essa configuração. Corrigi. Prova: o script
de arranque diz "PONTE OK" e o PC respondeu com o teu utilizador. A voz chegou-te por Telegram.

Quinto, as cópias por apagar. Confirmei que estão todas no servidor. A trava não deixa apagar pastas,
por isso movi-as para C:\BoraLocal\_to_delete\omniroute-23-10-copias-20261023, onde as podes apagar.
A pasta de trabalho C:\BoraLocal\wt-omniroute-23-10 tirei-a no fim, depois de guardar esta ronda no
servidor.

Sexto, o painel. O cartão OmniRoute do ecrã Motores já não mostra o Go: lê as ligações do próprio
OmniRoute e a do Go deixou de existir. Mostra sete vivos e os dois Cerebras desligados. Não foi preciso
mexer no código da app, por isso não houve nova versão para Android, iPhone nem site.

Estado do que mandaste só reportar, medido às 07h20 de Lisboa. O disco da VPS está a 88%, com 6 GB
livres; as imagens do Docker ocupam quase 12 GB. A proteção de rede da própria VPS está desligada, e do
teu PC, pela internet, respondem quatro portas: a do painel do Hermes, a do bora-trader, outra aplicação
e o serviço de impressoras; o OmniRoute e o Motor Bora não respondem de fora. A voz da Microsoft falha
sempre e a voz cai para a reserva, que funciona. O Cerebras responde "pagamento necessário" com as duas
chaves.

Erros que encontrei pelo caminho e não corrigi. O Hermes principal ainda tem, na lista de recurso dele,
o OpenCode Go e os modelos grátis do Zen chamados de fora do OpenCode; hoje isso só se usa se o
OmniRoute cair, e esses níveis já não respondem. A tua nota "Troca de motor em 1 minuto" no Obsidian
está desactualizada. O carteiro aceita qualquer resposta não vazia do recurso como trabalho feito: na
primeira tentativa devolveu um erro e ele disse que tinha assumido; quem apanha isso é o juiz.

Próximo passo: a 30/10, se o OmniRoute estiver estável, desligar o Motor Bora e passar os outros 18
agentes para o OmniRoute (o lembrete está no Córtex).

## Registo técnico

e2e_log, fluxo omniroute-23-10, passos r2-*. Córtex, caixa hermes-reporte: ref-0f896f, ref-6afc4a,
ref-ef2cb5, ref-281e04 e o lembrete ref-c3b865. Correcção à ref-ef2cb5: o executor normal do carteiro
(pc-loop-novo) e o juiz (pc-judge-novo) já usavam o caminho real no PC; só o recurso (pc-loop-go)
estava preso ao portátil velho e à junção. Scripts: ferramentas/omniroute/ e
.claude/.ai/hermes/orquestrador-carteiro/deploy/ (carteiro.sh, bora-bridge-up.sh, pc-loop-go,
run-opencode-recurso.ps1).
