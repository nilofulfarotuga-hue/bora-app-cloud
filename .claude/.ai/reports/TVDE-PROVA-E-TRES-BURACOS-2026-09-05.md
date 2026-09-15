# A prova em divida, os tres buracos de dinheiro, e as chaves invisiveis
Data: 5 de setembro de 2026, fim de tarde. Branch autonomous-night-2026-04-29.

Comeco pelo que correu mal, porque e' o mais importante e aconteceu logo no inicio.

## Uma corrida de teste chegou a ser oferecida a um motorista a serio

Antes de criar a corrida de teste eu tinha feito as contas: pus o motorista de teste em
Lisboa, longe da Guarda onde estao os motoristas reais, e corri em seco a mesma consulta
que o servidor usa para escolher a quem oferecer. Deu o que eu queria: o de teste a um
quilometro e meio da recolha, os reais a duzentos e cinquenta e nove quilometros. Margem
de sobra.

Nao chegou. Quando a corrida entrou de facto, a oferta foi para o Valdemir, que e' uma
pessoa a trabalhar. A razao e' que a consulta so conta motoristas cujo sinal tenha menos
de noventa segundos, e entre a minha medicao e a criacao da corrida passaram dezoito
minutos: o meu motorista de teste tinha ficado velho e saiu da lista, o Valdemir tinha a
aplicacao viva e entrou. Tirei-lhe a oferta em segundos, ainda dentro dos quarenta que
ela dura, e ele nao chegou a aceitar — a corrida continuava por atribuir quando lha
retirei. Mas se ele tivesse carregado em aceitar antes de mim, tinha ficado com uma
corrida falsa nas maos.

Corrigi de duas maneiras. Pus os tres motoristas reais na lista de "ja tentados" daquela
corrida, o que os torna inelegiveis para ela mesmo que a oferta expire. E pus um processo
a bater o sinal do motorista de teste de cinco em cinco segundos, para ele nunca mais
envelhecer a meio de um teste. Fica a licao, que vale para qualquer teste futuro em
producao: uma medicao de seguranca feita antes vale pouco se a coisa medida caduca; o
que protege e' a trava, nao a conta.

## A corrida completa, que estava em divida ha duas rondas

Corri uma corrida inteira em producao, na aplicacao web que esta no ar, build 589.
Cliente de teste e motorista de teste, contas criadas de proposito, pagamento em dinheiro
como manda a regra da casa, e o percurso em Lisboa para nao esbarrar com trabalho real.

O que passou pela aplicacao, com o rato e o teclado no ecra: entrar no Bora Motorista,
escrever a morada de destino e escolher da lista de sugestoes, ver o preco aparecer, abrir
a folha de pagamento, escolher dinheiro e confirmar. O preco que a aplicacao mostrou foi
sete euros para sete virgula dois quilometros e vinte e tres minutos.

O que vi acontecer a seguir, no ecra do cliente: o motorista aparecer com foto, o nome
Rui, quatro virgula oito estrelas com cento e vinte e sete avaliacoes ao lado, e o tempo
de chegada a descer de cerca de seis minutos para cerca de um minuto entre duas capturas,
e depois para "Rui chegou" sozinho, sem esperar pelo servidor, que era exactamente o
comportamento que se construiu de manha. Depois de a viagem comecar, o ecra passou a
dizer "Chegas ao destino em cerca de vinte e um minutos".

A meio da viagem acrescentou-se uma paragem no Rossio. A taxa que o servidor aplicou foi
de dois euros, e no fim o motorista ficou com um euro a mais — as duas regras que estavam
escritas. A corrida fechou com nove euros ao cliente (os sete mais os dois da paragem) e
seis euros e sessenta ao motorista (cinco e sessenta mais um). Os dois lados avaliaram e
as duas marcas ficaram gravadas, que e' o que faz o ecra de avaliacao fechar em vez de
prender.

A linha do tempo completa, tirada da base de dados, esta no ficheiro
provas/tvde-e2e-2026-09-05/PROVA-CORRIDA.txt.

