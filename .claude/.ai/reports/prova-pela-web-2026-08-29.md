# A prova pela web, e o que estes dois dias ensinaram

Data: 29 de Agosto de 2026.

---

## Onde parei

As seis provas estão feitas, com fotografia de cada uma, e o `PADRAO_BORA.md`
está actualizado com onze regras novas e o inventário refeito. Os dados de teste
foram todos apagados e provei por consulta que ficou zero.

Tinhas razão e a correcção era grande: **a prova de ecrãs nunca precisou de
cabo**. A app corre inteira em `app.boraguarda.com` e eu passei três missões a
escrever "não consigo, falta o cabo" com ela disponível o tempo todo. Ficou
escrito no padrão como regra 3.10, com a cicatriz.

E a prova valeu por si: **encontrou dois defeitos que ninguém tinha visto**, um
deles meu, de ontem. Estão no fim.

---

## Todos os acessos

As palavras-passe continuo a não as ter; a recuperação por email funciona e
resolve qualquer conta em meio minuto.

Parceiros: `goola@bora.app`, `mr.kebab@bora.app`, `sabores.brasil@bora.app`,
`saboresde.casa@bora.app`, `ouro.prata@bora.app`, e `beunique@bora.app`, que
está desligada por tua ordem.

Estafetas e motoristas: `boraappbora@gmail.com`, que é a tua e tem cinco papéis;
`nilofulfaro@gmail.com`, `ramosjuniorwaldyr@gmail.com`,
`valdemirvasconcelos28@gmail.com`, `vanessaerika809@gmail.com` e
`test_courier@boraapp.test`.

Lavador: `lava.leva@bora.app` com `LavaLeva!2026` — é o lavador de teste que o
guião da lavagem cria.

Clientes de teste: `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`. A tua
conta de cliente é `nilofulfarotuga@gmail.com`, que é também a de admin.

---

## Uma nota sobre como entrei, e o que não fiz

Não tinha a tua palavra-passe e **não a mudei**. Mudar a palavra-passe de uma
conta real para poder testar seria estragar a tua conta para fazer o meu
trabalho. Em vez disso criei uma conta de prova, `prova.web@bora.app`, com
motorista, faxineiro e lavador aprovados, corri tudo com ela, e apaguei-a no
fim. Ficou escrito no padrão que é assim que se faz.

---

## As seis provas

Todas em `.claude/.ai/provas/web-2026-08-29/`, num ecrã de 430 por 880, que é o
tamanho de um telemóvel.

**Um — aceitar, sair, voltar, e cair dentro do trabalho.** Aceitei uma limpeza
de teste, recarreguei a página (que é o mesmo que fechar a app e voltar), e a
app abriu **dentro do trabalho**, não no ecrã de motorista. A ficha mostra a
morada, o valor que ele ganha, "Confirmada", e o botão "Abrir rota". Isto era o
que te tinha feito julgar que tinhas perdido a lavagem.
`01-voltou-para-dentro-do-trabalho.png`

**Dois — a barra verde noutro ecrã.** Com o trabalho a decorrer, saí para o mapa
do motorista e lá está a barra em baixo: "Limpeza a decorrer — aceite · a
caminho · Rua Alves Rocadas 12, G... Voltar".
`02-barra-verde-noutro-ecra.png`

**Três — finalizar e voltar sozinho.** Carreguei em "Concluir limpeza" e a app
voltou por si ao ecrã anterior, sem eu tocar na setinha. A barra verde
desapareceu no mesmo instante, porque o trabalho deixou de estar a decorrer.
`03-finalizou-e-voltou-sozinho.png`

**Quatro — saltar entre papéis.** A folha "Ir trabalhar em" abre com Limpeza,
Lavagem de carros e "Juntar outra actividade", e diz em letra pequena que isto
muda o ecrã e que o que se aceita receber se muda na outra caixa.
`04-saltar-entre-papeis.png`, com a fila de botões em `04-botoes-do-mapa.png`.

