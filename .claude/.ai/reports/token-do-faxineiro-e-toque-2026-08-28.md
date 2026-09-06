# O token do faxineiro, o toque, e onde parei

Data: 28 de Agosto de 2026, noite.

---

## Onde parei

Fiz a tarefa urgente por inteiro e provada. Fiz a canalização da Tarefa 4 e
provei-a até ao FCM. **Não fiz a prova no telemóvel**, e explico porquê — não é
desculpa, é uma ordem de acontecimentos que não dá para saltar. E **não fiz a
Tarefa 3**, o ecrã único e o painel admin.

---

## Todos os acessos

As palavras-passe continuo a não as ter, e já não é problema: a recuperação por
email funciona desde hoje de manhã, com prova. Qualquer uma destas contas se
recupera em meio minuto.

Os parceiros são seis. A Goola é `goola@bora.app`. O Mr Kebab é
`mr.kebab@bora.app`. O Sabores do Brasil é `sabores.brasil@bora.app`. O Sabores
de Casa é `saboresde.casa@bora.app`. A Ouro e Prata é `ouro.prata@bora.app`. A
BeUnique é `beunique@bora.app` e está desligada por tua ordem.

Os estafetas e motoristas são seis: `boraappbora@gmail.com`, que é teu,
`nilofulfaro@gmail.com`, `ramosjuniorwaldyr@gmail.com`,
`valdemirvasconcelos28@gmail.com`, `vanessaerika809@gmail.com` e
`test_courier@boraapp.test`.

Os clientes de teste são `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`.
A tua conta de cliente é `nilofulfarotuga@gmail.com`.

O único faxineiro é o `nilofulfaro@gmail.com`, que acumula faxineiro e
motorista — é a pessoa certa para testar o toque cruzado. O único lavador é
`lava.leva@bora.app`.

---

## O urgente — o token do faxineiro

Está feito, e o buraco era maior do que eu tinha dito ontem.

Eu tinha dito que o token não era guardado. Era verdade, mas faltava metade da
história, e a metade que faltava tornava tudo pior. Havia **dois** caminhos
possíveis para chamar um faxineiro, e os dois estavam cortados.

O caminho novo, o das tabelas de tokens por papel: a função da base só sabia
escrever em três tabelas, cliente, motorista e parceiro, e mandava embora
qualquer outro papel. O caminho antigo, a coluna `fcm_token`: a tabela dos
motoristas tem essa coluna, mas as dos faxineiros e dos lavadores **não têm**.
E a função que envia o aviso lia essa coluna na tabela dos utilizadores, que
está vazia tanto para o faxineiro como para o lavador que existem — fui
confirmar um a um.

E havia uma terceira coisa, que é a que mais me incomoda: existia uma função
chamada "regista este aparelho em todos os papéis" e ela **não tinha um único
chamador**. Era casca sem fio. Quem registava eram os ecrãs, cada um a fixar o
seu papel à mão, e os ecrãs do faxineiro e do lavador não registavam nada.

O que fiz. Criei **uma** tabela para os papéis de prestador, com o papel numa
coluna em vez de uma tabela por papel — era esse padrão que criava o problema
de cada vez que aparecia um papel novo. Agora o papel seguinte não precisa de
migration nenhuma. A função da base passa a aceitar faxineiro e lavador. Criei
uma função que devolve **todos** os papéis da pessoa, lida da tabela que aguenta
acumulação, porque o campo do metadata guarda um valor só e nunca poderia
descrever quem é motorista e faxineiro ao mesmo tempo. E liguei o registo ao
portão de autenticação, para apanhar toda a gente a cada entrada, seja qual for
o papel e sejam quantos forem. Também tratei da renovação do token do
aparelho, que repunha só o último papel e deixava os outros mudos.

Provei na base com a pessoa que acumula: a função aceita os dois papéis, grava,
e a função dos papéis devolve faxineiro e motorista. Sete testes novos fixam a
lista de papéis e o destino de cada um.

---

## Tarefa 4 — a canalização está feita, o telemóvel não

