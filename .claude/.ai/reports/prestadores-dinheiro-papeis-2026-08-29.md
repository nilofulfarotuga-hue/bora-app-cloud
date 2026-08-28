# A porta de entrada, o dinheiro da semana, o painel dos papéis — e o toque

Data: 29 de Agosto de 2026, madrugada.

---

## Onde parei

Os três primeiros pontos estão feitos ponta-a-ponta, com prova por consulta em
cada passo. O quarto — a prova no telemóvel — **fiz metade e a outra metade é
tua**: o cabo continua desligado, o `adb devices` veio vazio outra vez, mas
descobri que não precisava dele para a parte que me competia. O teu telemóvel
está registado nas duas categorias desde ontem às 16h04, por isso disparei o
toque a sério pelo caminho real, e o servidor da Google aceitou os dois. O que
falta é alguém olhar para o ecrã, e esse alguém és tu.

Está tudo commitado e no `origin`.

---

## Todos os acessos

As palavras-passe continuo a não as ter, e a recuperação por email funciona
desde 27 de manhã. Qualquer conta se recupera em meio minuto.

Parceiros: `goola@bora.app`, `mr.kebab@bora.app`, `sabores.brasil@bora.app`,
`saboresde.casa@bora.app`, `ouro.prata@bora.app`, e `beunique@bora.app` que
está desligada por tua ordem.

Estafetas e motoristas: `boraappbora@gmail.com`, que é a tua e é a conta com os
cinco papéis; `nilofulfaro@gmail.com`, que também tem cinco;
`ramosjuniorwaldyr@gmail.com`, `valdemirvasconcelos28@gmail.com`,
`vanessaerika809@gmail.com` e `test_courier@boraapp.test`.

Lavadores: `lava.leva@bora.app`, mais as tuas duas contas, que agora aparecem
todas com o papel — ver mais abaixo.

Clientes de teste: `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`. A tua
conta de cliente é `nilofulfarotuga@gmail.com`, que é também a de admin.

---

## 1. Cadastro de prestadores

### O que estava mal, e era pior do que parecia

Não havia forma de ninguém se inscrever como lavador. Isso já sabias. O que
não sabíamos é que a tabela dos lavadores **não tinha o gatilho que dá o
papel** — a dos faxineiros tem um desde sempre, a dos lavadores não tinha
nenhum. Prova disso: dos três lavadores que existem, o "Lava & Leva" tinha
linha na tabela e **não tinha o papel** em lado nenhum. É a regra dos gémeos
outra vez: o papel vive em quatro sítios e um deles ficava por preencher.

### O que fiz

Na base, a candidatura de lavador nasceu no molde da de faxineiro, com uma
diferença de tabela — a dos lavadores não tem a coluna do material, que passa
a viver dentro dos documentos — e uma de ofício: quem se recandidata depois de
ter sido banido é recusado, porque desbanir é decisão tua e não dele. Criei o
gatilho que faltava, e os três lavadores passaram a ter o papel.

Os documentos do lavador ganharam balde próprio, com as **mesmas quatro
regras** do balde da limpeza, copiadas à letra — as que estão provadas desde
Julho, em que a pessoa só mexe na sua própria pasta e o admin lê tudo pelo
crachá do login, sem nunca consultar a tabela de contas, que é proibida.

Apanhei ainda uma coisa pelo caminho que vale registar: o Supabase dá
permissão de execução ao papel anónimo a **toda** a função nova, por omissão, e
essa permissão sobrevive a revogá-la do público. Tive de a tirar
explicitamente para a função ficar igual à irmã.

### A porta

O ecrã "Trabalhar no Bora" mostra as quatro actividades — entregas, corridas,
limpeza, lavagem —, o estado real de cada uma para quem está a olhar, e leva à
candidatura certa com os dados que já conhecemos da pessoa preenchidos. Quem já
é estafeta não reescreve nada.

Está no perfil, e está no ecrã de entrada, onde antes só se via a candidatura
de estafeta. Aparece com dois textos conforme quem olha: "Quero trabalhar no
Bora" para quem ainda não é nada, "O meu trabalho no Bora" para quem já é
alguma coisa.

Entregas e corridas partilham a candidatura porque partilham a tabela: quem já
é estafeta não se recandidata para passar a fazer corridas, liga o interruptor.
Isso está escrito na própria linha e há teste que o guarda.

O convite antigo, que era só da limpeza e estava **duplicado** em dois sítios
do perfil, foi apagado. A regra é apagar mesmo o que se substitui.

