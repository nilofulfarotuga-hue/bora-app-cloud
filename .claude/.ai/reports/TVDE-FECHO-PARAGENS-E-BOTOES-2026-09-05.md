# Missao TVDE parte 2 — as paragens entram na rota, o carro deixa de saltar, e o botao preso acabou
Data: 5 de setembro de 2026, tarde. Branch autonomous-night-2026-04-29.
Fecha o que tinha ficado em aberto no relatorio TVDE-CLIENTE-VE-O-CARRO da manha.

## Duas coisas em que o mapa da ordem estava errado, e que eu nao segui

Comeco por aqui porque sao decisoes minhas contra o que estava escrito, e tens de as poder
contestar.

A primeira. A ordem mandava acrescentar o tipo "location" ao servico em primeiro plano
declarado na linha 133 do manifest do Android. Se eu tivesse feito isso, a aplicacao do
PARCEIRO passava a rebentar ao abrir a loja. A razao e que esse servico e partilhado: o
estafeta liga-o quando fica online, mas a loja de restaurante liga o MESMO servico quando
abre, e o plugin arranca-o sempre com todos os tipos declarados no manifest de uma vez. O
tipo location exige permissao de GPS concedida em tempo de execucao. Um restaurante nao tem
essa permissao nem tem razao para a ter, e a consequencia era uma excecao de seguranca a
matar a aplicacao num caminho que hoje funciona. Verifiquei os dois lados: a chamada do
parceiro existe mesmo no ficheiro que gere as lojas.

E a permissao que parecia estar a ser desperdicada nao estava. Quem a usa e um terceiro
servico que nao se ve nesse ficheiro: o proprio pacote de localizacao traz o seu, ja
declarado com o tipo location, e o sistema de compilacao funde-o no manifest final. Fui ver
o manifest do pacote na cache e esta la. A correcao verdadeira era outra e ja existia na
casa: basta passar a configuracao de notificacao ao pedir a localizacao, que e exactamente o
que as entregas ja fazem ha muito e o TVDE nao fazia. E uma linha. Ficou feita, e o manifest
so ganhou um comentario a explicar porque o location nao pode la entrar, para o proximo
agente nao repetir a tentativa.

A segunda. A ordem dizia que o botao preso ao estado global estava em vinte e um ecras. So
dez tinham mesmo o defeito. Os nove ecras do painel de administracao usam um estado local
declarado no proprio ecra, e dois deles usam um padrao melhor do que o meu: travam so a
linha em que carregaste, nao o ecra inteiro. O ecra da agenda do parceiro usa um conjunto
por item, tambem ideal. O ecra de permissoes do estafeta usa estado local. E o botao de
finalizar compra ja estava certo, com dupla protecao. Mexer nesses seria estragar o que esta
bem, por isso nao lhes toquei.

Em compensacao, encontrei cinco que nao estavam na lista, todos no ecra da profissional de
limpeza, incluindo o recusar de uma oferta que expira e o concluir limpeza, que e o fim de
trabalho dela. Esses tinham mesmo o defeito e foram corrigidos.

## As paragens, que era o mais importante

O cliente paga dois euros por cada paragem que acrescenta a meio da corrida e o motorista
recebe um euro, ate duas paragens. Isso estava certo na base. O que estava errado e que o
mapa ignorava as paragens por completo: o servico de rotas aceita pontos de passagem desde
sempre, mas em todo o programa so o mapa das entregas os usava. Os dois mapas do TVDE
carregavam as paragens e nunca as passavam a lado nenhum. Cobrava-se por um servico que o
mapa nao mostrava.

Agora os dois mapas pedem a rota com as paragens ainda por alcancar, pela ordem em que o
cliente as pediu. Assim que o motorista marca chegada a uma, ela sai da lista e a linha
refaz-se para a seguinte, ou para o destino se ja nao houver nenhuma. Acrescentar uma
paragem conta como mudanca de fase, o que faz a linha mudar no instante em vez de esperar os
quinze segundos da trava de recalculo. As paragens aparecem nos dois mapas como circulos
numerados, um e dois, que se distinguem da recolha e do destino; as ja feitas ficam em
cinzento em vez de desaparecerem, porque a meio de uma corrida com duas paragens e isso que
responde a pergunta de qual e qual.

