# Missao TVDE — o cliente ve o carro, a avaliacao nao prende, o mapa nao trava
Data: 5 de setembro de 2026. Branch autonomous-night-2026-04-29.

## O que se passava

Corridas reais de hoje, com passageiro a pagar. No telemovel do cliente nao aparecia o
carro no mapa, nem quem era o motorista, nem que carro era, nem a matricula, nem tempo
nenhum de chegada. O cliente teve de telefonar ao motorista para saber quantos minutos
faltavam. No fim ficou preso no ecra de avaliacao: carregou em enviar e nao aconteceu
nada, so saiu pelo agora nao. E o mapa do motorista travava e nao recalculava a rota
quando ele se desviava.

Esta tudo corrigido. Segue o que mudou, com as provas.

## A causa de o cliente nao ver nada era uma so

A tabela dos motoristas tem regras de seguranca que so deixam o proprio motorista e o
administrador ler a linha. Nao existia regra nenhuma que deixasse um cliente ler. O ecra
pedia a tabela, recebia vazio, e o erro morria num apanhador de erros mudo. Por isso nao
havia carro no mapa, nem nome, nem matricula, nem foto, nem estrelas, nem telefone. E como
nao havia posicao do motorista, tambem nao havia tempo de chegada. Um problema so, sete
sintomas.

Nao se abriu a tabela ao cliente, e nunca se deve abrir: la dentro estao o IBAN, o numero
de contribuinte, a morada, a foto do documento de identidade e a conta do Stripe do
motorista. Passou a usar-se uma funcao propria que devolve so o que e publico, e que so
responde a quem e mesmo o passageiro daquela corrida. Confirmei por consulta directa a base
que essa funcao existe mesmo em producao e que corre com privilegios elevados. Qualquer
outra pessoa que pergunte leva um nao.

Deixei um teste que impede alguem de voltar a ler a tabela directamente, e outro que
impede o apanhador de erros mudo de voltar. Foi o silencio dele que escondeu isto durante
semanas.

## O que o cliente ve agora

O motorista deixou de ser um alfinete laranja e passou a ser um carro azul visto de cima,
desenhado em codigo, que aponta para onde o carro segue. A direccao e suavizada para nao
tremer com o ruido do sinal, e a suavizacao vai pelo caminho mais curto da circunferencia,
senao passar de trezentos e cinquenta e nove graus para um grau dava uma pirueta. Azul
porque o verde e o laranja ja sao as cores da casa e ja estao nos pontos de recolha e
destino.

O cartao mostra a foto redonda, o nome proprio a serio, as estrelas com o numero de
avaliacoes ao lado, o carro em destaque, e a matricula numa moldura propria, grande, no
formato portugues com tracos. A matricula e o elemento mais importante do cartao porque e
por ela que a pessoa reconhece o carro certo na rua. O formatador e defensivo: se a
matricula ja vier com tracos, ou se nao tiver seis caracteres, fica como esta. Nunca se
inventa um formato que a base nao tem.

O tempo de chegada recalcula a cada leitura e a cada mudanca de fase, e nunca mostra zero
nem numeros negativos. Quando o carro esta a menos de cem metros, ou travado a menos de
cento e cinquenta, o ecra diz que o motorista chegou sem esperar pelo aviso do servidor.

E ha agora um aviso no telemovel quando faltam dois minutos, a dizer o nome, o carro e a
matricula. Reutiliza o canal de avisos que ja existia, nao se criou canal novo. Dispara uma
vez por corrida.

## A regra dos vinte por cento, e um aviso honesto

Cumpri a tua regra: o tempo que o cliente ve e menor que o real. Dez minutos mostram oito,
que e o teu exemplo. O corte tem um tecto de dois minutos, por isso trinta minutos mostram
vinte e oito e nao vinte e quatro. Nunca desce abaixo de um minuto. Esta tudo em definicoes
que podes mexer no painel, sem esperar por versao nova.

O aviso, que fica escrito porque prometi dizer-to: encurtar o tempo mostrado e o contrario
do que o mercado faz. As aplicacoes grandes poem de proposito uma folga para mais, porque
chegar antes do previsto agrada e chegar depois irrita. Nas analises de milhares de
avaliacoes negativas de Uber, Bolt, Lyft e Grab, a queixa sobre tempos de chegada e sempre a
mesma: as pessoas preferem ver quinze minutos e o carro chegar, do que ver tres e esperar
dez. O Uber chegou ao ponto de deixar cancelar sem multa quando o motorista passa cinco
minutos do prometido.

