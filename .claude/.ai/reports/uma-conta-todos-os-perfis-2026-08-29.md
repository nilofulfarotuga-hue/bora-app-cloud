# Uma conta, uma pessoa, todos os perfis — e nenhum ecrã preso

Data: 29 de Agosto de 2026.

---

## Onde parei

As seis provas estão feitas, com fotografia, pela web. O `PADRAO_BORA.md` levou
as duas regras. A conta de remendo do Waldyr foi apagada e a base ficou limpa,
provado por consulta.

Duas coisas que tens de saber já:

**A causa não era uma, eram três.** Corrigir o login não chegava. Só se
descobriu porque testei mesmo, ecrã a ecrã.

**Encontrei um defeito meu na correcção, a meio da prova**, e outro na prova em
si — dei uma coisa por boa que não era. Ambos estão contados em baixo, sem
enfeite.

---

## Todos os acessos

As palavras-passe continuo a não as ter, e a recuperação por email funciona.

Parceiros: `goola@bora.app`, `mr.kebab@bora.app`, `sabores.brasil@bora.app`,
`saboresde.casa@bora.app`, `ouro.prata@bora.app`, e `beunique@bora.app`,
desligada por tua ordem.

Estafetas e motoristas: `boraappbora@gmail.com`, que é a tua;
`nilofulfaro@gmail.com`, `ramosjuniorwaldyr@gmail.com` — o cliente real desta
história, que agora tem `client`, `delivery` e `driver` na mesma conta —,
`valdemirvasconcelos28@gmail.com`, `vanessaerika809@gmail.com` e
`test_courier@boraapp.test`.

Lavador de teste: `lava.leva@bora.app` com `LavaLeva!2026`.

Clientes de teste: `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`. A tua
conta de cliente é `nilofulfarotuga@gmail.com`, que é também a de admin.

---

## O que estava mal, e eram três coisas

**A primeira, a que apanhaste nos registos.** Os três ecrãs de entrar liam o
campo `bora_role` do metadata — que é **um campo só**, o do último modo em que
a app ficou — e faziam `signOut` quando não batia certo com a porta. O Waldyr
tinha `bora_role: driver` porque se candidatara a estafeta; ao entrar como
cliente, a app punha-o fora no mesmo segundo. Quatro vezes, com a palavra-passe
certa das quatro.

Agora: **nunca se faz `signOut` por causa de papel**. O cliente não é recusado
nunca — se lhe falta a linha, cria-se e segue. O estafeta e o parceiro
confirmam-se pelo perfil e pelo `user_roles`, que é a única fonte que aguenta
acumulação. E um erro de rede não fecha a porta a ninguém.

**A segunda, que só apareceu ao testar.** O ecrã de escolha de perfil fazia
`logout()` em **todos** os botões, mesmo com sessão aberta. Quem já estava
dentro e só queria mudar de perfil era posto fora e obrigado a escrever a
palavra-passe. Se eu tivesse corrigido só o login, tu terias continuado a
escrever a palavra-passe a cada troca.

**A terceira, que só apareceu na segunda passagem.** Corrigi o ecrã de escolha
e a troca continuou a pedir a palavra-passe. A razão: o botão "Mudar modo",
nos **três** ecrãs, fazia `logout()` **antes** de chegar ao ecrã de escolha —
quando a minha correcção corria, já não havia sessão nenhuma para reaproveitar.
Passa a largar só a conta activa em memória; a sessão fica.

E ainda: "Candidatura em análise" era uma parede com um único botão, "Sair".
Agora tem "Usar a app como cliente". Havia **dois** ecrãs de "em análise" e eu
pus o botão no errado — descobri com a fotografia do certo à minha frente.

A porta do parceiro ganhou o "Voltar à escolha de perfil" que as outras duas já
tinham. E as três dizem agora a quem se destinam.

---

## O defeito que eu próprio criei, e apanhei a tempo

Ao deixar de fazer `logout` no ecrã de escolha, abri um buraco: a função que
troca de perfil montava a conta de parceiro a partir do metadata e devolvia
"sim" a **qualquer pessoa**. Com o logout pelo meio isso nunca se via; sem ele,
um cliente que carregasse em "Sou Parceiro" caía no assistente de criar loja,
que para ele é um beco.

Está fechado: a porta só abre a quem tem o papel.

---

## O falso positivo da minha própria prova

Fotografei um "estafeta pendente a usar a app como cliente" e dei-o por bom. Ao
verificar **quem estava mesmo na sessão**, o email era `guest@bora.com`.

A porta "Sou Cliente" entra logo como convidado — não há ecrã de entrar ali. O
que eu tinha fotografado era a app a funcionar como convidado, e teria passado
por prova sem ninguém dar por isso. O login de cliente está no separador
Perfil, depois de terminar a sessão de convidado. É lá que o Waldyr batia.

Refiz as duas provas por esse caminho e passei a **confirmar sempre o email da
sessão** antes de dar qualquer coisa por provada. Uma fotografia de um ecrã não
diz quem está lá dentro.

---

## O ecrã preso à espera do GPS

Aquele tinha `try/catch` e um recurso que centrava na Guarda — parecia coberto.
Não estava: `getCurrentPosition` **não devolve e não rebenta** quando a posição
nunca chega. O `catch` nunca corria, a variável nunca deixava de ser nula, e o
carregador rodava para sempre, sem uma palavra.

