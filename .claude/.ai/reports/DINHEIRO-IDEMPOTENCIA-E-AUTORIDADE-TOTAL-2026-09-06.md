# Os tres buracos de dinheiro e a autoridade total no painel
Data: 6 de setembro de 2026. Branch autonomous-night-2026-04-29.
Fecha as duas coisas que tinham ficado a espera do teu "vai".

## O que aconteceu, em duas frases

Os tres buracos que eu tinha diagnosticado ontem ja estavam tapados no servidor
quando fui la hoje — nao por mim, por outra sessao. Se eu tivesse feito o que a
ordem dizia e enviado a correccao a partir do repositorio, teria APAGADO as tres
correccoes que ja la estavam.

## Porque e que isso quase aconteceu, e como se evitou

A primeira coisa que fiz nao foi escrever codigo: foi ler o que esta MESMO no ar.
E ainda bem. A funcao dos planos e do pacote esta na versao nove. O diagnostico de
ontem dizia versao sete no ar e cinco no repositorio. Estava desactualizado outra
vez, na mesma direccao: o ar a andar mais depressa do que o repositorio.

Isto ja tinha mordido antes e esta escrito na memoria da casa. Hoje foi a segunda
vez que valeu a pena. A regra confirma-se: antes de enviar uma funcao, ler a que
la esta. Nunca deployar do repositorio as cegas.

## O estado real dos tres buracos

O primeiro, a chave de idempotencia no pacote ida-e-volta: ja la esta, e tambem no
plano, tanto em cartao como em MB Way. A funcao aceita um identificador vindo da
aplicacao e, quando ele nao vem, usa uma janela de dez minutos por utilizador e
valor.

O segundo, o estorno da limpeza que podia devolver duas vezes: ja tem duas travas.
Primeiro pergunta a Stripe se aquele pagamento ja tem estorno e, se tiver, devolve
o que ja existe sem criar nada. Depois, o pedido leva uma chave fixa por reserva,
por isso duas chamadas ao mesmo tempo devolvem o mesmo estorno.

O terceiro, a reserva de limpeza que um timeout podia duplicar: a funcao da base
passou a aceitar uma chave, tem uma trava de concorrencia e, se a reserva ja
existir, devolve a que existe em vez de criar outra. Ha tres reservas na base ja
gravadas com chave.

## O que faltava mesmo, e era grave

Uma chave de idempotencia so serve se a segunda tentativa mandar a MESMA chave. E
no pacote ida-e-volta a aplicacao estava a mandar uma chave nova a cada toque.

O identificador nascia dentro do metodo que faz o pagamento, com um gerador de
identificadores unicos. Ou seja: o cliente carrega, nao ve resposta, carrega
outra vez, e as duas tentativas vao com identificadores diferentes. A Stripe cria
dois pagamentos. Duas cobrancas.

E ha uma parte pior. Como a aplicacao manda o identificador, o servidor deixa de
aplicar o recurso dele proprio, que e a janela de dez minutos por utilizador e
valor. Essa janela teria apanhado os dois toques. Ou seja: mandar um
identificador novo era pior do que nao mandar nenhum. O ecra dos planos ja fazia
isto bem — guardava o identificador por plano — e o do pacote nao.

Agora o identificador vive no ecra, e nao dentro do metodo. E reutilizado
enquanto a compra e a mesma, e renovado em dois momentos: quando a compra fecha,
para uma segunda compra igual nao reusar a chave e ficar por cobrar; e quando o
preco muda, porque a Stripe recusa a mesma chave com um valor diferente e sem
isso mudar a rota depois de uma tentativa falhada dava erro em vez de compra nova.

Dez testes guardam isto, e o primeiro deles reprova exactamente o regresso do
padrao antigo.

## A segunda parte: as chaves invisiveis do painel

Tambem aqui metade do trabalho ja estava feito. As quarenta e nove chaves sem
categoria foram todas categorizadas. Confirmado por consulta directa: zero chaves
sem categoria, num total de duzentas e quarenta e oito, repartidas por trinta
categorias.

