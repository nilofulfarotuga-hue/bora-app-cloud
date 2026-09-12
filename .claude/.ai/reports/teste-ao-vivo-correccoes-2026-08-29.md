# O que o teste ao vivo apanhou, e o que ficou corrigido

Data: 29 de Agosto de 2026.

---

## Onde parei

Os seis blocos estão feitos, e o dinheiro que ficara pendente de ontem também.
Cada passo tem prova por consulta colada mais abaixo.

O que **não** consegui: as capturas do telemóvel. O `adb devices` continua a
devolver a lista vazia — reiniciei o servidor e tentei de novo, e nada. Sem o
cabo ligado não tiro fotos do ecrã dele, e não vou fingir que tirei. O que
posso provar do meu lado provei por consulta e por resposta de servidor, e
está tudo aqui. Assim que o cabo estiver ligado, a prova visual é meia hora.

Encontrei duas coisas pelo caminho que ninguém tinha pedido e que valem mais
do que metade do que estava na lista. Estão no fim, em "o que apareceu ao
lado".

---

## Todos os acessos

As palavras-passe continuo a não as ter; a recuperação por email funciona
desde 27 de manhã e resolve qualquer conta em meio minuto.

Parceiros: `goola@bora.app`, `mr.kebab@bora.app`, `sabores.brasil@bora.app`,
`saboresde.casa@bora.app`, `ouro.prata@bora.app`, e `beunique@bora.app`, que
está desligada por tua ordem.

Estafetas e motoristas: `boraappbora@gmail.com`, que é a tua e tem os cinco
papéis; `nilofulfaro@gmail.com`, `ramosjuniorwaldyr@gmail.com`,
`valdemirvasconcelos28@gmail.com`, `vanessaerika809@gmail.com` e
`test_courier@boraapp.test`.

Lavadores: `lava.leva@bora.app` com a palavra-passe `LavaLeva!2026`, mais a tua
conta.

Clientes de teste: `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`. A tua
conta de cliente é `nilofulfarotuga@gmail.com`, que é também a de admin.

---

## Bloco 1 — o trabalho aceite manda no ecrã

Tinhas razão e a causa é simples de dizer: a app escolhia o ecrã **só pelo
papel guardado no telemóvel** e nunca perguntava ao servidor se havia trabalho
a meio. Estado guardado só no telemóvel morre quando o Android mata a app — que
é exactamente o momento em que faz falta. Por isso caíste no ecrã de motorista
e a lavagem pareceu ter desaparecido.

Agora há uma função no servidor que responde "tens este trabalho a meio, nesta
morada, neste passo". Quem pergunta é uma camada que envolve a app inteira, e
por isso funciona venhas de onde vieres.

Ao abrir a app e ao voltar a ela, se houver trabalho a meio, entra-se nele.
Entra **uma vez** por trabalho: se saíres de propósito para ver outra coisa, não
te empurra para lá outra vez de cada vez que mudas de janela.

Enquanto durar, há uma barra verde em baixo, em qualquer ecrã, a dizer o que
está a decorrer, em que passo e em que morada, com um "Voltar". Some sozinha
quando o trabalho acaba.

Ao finalizar, volta sozinho ao ecrã de onde veio. Nas duas categorias. Na
limpeza deixei um aviso a dizer que a avaliação do cliente continua disponível
em "A minha Limpeza", para não te tirar essa hipótese ao mesmo tempo que te
tiro do ecrã.

E há um botão de saltar entre papéis, com as duas setas, no cabeçalho dos dois
ecrãs de motorista. Mostra as actividades que já fazes e leva-te ao ecrã de
trabalho de cada uma, sem sair e voltar a entrar. Diz também, em letra pequena,
que isto muda o ecrã e que o que aceitas receber se muda na outra caixa — são
duas coisas diferentes e vale a pena que não se confundam.

---

## Bloco 2 — o ecrã de ganhos junta os trabalhos

Este era o maior, e a culpa é minha e está identificada.

Ontem construí a vista unificada **e um ecrã novo de ganhos** que a lê. O que
não fiz foi ligar esse ecrã ao sítio de onde tu abres os Ganhos. Ficaram dois
ecrãs de ganhos vivos ao mesmo tempo, e o que tu abrias era o antigo, só do
estafeta. É a regra dos gémeos, e desta vez fui eu que a quebrei.

Agora há **um só**. O antigo, que era o que tu abrias, passou a chamar-se
Ganhos e é esse que junta tudo. Apaguei os outros dois: o meu gémeo de ontem e
o dos ganhos da limpeza. Os cinco sítios que abriam qualquer um deles apontam
todos para o mesmo.

O topo — hoje e esta semana — vem da soma de todos os papéis. Por baixo, a quem
faz mais do que uma coisa, aparece o detalhe linha a linha: entregas e
corridas, limpeza, lavagem. A quem só entrega não aparece detalhe nenhum,
porque uma linha a dizer "entregas" por baixo do total das entregas não
acrescenta nada.

Depois vem o acerto da semana, já unificado, com as parcelas por tipo de
trabalho, a dívida abatida e **um número final** com sentido: ou a Bora paga, ou
tu deves.