**Cinco — os Ganhos com mais do que entregas.** Hoje 0,00 €, esta semana
17,00 €, e por baixo "Esta semana, por tipo de trabalho": Entregas e corridas
0,00 €, Limpeza 0,00 €, **Lavagem de carros 17,00 €**. Em baixo, "Detalhe das
entregas e corridas", que é o cartão antigo do estafeta, agora com o título a
dizer de que é. A limpeza aparece a zero **de propósito**: marquei-a como pedido
de teste e a app exclui pedidos de teste do dinheiro. A lavagem contou porque a
tabela da lavagem **não tem forma de marcar um pedido como teste** — o que é um
achado por si, e ficou no inventário.
`05-ganhos-com-todos-os-trabalhos.png`

**Seis — o painel das ofertas.** Abre com filtros por categoria e por período,
botão de exportar, e o resumo em cima: "2 oferta(s) · 2 para quem não tinha
aparelho · 0 aceita(s)". Cada linha diz o nome, a categoria, a hora, a janela —
30 minutos para um, **1 minuto** para o que não tinha aparelho — e "SEM
APARELHO". As duas linhas foram escritas pela mesma função que a rotação usa,
não por SQL à mão.
`06-painel-admin-ofertas.png`. E as três telas novas no painel, lado a lado, em
`06a-painel-admin-tres-telas-novas.png`.

---

## Os dois defeitos que a prova apanhou

**O primeiro é meu, de ontem.** O botão de "trabalhar noutra coisa" que criei
ficou só na barra de topo do ecrã do estafeta — mas o ecrã do estafeta tem
**dois desenhos**, e a barra que eu editei é a do que só aparece **quando há
pedidos**. No dia-a-dia o estafeta vê o mapa, e ali o botão não existia. Nunca
tinha aberto o ecrã; só se vê abrindo.

Pior: o botão novo tinha o **mesmo ícone de setas** do "Mudar modo" que já lá
estava. Ao carregar no que julgava ser o meu, saí da conta. Dois botões com o
mesmo ícone e significados diferentes são, para quem usa, um botão só.

Corrigi os dois — o botão passou a estar no mapa, com ícone próprio — e a
correcção está publicada e provada na fotografia quatro.

**O segundo é mais antigo e é sério.** O ecrã do estafeta **não abre sem posição
de GPS**. Fica um carregador a rodar, sem limite de tempo e sem uma palavra a
dizer porquê. Quem recuse o consentimento de localização, ou esteja num sítio
sem sinal, fica com um ecrã em branco para sempre. Não é problema da web: é o
mesmo código no telemóvel. Não lhe mexi — esta missão era de provar e escrever —
e ficou no inventário.

**E um terceiro, mais pequeno, também meu.** A barra verde do trabalho em curso
só se actualiza no arranque da app, ao voltar a ela, e ao fechar o ecrã do
trabalho que ela própria abriu. Quem aceita um trabalho e depois sai daquele
ecrã pelo seu próprio caminho não vê a barra até a app ir a segundo plano e
voltar. Foi por isso que ela não apareceu à primeira na minha prova. Está
registado.

---

## O que ficou escrito no padrão

Onze regras novas, cada uma com a cicatriz e a data.

Na lista fechada entraram cinco pontos, que passaram de dezanove para vinte e
quatro. A função de acerto semanal **e** a tarefa agendada que a chama, com a
cicatriz da lavagem que não tinha nenhuma das duas e onde um carro lavado nunca
seria pago. O ganho recebido em mão que não volta a ser pago no acerto, com os
quarenta euros onde deviam ser quinze. O cliente avisado em todas as mudanças de
estado e com o aviso a ir buscar o aparelho à tabela certa — com a cicatriz de
que nenhum cliente recebeu um único aviso da limpeza ou da lavagem, desde
sempre. A rotação que não gasta a vez com quem não pode ser avisado. E o
trabalho aceite que manda no ecrã até estar terminado.

Nos gémeos entraram dois. Um ecrã novo que não substitui o antigo deixa dois
vivos e a pessoa abre o velho — que foi exactamente o que fiz com os Ganhos. E
um botão novo tem de estar no ecrã que a pessoa vê mesmo, que foi o que fiz com
o das duas setas.