Mas a ordem tinha duas metades, e a segunda nao e base de dados, e programa: elas
ficarem EDITAVEIS. E aqui houve uma descoberta que mudou o desenho. A funcao do
servidor que grava uma definicao nunca teve lista branca nenhuma: aceita qualquer
chave e ja regista quem mudou. A unica coisa que te impedia de editar as chaves de
dinheiro era a lista do lado da aplicacao.

Abri-a, como mandaste. Mas com uma diferenca que quero que saibas: uma chave de
dinheiro nunca passa pela caixa de edicao comum. Vai por um caminho proprio que
exige MOTIVO escrito e que grava no registo de auditoria quem mudou, de quanto
para quanto, quando e porque. E o mesmo tratamento que as taxas de cancelamento ja
tinham desde ha meses. Autoridade total nao e o mesmo que mudar dinheiro sem
deixar rasto, e tu pediste as tres coisas: ver, editar e auditar.

Criei para isso uma funcao nova na base, que alem do motivo tem uma trava que nao
te vai estorvar mas que evita um estrago silencioso: nao deixa trocar o TIPO do
valor. Um numero continua numero, um interruptor continua interruptor. Trocar o
tipo partia quem le a chave durante uma corrida ou um checkout, e o erro so
aparecia la, longe do ecra onde foi feito.

## Um erro meu, apanhado pelo meu proprio teste

Ao classificar o que e uma chave de dinheiro, usei a palavra "ratio" como marca. E
"ratio" esta dentro de "duration". Resultado: afinar a duracao de uma lavagem de
carro passava a exigir motivo escrito. Nao era grave, mas era irritante e errado.
O teste apanhou-o antes de sair daqui. Passou a "_ratio", com o traco.

## As provas, por consulta e nao pela minha palavra

Chaves sem categoria: zero. Total de chaves: duzentas e quarenta e oito.
Categorias distintas: trinta. Funcao auditada de dinheiro criada: existe, com
motivo obrigatorio e privilegio elevado. A funcao de criar reserva de limpeza
aceita chave de idempotencia: sim. Reservas ja gravadas com chave: tres.

Analise estatica com zero erros. Bateria de testes inteira verde: quatrocentos e
setenta e tres testes, contra quatrocentos e cinquenta e cinco antes desta
missao. Dezoito testes novos, divididos entre a idempotencia dos pagamentos e a
autoridade no painel.

Um dos testes novos merece nota: ele verifica que a lista de marcas do teste nao
divergiu da lista do ecra. Sem isso, alguem apertava a classificacao no programa,
uma chave de dinheiro caia na caixa comum sem motivo nem auditoria, e a bateria
continuava verde. Um teste que verifica uma copia de si proprio nao verifica nada.

## O que NAO foi feito, e porque

Nenhum valor foi alterado. Nem um preco, nem uma comissao, nem uma percentagem,
nem um centimo. So se criou o caminho e se impediu a repeticao, que era o que
mandaste.

Nao mexi nas tres funcoes do servidor que ja estavam corrigidas. Confirmei-as e
deixei-as em paz.

E ha uma coisa que te devo dizer sobre as chaves que abri. Algumas sao ESPELHO de
restricoes da base de dados. A que limita o saldo negativo da carteira diz na
propria descricao que copia uma restricao da tabela dos saldos. Mudar essa chave
no painel muda o numero que o programa le, mas NAO muda a restricao real na base.
Ficam a divergir em silencio, e o efeito so aparece quando um cliente bate no
limite verdadeiro em vez do que tu puseste. Sao poucas e reconhecem-se pelo nome:
as que falam de limite absoluto da carteira. Se quiseres, numa proxima ordem
alinho as duas pontas para que mudar no painel mude tambem a restricao.

## PARA O DANILO

Nada aqui espera decisao tua. As duas coisas que pediste estao feitas, e a parte
que ja estava feita esta identificada como tal, para nao te vender trabalho que
nao foi meu.

A unica coisa que te deixo, e nao e urgente, e o alinhamento das chaves que
espelham restricoes da base, explicado no paragrafo acima.
