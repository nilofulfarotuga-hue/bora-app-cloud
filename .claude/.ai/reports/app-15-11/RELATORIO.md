# Missão 7 app-15-11 — relatório

Claude Code no PC, Opus 5.5, 15/11/2026 das 10:17 em diante. Ordem do Danilo de 10:14-10:15,
chegada pela Claude.ai (texto na caixa_guardados 23). Sem Chrome nesta sessão. Memória livre do
PC entre 406 e 1250 MB: um ajudante de cada vez, sem Flutter local (os testes correm no CI).
Registo passo a passo no e2e_log, fluxo app-15-11 (ids 9104 em diante).

## Fiz isto

Ecrã do estafeta. No separador Pedidos a lista de entregas tem agora os botões Hoje, Esta
semana, Semana passada e Este mês, abre e fecha ao tocar no total, e mostra em número grande
quanto ele ganhou no período e quantas entregas fez. Conta pela hora da entrega, como a Uber e a
Glovo, e abre na semana. O valor que o cliente pagou só aparece, pequeno, nos pedidos a dinheiro.
No Início saiu o que estava repetido: a etiqueta Online de cima (o cartão de baixo já o diz), o
cartão do veículo (está no Perfil), a lista de entregas feitas (agora vive em Pedidos) e o segundo
botão de ligar ao cliente. O cartão "Ganhos de hoje" leva ao separador Ganhos em vez de abrir outro
ecrã por cima. Textos acertados: Estado em vez de Status, Recusar em vez de Rejeitar, o número de
tokens com a palavra tokens, sem a referência interna "BR 5.2" no aviso de ajuda. No painel admin,
na ficha do estafeta, os pedidos têm o mesmo seletor de período e o total, e ainda "Últimos 50".
Não mexi no toque de chamada, no botão Online, na compra nem no talão.

Farmácias. Revi os quatro lados. No app: a confirmação de receita que o servidor recusa fica à
vista a dizer para ir levantar à farmácia; em demonstração já não aparece pagamento nem código
"para o estafeta"; acabaram as rodas que nunca paravam e o erro que parecia "ainda não fez
pedidos"; a autorização volta a tentar; o painel mostra horas de Lisboa e o interruptor de
receitas reais diz a verdade (ainda não faz nada no servidor).

Robôs. Descobri que a base que o robô do suporte pesquisa só tem notas internas de maio
(auditorias de dinheiro, contactos da equipa, zonas protegidas) e que a pesquisa não filtra nada.
A ajuda nova (31 trechos) está pronta, corrigida (reservas: descontam 2 euros, não 3) e o robô
passa a assinar "Equipa Bora" e a tratar o nome só pelo suporte. A lista de prova (30 perguntas
reais e 10 armadilhas) está escrita.

## Falta isto (e porquê)

A tranca não me deixou publicar: enviar o ramo, a migração que deixa a tabela aceitar texto de
ajuda, inserir a ajuda, a proposta 8e e o robô novo. Está tudo no e2e_log como
pronto-para-claude-ai, por esta ordem (9123, 9124, 9128, 9129). As farmácias têm cinco coisas de
servidor por decidir antes de abrirem ao público (9127). A pesquisa no livro e no Córtex para os
robôs (A3) precisa de uma função nova no servidor e não foi feita.

## Erros que encontrei pelo caminho

A skill parceiro-servicos diz que a reserva reparte 0,50 e 2,50 euros; o livro e o servidor dizem
1 e 2 (9120). O cartão de oferta do estafeta mostra o ganho três vezes e a janela "Novo pedido"
repete a oferta por cima do cartão; não mexi porque é o fluxo do toque (9115).

## Depois das 10:48 (ordens da Claude.ai)

O ramo foi para o GitHub: a tranca deixa enviar sozinha para ramos de ensaio, desde que o comando
vá limpo (o meu primeiro envio levava um corte da saída e foi recusado; erro meu, já conhecido).
O pedido de revisão é o #19. Os textos que a Claude.ai pediu para aplicar estão nas caixas 25 a 33,
cada uma com o link fixo do ficheiro no GitHub e a impressão digital, porque a tranca não deixa pôr
texto de migração dentro da caixa. O ganho da oferta do estafeta passou a aparecer uma vez só, em
número grande (aprovado). As farmácias têm a proposta de servidor pronta e, no app, o botão
"Marcar como levantado" nos pedidos de demonstração e o "Pedir outra vez" do lembrete mensal.

A montagem do iPhone que falhou três vezes a 14/11 caiu sempre num só teste, que o próprio ramo do
fechar-app consertou a seguir; as corridas seguintes passaram. No meu ramo, a corrida #278 deu 3
testes falhados: achei e corrigi dois (um teste da farmácia que acompanha a regra nova e uma frase
da manhã sem inglês); o terceiro não o encontrei por leitura e a corrida seguinte dirá.

A varredura do cliente e do parceiro achou 24 defeitos. Já corrigidos os piores: o parceiro que
ficava preso no ecrã de entrada, o erro de rede que mandava um parceiro aprovado criar outra loja,
os erros técnicos mostrados ao parceiro, o "CARD/MBWAY/CASH" e o saldo da carteira em formato
inglês. Os restantes (dinheiro com ponto, datas no fuso do telemóvel, frases do Brasil) estão a ser
feitos por um ajudante e passam pela minha revisão antes de gravar.

Correção minha: escrevi no registo que nenhum teste corria nos pedidos de revisão; corre, na
montagem do iPhone (corrigido em 9142). E o alerta do repositório público era decisão conhecida
(fica público para o CI ser grátis).

## Depois das 11:55 (bloco da Claude.ai, letras A a F, e o inventário)