Agora há limite de tempo em cada espera, e a recusa mostra um ecrã que diz
"Precisamos de saber onde estás", explica porquê, e dá "Tentar outra vez" e
"Abrir as definições". Corrigi o mesmo `await` sem limite no ecrã do motorista
TVDE, onde prendia o arranque do fluxo de posição inteiro.

Procurei o mesmo padrão nos outros perfis: o serviço de localização partilhado
já tinha limite de tempo, e a limpeza e a lavagem não bloqueiam por posição.

---

## O painel dos papéis

`admin_add_user_role` tinha a lista de papéis **cravada no corpo** e recusava
`delivery` e `washer`, que existem desde 28/08 — quem tentasse dar o papel de
lavador pelo painel levava "papel inválido". Passou a delegar nas funções que
lêem a lista do `CHECK` da própria tabela, e que travam a remoção de quem tem
trabalho a decorrer. Uma implementação, não duas.

`admin_user_role_flags` mostrava o estado de dois dos cinco papéis; passa a
mostrar os cinco. E a ficha de cada pessoa ganhou entrada directa para os
papéis dela.

---

## As seis provas

Todas em `.claude/.ai/provas/perfis-2026-08-29/`, num ecrã de telemóvel.

**Um — estafeta pendente a usar a app como cliente.** `SESSAO =
prova.multi@bora.app`, com a candidatura de estafeta em `pending`. Antes da
correcção era exactamente aqui que a app o deitava fora.
`01-estafeta-pendente-a-usar-como-cliente.png`

**Dois — a mesma conta a trocar para estafeta sem palavra-passe.** O email da
sessão é o mesmo antes e depois (`prova.multi@bora.app`), o que prova que não
houve login novo. Caiu no "Conta em análise", que é o correcto para quem está
pendente — e esse ecrã tem agora o botão de voltar a cliente.
`02-trocou-para-estafeta-sem-senha.png`

**Três — conta de parceiro a entrar como cliente.** `SESSAO =
prova.loja@bora.app`. `03-parceiro-a-usar-como-cliente.png`

**Quatro — o botão de voltar na porta do parceiro.** "← Voltar à escolha de
perfil", como nas outras duas. `04-porta-do-parceiro-com-voltar.png`

**Cinco — recusar a localização.** Em vez do carregador eterno, a explicação em
português com os dois botões. `05-sem-localizacao.png`

**Seis — os registos de autenticação.** Das contas de prova, nesta sessão de
testes: **cinco logins, zero logouts**. O padrão do Waldyr era login seguido de
logout no mesmo segundo, quatro vezes.

```
05:56:26  prova.loja@bora.app    login
06:11:22  prova.multi@bora.app   login
06:13:09  prova.loja@bora.app    login
06:14:56  prova.multi@bora.app   login
06:20:15  prova.multi@bora.app   login
logins: 5   logouts: 0
```

E as três portas, com as legendas novas, em `00-as-tres-portas.png`.

---

## O remendo e a limpeza

A conta `ramosjuniorwaldyr+cliente@gmail.com` não tinha **nada** — nem pedidos,
nem papéis, nem carteira, nem tokens. Não havia o que fundir: apaguei-a. A conta
principal dele ficou com `client`, `delivery` e `driver`, e o email normal volta
a servir para tudo.

As contas que criei para provar foram apagadas. Confirmado por consulta:

```
contas de prova            0
conta +cliente do Waldyr   0
drivers de prova           0
cleaners de prova          0
washers de prova           0
papeis orfaos              0
```

Ficam na base três contas de teste antigas, de missões anteriores, que não são
minhas de hoje e não toquei: `teste.lavagem@bora.app` (27/08, criada pelo guião
da lavagem), `teste.festas@bora.app` (25/08) e `teste-percurso-20260823@bora.app`.
Diz se queres que desapareçam.

---

## Uma coisa que te trava, e é do PC

**O disco encheu a meio do trabalho — zero bytes livres.** Foi por isso que uma
corrida de testes rebentou. Limpei só o balde 1, o que volta sozinho: caches do
Chrome e do Edge, as pastas `build/`, e os browsers do Playwright que não uso —
uso o Chrome do sistema. Ficaram 2,7 GB.

Não toquei em fotos, exports, transferências nem no BoraStudio.

O que ainda ocupa e é decisão tua: o **NDK do Android**, 2,12 GB, em
`AppData\Local\Android\Sdk\ndk`. Os builds de Android correm no CI, não aqui —
mas apagá-lo é lento de repor na tua ligação. Diz se queres.

---

## Verificações

`flutter analyze` com zero erros. Os testes passam todos — trezentos e
dezasseis. As migrações foram aplicadas e verificadas por consulta. Tudo
publicado pelo CI e provado contra o endereço público, comparando o ficheiro
servido antes e depois de cada correcção.

Nada do que fiz toca em preços, comissões, tokens, despacho,
`quote_order_pricing`, `partner_shelf_price` nem no `versionCode`.

---

## Por ordem, para a seguir

Primeiro, o flyer pode circular: quem for estafeta ou lojista já consegue pedir
com a mesma conta.

Segundo, decidir o NDK e as três contas de teste antigas.

Terceiro, o que ficou de trás: o cartão da limpeza e da lavagem pelo caminho
provado das entregas, os ladrilhos, e o site do Mr Kebab.
