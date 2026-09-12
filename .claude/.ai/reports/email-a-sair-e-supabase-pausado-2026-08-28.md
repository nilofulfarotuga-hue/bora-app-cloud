# Email a sair, o CI reposto, e uma paragem grave a meio

Data: 28 de Agosto de 2026, tarde.

---

## LÊ ISTO PRIMEIRO — a base de dados está em baixo e é dinheiro

A meio desta missão o projecto Supabase **passou a INACTIVE**. Não fui eu que o
pausei: estava a responder normalmente às nove menos um quarto, e às nove e pouco
começou a devolver erro. Confirmei de três maneiras: a API de gestão diz
`status: INACTIVE`, e tanto o REST como o Auth devolvem HTTP 540, que é o código
de projecto pausado.

Isto quer dizer que **a app está parada para toda a gente neste momento**. Quem
abrir a app não consegue entrar, não vê lojas, não faz pedidos. O site continua no
ar porque é estático, mas a app depende toda desta base.

Tentei repor pela API e a resposta foi clara: erro quatrocentos e dois, com a
mensagem de que a organização tem facturas por pagar e que é preciso liquidar
antes de repor o projecto. A organização está no plano gratuito, o que significa
que a factura em dívida é de consumo acima do incluído, não de assinatura.

**Parei aqui, como mandaste.** Não meto cartão nem pago nada. Deixei-te a página
da facturação aberta no ecrã — pede a entrada na conta primeiro, que é acto teu
porque envolve palavra-passe. Depois de liquidares, diz-me e eu reponho o projecto
pela API em segundos e continuo o resto.

Enquanto isso não estiver feito, **nada do que vem a seguir sobre email pode ser
provado ponta-a-ponta**, porque o servidor que envia os emails é precisamente este.

---

## Todos os acessos

Antes de mais, sobre as palavras-passe, e é a terceira vez que o digo porque
continua a ser verdade: **não as tenho e não as consigo obter**. Ficam cifradas do
lado do Supabase e escrever palavras-passe em formulários é linha que não passo.
A boa notícia é que, assim que a base voltar, a recuperação por email passa a
funcionar e qualquer uma destas contas se recupera sozinha em meio minuto — que é,
no fundo, o que esta missão foi resolver.

Os parceiros são seis. A Goola é `goola@bora.app`, ligada à loja, com entrada feita
hoje. O Mr Kebab é `mr.kebab@bora.app`, ligado à loja, nunca entrou. O Sabores do
Brasil é `sabores.brasil@bora.app`, ligado à loja da Keli. O Sabores de Casa é
`saboresde.casa@bora.app`, ligado à loja. A Ouro e Prata é `ouro.prata@bora.app` e
a BeUnique é `beunique@bora.app` — e estas duas continuam **sem loja ligada na
base**, o que quer dizer que caem no assistente de criar conta se entrarem hoje.
Fica por resolver.

Os estafetas e motoristas são seis: `boraappbora@gmail.com`, que é teu,
`nilofulfaro@gmail.com`, `ramosjuniorwaldyr@gmail.com`,
`valdemirvasconcelos28@gmail.com`, `vanessaerika809@gmail.com` e a de teste
`test_courier@boraapp.test`.

Os clientes são trinta e seis. As de teste que uso são `demo.cliente@bora.app` e
`e2e_client_a@boraapp.test`. A tua é `nilofulfarotuga@gmail.com`.

Continua a não existir nenhuma conta de faxineiro nem de lavador de carros, porque
o cadastro unificado é o bloco que ficou para a sessão seguinte.

Acessos novos criados nesta missão: uma chave de API do Resend chamada
`bora-smtp-supabase`, com acesso completo, guardada em `bora-site/.env` na variável
`RESEND_API_KEY`. O `.env` continua fora do git, verificado.

---

## Tarefa 1 — email a sair

Fiz tudo menos a prova final, e a prova final está travada pela paragem lá de cima.

Primeiro, uma correcção importante ao que eu próprio disse esta manhã. Eu tinha
concluído que o email não saía de todo. **Estava enganado.** Fui ao registo do
Resend e há lá um email marcado como entregue, às sete e cinquenta, para
`nilofulfarotuga@gmail.com`, com o assunto da recuperação. Ou seja, saiu e chegou.

O que se passava é mais simples e mais cruel do que eu tinha percebido: o remetente
era `onboarding@resend.dev`, o endereço de caixa de areia do Resend, e esse **só
entrega ao dono da conta Resend**, que é o `nilofulfarotuga@gmail.com`. Para
qualquer outra pessoa o servidor devolve erro quinhentos e o email nunca sai. Foi
exactamente o que vi quando testei com o `boraappbora@gmail.com`. Não procurei o
email na caixa certa porque a caixa que eu consigo ler é a `boraappbora`, e o email
tinha ido para a outra. O erro de diagnóstico foi meu.