E o tempo de chegada passou a somar o tempo parado que ainda falta. A conta da Google so
mede o tempo a andar; duas paragens de dois minutos sao quatro minutos que o carro esta
quieto. Sem essa parcela, o cliente via uma hora de chegada que o carro nao conseguia
cumprir, o que era voltar a mentir-lhe por outra porta.

A matematica das paragens ficou num ficheiro proprio, puro, partilhado pelos dois mapas para
a conta nao ser feita em dois sitios diferentes. Tem dezoito testes.

## O carro do cliente

Andava em linha recta entre duas leituras de posicao. Como as leituras chegam de cinquenta
em cinquenta metros, o carro cortava as esquinas e atravessava quarteiroes: via-se o carro a
passar por dentro dos predios enquanto a linha da rota passava pela rua ao lado. Agora anda
por cima da propria linha desenhada, o que o faz dobrar onde a estrada dobra. Quando nao ha
linha desenhada, volta ao movimento em recta, que continua a ser o recurso honesto.

Roda com a direcao que a funcao ja devolvia e distribui o movimento pela velocidade real, o
que quer dizer que um carro parado deixa de deslizar e um carro rapido deixa de se arrastar.

E ha agora a nocao de sinal velho. A funcao ja devolvia a hora da ultima posicao e ninguem a
lia. Um motorista com o GPS morto aparecia ao cliente exactamente como um motorista parado,
sem explicacao nenhuma. Passados quarenta e cinco segundos sem posicao nova, a animacao para,
o carro esbate-se e aparece por baixo do cartao ha quanto tempo foi a ultima posicao.
Passados tres minutos, diz que se esta a ligar ao motorista. Os dois limites sao afinaveis no
teu painel. Quinze testes, com o relogio injectado para nao dependerem da hora da maquina.

## Uma so stream de localizacao

Ficavam duas abertas durante a corrida: a do ecra de corrida, de tres em tres metros, e a da
home, de cinquenta em cinquenta. Agora a da home fica suspensa enquanto o ecra de corrida
esta aberto e volta quando ele fecha.

O ponto delicado aqui era nao deixar o servidor sem posicao, porque e essa posicao que
alimenta o motor que distribui corridas, que nao se toca. A garantia e esta: o ecra de
corrida so reclama a localizacao depois de a stream dele ter dado a primeira posicao de
verdade, usa exactamente as mesmas funcoes de envio que a home usava, e essas funcoes vivem
num objecto unico partilhado pelos dois ecras, com o mesmo travao de tempo la dentro. Por
cima disso ha um portao de cinquenta metros que reproduz a mesma cadencia de antes. Se o GPS
do ecra de corrida morrer a meio, a home reabre a dela.

## O botao preso ao estado global, e o que se descobriu nos ecras de dinheiro

A regra escrita esta manha diz que um botao se trava pelo seu proprio pedido, nunca por um
estado global de ocupado. Faltava aplica-la.

Nos ecras que mexem em dinheiro, seguiu-se a chamada ate ao servidor antes de tocar em cada
botao, porque tirar o estado global as cegas podia trocar um botao morto por uma cobranca a
dobrar, que e muito pior. O resultado, ecra a ecra:

O confirmar limpeza concluida, o cancelar limpeza e o parar recorrencia ja eram seguros do
lado do servidor: a funcao rebenta se o estado ja mudou, e uma delas ate tranca a linha na
base antes de mexer. Levaram trava local e ficou feito.

Chamar a volta de um pacote e a corrida normal online tambem ja eram seguros: a primeira
tranca o vale antes de o gastar, a segunda usa chaves de idempotencia da Stripe.

Tres nao eram seguros, e dois deles de forma grave. O pagar agora da limpeza e o pacote
ida-e-volta do TVDE estavam com zero protecao contra duplo toque, porque os metodos de
pagamento nunca chegavam a ligar o tal estado global — e ao mesmo tempo o botao podia morrer
por causa de outra operacao qualquer. Era o pior dos dois mundos: destravado quando devia
travar, e morto quando devia funcionar. Verifiquei eu proprio essa afirmacao no codigo da
loja de limpeza: as travas do estado global estao todas em linhas anteriores as dos metodos
de pagamento. No MB Way, dois toques ali eram dois pedidos na aplicacao do banco. Agora tem
trava propria. O terceiro e o criar reserva de limpeza, que nao tem guarda nenhuma no
servidor: dois toques eram duas reservas.