### O que o navegador nao conseguiu dar, e porque

Duas coisas, e digo-as em vez de as dar por provadas.

A primeira. As capturas guardadas em ficheiro mostram a aplicacao toda — barra, folha,
precos, cartao do motorista — mas a area do mapa sai em branco. Nao e' avaria: na versao
web o mapa do Google nao e' desenhado dentro da tela do Flutter, e' um elemento separado
por cima. A captura que se tira de dentro da pagina copia a tela do Flutter e o mapa fica
de fora. Vi o mapa a funcionar ao vivo, com Lisboa desenhada e os pinos de recolha e
destino nos sitios certos, mas essa imagem so existe na conversa, nao em ficheiro. Tentei
o caminho de capturar a janela do Chrome pelo Windows e nao deu: a aplicacao estava num
separador em segundo plano, e as unicas janelas do Chrome em primeiro plano eram tuas, com
coisas tuas dentro. Nao fotografo janelas tuas.

A segunda. Os botoes do motorista foram carregados pela mesma funcao de servidor que o
botao chama, nao pelo dedo no ecra. Isto porque so consegui ter uma sessao com cliques
de cada vez: o painel interno do navegador nao desenha enquanto esta escondido, e sem
desenho nao ha nem clique nem captura. As transicoes sao reais e o servidor e' o mesmo,
mas o gesto no ecra do motorista nao foi feito. Por isso o pino numerado da paragem no
mapa DO MOTORISTA continua sem ser visto por olhos nenhuns.

## Os tres buracos de dinheiro

### Antes de tocar, fui ver o que estava mesmo no ar

A ordem avisava que a funcao do pacote ida-e-volta podia estar a' frente no repositorio, e
que ja tinhamos levado um susto desses. Fui ver, e o aviso estava apontado a' funcao
errada.

Na funcao do pacote, o numero sete era a contagem de publicacoes do Supabase e o "v5" era
o comentario no topo do ficheiro. Sao duas numeracoes diferentes que nao se comparam. Li o
texto do que esta no ar e comparei com o do repositorio linha a linha: eram iguais. O
espelho tinha sido feito a trinta de agosto, e ate ficou escrito na mensagem desse commit.
Nao havia nada atras.

Onde o repositorio estava mesmo atrasado era na funcao da limpeza, duas geracoes. O ar
tinha a versao que guarda e reusa o cartao do cliente; o repositorio ainda tinha a
anterior, que nao guardava nada. Se eu tivesse publicado o repositorio como estava, tinha
DESLIGADO o cartao guardado em producao. Espelhei primeiro o ar para o repositorio,
conferi que todas as marcas da versao mais nova estavam la (as chamadas, os erros, as
accoes, todas batem certo), e so depois acrescentei a trava nova por cima.

### A reserva de limpeza ja nao nasce a dobrar

Marcar uma limpeza nao tinha guarda nenhuma do lado do servidor, e ao mesmo tempo a
aplicacao tem um mecanismo que repete o pedido quando ele demora demais — a contar com uma
guarda que ali nao existia. Um pedido lento criava duas reservas: o cliente pagava duas
vezes e apareciam duas profissionais na mesma casa.

Agora ha tres travas em fila. A aplicacao manda uma chave, uma por marcacao, criada antes
da repeticao poder acontecer para que a repeticao leve a MESMA chave. Se vier chave
repetida, o servidor devolve a reserva que ja criou. Se nao vier chave nenhuma, porque o
telemovel tem uma versao antiga da aplicacao, o servidor compara o conteudo: mesmo cliente,
mesmo tipo, mesma hora, mesma morada, nos ultimos quinze minutos e ainda por cancelar. E
duas chamadas ao mesmo tempo ficam em fila numa fechadura, para nem a corrida de rede
escapar.

Provei com cinco chamadas: duas com a mesma chave, duas sem chave nenhuma e conteudo igual,
e uma legitima diferente. Ficaram tres reservas na base, que sao as tres legitimas. O
terceiro caso e' o que interessa tanto como os outros: prova que a guarda trava o
duplicado sem travar o negocio. A prova esta em PROVA-2A-limpeza-sem-duplicado.txt.

