# Sessão de fechar — email a chegar, vídeo a dar, e onde parei

Data: 28 de Agosto de 2026, fim de tarde.

---

## Onde parei, já aqui em cima

Fiz as Tarefas 1 e 3 em parte, a 2 até onde consigo, e a **4 não comecei**.

A Tarefa 1, o email, está **feita e provada**: chega a uma conta que não é a
tua, com a marca, em português, e a ligação abre o ecrã certo. No caminho
apanhei o último defeito da cadeia, que era da app e não do servidor.

A Tarefa 2, o plano, tem um bloqueio que não é decisão minha: **a extensão do
navegador não tem permissão para o domínio do painel do Supabase**, portanto
não consigo clicar lá. Deixei-te a página aberta no ecrã, no sítio exacto.

A Tarefa 3, o cadastro de prestadores, foi **até ao diagnóstico e à base**. O
diagnóstico é duro e explica tudo. Construí a peça que sustenta o resto, com
testes. O ecrã único e o painel admin não foram construídos.

A Tarefa 4, o toque persistente, **não comecei** — e ainda bem, porque o
diagnóstico da 3 mostrou que ela era impossível como está. Explico abaixo.

Fora do plano, o adendo do vídeo da Goola: **estavas certo, e eu tinha estado
errado duas vezes.** Está resolvido e provado com a página a correr.

---

## Todos os acessos

As palavras-passe continuo a não as ter — ficam cifradas do lado do Supabase e
escrevê-las em formulários é linha que não passo. **Mas isso deixou de ser um
problema hoje:** a recuperação por email passou a funcionar, e qualquer uma
destas contas se recupera em meio minuto pelo botão "Esqueci-me da
palavra-passe".

Os parceiros são seis. A Goola é `goola@bora.app`, ligada à loja Goola Açaí. O
Mr Kebab é `mr.kebab@bora.app`, ligado à loja. O Sabores do Brasil é
`sabores.brasil@bora.app`, ligado à loja da Keli. O Sabores de Casa é
`saboresde.casa@bora.app`, ligado à loja. A Ouro e Prata é
`ouro.prata@bora.app` — e aqui devo-te uma correcção: eu tinha dito que ela
estava sem loja ligada, e não estava. Eu é que só tinha olhado para a tabela
dos restaurantes, e uma barbearia não vive lá, vive na dos serviços. Tinhas
razão. A BeUnique é `beunique@bora.app` e está desligada por tua ordem; não lhe
toquei.

Os estafetas e motoristas são seis: `boraappbora@gmail.com`, que é teu,
`nilofulfaro@gmail.com`, `ramosjuniorwaldyr@gmail.com`,
`valdemirvasconcelos28@gmail.com`, `vanessaerika809@gmail.com` e a de teste
`test_courier@boraapp.test`.

Os clientes de teste são `demo.cliente@bora.app` e `e2e_client_a@boraapp.test`.
A tua conta de cliente é `nilofulfarotuga@gmail.com`.

Continua a não existir nenhuma conta de faxineiro nem de lavador — e a razão
está no diagnóstico da Tarefa 3.

Um detalhe que vale a pena veres: o `nilofulfaro@gmail.com` já acumula dois
papéis, faxineiro e motorista, e o `valdemirvasconcelos28@gmail.com` acumula
cliente e motorista. Ou seja, a base já aguenta a acumulação. É a app que não.

Acessos novos desta sessão: a chave do Resend chamada `bora-smtp-supabase`,
guardada em `bora-site/.env`, e o remetente de email
`nao-responder@boraguarda.com`.

---

## Tarefa 1 — o email chega, e chega a quem não és tu

Troquei o remetente de `onboarding@resend.dev` para
`nao-responder@boraguarda.com` assim que a base voltou. Depois pedi
recuperação para o `boraappbora@gmail.com`, que é justamente a conta que antes
devolvia erro quinhentos por não ser a dona da conta do Resend.

