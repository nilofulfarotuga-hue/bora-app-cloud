# O espelho da v9, a prova que nao se fez, e um buraco de dinheiro que ninguem tinha visto
Data: 5 de setembro de 2026, noite. Branch autonomous-night-2026-04-29.
Fecho da ordem ordem-20260905145531-84c5.

Comeco pelo achado, porque e' o que muda alguma coisa.

## O suporte cancela uma limpeza paga e o dinheiro NAO volta

Fui procurar por onde e' que o painel poderia accionar um estorno de limpeza, como a
ordem pedia. Nao ha por onde, e ao ir ver porque nao, encontrei isto.

Quando o suporte cancela uma limpeza pelo painel, a funcao `admin_cancel_cleaning` faz
tres coisas: poe a reserva em cancelada, marca o pagamento como `estornado`, e manda ao
cliente uma notificacao a dizer, palavra por palavra, "A tua limpeza foi cancelada pela
equipa Bora. Sem qualquer custo."

O que ela NAO faz e' chamar a Stripe. Nao ha nenhum estorno. A base de dados diz que o
dinheiro voltou, o cliente le que nao paga nada, e o dinheiro fica ca'. Numa limpeza de
35 euros sao 35 euros que ficam indevidamente do nosso lado, com o registo a dizer o
contrario — o que e' pior do que so ficar com o dinheiro, porque tapa o rasto.

Confirmei que o caminho do CLIENTE esta certo: quando e' ele a cancelar na app, o ecra
chama o estorno logo a seguir ao cancelamento e o dinheiro volta. Mas mesmo ai ha uma
fragilidade: essa chamada e' feita sem esperar pelo resultado e engole o erro em silencio,
e a base ja tinha sido marcada `estornado` antes de ela sair. Se a chamada falhar — rede,
Stripe em baixo, o que for — ninguem fica a saber e o registo passa a mentir.

E confirmei que o caminho da PROFISSIONAL nao tem problema: quando e' ela a cancelar, a
reserva volta a ficar por atribuir em vez de acabar, por isso nao ha estorno a fazer.

Nao lhe toquei. E' a funcao que move dinheiro, e mexer nela sem ordem seria eu a decidir
sozinho sobre o dinheiro dos teus clientes.

### ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Esta tudo pronto — confirma que eu aplico.

A correccao tem duas metades, e a ordem entre elas importa.

Primeira metade, na Edge Function `cleaning-checkout`: hoje a accao `reverse` recusa quem
nao e' o dono da reserva, e um administrador nao e' o dono, logo leva um "nao" com codigo
403. Tem de passar a aceitar tambem quem e' administrador. Isto e' abrir uma porta numa
funcao que devolve dinheiro, por isso e' a parte que exige o teu "vai".

Segunda metade, na funcao `admin_cancel_cleaning`: deixar de escrever `estornado` quando
nada foi estornado. Ou chama o estorno de verdade, ou marca um estado que diga a verdade
("estorno por fazer") para aparecer no painel como pendente em vez de aparecer como feito.
A mensagem ao cliente tambem tem de deixar de prometer "sem qualquer custo" antes de o
dinheiro ter saido.

Sugiro fazer as duas de uma vez, com um botao no painel que estorna e mostra o resultado.
Diz "vai" e faco.

## A prova do estorno com dinheiro real NAO se fez

Duas tentativas, nenhuma aprovada.

A primeira saiu as 16h49 e morreu as 16h53, quatro minutos depois. A segunda saiu as 16h54
e morreu as 17h00, seis minutos depois. As duas morreram do mesmo modo: o pagamento passou
de "a espera do cliente" para "sem metodo de pagamento", que e' como a Stripe marca um
pedido MB Way que caducou sem ser aprovado. Nao foi recusa de sistema nem erro nosso — e'
o tempo de vida normal de um pedido MB Way, que e' curto.

Nao fiz uma terceira. A ordem dizia para nao insistir, e a regra da casa diz que dois
falhancos iguais mudam a abordagem em vez de repetirem. Fica por fazer, e fica dito.

O que importa: **nao foste cobrado**. A reserva foi cancelada, com taxa zero, e o registo
mostra que nunca chegou a ter pagamento associado. Verifiquei a seguir que nao ficou
nenhuma limpeza de teste viva a oferecer trabalho a ninguem, e que nao existe na base uma
unica reserva de limpeza com pagamento em qualquer estado que nao seja "por pagar".

Se quiseres a prova noutro dia, o caminho e' o mesmo e demora dois minutos: eu disparo, tu
tens o telemovel na mao, aprovas dentro dos primeiros dois ou tres minutos. O desenho
tambem melhorou entretanto: marquei a limpeza para daqui a tres dias, muito acima da janela
livre de vinte e quatro horas, o que poe a taxa de cancelamento a zero. Isso quer dizer que
o estorno seria do valor INTEIRO e nao de metade — a mesma prova, sem te custar 17,50.

