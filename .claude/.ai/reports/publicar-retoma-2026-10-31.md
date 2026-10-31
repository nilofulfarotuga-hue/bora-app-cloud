# Publicar a retoma — 31/10/2026

Missão publicar-retoma-2026-10-31, Claude Code no PC (Opus 5.5). Autorização do Danilo no chat da
Claude.ai a 31/10 às 19:53: "Eu autorizo de 1 a 8". Esta sessão fez os itens 2, 3 e 4. Registo passo
a passo no e2e_log, fluxo publicar-retoma-2026-10-31.

## Fiz isto

Apliquei na base as cinco partes que estavam à espera desde o meio-dia, a partir do ficheiro, uma a
uma e pela ordem: as funções do profissional da Casa e as tarefas automáticas, o painel de admin da
Casa, o contador do crédito do Claude, a decisão que passa a aceitar o Claude como motor, e a fila de
entrada do porteiro do Telegram. Cada uma ficou registada na lista de migrações no mesmo envio (ou
entra tudo, ou nada) e foi provada por consulta: todas as funções existem, nenhuma fica aberta a quem
não tem conta, os dois baldes de ficheiros novos da Casa são privados, as funções de admin só abrem
para o admin, e a Casa continua desligada para os clientes.

Depois publiquei o aviso de alertas do admin (notify-admin-urgent, versão 22). Parti da versão que
estava no ar desde as 13:02 e juntei por cima a mudança do porteiro, sem perder nada. Acrescentei uma
coisa pequena que faltava para o teste pedido: o aviso pode vir marcado como informação, e aí não toca
no telemóvel nem vai ao teu chat, fica só nos bastidores do porteiro. Sem essa marca tudo continua como
antes, urgente. Os testes passaram todos (41 de 41). Provas: o ping respondeu pong; o aviso de teste de
informação foi tratado pelo porteiro em 5 segundos e ficou no registo, sem mensagem no Telegram; e de
fora, sem chave ou com chave falsa, a porta recusa.

Por fim enviei o código para o servidor: juntei o trabalho da sessão das chaves, guardei no repo as 17
migrações que hoje só existiam no banco (as da Claude.ai, incluindo a correção do create_order, e as
cinco de cima), e o envio levou a marca para não criar versão nova nas lojas. Confirmei que nenhuma
compilação arrancou.

## Falta isto

A função decidir e o robot-b com o Claude primeiro (missão motor-claude) estão no código mas não foram
publicados: o que está no ar é a versão das chaves. Não estava pedido nesta missão. A Casa está pronta
no servidor mas desligada; ligar é decisão tua, depois de autorizares os valores no painel. A versão
nova das apps nas lojas fica para quando quiseres publicar, porque este envio não a criou.

## Erros que encontrei

Primeiro: o varredor das chaves ainda aponta três funções de zona protegida (dispatch-engine,
finalize-order-from-intent e refund) que leem o papel da chave à mão. As propostas de correção já estão
em docs/propostas/chaves-2026-10-31; não mexi, porque é zona protegida. Segundo: a mudança das taxas do
Divan não aparece na lista de migrações de hoje, por isso não pôde ser copiada para o repo (deve ter
sido feita como correção de dados). Terceiro: a pasta principal do Bora no PC tem três gravações locais
que não estão no servidor, os dois commits órfãos dos documentos de 25/10 e o do livro comum
(bdfbf1d6); não mexi, porque essa pasta tem trabalho de outras sessões por gravar. Quarto: a tranca
recusou apagar uma pasta temporária minha; não era preciso, segui sem apagar.

## Depois do teu "Sim, publica" (20:19)

Publiquei o decidir e o robot-b com o Claude primeiro. Parti da versão que estava no ar e juntei só a
mudança do motor Claude, sem perder nada. Provas: lidas de volta iguais ao que publiquei; de fora, sem
chave, a porta recusa; o ping respondeu pong; uma decisão de teste respondeu bem sem gravar nada; as
decisões automáticas de 30 em 30 segundos continuam a correr; e uma volta de ensaio do robot-b correu
sem escrever nada.

Mas atenção: o Claude ainda não está a ser usado, porque ainda não existe a chave da API do Claude. De
manhã, criar o espaço "Robos Bora" na consola do Claude foi recusado pelo sistema e ficou à espera de um
clique teu. Sem a chave, as duas funções seguem pelo Gemini como antes; quando a chave existir, passam
ao Claude sozinhas, sem publicar de novo.