Devolveu duzentos. O registo do Resend marca-o como entregue, às nove e
quarenta e três, de `nao-responder@boraguarda.com` para essa conta, com o
assunto "Definir uma palavra-passe nova — Bora". Abri a caixa de correio e o
email lá está, em português de Portugal, com o logótipo da Bora, o botão verde
e o rodapé com o boraguarda.com. Segui a ligação e ela devolve uma sessão de
recuperação válida.

E foi aqui que apanhei **o último defeito, que era da app**. Abri a ligação num
navegador a sério e ela aterrava no ecrã de escolha de perfil, não no de
definir palavra-passe. A razão: o Supabase **substitui** o fragmento do
endereço de retorno em vez de lhe acrescentar o token. O comentário que estava
no código dizia exactamente o contrário, e é por isso que ninguém tinha
percebido. A rota da recuperação nunca chega à app, e a rede de segurança que
lá estava também não apanhava, porque o aviso pode ser emitido antes de alguém
estar a ouvir.

Corrigi olhando directamente para o endereço de arranque. Ficam os dois
caminhos, seja qual for o que dispare primeiro. Sete testes fixam as formas
reais, incluindo as que **não** devem abrir aquele ecrã: confirmação de conta,
convite, e a ligação já gasta.

O que falta, e é teu: escrever a palavra-passe nova. Peço-te desculpa por
insistir, mas escrever palavras-passe em formulários é a única coisa nesta
missão que não faço, nem em conta de teste.

Uma coisa que deixei propositadamente como está: a confirmação de email no
registo continua desligada. Ligá-la agora trancava toda a gente que se
registasse antes de tu confirmares que o email te chega às mãos. Faz esse teste
e eu ligo-a a seguir.

---

## Tarefa 2 — o plano do Supabase

Primeiro a resposta à tua pergunta, numa linha: **não dá para ficar no grátis
com pagamento automático do excedente.** O plano grátis tem tecto fixo e, ao
bater no tecto, pausa o projecto — foi exactamente o que aconteceu hoje. A
cobrança do que passa do incluído só existe no plano pago.

O projecto está `ACTIVE_HEALTHY` e a base responde. Confirmei os dois.

A mudança de plano em si não consegui fazer: a API de gestão do Supabase não
tem sequer um caminho para isso, e no painel a extensão do navegador **não tem
permissão para o domínio deles** — tentei e a resposta foi que falta permissão
no manifesto da extensão. Não é decisão minha nem trava de segurança, é uma
limitação da ferramenta.

Deixei-te a página aberta no ecrã, na secção do plano. É um botão: **Upgrade to
Pro**. O método de pagamento já lá está.

---

## Tarefa 3 — o cadastro de prestadores, e porque é mau

Fui a fundo primeiro, como pediste. São cinco coisas, e a última explica a
Tarefa 4.

**Não há porta.** O ecrã de escolha de perfil tem três botões: sou cliente, sou
estafeta, sou parceiro. Limpeza e lavagem de carros não existem ali. Uma pessoa
que queira trabalhar em limpeza não tem por onde entrar.

**Quem quer limpar tem de entrar pela porta de outra pessoa.** A candidatura de
limpeza só é alcançável de um sítio: já tens de estar dentro da app, ir ao
perfil, encontrar lá a entrada da limpeza, cair no ecrã de trabalho do
faxineiro, e só aí aparece o botão de candidatar. São quatro níveis, e só se
encontra se já se souber que existe.

**A lavagem de carros não tem candidatura nenhuma.** A tabela dos lavadores
existe, com vinte e oito colunas, e há ecrã de trabalho e painel de admin — mas
não há forma de alguém se inscrever. Ninguém pode ser lavador.

**Os papéis foram pensados aos pares.** O serviço que trata disto só sabe de
estafeta e limpeza, um contra o outro. Não há lugar para um terceiro nem para
um quarto. Cada actividade nova obrigava a reescrever tudo.

**E o achado que muda tudo:** o registo do aparelho para receber avisos só
acontece se o papel for estafeta ou cliente. Está escrito assim no código e a
função da base também só aceita esses. **Um faxineiro ou um lavador nunca chega
a ter um token de notificação guardado.** Ou seja, a Tarefa 4 não era difícil —
era impossível. Não há para onde mandar o toque.