## O espelho da v9

A ordem avisava, e o aviso era bom: o ar estava a' frente do repositorio. Se eu tivesse
publicado o repositorio como estava, apagava a correccao que ja esta' a proteger clientes.

Nao publiquei nada. Li o que esta' no ar e trouxe as diferencas para o repositorio. Eram
exactamente as tres que a ordem descrevia: o cabecalho a passar para v7 com a nota do
porque, a chave no pagamento do plano por cartao, e a chave no pagamento do plano por
MB Way. A funcao que constroi a chave ja existia, criada para o pacote ida-e-volta, e nao
foi duplicada.

Verifiquei o espelho de forma exaustiva em vez de confiar no olho: as dezasseis mensagens
de erro que a funcao devolve, com as contagens certas; as chamadas a' Stripe (quatro
criacoes de pagamento, duas leituras, uma criacao de cliente, uma remocao); as cinco
funcoes de base de dados que ela chama; as seis accoes que aceita; e as chavetas e
parenteses, que fecham todos. As quatro chaves de idempotencia estao la com os prefixos
certos: uma para o pacote em cartao, uma para o pacote em MB Way, uma para o plano em
cartao, uma para o plano em MB Way.

O `verify_jwt` continua ligado.

## O app passa a mandar o id da compra no plano

Sem esse id, o servidor cai numa chave por janela de dez minutos. Apanha a repeticao, mas
e' grosseira: duas compras legitimas do mesmo plano e do mesmo valor dentro da mesma janela
seriam vistas como uma so.

Agora o ecra dos planos guarda um id por plano. Nasce quando a compra comeca, sobrevive a
uma repeticao (folha cancelada, voltar atras, tentar outra vez), e morre quando a compra
conclui — para a compra seguinte do mesmo plano nascer com id novo em vez de reusar um
pagamento ja feito. Sair do ecra tambem limpa, o que e' a saida natural se um dia o preco
mudar a meio de uma repeticao.

Segui o padrao que ja estava escrito para o pacote ida-e-volta, com uma diferenca
deliberada: no pacote o id nascia a' chamada; aqui fica guardado no estado do ecra, porque
a ordem pedia explicitamente que uma repeticao levasse o mesmo id.

## O painel passa a mostrar o rasto do dinheiro

Isto responde a uma pergunta concreta: "este cliente diz que pagou duas vezes — pagou?".

Nas limpezas, cada reserva mostra agora o id do pagamento na Stripe, a chave da marcacao,
a situacao do pagamento, quanto foi retido no cancelamento e quanto deve voltar. O dado ja
vinha todo do servidor — a funcao de listagem devolve a linha inteira — e so nao era
mostrado. Duas reservas com a MESMA chave seriam um bug nosso; e' isso que a chave serve
para apanhar.

Nos planos TVDE e nos pacotes ida-e-volta o dado NAO vinha. Alarguei as duas funcoes de
listagem do painel para devolverem tambem o id do pagamento, e os dois ecras para o
mostrarem. Dois planos do mesmo cliente com ids diferentes e datas coladas sao uma cobranca
dupla; o mesmo id repetido e' so a mesma compra vista duas vezes. Planos concedidos por ti
e pacotes pagos em dinheiro nao tem pagamento na Stripe e nao mostram a linha.

A migration so acrescenta campos de leitura. Nao altera nenhum valor.

## As provas

Analise estatica: zero erros. Corri tambem a analise so sobre os meus seis ficheiros, um
de cada vez, e deu "nenhum problema encontrado" nos dois lotes.

Bateria de testes: quatrocentos e cinquenta e dois, todos verdes, zero saltados, zero
falhas. O piso desta arvore era quatrocentos e cinquenta, medido ontem com o meu trabalho
posto de lado. Subiu dois, e os dois nao sao meus — nao escrevi teste nenhum nesta sessao;
vieram de um commit de outra sessao que entrou na arvore entretanto. Digo-o porque um
numero que sobe sem se saber porque e' tao suspeito como um que desce.

Nao toquei no `pubspec`. O versionCode e' do servidor de compilacao.

## Limpeza

A reserva de limpeza que criei para a prova ficou cancelada, com taxa zero e sem pagamento
associado. Confirmei por consulta directa: zero limpezas de teste vivas, zero reservas do
cliente de teste por fechar, e zero reservas de limpeza na base inteira com pagamento em
qualquer estado que nao seja "por pagar".

## PARA O DANILO

Uma coisa so, e e' a de cima: o suporte a cancelar uma limpeza paga nao devolve o dinheiro,
e diz ao cliente que nao ha custo nenhum. A correccao esta explicada, tem duas metades, e
uma delas abre uma porta numa funcao que devolve dinheiro. Diz "vai" e faco as duas.

E se quiseres a prova do estorno, e' so dizeres quando tens o telemovel na mao — dois ou
tres minutos e esta feita, agora com o valor inteiro a voltar em vez de metade.