A conta do Resend já existia — não precisei de criar nada, e ainda bem, porque criar
contas é coisa que não faço. Tinha lá um domínio, o `bora.app`, com estado "não
iniciado" desde há dois meses. Nunca chegou a ser verificado, e é por isso que o
remetente continuava a ser o de caixa de areia.

O que fiz: acrescentei o `boraguarda.com` ao Resend, na região da Irlanda, que é a
certa para Portugal. O Resend pediu três registos de DNS — a chave de assinatura
DKIM, um registo de correio e um de SPF — e criei os três na Cloudflare com o token
de DNS, todos sem passar pela nuvem laranja, porque registos de autenticação de
email nunca podem ser mascarados. Confirmei que os três se vêem em resolvedores
públicos, e o Resend deu-os por **verificados**, os três a verde.

Também escrevi os modelos de email em português de Portugal, com a marca. São
cinco: recuperar palavra-passe, confirmar email, mudar de email, ligação de entrada
e convite. Todos com o logótipo servido do `boraguarda.com`, o verde e o laranja da
marca, texto humano e um rodapé com o endereço. Estão aplicados no servidor,
confirmados um a um. E ficaram versionados em
`.claude/.ai/scripts/modelos-email-supabase.py`, para não viverem só dentro do
painel onde ninguém os vê — basta correr o script para os repor.

O que **falta**, e falta só por causa da paragem: mudar o remetente do SMTP de
`onboarding@resend.dev` para `nao-responder@boraguarda.com` e pôr a chave nova como
palavra-passe do SMTP. Tentei e o servidor respondeu "projecto pausado". É um
comando de dez segundos assim que a base voltar.

E depois disso falta a prova que pediste: pedir a recuperação, mostrar o email
recebido, abrir o link e mudar a palavra-passe. Faço as três primeiras partes; a
última, escrever a palavra-passe nova, é tua.

Uma nota que não quero deixar passar: a confirmação de email no registo continua
**desligada**, com o autoconfirmar ligado. Não lhe toquei de propósito, porque
ligá-la antes de o envio estar provado tranca toda a gente que se registe a partir
desse momento. Fica para logo a seguir à prova.

---

## Tarefa 2 — o CI

Feito, e provado com uma publicação real.

Metade da confirmação veio de graça: a corrida das oito e cinquenta e um, disparada
pelo meu próprio commit, **falhou** — e falhou exactamente no passo do Cloudflare
Pages, porque o segredo ainda tinha o token que eu tinha matado. Era a previsão que
eu tinha feito, agora com prova.

Pus o token novo no segredo `CLOUDFLARE_API_TOKEN` do repositório, pela linha de
comandos, usando a credencial do GitHub que já estava guardada no computador. A
data do segredo passou a ser de hoje. Disparei a publicação outra vez e correu até
ao fim, com sucesso, em dois minutos e trinta e dois.

Ou seja: falhou com o token velho, passou com o novo. Não fica dúvida.

---

## Tarefa 3 — o token que rodei por engano

Fui ver e tenho a resposta.

Era um token de utilizador chamado "Editar Cloudflare Workers", com treze permissões
sobre uma conta e todas as zonas. O que interessa é a coluna do último uso: **cinco
de Julho de 2026**. Ou seja, ninguém o usava há quase dois meses.

Conclusão: **não partiu nada**. O que quer que o usasse já tinha deixado de o usar,
ou nunca chegou a entrar em serviço. Não criei substituto, porque criar um token
novo com treze permissões para não servir nada seria só mais uma chave à solta.

Fica lá, activo, com um valor que ninguém tem. Se quiseres arrumar, apaga-se — mas
digo-te já que é cosmético, não é segurança: um token cujo valor ninguém conhece não
abre porta nenhuma.

Do lado que interessa, os dois tokens que estiveram públicos continuam mortos e os
novos continuam a funcionar — o de Pages acabou de o provar na publicação do CI.

---

## Tarefa 4 — os blocos 4 e 5

Não comecei, como combinado. O cadastro unificado de prestadores e o toque
persistente em todos os papéis ficam para a sessão seguinte, com o telemóvel por
cabo. Concordo com a tua leitura: não vale a pena abri-los sem fôlego para os
fechar.

---

## A Goola

Anotado: o "em breve" fica. Não lhe toquei e não lhe toco.

---

## O que falta, por ordem de urgência

Primeiro, e é urgente porque a app está parada: liquidar a factura do Supabase.
Página aberta no ecrã, precisa da tua entrada na conta. Assim que estiver, diz-me e
eu reponho o projecto e sigo.

Segundo, logo a seguir e depende do primeiro: mudar o remetente do SMTP, fazer a
prova ponta-a-ponta da recuperação, e só então ligar a confirmação de email no
registo.

Terceiro, quando houver sessão para isso: os blocos quatro e cinco.

E fica uma coisa pequena que encontrei e não tratei: a Ouro e Prata e a BeUnique
não têm loja ligada ao dono na base, portanto caem no assistente de criar conta.
É o mesmo defeito que se corrigiu para a Goola, e resolve-se com duas linhas de SQL
— mas precisa da base de pé.