Escrevi tambem um teste que varre o programa inteiro e reprova se alguem voltar a ligar um
botao ao estado global de um store. A regra estava no papel desde a manha; agora tem dentes.
O teste apanhou dezasseis sitios quando nasceu e hoje passa a zero. Tem auto-verificacao,
para provar que nao esta a dormir: exercita cinco formas erradas que tem de apanhar e seis
formas certas que nao pode marcar. E tem lista de excecoes explicadas, com dois testes que
garantem que uma excecao esquecida nao fica a tapar problemas futuros.

Ao escrever esse teste descobri um buraco no meu proprio desenho: quando o formatador parte
a expressao em duas linhas, o padrao escapava. Dois botoes reais do ecra da profissional de
limpeza estavam a passar por esse buraco. Corrigido com uma janela de tres linhas.

## As provas

Analise estatica com zero erros. Sao duzentas e quinze notas de estilo e dez avisos, e
nenhum deles esta nos ficheiros desta missao — sao todos anteriores. Verifiquei
especificamente isso, porque a ordem pedia zero avisos novos meus, e a meio houve dois que
apareceram por minha causa: dois imports que ficaram sem uso quando troquei o bloco de
plataforma pela chamada ao servico. Limpei-os.

Bateria de testes inteira verde: quatrocentos e cinquenta e um testes, contra os
quatrocentos e catorze da ronda da manha. Subiu, como a ordem exigia.

Os testes novos sao tres ficheiros. Um prova que a rota inclui as paragens por ordem e larga
cada uma quando e alcancada, que o tecto de duas paragens protege a chamada, que o tempo
parado entra no tempo de chegada e que acrescentar uma paragem conta como fase nova. Outro
prova os tres estados do sinal do motorista, incluindo que uma posicao com mais de quarenta
e cinco segundos marca sinal velho e para a animacao, e que valores disparatados postos no
painel nao partem o ecra. O terceiro e o teste-guarda dos botoes.

Houve um teste meu que falhou a primeira e estava mal escrito eu, nao a funcao — o caso do
limite perdido configurado abaixo do limite velho. Corrigi o teste, nao o codigo.

Os tres trabalhos do servidor de compilacao passaram todos com o commit desta missao: as
imagens de referencia, a web e o Android que vai para a loja.

E fui ver por dentro o que ficou publicado na web, em vez de acreditar no "sim" do servidor.
Dentro do ficheiro compilado que esta no ar estao as chaves das paragens, o parametro de
pontos de passagem que faltava passar ao servico de rotas, o texto do pino de paragem, as
duas chaves novas do sinal velho, as frases da ultima posicao e de ligar ao motorista, e a
traducao inglesa nova. Um aviso sobre o metodo: a primeira vez que fiz esta verificacao ela
deu quase tudo negativo, e era um falso negativo meu — o compilador troca os nomes das
funcoes por nomes curtos, e so as frases escritas sobrevivem. Refiz a procurar so por frases.
As frases da notificacao do servico em primeiro plano nao aparecem no pacote da web, e isso
esta certo: esse caminho e so do Android e o compilador removeu-o, o que confirma de caminho
que a guarda de plataforma funciona.

Uma armadilha que eu proprio criei e fechei: tinha escrito uma funcao que devolvia "ha X
minutos" em portugues cru, e so o teste a usava. Se algum ecra a adoptasse, um cliente em
ingles via portugues. Apaguei-a e deixei escrito no ficheiro porque nao deve voltar — a
frase que o cliente le e montada no ecra sobre as chaves do dicionario.

## O que NAO foi provado, e digo-o de frente

A corrida ponta a ponta no navegador, com duas contas em dois perfis, nao foi feita. Fica em
divida pela segunda vez.

Nao ha telemovel Android ligado a este computador: o comando que os lista devolve lista
vazia. E nao ha emulador nenhum instalado: o comando que os lista responde que nao ha
nenhum, e criar um exige descarregar varios gigabytes de imagem de sistema para uma maquina
com quatro gigabytes de memoria. Portanto o Bloco 5 na parte do emulador e do telemovel nao
foi feito, e nao vou fingir que foi.

