# A caixa dos papéis, e a primeira peça do acerto único

Data: 28 de Agosto de 2026, fim da noite.

---

## Onde parei

Fiz a caixa "O que queres aceitar?" por inteiro, com os interruptores a mexerem
mesmo em quem recebe o quê. Do acerto semanal fiz a **primeira peça**, que é a
que junta as contas, e parei aí de propósito — o resto mexe em dinheiro que sai
para pessoas.

**Não fiz** o painel admin dos papéis. **Não fiz** a prova no telemóvel, e a
razão é a mesma de ontem, que não mudou. **Não fiz** o ecrã do prestador nem o
painel do acerto, nem a exportação, nem a semana de teste.

---

## Todos os acessos

As palavras-passe continuo a não as ter. A recuperação por email funciona desde
esta manhã, com prova, e qualquer conta se recupera em meio minuto.

Parceiros: `goola@bora.app`, `mr.kebab@bora.app`, `sabores.brasil@bora.app`,
`saboresde.casa@bora.app`, `ouro.prata@bora.app`, e `beunique@bora.app` que está
desligada por tua ordem.

Estafetas e motoristas: `boraappbora@gmail.com` que é teu, `nilofulfaro@gmail.com`,
`ramosjuniorwaldyr@gmail.com`, `valdemirvasconcelos28@gmail.com`,
`vanessaerika809@gmail.com` e `test_courier@boraapp.test`.

Clientes de teste: `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`. A tua
conta de cliente é `nilofulfarotuga@gmail.com`.

As duas contas com os quatro papéis são a tua, `boraappbora@gmail.com`, e a
`nilofulfaro@gmail.com`. Confirmei as duas na base: cliente, motorista,
faxineiro e lavador. E confirmei que o CHECK do `user_roles` já aceita lavador —
sem isso, ninguém se podia sequer inscrever nessa categoria.

O único lavador com linha própria é `lava.leva@bora.app`.

---

## A caixa "O que queres aceitar?"

Está feita e o interruptor mexe mesmo.

Era um rádio de duas opções fixas, e é por isso que tu não vias a limpeza nem a
lavagem: a caixa nunca soube que existiam. Passa a ser construída dos teus
papéis reais, lidos da tabela que os guarda. Quem tem dois vê dois; tu, que tens
quatro, vês três interruptores de trabalho — corridas e entregas, limpeza,
lavagem de carros — porque o de cliente não é trabalho.

Cada um liga e desliga por si. A escolha fica no servidor, por isso sobrevive a
fechar a app e acompanha-te se trocares de telemóvel.

Duas decisões que tomei e que quero explicar. Primeira: quem só tem um papel não
vê caixa nenhuma, porque não tem escolha para fazer e uma caixa de uma linha só
estorva — foi o que pediste. Segunda: não deixo desligar o último que está
ligado. Ficarias online sem receber nada, e isso lê-se como avaria e não como
escolha; para parar de todo existe o "estou online", que é o interruptor feito
para isso. Quem tenta vê uma frase a dizer exactamente isso.

E há uma parte que era fácil esquecer e que faz toda a diferença: **as funções
que enviam os avisos passam a perguntar se a pessoa quer receber daquele papel
antes de enviar**. Sem isso o interruptor era decorativo — ligava e desligava
uma coisa que ninguém consultava. Já tivemos disso que chegue nesta semana.

Provei na base com a tua conta: ler os três papéis, desligar a limpeza, ver que
quem envia passa a receber "não", e voltar a ligar. Treze testes novos.

Dentro do papel de condução ficou a distinção que já existia, entre só
passageiros e passageiros mais entregas, porque essa mora noutro sítio e é lida
pelo dispatch das corridas.

**Não fiz o painel admin dos papéis** — ver e mudar os papéis de qualquer
pessoa. Fica para a sessão seguinte.

---

## A prova no telemóvel