Sobre preencher todos os sítios onde o papel vive: ao **acrescentar** um papel
a quem já tem conta, os sítios que mexem são a tabela do papel e a lista de
papéis — e são os dois que o gatilho preenche agora. O crachá do login continua
a dizer em que modo a pessoa está a usar a app, que é outra coisa e está certo
assim.

---

## 2. O dinheiro do acerto semanal

### A prova mudou o desenho, e evitou pagar a dobrar

Antes de escrever uma linha fui ver a aritmética das quatro semanas de acerto
que existem a sério. Deu isto:

| semana | ganhos | dinheiro recebido em mão | dívida | saldo |
|---|---|---|---|---|
| 26/07 | 4,85 | 11,80 | 6,95 | −6,95 |
| 02/08 | 11,26 | 25,74 | 1,24 | −0,53 |
| 09/08 | 5,23 | 12,09 | 0,80 | −0,80 |
| 23/08 | 6,07 | 27,13 | 4,30 | −4,30 |

Em todas, o saldo é **exactamente menos a dívida**. Quer dizer: no estafeta a
dívida **já está abatida** dentro do saldo — a fórmula dele já desconta o
dinheiro que recebeu em mão. Se eu tivesse abatido a dívida outra vez, como
"abater a dívida" faz parecer óbvio, tinha duplicado a dívida de toda a gente.
Na semana de 26 de Julho isso seria cobrar 13,90 em vez de 6,95.

Na limpeza e na lavagem é ao contrário: o líquido é o ganho bruto, sem nada
abatido, porque normalmente é a Bora que tem o dinheiro. Quando o cliente paga
em dinheiro, o prestador ficou com a parte da Bora na mão e deve-a.

Por isso cada papel diz agora se a sua dívida já está descontada ou não, e o
total só desconta as que faltam. **Um número final, nenhum a dobrar.**

### O que passou a existir

O prestador tem um ecrã só — "Os meus ganhos" — com o que ganhou hoje, o que
ganhou esta semana, o detalhe por tipo de trabalho, e as últimas oito semanas
fechadas. Cada semana dá um número com sentido: ou a Bora paga, ou a pessoa
deve.

O painel do admin tem cada pessoa **uma vez só**, com entregas, corridas,
limpeza e lavagem somadas, os totais a pagar e a receber no topo, e o botão de
marcar como pago. Marcar pago corre as três tabelas de uma vez e inclui a
lavagem — a função antiga não a conhecia. Só muda o estado; não toca em valor
nenhum, e o diálogo diz-te isso antes de confirmares.

Exportar em ficheiro está lá. E aqui apanhei outro botão morto: o exportar
CSV, na **web**, fazia uma linha de registo e voltava. Ou seja, no painel que
tu usas mesmo, o botão de exportar não exportava e não dizia porquê. Arranjei
no serviço partilhado, portanto vale para todas as telas de admin de uma vez.

### Provado assim

Fiz o ensaio de marcar pago dentro de uma transacção e depois desfi-la. Dentro
da transacção o acerto passou a "tudo pago" e o valor manteve-se nos −0,80.
Depois de desfazer, voltou a "pendente", sem data de pagamento, e o valor
continuou −0,80. É a prova de que marcar pago muda o estado e não mexe no
dinheiro.

### ⚠️ Uma coisa que encontrei e NÃO mexi

Para uma limpeza ou lavagem paga **em dinheiro**, a função que fecha a semana
conta os ganhos do prestador como se a Bora lhos fosse pagar, quando ele já os
recebeu do cliente na mão. Isso pagaria duas vezes.

Não lhe toquei porque disseste para não mexer em cálculo nenhum, e isto é
cálculo. **Hoje o efeito é zero** — não há nenhuma limpeza nem nenhuma lavagem
paga em dinheiro por liquidar; confirmei-o por consulta às duas tabelas. Mas
passa a haver assim que a primeira aparecer.

Está tudo preparado do meu lado: o número da dívida já é medido e já é
mostrado. Falta só decidir se a fórmula do fecho passa a descontar o que o
prestador recebeu em mão. **Isto mexe em dinheiro — diz "vai" e eu aplico.**

---

## 3. O painel dos papéis

Não existia para categoria nenhuma, e agora existe, com duas abas.

