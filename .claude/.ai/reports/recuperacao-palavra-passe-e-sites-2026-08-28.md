# Recuperação de palavra-passe, tokens da Cloudflare e os dois caminhos para pedir

Data: 28 de Agosto de 2026.

Aviso de honestidade logo no início: esta missão tinha cinco blocos e **não os fiz
todos**. Fechei o primeiro em parte, os dois adendos por inteiro, e o terceiro em
diagnóstico. Os blocos quatro e cinco, que são o cadastro unificado de prestadores
e o toque persistente em todos os papéis, não foram sequer começados. Digo isto
aqui em cima para não teres de o descobrir no fim.

---

## As contas

Sobre as palavras-passe, tenho de ser directo: **não as tenho e não as consigo
obter**. Ficam guardadas cifradas do lado do Supabase, e escrever palavras-passe
em formulários é coisa que eu não faço, nem em conta de teste. O que te posso dar
é a lista de quem existe, e é isso que segue. Assim que a recuperação por email
estiver a funcionar, qualquer uma destas contas se recupera sozinha em meio minuto.

**Parceiros.** A Goola é `goola@bora.app` e está ligada à loja Goola Açaí, com
entrada feita hoje. O Mr Kebab é `mr.kebab@bora.app` e está ligado à loja, mas
nunca entrou. O Sabores do Brasil é `sabores.brasil@bora.app`, ligado à loja da
Keli, última entrada a vinte e cinco de Agosto. O Sabores de Casa é
`saboresde.casa@bora.app`, ligado à loja, última entrada em Junho. A Ouro e Prata
é `ouro.prata@bora.app` e a BeUnique é `beunique@bora.app` — estas duas **não têm
loja ligada na base**, o que quer dizer que, se entrarem hoje, caem no assistente
de criar conta. É o mesmo defeito que corrigi ontem para a Goola, e vale a pena
tratá-lo para estas duas também.

**Estafetas e motoristas.** São seis: `boraappbora@gmail.com` (teu),
`nilofulfaro@gmail.com`, `ramosjuniorwaldyr@gmail.com`,
`valdemirvasconcelos28@gmail.com`, `vanessaerika809@gmail.com` e a de teste
`test_courier@boraapp.test`.

**Clientes.** São trinta e seis contas reais. As de teste que uso são
`demo.cliente@bora.app` e `e2e_client_a@boraapp.test`. A tua é
`nilofulfarotuga@gmail.com`.

Não existe ainda nenhuma conta de faxineiro nem de lavador de carros com papel
atribuído — o que faz sentido, porque o cadastro unificado é justamente o bloco
que não cheguei a fazer.

---

## Bloco 1 — porque é que a recuperação nunca chegou

Comecei por corrigir a premissa. Disseste que `auth.audit_log_entries` tem zero
pedidos de recuperação, e tem. Mas **essa tabela tem zero linhas de tudo** — nem
sequer os logins lá estão. Fui confirmar: zero linhas ao todo. Portanto ela não
prova que a recuperação nunca disparou; prova só que esse registo não está a ser
escrito neste projecto. Se tivéssemos ficado por aí, iríamos procurar o problema
no sítio errado.

Fui então ao registo verdadeiro do Auth e ao pedido real. São **dois problemas
sobrepostos**, e é por isso que nada funcionava.

O primeiro é o endereço de retorno. A lista de endereços autorizados no Supabase
só tinha quatro deep links, todos a começar por `pt.boraapp.bora://`. O código da
app manda um endereço https — está em `lib/config/auth_links.dart`, na constante
`boraWebBaseUrl`, e é usado em `lib/auth/auth_store.dart` na linha 1003, dentro do
`resetPassword`, no parâmetro `redirectTo`. Esse endereço não estava na lista.
Quando isso acontece, o Supabase deita fora o endereço pedido e usa o de recurso,
que estava configurado como `pt.boraapp.bora://auth` — ou seja, um deep link. Um
deep link só abre em telemóvel **com a app instalada**. Quem abrisse o email no
portátil, ou tivesse desinstalado a app, ficava sem caminho nenhum.

Isto está corrigido, e corrigido na mesma passagem como pediste. O endereço de
recurso passou a ser `https://app.boraguarda.com`. A lista de autorizados passou a
ter os dez: os quatro deep links todos, que ficam porque há emails em trânsito, e
os https do domínio novo e do endereço antigo, para não partir links já enviados.
O `auth_links.dart` acompanhou na mesma passagem e já está no repositório.