O que tu queres mesmo, que e o cliente ja estar a porta quando o motorista chega, e o aviso
dos dois minutos que ficou construido. Esse resolve o problema sem enganar ninguem. Se um
dia quiseres seguir o mercado, poes a percentagem a zero no painel e o cliente passa a ver o
tempo verdadeiro, sem precisares de nada de mim. Deixei um teste que prova que pôr a zero
devolve mesmo o tempo real.

Uma coisa que quero deixar clara: o desconto e so no numero mostrado. O aviso dos dois
minutos usa sempre o tempo verdadeiro. Se usasse o descontado, o aviso saia tarde e era pior
do que nao existir.

## A avaliacao que prendia

Encontrei a causa exacta. O botao de enviar estava ligado a um unico interruptor de ocupado
partilhado por dezenas de operacoes do sistema. Bastava outra coisa qualquer estar a meio,
um refrescar, uma leitura, e o botao nascia morto, a rodar. O agora nao funcionava porque
era um botao de outro tipo, que nao olhava para esse interruptor. Bate exactamente com o que
o cliente descreveu.

Agora cada ecra tem o seu proprio estado de envio e trava so o seu proprio pedido. Alem
disso a porta ficou sempre aberta: ha espera curta de seis segundos e, se estourar, o ecra
fecha na mesma e diz que a avaliacao segue mais tarde; a avaliacao que nao saiu fica
guardada e vai sozinha na proxima vez; o botao fisico de voltar do Android sai e limpa a
corrida; e se falhar de vez, mostra o aviso e deixa sair. O mesmo foi feito no ecra do
motorista.

A fila de reenvio distingue uma recusa definitiva do servidor de uma falha de rede. O
servidor recusa avaliar duas vezes, e uma fila ingenua ficaria a bater nessa recusa para
sempre.

## A varredura, que foi metade do valor

Procurei o mesmo defeito no programa inteiro e ele estava em cerca de trinta sitios. O mais
grave nao era a avaliacao: era o botao de recusar uma corrida encadeada no ecra do
motorista. Essa oferta tem contagem decrescente, e o botao morto durante alguns segundos
significa a oferta a expirar sozinha nas maos dele, sem ele poder fazer nada. Corrigi esse
eu proprio.

Corrigidos: os dois ecras de avaliacao, o botao de sair do assistente de limpeza, e o
recusar e aceitar da oferta encadeada do motorista.

Listados e nao corrigidos por serem zona de dinheiro, que so mexo com ordem tua: pagar
pendente e cancelar com estorno no acompanhamento da limpeza, confirmar reserva no
assistente de limpeza, adesao a planos no TVDE, e o botao de finalizar compra. Todos estes
tem saida, ou seja ninguem fica preso, mas o botao de agir pode morrer por causa de outra
coisa a correr. Nao lhes toquei.

Listados e nao corrigidos por terem saida e risco menor, para tu decidires: concluir limpeza
e aceitar ou recusar ofertas no ecra da profissional de limpeza, guardar disponibilidade,
candidaturas de limpeza e de lavagem, chamar corrida, e alguns paineis do administrador.

Um sitio ja estava certo, com um comentario a explicar exactamente este mesmo defeito. A
casa ja tinha aprendido isto uma vez e a licao nao se espalhou.

## O mapa do motorista

Havia duas causas e a segunda nao estava no teu mapa. A primeira: a aplicacao pedia uma rota
nova a cada cento e onze metros, o que a conduzir e um pedido de oito em oito segundos, e
nunca perguntava se o motorista tinha saido da linha. A segunda, que descobri ao ler o
codigo e o esquadrao do mapa confirmou por caminho proprio: o ecra so recebia uma posicao
verdadeira a cada cinquenta metros, com precisao media. A cinquenta a hora isso e uma
posicao de tres segundos e meio em tres segundos e meio. A animacao cobria um segundo e o
mapa ficava congelado os outros dois e meio. Era isso o travar, e nenhuma afinacao de camara
conserta um mapa que so sabe onde o carro esta de cinquenta em cinquenta metros.