Na primeira, as pessoas: cada uma com os papéis todos dela em etiquetas, o
estado da candidatura de cada papel que ainda não esteja aprovado, e os botões
de acrescentar e de tirar à mão. Tirar tem trava: se a pessoa tiver trabalho a
decorrer, recusa e diz porquê — deixar o cliente pendurado não é opção.

Na segunda, as candidaturas dos três papéis num sítio só, filtráveis por
estado, com aprovar e recusar. **Aprovar e recusar chamam as funções que já
existiam por papel**, aquelas que já mandam o aviso ao candidato. Não escrevi
decisão nova nenhuma: copiar essa lógica para aqui era criar gémeos numa coisa
que muda estado e manda avisos.

Ao lavador faltava a porta com nome — só havia uma função genérica de editar.
Fiz-lhe uma fachada fina por cima, que escreve exactamente o mesmo, para o
painel não ter de montar o pedido à mão em cada sítio.

Tudo em PT-BR, que é como tu queres o painel.

---

## 4. A prova no telemóvel

### O que consegui provar

O cabo continua desligado. O `adb devices` veio vazio, reiniciei o servidor e
veio vazio outra vez. Mas descobri que para a metade que é minha não precisava
dele.

O teu telemóvel — um Samsung Android, o mesmo aparelho nas duas linhas — está
registado para **limpeza e lavagem** desde ontem às 16h04, e usado às 17h03. Os
teus quatro interruptores estão todos ligados, e o portão que pergunta "esta
pessoa quer receber deste papel?" responde sim às duas.

Com isso, disparei o toque a sério: dois avisos, um de limpeza e um de
lavagem, pelo caminho real das funções que a rotação usa. As duas respostas do
servidor:

```
{"ok":true,"enviados":1,"aparelhos":1}   ← lavagem
{"ok":true,"enviados":1,"aparelhos":1}   ← limpeza
```

Ambas HTTP 200, e zero falhas registadas. Os avisos saíram para o teu aparelho.

Do lado da app confirmei por leitura do código que os quatro tipos das duas
categorias estão nos quatro sítios que importam: no conjunto dos que tocam de
forma persistente, no tratador que corre com a app fechada, no encaminhador, e
no que abre o ecrã certo quando se toca.

### O que falta, e é tua a metade

Ver. Se tocou com o ecrã aceso por cima, se tocou com a app em segundo plano,
se tocou com a app fechada, e se ao tocares no aviso abriu o ecrã certo. Se
alguma das três não tocou, diz qual, que aí é afinação do aparelho e não de
código.

Os dois avisos que te mandei dizem **TESTE** no título de propósito, para não
pensares que entrou trabalho a sério. Se lhes tocares, abrem o ecrã da
categoria e não encontram nada — o pedido não existe, era só o toque.

---

## Uma coisa pequena que encontrei

As duas funções de aviso irmãs pedem o destinatário com **nomes diferentes**: a
da lavagem aceita dois nomes por precaução, a da limpeza aceita só um. Bati
nisso à primeira tentativa e levei um erro 400. Fui ver quem a chama a sério: a
rotação da limpeza usa o nome certo, portanto **não há problema em produção** —
o erro foi meu, não dela. Não lhe mexi para não deixar o que está publicado
diferente do que está no repositório. Fica aqui escrito para a próxima pessoa
não perder os mesmos cinco minutos.

---

## Verificações

O `flutter analyze` corre com **zero erros**. Os testes passam todos —
**316**, treze deles novos, a guardar a porta de entrada: as quatro
actividades têm de estar lá, com o estado certo, nenhuma pode mostrar o nome
técnico do papel, e uma app velha a falar com a base nova não pode rebentar.

Os testes falharam à primeira por falta de memória — o PC tem 4 GB e dois
processos de teste ao mesmo tempo não cabem. Fechei o que estava aberto e
corri-os um de cada vez: passaram os 316. Não foi código.

As três migrações foram aplicadas e verificadas uma a uma por consulta.

Nada do que fiz toca em preços, comissões, tokens, despacho, `quote_order_pricing`,
`partner_shelf_price` nem no `versionCode`.

---

## Por ordem, para a seguir

Primeiro, olhar para o telemóvel e dizer-me se tocou nas três situações.

Segundo, o "vai" para a dívida das limpezas e lavagens pagas em dinheiro, se
concordares com o raciocínio.

Terceiro, o que ficou de trás da sessão anterior: alinhar o cartão da limpeza e
da lavagem pelo caminho já provado das entregas, os ladrilhos, e o site do
Mr Kebab.