O que construí: a peça que faltava por baixo, com a tua regra escrita nela — os
papéis acumulam-se, nunca se substituem. Sabe as quatro actividades, sabe que
entregas e viagens dão **um** papel de motorista e não dois (senão a
candidatura era submetida a dobrar), e sabe não pedir outra vez o que a pessoa
já deu. Dezassete testes, incluindo o caso de quem já é motorista e acrescenta
lavagem.

**O que não construí:** o ecrã único "Quero trabalhar no Bora", a candidatura do
lavador, e o painel de admin das candidaturas. Não os comecei porque não os
conseguia acabar bem nesta sessão, e preferi entregar uma base sólida a um ecrã
meio feito. É a primeira coisa a fazer na sessão seguinte, e agora tem chão.

---

## Tarefa 4 — o toque persistente

Não comecei, e o diagnóstico acima explica porquê: sem token guardado para os
papéis novos, não há push nenhum para tornar persistente. A ordem certa é
arranjar primeiro o registo do token e a função da base que o aceita, e só
depois copiar o mecanismo do parceiro.

Fica também dito: a prova com o telemóvel por cabo não foi feita.

---

## O adendo do vídeo — tinhas razão, eu estava errado

Fui medir a página publicada com o navegador a sério, em vez de me fiar no
código de resposta, e o erro apareceu de imediato: **o Chrome não conseguia
descodificar o ficheiro webm**. Dizia erro de descodificação na canalização de
vídeo.

O que se passava é traiçoeiro. Os ficheiros estavam lá e eram vídeo a sério —
confirmei pela assinatura dos primeiros bytes, não pelo código de resposta. Mas
o webm estava a primeira fonte da lista, o Chrome diz que suporta webm, escolhe
esse, falha a descodificar, e **não cai para a fonte seguinte**. Resultado:
caixa vazia. Foi por isso que os meus testes anteriores diziam que estava tudo
bem: os ficheiros respondiam duzentos com o tamanho certo, e respondiam mesmo.

A causa do webm: saiu em gama de cor completa, que o descodificador do Chrome
recusa. Recodifiquei com gama limitada.

Mudei quatro coisas. O mp4 passou a ser a primeira fonte, porque é o que toda a
gente descodifica. O filme só arranca quando entra no ecrã, e se a fonte
falhar cai-se para a seguinte à mão. Tirei o texto sobreposto da secção, porque
a mensagem passou a estar dentro do filme e as duas camadas punham uma frase
por cima da outra. E tirei o corte de altura que estava a comer as legendas a
meio.

Verifiquei os quatro sites com o navegador a medir a caixa e o estado do vídeo.
A Goola está a dar, do mp4, caixa de mil duzentos e oitenta por setecentos e
vinte. A Ouro e Prata estava carregada mas parada e agora dá. O Sabores do
Brasil já dava. O do site da Bora está parado **de propósito** — esse tem
controlos e só carrega quando se carrega em play; é um leitor, não um filme de
fundo, e não lhe toquei.

---

## Verificações

O `flutter analyze` corre com zero erros. Os testes passam todos: duzentos e
setenta e seis, mais vinte e quatro do que ontem, porque entraram os novos.
Commits feitos e empurrados nos dois repositórios com git.

Uma coisa a corrigir um dia: a pasta do site da Ouro e Prata **não está em
git**. A alteração de hoje está no disco e publicada, mas não versionada.

---

## Por ordem, para a sessão seguinte

Primeiro, o botão do plano Pro, que está à espera no ecrã.

Segundo, testares a recuperação até ao fim escrevendo a palavra-passe nova —
depois disso ligo a confirmação de email no registo.

Terceiro, o registo do token de notificação para faxineiro e lavador, que é o
chão da Tarefa 4 e sem o qual ela não existe.

Quarto, o ecrã único de candidatura, a candidatura do lavador e o painel de
admin.

Quinto, o toque persistente, com o telemóvel por cabo.