O ecra passou a ter sinal proprio, com precisao de navegacao e filtro de tres metros. Nao se
mexeu no sinal que alimenta o servidor, que continua nos cinquenta metros porque para dizer
ao servidor onde o motorista anda isso chega, e porque esse alimenta o motor de distribuicao,
que nao se toca.

O recalculo passou a ser por desvio a serio: distancia perpendicular a linha desenhada,
acima de quarenta e cinco metros, durante tres leituras seguidas, com um minimo de quinze
segundos entre recalculos. Usa distancia ao segmento e nao ao ponto mais proximo, e a
diferenca nao e teorica: numa rua direita de seiscentos e oitenta metros com dois pontos, o
carro em cima da linha da zero metros pela conta certa e trezentos e trinta e oito metros
pela conta errada. Seria um desvio falso a cada rua comprida.

A camara deixou de ter travao e encadeia agora animacoes de novecentos milissegundos, mais
longas do que o intervalo entre leituras, para o movimento nunca parar. A linha da rota
apaga-se atras do carro. E os valores todos, zoom, inclinacao, sensibilidade de desvio,
suavidade da camara, ficaram no painel do administrador para tu afinares sem esperar por
versao nova.

## Quantas chamadas ao servico de rotas

Antes, numa corrida de mil e quinhentos metros ate ao passageiro mais quatro quilometros de
viagem, eram cerca de sessenta chamadas, uma a cada oito segundos. Agora, com o motorista a
seguir a rota, sao duas: uma para o troco ate a recolha e outra ate ao destino. Mais uma por
cada paragem que o passageiro acrescente e uma por cada engano real ao volante. E de
sessenta para duas, cerca de noventa e sete por cento menos. E o pior caso passou a ter
tecto, quatro por minuto, contra sete e meia por minuto que a versao antiga fazia so por
andar.

## Os pacotes

Aqui o teu mapa estava meio certo. O pacote dos mapas nao estava velho: o ficheiro dizia uma
versao antiga como minimo, mas o que estava mesmo instalado ja era a versao mais recente.
Confirmei que nem sequer aparece na lista de desactualizados. E fui ao codigo do proprio
pacote instalado ver como desenha: o modo antigo, que e causa conhecida de tremura, esta
desligado por defeito e o projecto nunca o liga. Ou seja ja estavamos no modo bom.

O pacote de localizacao esse estava mesmo velho, quatro versoes maiores atras. Subi-o. Deu
conflito a primeira, por uma cadeia que acaba no pacote que guarda as credenciais, e a saida
foi fixar uma versao ligeiramente anterior. Ficou a funcionar, sem erros e com todos os
testes verdes.

Uma coisa importante que descobri e que deixei escrita no proprio ficheiro: a lista de
versoes travadas nao vai para o servidor de compilacao, ou seja ele resolve tudo de novo
sozinho. Por isso a versao ficou fixa, sem o simbolo que permite subir. Se alguem
"arrumar" isso e puser o simbolo, o servidor apanha a versao seguinte e a compilacao para.
Ficou um aviso em portugues no ficheiro a explicar porque nao se deve mexer. Testei a
resolucao do zero, sem lista travada, tal como o servidor faz, e resolveu certo.

## As provas

Analise estatica sem um unico erro. Sao duzentas e catorze notas de estilo, menos do que as
duzentas e quinze que ja estavam antes de eu comecar, e nenhuma delas nos ficheiros desta
missao. Os dez avisos existentes sao todos anteriores, em ecras que nao toquei.

Bateria de testes inteira verde: quatrocentos e catorze testes, contra os trezentos e vinte
e quatro da ronda anterior. Corri-a duas vezes, a segunda depois de reinstalar as
dependencias todas de raiz.