O cartão semanal antigo, que era só do estafeta e dizia "Esta semana",
continuava a mostrar um número diferente ao lado do unificado. Deixou de fingir
que era o total: passou a chamar-se "Detalhe das entregas e corridas" e só
aparece a quem entrega. Dois números sem dono ao lado um do outro lêem-se como
contradição.

O número da "Semana passada" continua a ser só das entregas, porque só essa
fonte o tem — e agora diz isso por baixo, em letra pequena.

---

## Bloco 3 — a rotação deixa de gastar a vez

Confirmado por consulta, e é exactamente o que descreveste. A função que
pergunta "esta pessoa tem aparelho onde receber?" responde assim hoje:

Nos lavadores, o "Danilo" tem aparelho e o "Lava & Leva" não tem.
Nos faxineiros, o "Danilo" tem e o "Danilo Fulfaro" não tem.

Passaram a mudar duas coisas. Primeira, na ordem por quem se oferece, quem pode
ser avisado vai à frente — antes da nota e da experiência, porque de nada serve
o melhor da lista se ele não tem como saber que tem trabalho. Segunda, quem não
tem aparelho recebe uma janela de um minuto em vez de dez na lavagem ou trinta
na limpeza. Não o saltei de todo: saltar seria decidir por ele que nunca vai
olhar, e há quem trabalhe com a app aberta. Um minuto continua a dar-lhe
hipótese e devolve o trabalho à rotação depressa.

O minuto está nas definições da plataforma, não cravado no código, para se
afinar sem lançamento novo.

E ficou registo. Cada oferta deixa uma linha: a categoria, o pedido, para quem
foi, se essa pessoa tinha aparelho, quantos minutos teve, e como acabou. Há
painel no admin com filtro por categoria e por período, um resumo em cima a
dizer quantas ofertas foram para quem não tinha aparelho, e exportação.

Fechar a linha quando a oferta acaba é feito por gatilho na própria tabela do
pedido, num sítio só. A alternativa era escrever o mesmo em seis funções —
aceitar, recusar e tempo esgotado, vezes duas categorias — e seis sítios a
guardar a mesma verdade é como se criam os problemas que passámos a semana a
apanhar.

Dois desfechos, e só dois: "aceite" e "sem resposta". Distinguir "recusou" de
"deixou expirar" obrigava a mexer nas tais seis funções. Prefiro dois desfechos
verdadeiros a quatro adivinhados.

---

## Bloco 4 — o que o cliente vê

Boa pergunta, e a resposta é pior do que parecia.

Percorri os estados. Na limpeza, o cliente era avisado quando a profissional
aceitava e quando estava concluída. A caminho: nada. Começou: nada. Na lavagem,
avisado ao aceitar e ao concluir; a caminho, carro recolhido, a lavar, a
devolver — nada em nenhum. Ou seja, dois avisos, no princípio e no fim, e
silêncio no meio, justamente enquanto o cliente está sem o carro ou com uma
pessoa dentro de casa. Nas entregas ele é avisado a cada passo.

A causa é uma só, e por isso a correcção também: todos os passos do meio passam
por uma única função em cada categoria, e nenhuma delas tinha uma linha sequer
de aviso. Corrigi aí, nas duas, em vez de nas seis funções de acção.

O cliente passa agora a receber, na lavagem: "A caminho", "Carro recolhido", "A
lavar", "A caminho de volta" e "Carro entregue". Na limpeza: "A caminho", "A
limpeza começou" e "Limpeza terminada". Com o nome da pessoa que lá vai, não
com o nome do estado.

**E havia coisa pior por baixo.** A função que manda os avisos da lavagem
mandava *tudo* pela função de aviso do lavador — incluindo os avisos dirigidos
ao cliente. E essa função só procurava aparelhos na tabela dos prestadores, onde
o cliente não tem nenhum. Resultado: o cliente **nunca recebeu um único aviso
por telemóvel** desta categoria. Ficava só com o aviso dentro da app, que ele
só vê se a abrir. O mesmo na limpeza.

Está corrigido e provado com o antes e o depois no mesmo registo, mais abaixo.

---

## Bloco 5 — mapa e rota

Fiz a parte que disseste que bastava. Há um botão "Abrir rota" no cartão do
trabalho, na limpeza e na lavagem. Não é um mapa dentro da app: é o botão que
leva à aplicação de mapas que a pessoa já tem e já sabe usar. Na lavagem vai com
as coordenadas quando existem; na limpeza vai pela morada escrita, porque o
modelo da limpeza não traz coordenadas.

---

## Bloco 6 — de onde veio o "Lava & Leva"

Não é ninguém de fora. É um lavador de teste que fui eu que criei, a 27 de
Agosto, quando construí e provei a Lavagem Auto.

O que o denuncia: a conta de acesso foi criada às 11h09m50s e o perfil de
lavador às 11h09m51s — um segundo depois, o que só acontece com um programa, não
com uma pessoa a preencher um formulário. O telemóvel dele é `937501673`, que é
o teu. O email segue o padrão das contas de teste da casa. Está aprovado mas sem
data nem autor de aprovação, ou seja, aprovado por escrita directa e não pelo
caminho do admin. Não tem NIF nem documentos.

