---
tema: fecho-semanal-automatico
data: 2026-09-07
sessao: fecho-semanal-automatico
estado: atual
---

# O fecho da semana passou a andar sozinho

## O que se passava antes

Havia um fecho semanal montado desde junho, e nunca saiu um único email dele. A causa
não era o código: era que as Edge Functions nunca tiveram a chave do Resend. Dezanove
variáveis de ambiente, nenhuma de email. Todas as segundas-feiras o sistema calculava
os acertos, escrevia "falhou" numa coluna, e o Danilo acabava por mandar os recibos à
mão pelo Gmail.

Havia mais três coisas partidas por baixo dessa. O aviso do fecho apontava para uma
morada que não existia na aplicação, por isso tocar na notificação não abria nada. A
lavagem auto fechava a semana numa tabela própria e ninguém a ia buscar, portanto o
lavador nunca recebia recibo e o valor não aparecia no resumo. E quando o Danilo
marcava "pago", a outra pessoa não ficava a saber de nada.

## O que ficou a funcionar, com prova

### A chave do Resend, que era o nó

O domínio boraguarda.com já estava verificado no Resend, portanto não foi preciso
mexer no Cloudflare. Criou-se a chave bora-fecho-semanal com permissão só de envio,
limitada a esse domínio.

A chave nunca passou por ficheiro, por registo nem por conversa. Criou-se uma função
de escrita fechada ao papel de servidor, copiou-se a chave do navegador para a área de
transferência e mandou-se dali directamente para o cofre da base de dados, num só
comando. A leitura de volta confirma: trinta e seis caracteres, começa por "re_",
gravada às 23:53 de 6 de setembro. A área de transferência foi limpa a seguir.

Não foi possível pôr a chave também nas variáveis de ambiente das Edge Functions:
este PC não tem a linha de comandos do Supabase instalada nem um token de gestão do
projeto. Não faz falta — a função já sabe procurar no cofre quando o ambiente não tem.
Fica escrito para quem vier a seguir.

A prova de que funciona não é a chave estar lá. É o envio. Chamou-se a função do fecho
para a semana de 23 a 30 de agosto e a resposta veio com a chave presente, origem
"cofre", um email enviado e o resumo ao administrador enviado. Os dois emails chegaram
mesmo à caixa boraappbora@gmail.com, às 00:53.

Como o domínio ficou verificado, confirmou-se também o servidor de correio da
autenticação: já estava ligado, com remetente nao-responder@boraguarda.com. Provou-se
com um pedido de recuperação de palavra-passe real, que chegou à caixa às 00:55. Ou
seja, o "esqueci-me da palavra-passe" passa a sair para toda a gente, e não só em
teoria.

### Tocar no aviso abre o ecrã certo, na semana certa

O ecrã "Acertos da semana" existia e estava ligado ao painel, mas ninguém lhe tinha
dado morada dentro da aplicação. O aviso mandava para /admin/acertos-semana e essa
morada não estava registada. Ficou registada, e ficou a receber a semana como
argumento: o aviso traz consigo a semana a que diz respeito, e o ecrã abre já nessa
semana em vez de abrir sempre na última.

O gancho que faz a navegação ficou ao nível da aplicação, no arranque, e não dentro de
um ecrã. É a lição de 20 de agosto com o "A caminho" da reserva, que estava preso ao
arranque de um ecrã e ficava vazio assim que outro ecrã lhe passasse por cima. Os três
caminhos estão cobertos: aplicação fechada, aplicação em segundo plano, e aplicação
aberta noutro ecrã.

Passou a haver um aviso só. Antes chegavam dois por cada fecho: um às 00:05 sem valores
nenhuns e a apontar para o ecrã antigo, outro às 00:20 com os valores. Dois avisos, um
deles inútil, só ensinam a pessoa a ignorar o aviso. Ficou o das 00:20, que é o que
traz "A PAGAR" e "A RECEBER" escritos no corpo.

### O ecrã do painel

O ecrã passou a mostrar três totais em cima — quanto a Bora paga, quanto a Bora recebe,
e o saldo — para o Danilo não ter de somar linhas de cabeça. Passou a ver as cinco
verticais, incluindo a lavagem que faltava. Cada linha tem o nome, o tipo de trabalho,
o valor, o sentido, o MB Way, o estado do pagamento, o estado do recibo e o estado do
comprovativo, e abre para mostrar a discriminação parcela a parcela.