O segundo problema é o envio do email em si, e este ainda **não está resolvido**.
O remetente configurado é `onboarding@resend.dev`, que é o endereço de caixa de
areia do Resend — aquele que eles dão antes de se verificar um domínio próprio.
Provei-o com pedidos reais: para a tua conta o servidor aceitou e devolveu duzentos,
mas o email nunca chegou à caixa; para a conta `boraappbora@gmail.com` devolveu
**quinhentos**, que é o código de "não consegui enviar". O registo do Auth mostra
o pedido a ser processado sem erro do lado dele, o que confirma que a coisa morre
do lado do Resend.

Para resolver é preciso um domínio verificado no Resend, e aí bate a parede: **não
existe nenhuma chave do Resend em lado nenhum**. Procurei nos segredos das Edge
Functions, que são quinze, e não está lá; procurei nos ficheiros do PC e não está.
Sem essa chave não consigo entrar por programa para acrescentar o domínio e ler os
registos de DNS que ele exige. Assim que me deres acesso ao Resend, ou uma chave de
API, faço o resto sozinho: acrescento `boraguarda.com`, crio os registos de DNS com
o token novo, mudo o remetente para um endereço do teu domínio e faço a prova
ponta-a-ponta.

Fica também por fazer, e por dependerem disto: os modelos de email em português de
Portugal com a marca, a verificação do deep link no telemóvel, e a prova completa
com email recebido e palavra-passe mudada. Sobre essa última parte, um aviso: eu
consigo pedir a recuperação, mostrar o email e abrir o link, mas **escrever a
palavra-passe nova é acto teu** — escrever palavras-passe em formulários é linha
que não passo.

Uma coisa que encontrei pelo caminho e que interessa ao bloco dois: a confirmação
de email no registo está **desligada**, com o autoconfirmar ligado. Ou seja,
ninguém recebe email de confirmação porque ele nunca é enviado. Não lhe mexi de
propósito: ligá-la antes de o envio funcionar tranca toda a gente que se registe
a partir desse momento.

---

## Bloco 3 — a Goola e as reservas

Fui ver e o diagnóstico não confirma o sintoma. Na base, a Goola tem
`reservations_enabled` a falso, e **nenhuma outra loja** tem reservas ligadas. No
código, o ecrã que lista lojas para reservar filtra por parceiro mais reservas
ligadas, em `restaurants_screen.dart`, e o botão dentro da loja tem a mesma guarda
em `restaurant_menu_screen.dart`. Com este código e estes dados, a Goola não pode
aparecer a aceitar reserva. A explicação mais provável é o telemóvel ter uma versão
antiga da app. Vale a pena confirmares depois desta actualização chegar.

Mas a investigação apanhou **dois defeitos a sério** ao lado, e esses corrigi.

O `copyWith` do modelo da loja não passava o `ownerId` adiante — deitava-o fora
em silêncio. Ora o `ownerId` é justamente o campo de que depende o conserto de
ontem, aquele que evita o parceiro cair no assistente de criar conta. Bastava uma
cópia do modelo para o defeito de ontem voltar.

Pior: quando um parceiro editava o perfil, o código reconstruía o modelo à mão,
campo a campo, e só copiava os que alguém se lembrou de escrever. Tudo o resto
desaparecia da memória — a capa, o logótipo, o dono, o "em breve". Ou seja, o
parceiro mudava o telefone e a loja ficava sem imagens até reiniciar a app. É o
mesmo padrão dos gémeos desalinhados que já nos mordeu antes. Passou a usar
`copyWith` completo, e o `copyWith` ficou com um aviso escrito por cima a dizer
que campo novo entra também ali.

Reparei ainda que a Goola está marcada como "em breve" na base. Não lhe toquei,
mas se ela já está a vender, isso está trocado.

---

## Adendo dos tokens da Cloudflare

Está feito, e fi-lo eu no painel como pediste.

Os dois tokens que estiveram públicos estão **mortos**. Confirmei os dois pela
API: o de DNS já não vê a zona, e o de Pages já não vê os projectos. Os novos
estão gravados no `.env`, que continua fora do git — verifiquei que nunca lá entrou,
em nenhum commit, nunca. Testei os dois novos: o de DNS lê os oito registos da zona
e o de Pages vê os projectos.

Duas coisas que correram mal e que tens de saber. Primeira: o token de Pages não
estava onde eu procurei. Ele é um token **de conta**, não de utilizador, e vive
noutra página. Antes de perceber isso, rodei dois tokens de utilizador chamados
"Editar Cloudflare Workers". Um deles adoptei como token de Pages e funciona. O
outro rodei e **não guardei o valor novo** — se alguma coisa tua usava esse token,
deixou de funcionar e vai precisar de valor novo. Não sei o que era; se algum
serviço teu falhar a autenticar na Cloudflare, é por aí.