A. Os testes do pedido #19. As três falhas eram minhas ou da manhã: um teste da farmácia, uma frase
sem inglês, um teste do histórico do estafeta que ficou sem espaço no ecrã de teste, e uma nota no
código com uma palavra que o meu próprio teste proíbe. As duas últimas foram achadas pelo Juiz.
Está tudo corrigido; a montagem do iPhone com tudo dentro está a correr.

B. Os erros de código da varredura da manhã: o estafeta novo já não fica preso em "candidatura
enviada", a palavra-passe fraca explica-se em português, o "Partilhar" do iPhone já não fecha a
app, os textos do Brasil saíram, o painel web já não rebenta sem Firebase, o visitante deixou de
fazer cerca de 440 pedidos por dia que o servidor recusava, o diálogo do código de entrega já não
rebenta e o botão Cancelar só aparece quando o servidor deixa cancelar.

C. Servidor, só propostas, cada uma na caixa com o link fixo: as 7 migrações do fechar-app pela
ordem (caixas 39 a 45), o pg_cron em lotes (46 e 47; a parte de despacho e dinheiro só com ordem),
os achados repetidos do vigia de pagamentos e o seu alarme falso (48 e 49), o "Aprovar N" das
sugestões com a guarda certa (50), a página pública de apagar conta e o erro das limpezas na
função de apagar conta (51).

D. Dinheiro: só relatório, sem mexer (29 cancelamentos a dinheiro em "pendente", 5 achados
críticos antigos, 8 pagamentos a prestadores parados, 142,96 €, e 2 limpezas a dinheiro presas).

E. Inventário das duas semanas na caixa 38 (15 no ar, 10 por publicar, 29 por fazer).

F. O robô do talão já estava corrigido no código; falta só publicar a função (caixa 52). A
pesquisa dentro das lojas já tinha sido feita e provada a 09/11.

Juntei também o trabalho dos robôs que a sessão da manhã fez ao mesmo tempo, para os dois pedidos
de revisão não chocarem: basta juntar o #19. O Juiz aprovou com consertos, que estão feitos, e
confirmou que nenhuma zona protegida foi tocada.

Do inventário, comecei as "Conversas ao vivo" dos robôs (pedido do Danilo de 12/11): a proposta de
servidor está na caixa 55, o Amigo Bora já se cala quando a equipa assume, e os ecrãs do painel e
do cliente estão a ser feitos.

## Depois das 12:58: o painel admin (Missão 9) e "fechar tudo" (Missão 10)

Fiz isto. Seis ajudantes revistaram o painel área a área, só a ler, e eu confirmei os achados maiores
no servidor. O maior: o painel não tinha licença para ler os pedidos, os saldos e os tickets de
ninguém a não ser da própria conta, por isso a lista de Pedidos, a ficha do pedido e a ficha do
estafeta mostravam quase nada. Propus a regra de leitura e a Claude.ai aplicou-a. O mapa ao vivo
mostrava 3 estafetas quando eram 2, porque um aparecia repetido; ficou certo. A ficha do estafeta
passou a procurar pelos dois números de cada estafeta (17 dos 22 têm dois), o "Editar dados" deixou
de dar erro e o "Remover" confere primeiro se ele tem pedidos a meio. Fiz a Área do entregador e a
Área do parceiro: o admin escolhe uma pessoa ou uma loja e faz por ela o que ela faz na app, com o
motivo de cada coisa guardado. O sino conta só os avisos que pedem ação, a pesquisa de telas ignora
acentos, os erros técnicos passaram a frases em português do Brasil, e cada tela aberta pelo menu
diz em baixo "Para que serve"; o Refinador reescreveu 99 dessas frases. Nas apps confirmei que os
erros graves da manhã estão corrigidos e passei os textos que ainda eram do Brasil para português de
Portugal. Fiz a categoria Loja Online, desligada até ser ligada no painel e ainda sem pagamentos.
Fiz a prova das 40 perguntas ao robô do suporte publicado: respondeu a todas e recusou as 10
armadilhas sem deixar escapar nada. Corrigi o robô do talão (depósitos e preços como estão
impressos), refiz o cancelamento e o webhook do Stripe sobre as versões das duas contas que estão no
ar, e fiz a devolução dos 3 euros quando a loja recusa uma reserva paga. Alinhei as migrações do
repositório com o que correu no servidor.

Falta isto. Publicar nas 3 lojas, autorizado pelo Danilo: espero a montagem do iPhone com os testes
verdes no último commit (a corrida 308 deu 2 testes vermelhos, já corrigidos no commit 6d01cd0c).
No servidor ainda por publicar: o cancelamento (client-cancel-order) sobre a v40, a admin-sync-user-name,
a delete-account, a devolução dos 3 euros e a nova admin-cancel-reservation. O "Sair a sério" do
estafeta fica para a Edge pela via oficial do Auth.

Erros que encontrei. Um cliente podia mudar os campos do pagamento da própria reserva; a Claude.ai já
pôs um gatilho a impedir. A confirmação do pagamento de reservas falha sempre por usar uma coluna que
não existe (correção a caminho). O alarme de "qualquer conta escreve na auditoria" era falso. Erro
meu: pus a Loja Online no meio de duas entradas do menu que um teste quer juntas (corrigido antes do
CI) e juntei o envio a um commit num comando (a tranca bloqueou, repeti em separado).

## Próximo passo

Com a montagem do iPhone verde no último commit, envio o #19 para o ramo de produção (a bora-tranca
pergunta no ecrã do PC e o Danilo carrega em Permitir) e provo as 3 lojas com a versão no ar.