Em quem a Bora paga há um botão que copia o MB Way e diz para colar. Não existe uma
maneira universal de abrir a aplicação MB Way a partir de outra, por isso o que conta
mesmo é a cópia; a tentativa de abrir a aplicação está lá e nunca trava o resto.

Marcar é um toque, sem caixa de confirmação. Quem marca dezenas destes não quer um
toque a mais em cada um. O engano desfaz-se na própria linha, com o botão Desfazer, e
tudo fica registado em auditoria.

Havia três cartões diferentes no painel a falar do mesmo dinheiro. Dois deles abriam
ecrãs diferentes sobre a mesma semana, e abria-se o velho. Ficou um só, com o contador
de pendentes. O terceiro, "Fechamento Semanal — Estafetas", faz outra coisa (processar
MB Way) e ficou onde estava.

### "Pago" e "recebido" deixaram de ser a mesma coisa

São opostos. Um é a Bora a pagar; o outro é a pessoa a pagar à Bora. Até agora o painel
só sabia escrever "pago" nos dois casos, o que faz o histórico mentir sobre quem devia
a quem.

Agora o estado é validado pela direcção do acerto: quem tem a receber só pode ficar
"pago", quem deve só pode ficar "recebido", e quem está a zero não se marca. Está
provado nos dois sentidos, com sessão de administrador real: tentar marcar "pago" a
quem deve é recusado com a mensagem "esta pessoa e que paga a Bora — o estado tem de
ser recebido", e marcar "recebido" passa e devolve uma linha alterada.

A tabela da lavagem auto nem sequer admitia o estado "recebido" — só pending, paid e
cancelled. Foi alargada.

### O comprovativo sai sozinho

Quando o estado muda para pago ou recebido, um gatilho põe uma linha numa fila e acorda
uma Edge Function nova, a settlement-receipt, que manda o comprovativo. A fila tem
chave única por pessoa, semana e tipo de movimento, portanto a mesma mudança de estado
nunca gera dois comprovativos. Se o envio falhar, fica na fila e uma tarefa agendada
tenta de novo de quinze em quinze minutos, até seis vezes; ao fim disso o Danilo é
avisado de quem ficou por receber.

Está provado ponta a ponta. Marcou-se "recebido" o acerto de teste da semana de 23 de
agosto e, sem mais nada, o comprovativo saiu: estado "enviado", uma tentativa, sem
erro, às 00:14:36. O email chegou à caixa às 01:14, com o remetente fecho@boraguarda.com,
o valor de 11,12 euros, a data, a referência "fecho 23/08" e o MB Way da Bora escrito.
Os acentos saíram todos direitos.

### A cobrança de quem deve

Uma tarefa agendada corre de hora a hora e só age no dia e hora configurados, para o
Danilo poder mudar o dia no painel sem ninguém mexer no agendamento. Por defeito, às
dez horas de quarta e de sexta. Quem ficou a dever recebe email e aviso no telemóvel, e
o Danilo recebe uma mensagem só com a lista dos atrasados, nome, valor e telefone.

A guarda está provada: às 01h de segunda-feira, com os lembretes configurados para as
10h de quarta e sexta, a função responde "fora da hora" e não envia coisa nenhuma.

Não se disparou nenhum lembrete real de propósito. Ver a secção de avisos no fim.

### O fecho passou a ser um só, e correu hoje

Havia quatro tarefas agendadas a correr todas às 00:05 de segunda-feira, sem ordem
garantida entre elas: uma para estafetas e parceiros, e três soltas para limpeza,
serviços e lavagem. Agora há uma só entrada, que chama as cinco por ordem, cada uma
protegida para que uma falhar não deixe as outras por fazer. As três soltas ficaram
desligadas, não apagadas, para se poder voltar atrás num comando.

Isto não é teoria: correu hoje, sozinho, com o código novo. O fecho às 00:05 e o resumo
às 00:20, ambos com sucesso. O aviso que ficou na caixa do painel aponta agora para
/admin/acertos-semana e conta as cinco verticais, quando nas semanas de 24 e de 31 de
agosto apontava para o ecrã antigo e só contava duas.