Isto quer dizer que ha coisas desta missao que ninguem viu a funcionar com os olhos: o carro
a dobrar as esquinas em vez de as cortar, os pinos numerados das paragens nos dois mapas, a
notificacao persistente do servico em primeiro plano, e o GPS a continuar a debitar com a
aplicacao minimizada. O que esta provado e que o codigo compila sem erros, que a logica pura
por tras de tudo isso passa em quatrocentos e cinquenta e um testes, e que o servidor de
compilacao aceitou o resultado.

## Coisas encontradas e nao corrigidas

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Esta tudo diagnosticado e nada foi aplicado — confirma
se queres que eu trate, noutra ordem:

Primeiro: a funcao do pacote ida-e-volta nao tem chave de idempotencia. A trava que se pos
no ecra protege o dedo do cliente, mas nao protege uma repeticao de rede. Atencao que a
versao que esta no ar e a sete e a que esta no repositorio diz cinco — o ar esta a frente,
tal como ja nos aconteceu antes. Ler o que esta mesmo no ar antes de mexer.

Segundo: o estorno da limpeza pode devolver o dinheiro duas vezes se for chamado duas vezes.
Hoje isso nao acontece por causa da ordem das chamadas, mas e protecao por acidente, nao por
desenho.

Terceiro: criar reserva de limpeza nao tem guarda contra duplicado no servidor, e ha um
mecanismo que repete a chamada quando ha timeout, a contar com uma guarda que ali nao
existe. Um timeout pode criar duas reservas.

Fora do dinheiro, ficaram registados: o plugin do servico em primeiro plano nao implementa o
metodo que o Android 15 exige quando o servico passa das seis horas diarias, o que pode
matar a aplicacao a um motorista num turno longo; e o arranque automatico no boot esta ligado
num tipo de servico que o Android 15 ja nao permite arrancar assim. Nenhum dos dois e desta
missao.

Ha ainda um buraco no teste de traducoes que ja la estava: quando a chamada de traducao fica
na linha seguinte a frase, o teste nao a ve. Encontrei uma frase nessa situacao e traduzi-a
a mao, mas o teste continua cego a esse caso.

E ha um achado maior do que parecia. Um dos esquadroes reportou seis chaves de reservas sem
categoria, que por isso nao aparecem no painel. Fui contar: sao quarenta e nove chaves sem
categoria, de duzentas e quarenta e sete, e treze delas sao de dinheiro — carteira, taxas de
cancelamento e tokens. NAO as corrigi, e a razao nao e o trabalho: dar categoria a uma chave
torna-a VISIVEL e editavel no teu painel, e tornar treze chaves de dinheiro editaveis de uma
assentada e uma decisao tua, nao minha. Fica registado para decidires. As outras trinta e
seis, que nao sao dinheiro, dao-se por arrumadas numa passagem propria.

Duas notas menores dos ecras do cliente, ambas anteriores a hoje: a camara segue a leitura
crua enquanto o carro anda a animar atras dela, pelo que o carro fica sempre um pouco
atrasado em relacao ao centro; e a direcao do motorista, uma vez recebida, nunca mais e
limpa, por isso se o telemovel dele deixar de a mandar o carro aponta para sempre para o
ultimo lado conhecido.

## PARA O DANILO

Uma coisa so, e e capaz de ja estar feita.

A Google exige que as aplicacoes declarem na consola os tipos de servico em primeiro plano
que usam. Como as entregas ja usam o tipo de localizacao ha muito tempo, essa declaracao
provavelmente ja foi feita e nao ha nada a fazer. Vale a pena so confirmares que o tipo
location la esta, junto com os outros tres que a aplicacao usa. O caminho e Play Console,
depois conteudo da aplicacao, depois tipos de servico em primeiro plano. Se faltar, o texto
pronto a colar esta no relatorio do servico em primeiro plano que ficou nesta mesma pasta.

Nada nesta missao mexeu em precos, comissoes, no valor cobrado por paragem, na carteira, nos
tokens, na cadencia com que o servidor recebe a posicao do motorista, nem no motor que
distribui corridas.
