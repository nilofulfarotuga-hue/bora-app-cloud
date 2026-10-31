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

## Próximo passo

Publicar o decidir e o robot-b do motor Claude quando quiseres que os robôs usem primeiro o crédito do
Claude. E, quando decidires, autorizar os valores da Casa no painel e ligá-la.

---

Detalhe para os agentes (não é para ler em voz alta):
- Partes aplicadas por `supabase db query --linked -f` (CLI 2.122), registo no mesmo envio:
  20261031200358 casa_04_profissional_e_tarefas, 20261031200444 casa_05_admin,
  20261031200511 motor_claude_porteiro, 20261031200533 decisoes_motor_claude, 20261031200546 porteiro_entrada.
- notify-admin-urgent v22 (verify_jwt=true): ping net 89758 = 200 pong; INFO net 89759 = 200,
  push_attempted 0; porteiro_entrada id 1 destino=registo.
- Commits: 47a06da9 (junta chaves + v22), 6b41d8e2 (junta origin), e91b1d22 (17 migrações). Push
  a7de18a4..e91b1d22. Juiz anti_trapaca CLEAN; 0 Dart mudado desde 82896eaf (analyze/test em e2e_log 5692).