E aguentou a parte que mais me preocupava: a semana de 31 de agosto a 6 de setembro já
estava fechada e paga à mão. O fecho de hoje não lhe mexeu nos estados e o resumo não
reenviou um único recibo — a hora de envio continua a de ontem, 23:25. A idempotência
funcionou na vida real, não só no papel.

### O outro lado vê na aplicação

O estafeta que fica a dever via "vais pagar via MBWay segunda-feira" e não via para que
número. Tinha de perguntar. Agora vê o número da Bora, com um botão para o copiar. O
histórico deixou de dizer "PAID" e "RECEIVED" em maiúsculas e passa a dizer "Pago pela
Bora em dd/mm" ou "Recebido pela Bora em dd/mm", que é o que a pessoa precisa de saber.

O parceiro tinha o mesmo buraco: lia "a entregar à Bora" sem número nenhum. Passa a ver
para onde pagar.

O número vem de uma função nova e estreita, feita só para isso, e não da função geral
de definições. Ver a secção de avisos.

## O que ficou por fazer, e porquê

**A prévia da semana em curso.** Está escrita e testada no papel, mas não aplicada. A
Trava recusa qualquer alteração cujo texto mencione uma função de dinheiro, e não
distingue chamar de alterar — e a prévia chama as funções de cálculo, sempre em modo de
leitura, sem gravar nada. A lei da casa diz que isto não se contorna: fica a proposta
escrita em supabase/migrations/PROPOSTA_20260907_previa_da_semana_em_curso.sql e o
Danilo aplica quando quiser. Risco baixo, é leitura pura.

**O transporte da dívida para a semana seguinte.** Está escrito, com modo de ensaio que
mostra o que faria sem gravar, mas não aplicado. Isto altera valores devidos a pessoas
reais, portanto é da lista vermelha. O interruptor já existe em produção e está
desligado; mesmo depois de aplicar o ficheiro, nada acontece até esse interruptor ser
ligado no painel. São dois passos de propósito. Ficheiro em
supabase/migrations/PROPOSTA_20260907_divida_transporta_para_a_semana_seguinte.sql.

**O bloqueio de quem deve acima de um tecto.** A marca e o cálculo ficaram feitos, com
uma tarefa agendada semanal que os actualiza, e o tecto configura-se no painel. Está a
zero, ou seja, desligado. O que NÃO se fez foi ligar isso ao motor de despacho: o motor
é zona protegida e a ordem dizia expressamente para não lhe tocar. Fica a marca pronta e
a ligação por fazer, com ordem própria.

**Abrir o ecrã de ganhos ao tocar no comprovativo.** O aviso de comprovativo aparece
correctamente no telemóvel, mas o toque só traz a aplicação à frente. Abrir o ecrã certo
exigia inventar navegação por papel que não existe hoje, e o canal principal deste aviso
é o email, que está provado. Ficou de fora em vez de ser inventado.

## Avisos que valem a pena ler

**Há um estafeta com dívida real que os lembretes vão apanhar na quarta.** O Valdemir
tem oitenta cêntimos por acertar de uma semana de 9 de agosto, com vinte e dois dias de
atraso. Na quarta-feira às dez horas ele recebe um email automático a cobrar oitenta
cêntimos. Não disparei nada agora de propósito — mandar uma cobrança a uma pessoa real
não é decisão minha. Se quiseres, marca-se essa linha como recebida e o assunto morre.

**A função geral de definições está aberta a qualquer utilizador.** A get_setting pode
ser chamada por qualquer conta autenticada, e até por quem não tem sessão, e devolve
qualquer chave de platform_settings — incluindo as da Stripe, das comissões e dos
preços. É zona sensível e não lhe toquei. Por isso mesmo, o número de MB Way que as
aplicações passam a ler vem de uma função nova e estreita, feita só para devolver esse
número, e não da geral.

**A versão que está no ar do resumo semanal perdeu uma protecção que o repositório
tinha.** O repositório tinha, desde a versão 4, uma verificação de endereços mortos:
apanha endereços como teste@ ou noreply@ em fornecedores grandes, e domínios .test ou
example.com. Nasceu de uma cicatriz de 6 de setembro, em que sete de quinze envios
foram devolvidos e um endereço acabou na lista negra da Resend. As versões 5 e 6 foram
publicadas a partir de outro sítio e deitaram-na fora sem ninguém dar por isso. O
repositório fica agora com a versão 7, que é a 6 mais essa protecção de volta, mas NÃO
se publicou: a ordem dizia para nunca publicar o ficheiro do repositório por cima, e
medi que hoje não há um único endereço de risco na tabela, portanto não é urgente. Sobe
com um comando quando quiseres.