Escrevi quatro ficheiros de teste novos. Um prova a regra dos vinte por cento com o teu
exemplo dos dez que mostram oito, o tecto dos dois minutos, o minimo de um, e que valores
disparatados postos no painel nunca produzem zero nem negativos nem um tempo maior que o
real. Outro prova o desvio de rota com coordenadas verdadeiras da Guarda, com as distancias
calculadas por trigonometria a mao e nao pela propria funcao, senao o teste era circular:
quem segue a rota nao dispara nada, e quem esta a sessenta metros durante tres leituras
dispara um e so um. Outro prova que o botao de avaliar nao depende do estado global e que
nenhuma avaliacao se perde. E o ultimo prova o contrato do cartao do motorista e impede a
volta atras.

## O que nao foi provado, e digo-o de frente

Nao houve prova em telemovel real nem em emulador com reproducao de rota. Nao ha nenhum
Android ligado por cabo a este computador, e o computador tem quatro gigabytes, o que nao
chega para o emulador ao lado de tudo o resto. Isto significa que o mapa a mexer numa corrida
a serio, e o carro azul no ecra do cliente, ainda nao foram vistos por olhos humanos. O
que segue neste envio e o que poe este codigo na loja para essa prova poder ser feita quando
actualizares o telemovel.

Tambem nao foi feito o teste no navegador com duas contas em paralelo. Fica em divida e e a
proxima coisa a fazer.

## O estudo da navegacao a serio, que nao vai para producao

Ficou num relatorio a parte, chamado estudo google navigation flutter, na mesma pasta.
Resumo: o caminho existe e e o plugin oficial da Google, mas corrigiu-me em quatro pontos.
A versao e a onze, saida ha cinco dias, e nao a dez de Julho. As mil rotas gratis sao mil
destinos, e a partir dai sao dois centimos e meio por corrida. Os recalculos por desvio sao
mesmo de graca. E o conflito com o mapa actual e real e tem explicacao: o plugin de navegacao
traz o motor de mapas dentro dele e o nosso traz outro, ficam duas copias das mesmas classes.
Em dez meses quebrou compatibilidade cinco vezes e nao tem garantia de servico nem suporte.
A recomendacao e migrar depois do lancamento, so o lado do motorista, e atras de um
interruptor que se possa desligar.

## Outros defeitos encontrados pelo caminho, listados e nao corrigidos

As paragens que o passageiro acrescenta nao entram na rota do motorista. Ele paga os dois
euros da paragem e a linha continua a apontar ao destino final. A funcao de rotas ja aceita
paragens, so nunca lhe sao passadas. Este parece-me o mais importante da lista.

O passageiro continua a ver o carro a saltar de cinquenta em cinquenta metros, porque e essa
a cadencia com que o servidor e actualizado. Arranjou-se o mapa do motorista; o do cliente
depende desse envio.

Ficam dois sinais de localizacao abertos durante a corrida. Funciona, mas gasta mais bateria.

Nenhum dos sinais do TVDE se declara como servico em primeiro plano no Android, ao contrario
do mapa das entregas. Se o motorista minimizar a aplicacao a meio de uma corrida, o sistema
pode estrangular o sinal. Vale a pena confirmar num telemovel a serio.

A funcao nova devolve a hora da ultima posicao conhecida e ninguem a usa. Dava para dizer
posicao de ha tantos minutos quando o sinal do motorista esta velho. Hoje um carro com sinal
morto parece um carro parado.

O ficheiro de configuracao da analise estatica foi alterado por outra sessao, nao por mim,
para excluir pastas de compilacao. Vai neste envio porque ja la estava.

## Para o Danilo

Ha tres decisoes que sao tuas e que eu nao tomo.

A primeira e o tempo encurtado. Esta feito como pediste, vinte por cento a menos com tecto
de dois minutos. Se depois de leres o aviso la em cima quiseres seguir o mercado, poes a
percentagem a zero no painel e fica resolvido, sem versao nova.

A segunda e a chave da Google para a navegacao a serio, que so se resolve se um dia
avancarmos com isso. Liga um artigo pago com mil destinos gratis por mes e dois centimos e
meio por corrida a partir dai. E pouco dinheiro mas e dinheiro real e e um botao que so tu
podes carregar.

A terceira e o peso da aplicacao. O motor de navegacao da Google pesa trinta e tres
megabytes e a aplicacao dos estafetas e instalada em telemoveis modestos. E uma decisao de
produto, nao de engenharia.

Nada nesta missao mexeu em precos, comissoes, carteira, tokens, pagamentos ou no motor que
distribui corridas.
