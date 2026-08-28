# A rotação da lavagem, o chamamento igual para todos, e onde parei

Data: 28 de Agosto de 2026, madrugada de 29.

---

## Onde parei

Fiz os blocos 2, 3 e 7 por inteiro. O bloco 1 estava feito e tu confirmaste-o
a meio, por isso só lhe tirei uma coisa que continuava lá escondida. Os blocos
4, 5, 6 e 8 **não foram feitos**.

E a prova no telemóvel **não a consegui fazer**, mas desta vez por razão nova:
o cabo desligou-se. O `adb devices` veio vazio, reiniciei o servidor e veio
vazio outra vez. Não insisti mais. Quando o ligares, é meia hora.

---

## Todos os acessos

As palavras-passe continuo a não as ter, e a recuperação por email funciona
desde ontem de manhã, com prova. Qualquer conta se recupera em meio minuto.

Parceiros: `goola@bora.app`, `mr.kebab@bora.app`, `sabores.brasil@bora.app`,
`saboresde.casa@bora.app`, `ouro.prata@bora.app`, e `beunique@bora.app` que
está desligada por tua ordem.

Estafetas e motoristas: `boraappbora@gmail.com` que é teu — e é a conta com os
cinco papéis —, `nilofulfaro@gmail.com` que também tem os cinco,
`ramosjuniorwaldyr@gmail.com`, `valdemirvasconcelos28@gmail.com`,
`vanessaerika809@gmail.com` e `test_courier@boraapp.test`.

O único lavador com linha própria é `lava.leva@bora.app`.

Clientes de teste: `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`. A tua
conta de cliente é `nilofulfarotuga@gmail.com`, que é também a de admin.

---

## Bloco 1 — o que ainda lá estava

Confirmaste a meio que o ecrã já estava certo, e estava: os quatro nomes em
português com as descrições certas. Não lhe toquei mais.

Mas tinha começado antes de tu me dizeres, e apanhei uma coisa que valia a
pena tirar. O menu antigo das duas opções **tinha desaparecido da caixa**, sim,
mas continuava vivo noutro caminho: uma função de recurso que se abria a quem
tivesse um papel só. E essa função escrevia `drivers.work_mode` **à mão** — o
mesmo campo que passou a ser projecção da preferência. Eram gémeos com atraso:
dois sítios a escrever a mesma verdade, e um deles à espera da primeira pessoa
com um papel só para se contradizerem.

Apaguei a função e apaguei também quem escrevia por ela. Já não há um único
vestígio de `rides_only` nesse ecrã.

Fechei ainda a porta por onde entrou o "delivery" em inglês: o tradutor de
nomes deixou de devolver o nome cru quando não conhece um papel. Devolve um
rótulo neutro, e há um teste que rebenta se um papel conhecido chegar ao ecrã
sem tradução. Da próxima vez o erro aparece na minha corrida de testes e não no
teu telemóvel.

---

## Bloco 2 — o chamamento

Comecei por ler, como mandaste, e ainda bem, porque encontrei uma decisão
antiga que eu ia contrariar sem saber.

**O que já existe.** Há uma peça partilhada, `IncomingJobAlert`, escrita a 18
de Julho precisamente para isto: extraiu o padrão que o estafeta já usava —
canal urgente, ecrã aceso por cima do que estiver à frente, som `bora_alert` em
ciclo, texto grande — para qualquer papel poder disparar o mesmo alerta sem
duplicar a mecânica. A limpeza já a usa. O parceiro usa. O motorista usa.

**A decisão que eu ia contrariar.** No topo desse ficheiro está escrito, em
maiúsculas: proibido usar `FlutterOverlayWindow`. Foi removido de propósito, e
a razão está escrita ao lado — o sistema de oferta do estafeta é delicado,
testado em aparelho e a funcionar, e mexer-lhe às cegas arriscava partir uma
peça central. O que faz o aviso aparecer por cima é o `fullScreenIntent`, que
acorda o ecrã. **Não ressuscitei a sobreposição antiga.** Usei o mecanismo
provado, que é o que faz o mesmo efeito.

**O que faltava, e é isto que explica tudo o que viste.** O `washer_store` não
tinha **uma única linha** de alerta. Zero referências. A lavagem não tinha som,
não tinha valor, e tocar no aviso não levava a lado nenhum — porque não havia
nada do lado da app a tratar disso. Não era um defeito de afinação; era ausência
completa.

O que fiz, tudo no molde da limpeza e sem construir mecanismo novo. A lavagem
passa a disparar o alerta partilhado quando a rotação lhe atribui um trabalho,
com dedup por pedido para não tocar duas vezes. **O valor vai no aviso**, e vai
o que a pessoa ganha e não o que o cliente paga. Aceitar e rejeitar calam o
alerta; rejeitar também limpa a marca de "já avisado", para o pedido poder
voltar se a rotação lho devolver.