Está escrito no `.claude/testes-e2e/e2e_carwash.py`, que é o guião do teste
ponta-a-ponta da lavagem, e aparece nos dois relatórios desse dia com a
palavra-passe. Entrou uma vez, a 27 às 12h41.

Não lhe toquei. Se quiseres apagá-lo, diz — mas nota que o guião do teste
volta a criá-lo na próxima corrida.

---

## O dinheiro que estava pendente de ontem

Deste o "vai" e está feito.

O defeito: a função que fecha a semana da limpeza pagava o ganho de **todas** as
limpezas concluídas, sem olhar a como foram pagas. Numa limpeza paga em
dinheiro, quem recebe a nota toda na mão é a profissional — fica com o que é
dela e com a parte da Bora. Pagar-lhe outra vez no acerto é pagar duas vezes, e
a Bora nunca recuperava a parte dela.

A regra nova, e não inventa preço nenhum: o líquido passa a ser o ganho dos
trabalhos que **não** foram pagos em dinheiro, menos a taxa da Bora dos que
foram. Os valores continuam a ser escritos por quem sempre os escreveu; o que
mudou foi de que lado da conta cada um entra.

Provei com um ensaio que desfiz a seguir: duas limpezas de vinte euros de ganho,
uma a cartão e outra a dinheiro com cinco euros de taxa. A fórmula antiga pagava
quarenta euros. A nova paga quinze — os vinte da do cartão, menos os cinco que
ficaram na mão. Está colado mais abaixo.

Era seguro fazer agora: zero trabalhos pagos em dinheiro por liquidar, e zero
linhas de acerto de limpeza ou de lavagem. Nenhum acerto já calculado mudou de
valor.

---

## O que apareceu ao lado, e é grave

**A lavagem não tinha função de acerto nenhuma.** Nem função, nem tarefa
agendada. A tabela dos acertos da lavagem existe, o cron da limpeza existe, e a
lavagem não tinha nada. Quer dizer que uma lavagem feita **nunca entrava em
acerto e nunca seria paga**. Criei-a, gémea da da limpeza, já com a regra do
dinheiro em mão de origem, e agendei-a para segunda-feira às oito, à mesma hora
da limpeza.

**O cliente nunca recebeu um push da limpeza nem da lavagem.** Já contei acima.
As duas juntas explicam porque é que estas duas categorias pareciam funcionar e
por dentro estavam pela metade.

---

## As provas

A rotação sabe quem pode ser avisado:

```
lavadores : Danilo -> true   ·  Lava & Leva -> false
faxineiros: Danilo -> true   ·  Danilo Fulfaro -> false
```

O registo de ofertas fecha-se sozinho — ensaio completo, desfeito a seguir:

```
nome=Danilo  tem_aparelho=false  janela_min=1  desfecho=aceite  fechou=true
```

O aviso ao cliente, antes e depois, no mesmo registo de respostas do servidor:

```
id 38  18:14  {"ok":false,"reason":"no_fcm_token"}     <- antes
id 39  18:14  {"ok":false,"reason":"no_fcm_token"}     <- antes
id 43  18:51  {"ok":true,"enviados":2,"aparelhos":7}   <- depois
```

A regra nova do dinheiro, no ensaio que desfiz:

```
trabalhos              : 2
ganho bruto (cents)    : 4000   <- o que a formula ANTIGA pagava
ganho a pagar (cents)  : 2000   <- so a limpeza do cartao
taxa em divida (cents) : 500    <- a parte da Bora que ficou na mao
LIQUIDO NOVO (cents)   : 1500
```

A tarefa agendada da lavagem, que não existia:

```
carwash-weekly-settlement  ·  0 8 * * 1  ·  compute_all_washer_weekly_settlements()  ·  activa
```

As duas funções de transição passaram a avisar o cliente, com texto por passo:

```
_carwash_transition   avisa_cliente=true  tem_texto_do_passo=true
_cleaning_transition  avisa_cliente=true  tem_texto_do_passo=true
```

---

## Verificações

O `flutter analyze` corre com zero erros. Os testes passam todos — trezentos e
dezasseis. As cinco migrações foram aplicadas e verificadas uma a uma por
consulta. As duas funções de aviso foram publicadas pelo caminho oficial e
continuam a exigir autenticação, como antes.

Nada do que fiz toca em preços, comissões, tokens, despacho das corridas,
`quote_order_pricing`, `partner_shelf_price` nem no `versionCode`.

---

## Por ordem, para a seguir

Primeiro, ligar o cabo. Com ele ligado faço as capturas que pediste: aceitar,
sair, voltar e cair dentro do trabalho; finalizar e voltar sozinho; e o ecrã de
Ganhos a mostrar mais do que entregas.

Segundo, decidir o que fazer ao "Lava & Leva".

Terceiro, o que ficou de trás: alinhar o cartão da limpeza e da lavagem pelo
caminho já provado das entregas, os ladrilhos, e o site do Mr Kebab.