Guardar o token não chegava. As funções que enviam o aviso à limpeza e à
lavagem liam a tal coluna antiga e devolviam "sem token" sem sequer contactar o
Google. Mudei as duas para juntarem a tabela nova com a coluna antiga e
enviarem para **todos** os aparelhos da pessoa — quem tem dois telemóveis é
chamado nos dois, e um token morto é desligado sozinho sem levar os outros à
frente.

Acrescentei também os avisos da lavagem à lista dos que a app trata como
persistentes. A limpeza já lá estava; a lavagem é nova e faltava por inteiro, e
por isso os avisos dela caíam no comportamento normal do Android, que desaparece
sozinho.

A prova, feita contra as funções já publicadas. Com um aparelho registado, a
função encontra-o e chega ao Google, que recusa por o meu token de teste ser
falso. Sem aparelho registado, volta a responder "sem token" — que é o estado em
que a limpeza sempre esteve. É a diferença entre a chamada morrer em casa e
chegar ao destino.

**A prova no telemóvel não foi feita, e não podia ser hoje.** O telemóvel está
ligado, vi-o. Mas o que está instalado nele é a versão da loja, que não tem
nada disto — testar agora provava a app velha, não o conserto. A ordem certa é:
isto sobe, o CI constrói, actualizas pela Play Store, entras como faxineiro uma
vez para o aparelho ficar registado, e só aí o teste tem sentido. Faço-o de
seguida quando disseres que a versão nova está no telemóvel.

Há um segundo passo que também é teu, e é rápido: entrar na app como
`nilofulfaro@gmail.com`, que é o faxineiro. Enquanto ninguém entrar com esse
papel, não há aparelho registado para chamar.

---

## Um susto que provoquei e corrigi

A meio, publiquei uma das funções com a verificação de autenticação desligada.
Isso abria-lhe a porta a quem soubesse o endereço. Dei por isso ao comparar com
a função irmã, fui ver quem as chama, confirmei que ambas as chamadas vêm de
dentro da base e mandam cabeçalho de autorização, e repus a verificação nas
duas. Estão as duas fechadas agora. Digo-o porque foi obra minha e porque, se
não estivesse escrito, ninguém saberia.

Também parti uma das funções a meio do trabalho: o meu recorte automático levou
com ele as funções auxiliares do fim do ficheiro e a coisa passou a dar erro
quinhentos. Vi no registo, repus a cauda e voltei a publicar. Está a responder.

---

## Tarefa 3 — não fiz

O ecrã único "Quero trabalhar no Bora", a candidatura do lavador que não existe,
e o painel de admin dos papéis: nada disso foi construído hoje. O que existe é a
base que fiz ontem, com as quatro actividades e a regra de que os papéis se
somam, e o diagnóstico escrito de porque é que o cadastro actual é mau — sem
porta no ecrã de entrada, a limpeza escondida a quatro níveis de profundidade, e
a lavagem sem forma nenhuma de alguém se inscrever.

Preferi entregar o token resolvido e provado a ter duas coisas meio feitas.
Ficam para a sessão seguinte, e agora têm chão a sério: os papéis acumulam-se
na base, a função que os lê existe, e o registo de aparelho já funciona para os
quatro.

---

## Verificações

O `flutter analyze` corre com zero erros. Os testes passam todos: duzentos e
oitenta e três. Duas funções publicadas e a responder. Três commits empurrados.

---

## Por ordem, para a seguir

Primeiro, o botão do plano Pro, se ainda não carregaste.

Segundo, esperar que o CI construa e actualizar a app no telemóvel pela Play
Store.

Terceiro, entrares uma vez como `nilofulfaro@gmail.com`, que é o faxineiro,
para o aparelho ficar registado. Confirmo na base em segundos que o token lá
está.

Quarto, o teste do toque com o telemóvel: disparo um pedido de limpeza contigo
no ecrã de motorista, e vê-se se toca.

Quinto, o ecrã único de candidatura, a candidatura do lavador e o painel admin.