O toque passa a abrir o ecrã certo. Fiz um gancho **único** para as duas
categorias, com a categoria no argumento, e registei-o no arranque da app e não
dentro de um ecrã — é a lição de 20 de Agosto, quando o gancho do "A caminho"
vivia no `initState` de um ecrã e ficava a nulo com outro ecrã por cima. Assim
responde mesmo com a pessoa parada no ecrã de motorista.

E a lavagem entrou no encaminhador de avisos, onde não estava. Sem esse ramo os
avisos dela caíam no comportamento normal do Android, que desaparece sozinho.

Rejeitar devolve o ecrã ao que estava por construção: o alerta é uma
notificação, não um ecrã empurrado por cima. Quem rejeita continua onde estava.

---

## Bloco 3 — a rotação da lavagem

Confirmei o que disseste e é pior do que parece à primeira: as três funções de
rotação existiam há dias e **não havia uma única tarefa agendada a chamá-las**.
A limpeza tinha oito tarefas. A lavagem tinha zero. Uma função que ninguém
chama é código morto com aspecto de funcionalidade.

O teu pedido conta a história toda: foi oferecido a um lavador às seis e vinte
e quatro, a oferta expirou às seis e trinta e quatro, e ficou ali seis horas
porque não havia nada a olhar para ele.

Criei as três tarefas. O tempo esgotado da oferta e a nova tentativa correm de
dois em dois minutos — a oferta da lavagem dura dez minutos, e a limpeza, cuja
oferta dura trinta, corre de cinco em cinco; mantive a mesma proporção. O
alerta de pedido preso corre de hora a hora, igual ao da limpeza.

Tirei também três números que estavam cravados no corpo das funções: até quando
vale a pena voltar a tentar, com que antecedência se insiste, e a partir de
quantas horas um trabalho a decorrer conta como preso. Passaram para as
definições da plataforma, com os mesmos valores de antes, para se afinarem sem
lançamento novo. O tempo da oferta em si já vinha das definições.

**A comparação por categoria.** As corridas têm rotação e expiração mas não têm
lembretes, alerta de preso nem acerto semanal agendado. As entregas têm a
manutenção do dispatch e a expiração de presença, e faltam-lhes as mesmas três.
A limpeza é a mais completa, com seis dos seis papéis cobertos, faltando-lhe só
a nova tentativa. A lavagem passou de zero para três — tempo esgotado, nova
tentativa e alerta de preso — e faltam-lhe expirar sem ninguém, lembretes e
acerto semanal. As reservas e marcações têm dez tarefas e faltam-lhes as de
rotação, que não fazem sentido nessa categoria.

Não criei as três que faltam à lavagem porque **as funções não existem** — ao
contrário das outras três, que estavam escritas e só não eram chamadas. Criar
as funções é trabalho de desenho, não de agendamento, e não cabia nesta sessão.

**O teu pedido preso está limpo.** Cancelei-o pelo caminho oficial do admin,
com a razão escrita. Ficou em cancelado, sem lavador, sem oferta, taxa zero, por
pagar. Confirmei por consulta que não há movimento nenhum no livro-razão para
esse pedido, que não entrou em acerto nenhum, e que não sobrou mais nenhum
pedido de lavagem parado.

---

## Bloco 7 — o padrão cresceu

A lista fechada passou de onze pontos para dezoito. Entraram os sete que
pediste, cada um com a cicatriz que o originou: a sobreposição por cima do ecrã
com a nota de que não se usa a sobreposição antiga e porquê, o valor no aviso, o
toque que abre o ecrã certo, a rotação **com as tarefas agendadas a chamá-la**,
o nome que a pessoa lê nunca ser o nome técnico, o cartão copiar-se em vez de
se provar outra vez, e apagar mesmo o que se substitui.

---

## O que não fiz

O bloco 4, a candidatura de lavador e a porta de entrada visível para quem quer
trabalhar. Continua a ser verdade que ninguém no mundo se pode inscrever para
lavar carros.

O bloco 5, alinhar o cartão pelo caminho já provado.

O bloco 6, o resto do dinheiro do acerto semanal. A vista está feita e certa; o
ecrã, o painel, o abate da dívida e a exportação não.

O bloco 8, os ladrilhos e o site do Mr Kebab.

E a prova no telemóvel, por o cabo estar desligado.

---

## Verificações

O `flutter analyze` corre com zero erros. As migrações foram aplicadas e
verificadas uma a uma por consulta. As três tarefas agendadas estão activas.
Nada do que fiz toca em preços, comissões, tokens, dispatch das corridas nem no
`versionCode`.

---

## Por ordem, para a seguir

Primeiro, ligar o cabo — e faço a prova do toque nas duas categorias, com a app
à frente, em segundo plano e fechada.

Segundo, o bloco 4, que é o que impede pessoas reais de se inscreverem.

Terceiro, o bloco 6, e aí precisas de dizer "vai" para a parte que abate a
dívida.