Nas regras de prova entraram três. A prova de ecrãs faz-se pela web, e "falta o
cabo" não é razão — com as três coisas que são a diferença entre funcionar e não
funcionar escritas por extenso, para não se voltarem a descobrir do zero: o GPS
tem de vir do contexto do browser, o consentimento grava-se antes de a app
arrancar, e escrever num campo exige clicar primeiro porque o campo só nasce com
o foco. Depois, quando tu e eu vemos coisas diferentes no mesmo endereço, o
desencontro resolve-se antes de se mexer no código. E procurar o que está mal,
não confirmar o que se mudou.

Sobre marketing não acrescentei nada: o texto que bate certo com a base ao
pormenor já era a regra 1.19, escrita anteontem com a cicatriz da Goola, e as
duas portas com o mesmo peso já eram a 1.11. Reli as duas e dizem o que pediste.

As ferramentas da prova ficaram guardadas em
`.claude/.ai/provas/web-2026-08-29/_ferramentas/`, para a próxima ser um comando.

---

## O inventário, refeito

Passei as quatro categorias pela lista, agora com vinte e quatro pontos.

**Limpeza.** Fechou muito desde ontem: a porta de entrada, o acerto unificado,
os avisos ao cliente, o dinheiro em mão, o trabalho que manda no ecrã, o botão
de rota. Falta o dinheiro não aparecer no ecrã de escolha de pagamento, o
assistente não usar o `AutoAddress`, a rotação não ter nova tentativa, e a prova
de som e ecrã bloqueado, que é a única que precisa mesmo do cabo.

**Lavagem Auto.** Fechou o maior buraco de todos — não tinha função de acerto
nem tarefa agendada, e uma lavagem feita nunca seria paga. Falta o cartão (é
acto teu, o PaymentSheet pede dados), o MB Way recusado pelo provedor, duas
tarefas de rotação cujas funções não existem, os tokens por aplicar, e **não ter
forma de marcar um pedido como teste**.

**Festas.** Os pontos novos quase não se lhe aplicam: quem recebe é o parceiro,
por caminhos antigos. Falta o mesmo de ontem — cartão e MB Way sem teste real de
festa, o ladrilho fora do padrão, a migration do dinheiro por absorver com dois
restos conhecidos, e a acessibilidade.

**Reserva de Mesa.** Igual: quem recebe é o parceiro. Falta confirmar se os
tipos de push das reservas estão no conjunto do toque persistente, e continua
sem nenhum parceiro a usá-la, o que é decisão comercial e não defeito.

Nos achados transversais, três buracos deixaram de existir (o painel dos papéis,
o acerto por pessoa e o registo de ofertas) e três entraram: o ecrã do estafeta
que não abre sem GPS, a barra que não se actualiza sozinha, e a lavagem sem
marca de teste.

---

## Limpeza dos dados de teste

Apaguei tudo o que criei e confirmei por consulta:

```
limpezas de teste     0
limpezas no total     1     (a cancelada de 06/08, que ja la estava)
lavagens no total     1     (a cancelada de 28/08, que ja la estava)
registo de ofertas    0
conta prova.web       0
perfis prova.web      0
acertos de limpeza    0
acertos de lavagem    0
```

---

## Verificações

`flutter analyze` com zero erros. Os testes passam todos — trezentos e
dezasseis. A correcção do botão está commitada e publicada, e provei que estava
mesmo no ar comparando o ficheiro servido antes e depois.

Nada do que fiz toca em preços, comissões, tokens, despacho,
`quote_order_pricing`, `partner_shelf_price` nem no `versionCode`.

---

## Por ordem, para a seguir

Primeiro, decidir o que fazer ao ecrã do estafeta que não abre sem GPS. É o mais
grave da lista e afecta o telemóvel tanto como a web.

Segundo, a prova que ainda precisa mesmo do cabo: o som a tocar, o aviso com o
ecrã bloqueado, e a app fechada.

Terceiro, o que ficou de trás: alinhar o cartão da limpeza e da lavagem pelo
caminho já provado das entregas, os ladrilhos, e o site do Mr Kebab.