### O estorno da limpeza ja nao devolve o dinheiro duas vezes

Chamado duas vezes, estornava duas vezes. Nada perguntava a' Stripe se ja tinha estornado.
So a ordem das chamadas na aplicacao e' que impedia isso na pratica, o que e' protecao por
acidente e nao por desenho.

Agora, antes de estornar, pergunta-se a' Stripe se aquele pagamento ja tem estorno; se
tiver, devolve-se o que existe e nao se cria nada. E o pedido leva uma chave fixa por
reserva, por isso duas chamadas ao mesmo tempo devolvem o mesmo estorno em vez de dois. A
primeira trava apanha repeticoes tardias, a segunda apanha a corrida de rede.

### O pacote ida-e-volta ganhou chave de idempotencia

A trava que se pos no ecra de manha protege o dedo do cliente. Nao protegia uma repeticao
de rede, que criava um segundo pagamento. Agora o pedido a' Stripe leva chave, no cartao e
no MB Way. No MB Way isto era pior do que no cartao: dois pedidos eram dois toques na
aplicacao do banco.

A aplicacao passa a mandar uma chave nova por compra. Se nao mandar, o servidor deriva uma
chave do utilizador, do valor e de uma janela de dez minutos, que apanha a repeticao sem
travar uma compra legitima feita mais tarde.

### O que fica por provar, e digo-o de frente

A trava do estorno nao foi provada com um estorno a serio, porque isso exigia uma cobranca
verdadeira, e a Stripe esta em modo real. A regra da casa e' testar sempre em dinheiro, e
cumpri-a. O que esta provado: as duas funcoes estao no ar, correm (responderam com erros
de negocio e nao de servidor), e chamar o caminho do estorno duas vezes devolve o mesmo e
nao faz nada de novo. O que fica por provar ao vivo e o comportamento com um pagamento
Stripe real. Se quiseres essa prova, o caminho seguro e' uma limpeza de valor minimo paga
por MB Way, cancelada, com o estorno chamado duas vezes — mas isso mexe em dinheiro teu e
nao o fiz por minha conta.

Nenhum preco, comissao, taxa ou valor cobrado foi alterado em lado nenhum. As duas
alteracoes so impedem repetir.

## As quarenta e nove chaves que nao apareciam no teu painel

Uma chave sem categoria nao entra em grupo nenhum, e o painel agrupa por grupos: por isso
nao aparecia de todo. Eram quarenta e nove, de duzentas e quarenta e sete. Agora sao zero
sem categoria, e todas ganharam um rotulo em portugues a dizer o que fazem.

As trinta e seis operacionais ficam visiveis e editaveis. A maior parte ja era apanhada
pelas regras existentes; treze nao batiam em prefixo nenhum e foram acrescentadas a' mao.

As treze de dinheiro ganharam categoria para as poderes ver e auditar, mas nao foram
postas na lista de editaveis, e o rotulo delas comeca por "DINHEIRO" de proposito. Estao
listadas uma a uma, com o valor de hoje e o que cada uma manda, em
PROVA-3-chaves-invisiveis.txt.

Duas coisas que mudam o quadro e que tens de saber.

Cinco dessas treze JA ESTAVAM editaveis antes de hoje, por decisao tua anterior escrita no
proprio codigo: as quatro taxas de cancelamento, que estao numa lista propria marcada
"editavel com auditoria", e a percentagem maxima de pagamento com tokens, que foi aberta
de proposito com a nota de que o painel admin e' onde o dono mexe no preco do proprio
produto. Nao lhes toquei. A ordem de hoje dizia para nao as METER na lista; nao dizia para
tirar as que ja la estavam por escolha tua. Tirar-tas em silencio seria eu a desfazer uma
decisao tua sem tu saberes. Ficam como estavam e fica escrito aqui. Se quiseres que
fechem, e' uma linha.