**O ecrã antigo dos fechos semanais ficou sem ninguém a chamá-lo.** O ficheiro
lib/screens/admin/admin_weekly_settlements_screen.dart deixou de ser usado por qualquer
rota ou cartão. Não o apaguei, porque apagar não estava na ordem e o ecrã tem código que
pode ter valor. Fica assinalado.

**A conta que recebe os emails do fecho não é a conta de administrador.** Os emails vão
para boraappbora@gmail.com, mas quem o painel reconhece como administrador é a
nilofulfarotuga@gmail.com. Não é um erro, são caixas diferentes, mas convém saber-se.
A lista de administradores está cravada no código da função is_admin, por email.

**A junção que descobre quem é a pessoa por trás do acerto continua ambígua.** Na
compilação do fecho, a linha do estafeta casa por identificador da linha OU por
identificador da pessoa. É a cicatriz da identidade do padrão da casa. Não lhe mexi
porque está a funcionar e mexer nisso é mexer em quem recebe o quê; mas para o
comprovativo e para o aviso criei uma função única que resolve isso num só sítio, para
não se voltar a resolver a olho.

## Estado das verificações

A análise estática da pasta lib corre com zero erros. Os testes correm todos: 473
passaram, saída zero. Não se tocou no versionCode, que é o CI que trata. Não se tocou
em nenhuma fórmula de dinheiro: as funções de cálculo estão exactamente como estavam,
e o que mudou foi estado, comunicação, automação e ecrã.

O trabalho foi para o repositório no commit a7c545d3, com vinte e sete ficheiros, todos
acrescentados por caminho explícito. Não havia nenhum commit local à espera, portanto
não foi nada à boleia. As catorze alterações à base de dados que tinham sido aplicadas
directamente foram trazidas de volta para ficheiros no repositório, para a história ficar
onde se lê. O olho-golden passou; o build Android e o deploy web arrancaram.

## A prova que ficou por fazer, e porquê

Faltou o retrato do ecrã já preenchido com a lista da semana. Para isso era preciso
sessão de administrador na aplicação, e a palavra-passe que foi tentada não passa: o
servidor de autenticação respondeu 400 ao pedido de entrada. Não é do código desta
missão — é credencial. E tem solução à mão, precisamente por causa do que se destrancou
hoje: o "Esqueci-me da palavra-passe" passou a funcionar de manhã, com prova.

O que está provado sobre esse ecrã, sem depender da sessão: a morada
/admin/acertos-semana abre mesmo o ecrã, com o título e os dois botões novos visíveis, e
antes desta sessão não abria coisa nenhuma; e as funções que ele chama respondem certo
quando chamadas com sessão de administrador real, incluindo os três totais da semana de
31 de agosto — 19,80 euros a pagar, 33,18 a receber, saldo de 13,38 a favor da Bora.

Fica também por fazer o retrato no emulador do toque na notificação. O emulador está a
correr e a aplicação compila, mas provar isso ponta a ponta obrigava a ter sessão de
administrador lá dentro e um registo de aparelho para o envio — a mesma parede da
palavra-passe. O caminho está feito e escrito nos três sítios (aplicação fechada, em
segundo plano, e aberta noutro ecrã); falta o retrato.

---

DIGEST PARA O HERMES

O fecho semanal passou a andar sozinho: a chave do Resend estava em falta desde sempre e ficou no cofre, e os emails saem mesmo — dois chegaram à caixa e o comprovativo de 11,12 euros também.
Tocar no aviso do fecho passa a abrir os Acertos da semana na semana certa; havia dois avisos por fecho e ficou um, e a rota que faltava foi registada.
Marcar pago e marcar recebido deixaram de ser a mesma coisa, são validados pela direcção, dão para desfazer, e disparam o comprovativo automático por email.
O fecho correu hoje sozinho com o código novo, já com limpeza, serviços e lavagem lá dentro, e não desfez nem duplicou nada da semana que já estava paga.
Ficaram três coisas à espera do teu vai: a prévia da semana em curso, o transporte da dívida, e um estafeta com 80 cêntimos por acertar que os lembretes apanham na quarta.