Não a fiz, e não é teimosia. O telemóvel está ligado, confirmei com o `adb`, e
vejo-o como `RZGYB1XQD2P`. O problema é outro: **o que está instalado nele é a
versão da loja**, que não tem nada do que se fez ontem nem hoje. Um teste agora
provava a app velha e dava-te uma resposta falsa — que é exactamente o que já
aconteceu duas vezes e que te fez, com razão, exigir prova.

A tabela dos tokens continua com zero linhas, e isso é o esperado: o registo
acontece ao entrar na app, e a app que tem o registo ainda não está no
telemóvel. Confirmei no código que o registo passa a acontecer no portão de
autenticação, para qualquer papel e para todos ao mesmo tempo, e não só nos
antigos como pediste que verificasse.

A ordem é esta e não dá para saltar: isto sobe, o CI constrói, actualizas pela
Play Store, entras uma vez como faxineiro para o aparelho ficar registado, e aí
faço o teste do toque com o telemóvel por cabo. Confirmo o token na base em
segundos assim que entrares.

---

## O acerto único — a primeira peça, e duas armadilhas

Li as três tabelas antes de desenhar, como mandaste, e ainda bem, porque havia
duas coisas escondidas lá dentro que dariam erro em dinheiro.

**A primeira são as unidades.** A tabela do motorista guarda **euros**: o teu
acerto da semana de vinte e três de Agosto tem menos quatro euros e trinta. As
tabelas da limpeza e da lavagem guardam **cêntimos** em número inteiro. Somar os
campos directamente dá um erro de cem vezes — a diferença entre pagar quatro
euros e pagar quatrocentos. Converti tudo para cêntimos inteiros, que é a única
unidade em que dinheiro se soma sem arredondar pelo caminho.

**A segunda é a identidade, e é pior.** A tabela do motorista aponta para a
pessoa. As da limpeza e da lavagem apontam para a linha do faxineiro e do
lavador, que é outra coisa. Juntar por identificador às cegas casava o acerto de
um motorista com a linha de um faxineiro qualquer — e ninguém daria por isso até
alguém receber o dinheiro de outra pessoa.

Feita a vista que junta as três, com isto resolvido. Uma linha por pessoa e por
semana, com o detalhe aberto por tipo de trabalho, as duas parcelas separadas
antes do total, e um número único no fim com o sentido: ou a Bora paga, ou a
pessoa deve.

Provei contra os dados reais que já lá estavam. Os teus menos quatro euros e
trinta aparecem como menos quatrocentos e trinta cêntimos, com o sentido "pessoa
deve". A semana de dois de Agosto aparece com dívida de cento e vinte e quatro
cêntimos e total de menos cinquenta e três, que é exactamente o que a tabela de
origem diz em euros. Confere linha a linha.

**O que não construí, e porquê.** O ecrã do prestador, o painel de admin com o
botão de pagar, a exportação para a contabilidade, e a semana de teste com um
trabalho de cada tipo. Duas razões, e a segunda é a que manda: a primeira é que
não cabia bem nesta sessão e preferi entregar a peça de baixo sólida a entregar
quatro meias; a segunda é que **o abate da dívida e o botão de pagar mexem em
dinheiro que sai para pessoas**.

⚠️ ISTO MEXE EM PAGAMENTO. A parte que junta e mostra está feita e é só de
leitura — não escreve, não paga, não altera valores. A parte que abate a dívida
e marca como pago está por fazer e espera que digas "vai".

---

## Verificações

O `flutter analyze` corre com zero erros. Os testes passam todos: duzentos e
noventa e seis, treze a mais do que na última corrida. Duas funções republicadas
e a responder. Duas migrações aplicadas, ambas de leitura ou de preferência,
nenhuma financeira. Commits empurrados.

---

## Por ordem, para a seguir

Primeiro, deixar o CI construir e actualizares a app no telemóvel.

Segundo, entrares uma vez como faxineiro — e aí faço o teste do toque, que é a
prova que falta desde ontem.

Terceiro, o painel admin dos papéis.

Quarto, e depois de dizeres "vai", o resto do acerto: o ecrã do prestador, o
painel com o botão de pagar, a exportação, e a semana de teste com a dívida
abatida.