Achei mais dois problemas, que não corrigi. O robot-b está a bater no limite grátis do Gemini (erro 429
às 19:07 e agora; às 20:07 foi um 503), por isso o diagnóstico dele sai vazio; a chave do Claude
resolve isto. E várias tarefas agendadas da base falharam hoje com "connection failed" às 12:00, 13:00,
15:30 e 18:00 (pedidos agendados dos não parceiros, ofertas da lavagem, pedidos órfãos, créditos TVDE,
relógio das encomendas por telefone, conferência de cobranças, lembretes da limpeza). Correram bem
noutras horas, mas merece ser visto.

O chat de ajuda e o assistente do painel também têm a mudança do motor Claude no código e continuam por
publicar; não estavam no teu "sim", e o assistente do painel tem a versão 13 da Claude.ai, que não se
mexe.

## As chaves do Claude (21:30 a 21:45)

Criaste o espaço "Robos Bora" e duas chaves nele, válidas até 31/01/2027: a "robos-vps", que ficou na
VPS para o motor dos robôs, e a "app-supabase", que ficou nos segredos das funções do servidor (com uma
cópia guardada na VPS). As duas são diferentes e nenhuma foi escrita em ficheiro do repositório. Provas:
o porteiro da VPS diz que tem chave; o decidir respondeu pelo Claude (Sonnet) em modo automático; o
robot-b fez o diagnóstico pelo Claude (Haiku) e deixou de dar o erro de quota do Gemini; os três pedidos
ficaram no livro de gastos, cerca de 0,0016 dólares ao todo.

Pelo caminho corrigi o vigia: a consola nova dá chaves que começam por "sk-ant-usr" e ele só conhecia
"sk-ant-api"; o teste passou a usar o mínimo de 1024 tokens que as funções usam; e só apaga a área de
transferência quando a chave é mesmo recusada, para não perder uma chave boa por um erro do pedido.

Um erro meu: uma captura de ecrã apanhou a janela da chave "robos-vps" ainda aberta. Não a escrevi em
lado nenhum, mas a imagem ficou numa pasta interna do Claude Code no teu PC. Pela regra da casa ("chave
exposta, chave trocada"), proponho trocar essa chave.

## A troca da chave da VPS (21:47 a 21:52)

Criaste a "robos-vps-2", que já está na VPS: testada, motor dos robôs ativo e com chave, e confirmei
pela impressão digital que a chave em uso mudou. Apaguei a "robos-vps" antiga na consola. A chave das
funções do servidor ("app-supabase") não mexeu e nunca apareceu em captura nenhuma.

Correram mal duas coisas. Carregaste em "Criar chave" enquanto eu ainda estava a preencher, por isso a
"robos-vps-2" ficou com a validade que vinha por omissão, até 30/11/2026, e não até 31/01/2027. E a
minha captura seguinte voltou a apanhar a janela com a chave nova à vista: o mesmo erro da primeira vez.
Já deixei escrita a regra para não se repetir: o formulário fica todo pronto antes de to pôr à frente,
digo-te "pronto" só no fim, e não olho para o ecrã até carregares em "Concluído".

Depois disseste que a validade tinha de mudar (eu primeiro li ao contrário e corrigi). Como a consola
não muda a validade de uma chave que já existe, criaste a "robos-vps-3", que está agora na VPS (testada,
impressão digital nova, motor dos robôs com chave), e eu apaguei a "robos-vps-2". Esta nunca apareceu em
captura nenhuma. Mas saiu sem data de fim, e não até 31/01/2027 como o formulário mostrava: o campo da
data não gravou o que lá escrevi.

## Próximo passo

Quando decidires, autorizar os valores da Casa no painel e ligá-la. Este relatório ficou gravado só no
PC: a tranca recusou o envio para o servidor (o push não estava autorizado).

---

Detalhe para os agentes (não é para ler em voz alta):
- Partes aplicadas por `supabase db query --linked -f` (CLI 2.122), registo no mesmo envio:
  20261031200358 casa_04_profissional_e_tarefas, 20261031200444 casa_05_admin,
  20261031200511 motor_claude_porteiro, 20261031200533 decisoes_motor_claude, 20261031200546 porteiro_entrada.
- notify-admin-urgent v22 (verify_jwt=true): ping net 89758 = 200 pong; INFO net 89759 = 200,
  push_attempted 0; porteiro_entrada id 1 destino=registo.
- Commits: 47a06da9 (junta chaves + v22), 6b41d8e2 (junta origin), e91b1d22 (17 migrações). Push
  a7de18a4..e91b1d22. Juiz anti_trapaca CLEAN; 0 Dart mudado desde 82896eaf (analyze/test em e2e_log 5692).