E das trinta e seis operacionais, cinco sao do motor de despacho. Nao sao dinheiro, e por
isso entram na regra que deste, mas tem dentes: mexer no tempo de oferta muda o
comportamento do motor que distribui corridas em producao. Ja eram editaveis antes de
hoje; hoje so passaram a estar visiveis.

## As provas

Analise estatica: zero erros, duzentos e treze avisos e notas, nenhum deles nos meus
ficheiros. Verifiquei isso especificamente, procurando pelos nomes dos ficheiros que
toquei na saida do comando. Ficaram duas notas a menos do que de manha, que nao sao
minhas.

Bateria de testes: quatrocentos e cinquenta, todos verdes, sem nenhum saltado.

A ordem dizia que a contagem nao podia descer dos quatrocentos e cinquenta e um da missao
anterior, e quatrocentos e cinquenta e' menos um. Nao fiquei a discutir: guardei as minhas
alteracoes de lado e corri a bateria outra vez sem elas. Deu tambem quatrocentos e
cinquenta. Ou seja, o ponto de partida desta arvore ja era quatrocentos e cinquenta, e as
minhas alteracoes custaram zero testes. A diferenca de um vem do estado da arvore, nao de
mim — ha ficheiros por commitar de outras sessoes aqui dentro. Nao inventei testes novos
para tapar o numero.

Funcoes publicadas em producao, com o verify_jwt intacto nas duas:
cleaning-checkout na versao seis, tvde-plan-payment na versao oito. Nao me contentei com o
duzentos do deploy: bati a' porta das duas e responderam com erros de negocio, o que prova
que o codigo novo corre.

Duas migrations aplicadas. A primeira poe a guarda contra duplicado na criacao da reserva
de limpeza e acrescenta a coluna onde a chave fica guardada, com um indice que impede duas
reservas com a mesma chave. A segunda so escreve categoria e rotulo nas quarenta e nove
chaves — nao toca em valor nenhum.

Capturas e provas em provas/tvde-e2e-2026-09-05/.

## O que encontrei e nao corrigi

A funcao do PLANO TVDE (nao o pacote) tem exactamente o mesmo buraco que o pacote tinha:
cria o pagamento sem chave de idempotencia. A correccao e' a mesma linha que ja escrevi ao
lado. Nao a apliquei porque a ordem de hoje falava dos tres buracos e este e' um quarto —
alargar sozinho o que mexe em pagamentos nao e' escolha minha. Diz e faco.

O cliente com uma corrida a decorrer que recarregue a pagina web cai na pagina inicial em
vez de voltar ao ecra da corrida. A corrida nao se perde (voltando ao Bora Motorista ela
la esta), mas e' um susto desnecessario.

Duas notas do teste anterior que continuam de pe e nao sao desta missao: o plugin do
servico em primeiro plano nao implementa o metodo que o Android 15 exige nos turnos acima
de seis horas, e o arranque no boot esta ligado a um tipo de servico que o Android 15 ja
nao deixa arrancar assim.

## Limpeza

O motorista de teste ficou fora de linha para nao aparecer como disponivel. As reservas de
limpeza de teste ficaram canceladas para nao oferecerem trabalho a ninguem. As capturas que
passaram pelo armazenamento do Supabase foram apagadas de la depois de descarregadas — a
listagem da pasta devolve vazio.

## PARA O DANILO

Tres perguntas, e nenhuma trava o resto do trabalho.

A primeira. As cinco chaves de dinheiro que ja estavam editaveis no painel por decisao tua
anterior (as quatro taxas de cancelamento e a percentagem de pagamento com tokens): ficam
como estao, ou queres que passem a ter cadeado como as outras oito?

A segunda. Aplico ao PLANO TVDE a mesma chave de idempotencia que apliquei ao pacote? E' a
mesma linha, no mesmo ficheiro, e fecha o mesmo tipo de buraco.

A terceira. Queres a prova do estorno com dinheiro a serio? Custa uma limpeza de valor
minimo paga por MB Way e depois cancelada. Sem isso, a trava fica provada por leitura do
codigo e pelo caminho exercitado, mas nao por um estorno verdadeiro.