Segunda: o CI usa `secrets.CLOUDFLARE_API_TOKEN` no `build_web_deploy.yml`. Se esse
segredo do GitHub tem o token antigo, o deploy automático da web vai falhar até lá
pôr o novo. O valor está no `.env` do `bora-site`.

Purguei a cache da zona. O `.env` deixou de ser servido em `www.boraguarda.com` e
no `bora-site.pages.dev`. No endereço sem www ainda sai uma cópia guardada de quase
duas horas, mas **já não interessa**: o que ela contém são os dois tokens mortos.

---

## Adendo dos dois caminhos para pedir

Feito nos quatro sites, e provado contra o endereço público.

Deixou de haver um botão grande para a Play Store com a web em letra miudinha por
baixo. Passam a ser dois botões do mesmo tamanho, lado a lado no computador e
empilhados no telemóvel, cada um com a sua linha por baixo: "Descarregar a app",
que diz que é Android e que instala e recebe os avisos do pedido, e "Pedir pelo
site", que diz que funciona no iPhone e no computador sem instalar nada. Nenhum
dos dois é secundário.

No Sabores do Brasil o bloco já tinha dois destinos, mas um levava um selo "O TEU"
que fazia o outro parecer menor. Tirei o selo e ficou só a ordem por aparelho, que
essa é útil.

As capturas dos quatro sites, no computador e no telemóvel, estão em
`bora-site/provas-duas-portas`. O contador de links confirma nos oito ecrãs que
existem os dois destinos.

---

## Adendo do vídeo

Primeiro, uma correcção ao diagnóstico: **o vídeo da Goola estava no ar**. Puxei o
HTML público e a secção do filme lá está, com o `video`, as duas fontes e o poster;
os três ficheiros servem com duzentos e o tamanho certo. O que se passava é que ele
era mudo e parado à espera de arrancar, e lido de relance parece uma fotografia.

Resolvi pela raiz, que é o que pediste: **o vídeo passa a dizer a mensagem**. Sete
planos, cada um com a sua legenda curta, sem locução. Diz que o açaí é cem por cento
da Amazónia, que é biológico e não leva corantes nem conservantes, que o açaí base é
sem glúten e sem lactose, que é montado à frente do cliente com os acompanhamentos à
escolha, que o quiosque é no piso três do La Vie, que entrega em casa pelo Bora, e o
horário. Vinte e três segundos e oito.

Apanhei um defeito grave pelo caminho, e este é meu: numa reconstrução anterior a
codificação do mp4 **rebentou a meio** por falta de memória, porque eu tinha dois
ffmpeg a correr ao mesmo tempo neste PC de quatro gigas. Ficou um ficheiro de
cinquenta e sete quilobytes com dois quadros, e esse ficheiro subiu para produção
sem eu dar por isso — o webm estava bom, o mp4 estava lixo. Refiz sozinho e pus uma
guarda no gerador: abaixo de um megabyte o script rebenta em vez de deixar passar.

A Ouro e Prata não tinha vídeo nenhum e agora tem, com o filme do próprio cliente
que estava na pasta dele, convertido para a web com poster. O Bora e o Sabores do
Brasil já tinham e continuam a ter.

Verifiquei tudo contra o endereço público, com quebra-cache e depois de purgar. Os
quatro sites têm `video` no HTML servido, e os ficheiros da Goola respondem
duzentos com dois milhões e novecentos mil bytes no mp4, dois milhões e quinhentos
mil no webm, e cento e vinte mil no poster.

Fica a regra registada: todo o site que fizermos leva vídeo, com o do cliente se
ele tiver, ou montado das fotos reais se não tiver.

---

## Verificações

O `flutter analyze` corre com zero erros, com duzentos e cinquenta e seis avisos
que são a linha de base desta branch. Os testes correm todos: duzentos e cinquenta
e dois passaram, nenhum falhou. Três commits feitos, o da app já empurrado.

---

## O que falta, e porquê

O envio de email, que é o que falta para fechar o bloco um, está travado por não
haver acesso ao Resend. Assim que mo deres, faço o resto sem te incomodar mais.

O bloco dois, que é varrer o que ficou pendurado no domínio antigo — confirmação
de email, convites, endereços de retorno da Stripe Connect —, não foi feito.

Os blocos quatro e cinco, o cadastro unificado de prestadores e o toque persistente
em todos os papéis, não foram começados. São os dois maiores da missão e precisam de
uma sessão só para eles. O quinto em particular exige o telemóvel ligado por cabo
para a prova, e vale a pena fazê-lo de seguida, não à pressa.
