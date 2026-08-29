# PADRÃO BORA — o que se aprendeu à força, escrito uma vez

> **Escrito a 2026-08-28** a partir dos relatórios e dos commits de Agosto de 2026.
> **Lê-se no arranque de TODA a missão**, antes de qualquer plano. É a lei da casa.
>
> Cada regra aqui tem uma **cicatriz** ao lado: o estrago real que a originou, com data.
> Uma regra com cicatriz cumpre-se; uma regra abstracta esquece-se. Nada aqui foi inventado.
>
> **Hierarquia:** este documento manda sobre hábitos e sobre planos. Só perde para uma
> ordem explícita do Danilo na conversa. Se este documento estiver errado, corrige-se este
> documento — não se contorna.

---

## 0. COMO USAR ISTO

1. **No arranque:** lê a secção 1 (a lista fechada) e a secção 6 (zonas que não se tocam).
   Se a missão tocar publicação, lê também a 4.
2. **Antes de dizer "está feito":** volta à secção 3 e prova cada afirmação.
3. **No fim:** o relatório segue a secção 5 — texto corrido, acessos no topo, o que não
   foi feito dito logo no início.

O documento não substitui o Cérebro (`.claude/.ai/knowledge/`) nem o `CLAUDE.md`.
O `CLAUDE.md` diz **como é a casa**; isto diz **onde é que já nos magoámos**.

---

## 1. LISTA FECHADA — categoria nova ou papel novo

Uma categoria só está **lançada** quando os dezanove pontos abaixo estão feitos. Se faltar um,
não está lançada — está a meio, e diz-se que está a meio.

Esta lista existe porque em Agosto lançámos três categorias e **todas** falharam em pontos
diferentes desta lista, sempre por esquecimento e nunca por dificuldade.

### 1.1 Os três pagamentos a funcionar desde o primeiro dia, com teste real dos três

Cartão, MB Way e dinheiro. Teste real quer dizer: um pedido a sério, criado pelo caminho
que o cliente percorre, com prova do lado do servidor.

> **Cicatriz (27/08, Lavagem Auto):** nasceu só com dinheiro. O cartão e o MB Way ficaram
> atrás de um interruptor desligado e só entraram no dia seguinte, em missão própria. E,
> quando entraram, o MB Way foi recusado pelo provedor e continua por provar.
>
> **Cicatriz (25/08, Festas):** o teste ponta-a-ponta foi só em dinheiro. Cartão e MB Way
> assumiram-se bons "porque passam pelos mesmos caminhos do delivery". Assumir não é provar.

Regra prática: se um método não puder ser testado (o cartão obriga a introduzir dados, que
o agente não faz), **diz-se qual é o passo que falta e de quem é**, e não se declara feito.

### 1.2 A morada do cliente preenche-se sozinha, é editável, e nunca trava o pedido

Cascata obrigatória, igual em todos os ecrãs: **morada guardada → morada de casa → GPS com
geocodificação inversa**. Existe `lib/services/auto_address.dart` para isto. Não se inventa
um mecanismo por ecrã.

O GPS negado, desligado, sem sinal ou lento devolve vazio e **deixa o campo escrever**.
Nunca lança, nunca bloqueia, nunca abre um alerta. Se a pessoa começar a escrever enquanto
o GPS resolve, ganha quem escreveu.

> **Cicatriz (24/08):** o pedido travava quando o GPS falhava. A regra nasceu daí.
> **Cicatriz (27/08):** o botão "Pedir lavagem" chamava `Form.validate()` e voltava atrás
> **em silêncio** quando faltava um campo. Os erros apareciam nos campos acima, fora do
> ecrã. Do lado do Danilo o botão simplesmente não fazia nada, e o servidor mostrava zero
> chamadas. Um botão que parece funcionar e não faz nada é pior do que um erro.

Portanto: quando a validação falha, **rola até ao primeiro campo em falta, realça-o e diz
o que falta em palavras** ("Falta a matrícula do carro").

### 1.3 O ladrilho `cat_<nome>.png`, quadrado, fundo de cor cheio, no estilo dos outros

Nunca transparente. Nunca com o xadrez que os editores desenham para representar
transparência — esse xadrez fica pintado dentro do ficheiro e aparece na app tal e qual.
Formato dos irmãos: 512×512, paleta, entre 15 KB e 120 KB.

Nome de duas palavras parte em **duas linhas**, não encolhe a letra. A caixa do nome tem
altura fixa de duas linhas mesmo quando o nome só tem uma — é isso que faz os ladrilhos
ficarem iguais. Prova com teste de imagem às larguras 360, 390 e 430.

> **Cicatriz (27/08):** a imagem da Lavagem Auto veio do gerador com o xadrez pintado por
> dentro. Foi preciso medir a cor exacta do quadrado claro e pintá-la por cima — 198.898
> píxeis — porque recortar já tinha corrido mal duas vezes.
> **Cicatriz (28/08):** o nome "Lavagem Auto" partia em três linhas e tapava o desenho.

### 1.4 O papel aceite em `user_roles`

O `CHECK` da coluna `role` tem de aceitar o papel novo **antes** de a categoria abrir.

> **Cicatriz (27–28/08, Lavagem Auto):** o `CHECK` recusava `washer`. A categoria esteve no
> ar sem que ninguém no mundo se pudesse inscrever como lavador. Hoje o `CHECK` aceita
> `client`, `driver`, `partner`, `cleaner`, `washer` e `admin`.

Regra geral que daqui sai: **antes de semear ou inserir dados em colunas que cheiram a
enumerado (papel, estado, tipo, zona), lê primeiro as constraints da tabela.**

### 1.5 O aparelho registado em `provider_push_tokens`, por papel

Uma tabela, uma linha por pessoa **e por papel**, com o papel numa coluna — nunca uma
tabela por papel. O registo acontece no **portão de autenticação**, para todos os papéis ao
mesmo tempo, e não dentro de cada ecrã.

> **Cicatriz (28/08):** faxineiro e lavador nunca tinham token. A função da base só sabia
> escrever em três tabelas — cliente, motorista e parceiro — e mandava embora qualquer
> outro papel. A coluna antiga `fcm_token` só existe na tabela dos motoristas.
> **A Limpeza esteve meses no ar sem nunca poder chamar ninguém.**
>
> **Cicatriz irmã, e a pior:** existia uma função chamada "regista este aparelho em todos os
> papéis" **sem um único chamador**. Era casca sem fio. Quem registava eram os ecrãs, cada
> um a fixar o seu papel à mão, e os ecrãs do faxineiro e do lavador não registavam nada.

**Lei da casca sem fio:** um serviço, widget ou função criada com **zero chamadores** não
está feita. Antes de dar por concluída uma peça nova, procura os pontos de chamada
(`git grep NomeDaPeca`). Zero chamadas = não está feito.

Não chega guardar o token: **a função que envia tem de o ir buscar à tabela nova**, juntar
com a coluna antiga, e enviar para **todos** os aparelhos da pessoa. Um token morto
desliga-se sozinho sem levar os outros à frente.

### 1.6 Toque persistente igual ao do parceiro

O aviso tem de tocar esteja a pessoa no ecrã que estiver, em segundo plano e com a app
fechada. Em `lib/services/notification_service.dart` existe o conjunto
`_kPersistentCategoryTypes`. **Todo o tipo de push de uma categoria nova entra ali.**

> **Cicatriz (28/08):** os avisos da lavagem faltavam por inteiro nesse conjunto e caíam no
> comportamento normal do Android, que desaparece sozinho.
> **Cicatriz (31/07):** a causa de um push que não abria o ecrã certo era o bloco
> `notification` na Edge Function, não o canal. As Edge Functions de aviso são
> **data-only**: título e corpo viajam dentro do `data`. Copiar um molde antigo traz o bloco
> `notification` atrás — apagar sempre.

### 1.7 Uma entrada visível para a pessoa se inscrever

O ecrã de candidatura tem de estar alcançável de fora, para quem ainda não é nada.

> **Cicatriz (28/08):** a candidatura da Limpeza estava a quatro níveis de profundidade —
> só se chega ao `CleanerApplyScreen` a partir do `CleanerHomeScreen`, ou seja, só quem já
> lá está. A Lavagem Auto **não tem ecrã de candidatura nenhum**.

### 1.8 O interruptor do prestador construído dos papéis reais

A caixa "O que queres aceitar?" lê-se de `user_roles`, nunca de uma lista fixa no código.
Quem tem dois papéis vê dois interruptores; quem tem um não vê caixa nenhuma.

E — a parte que era fácil esquecer — **as funções que enviam os avisos têm de perguntar se
a pessoa quer receber daquele papel antes de enviar**. Sem isso o interruptor é decorativo.

> **Cicatriz (28/08):** era um rádio de duas opções fixas. A caixa nunca soube que a limpeza
> e a lavagem existiam, e por isso o Danilo não as via.

Não se deixa desligar o último papel ligado: ficaria online sem receber nada, e isso lê-se
como avaria e não como escolha. Para parar de todo existe o "estou online".

### 1.9 Acerto semanal único por pessoa, com todos os papéis somados e a dívida abatida

Uma linha por pessoa e por semana, com o detalhe aberto por tipo de trabalho, as parcelas
separadas antes do total, e um número único no fim com o sentido: ou a Bora paga, ou a
pessoa deve.

Duas armadilhas que estavam escondidas nas tabelas e que dariam erro **em dinheiro**:

> **Cicatriz das unidades (28/08):** `driver_weekly_settlements` guarda **euros**;
> `cleaner_weekly_settlements` e `washer_weekly_settlements` guardam **cêntimos inteiros**.
> Somar os campos directamente dá um erro de cem vezes — a diferença entre pagar quatro
> euros e pagar quatrocentos. **Converte-se tudo para cêntimos inteiros**, que é a única
> unidade em que dinheiro se soma sem arredondar pelo caminho.
>
> **Cicatriz da identidade (28/08), e é pior:** a tabela do motorista aponta para a
> **pessoa** (`drivers.user_id`); as da limpeza e da lavagem apontam para a **linha** do
> faxineiro e do lavador (`cleaners.id`, `washers.id`), que é outra coisa. Juntar por
> identificador às cegas casa o acerto de um motorista com a linha de um faxineiro
> qualquer — e ninguém dava por isso até alguém receber o dinheiro de outra pessoa.

### 1.10 Correspondência total no painel admin

Ver, editar, criar, banir, configurar, exportar, auditar. Em PT-BR. Toda a feature nova
convoca o agente `admin` no fim — é gatilho, não é opinião.

A **reatribuição** entra desde o início. Foi o que faltou nos pedidos normais e obrigou a
SQL à mão a 16/08; a Lavagem Auto já nasceu com ela.

### 1.11 Mini-site do parceiro com vídeo e com os dois botões de pedir

**Vídeo:** todo o site que se faça leva vídeo — o do próprio cliente se ele tiver, ou
montado a partir das fotografias reais dele se não tiver. Nada gerado por inteligência
artificial e nada de banco de imagens. Com legendas que digam a mensagem, porque um vídeo
mudo e parado lê-se de relance como uma fotografia.

**Dois botões do mesmo tamanho, nenhum secundário:** "Descarregar a app" (Android, instala
e recebe os avisos) e "Pedir pelo site" (iPhone e computador, sem instalar nada).

> **Cicatriz (28/08):** havia um botão grande para a Play Store com a web em letra miudinha
> por baixo. Metade das pessoas não tem Android.
> **Cicatriz (28/08):** o mp4 da Goola rebentou a meio da codificação por falta de memória
> — dois ffmpeg ao mesmo tempo num PC de 4 GB — e **subiu para produção um ficheiro de 57 KB
> com dois quadros**. O webm estava bom e o mp4 era lixo. O gerador tem agora uma guarda:
> abaixo de um megabyte rebenta em vez de deixar passar.


### 1.12 A sobreposição por cima do ecrã, seja qual for o papel

Entra um trabalho, o aviso aparece **por cima do que a pessoa estiver a fazer** — mesmo
noutro papel, mesmo com a app em segundo plano, mesmo com a app fechada. O mecanismo é
`IncomingJobAlert`: canal urgente `bora_orders_urgent_v3`, `fullScreenIntent`, som
`bora_alert` em ciclo com `FLAG_INSISTENT`. É o padrão do estafeta, extraído para se
reutilizar.

**Não se usa `FlutterOverlayWindow`.** Foi removido de propósito a 18/07 e está escrito no
topo do ficheiro: o sistema de oferta do estafeta é delicado e testado em aparelho, e
mexer-lhe às cegas arriscava partir uma peça central. Quem quiser sobreposição usa o
`fullScreenIntent`, que acorda o ecrã e já está provado.

> **Cicatriz (28/08, Lavagem Auto):** a lavagem nasceu sem uma única linha de alerta do lado
> da app — zero referências a `IncomingJobAlert` no `washer_store`. Não havia som, não havia
> valor, e tocar no aviso não levava a lado nenhum.

### 1.13 O aviso leva sempre o valor, e o valor é o que a pessoa GANHA

Todo aviso de trabalho novo leva o dinheiro no corpo. E leva o que o prestador recebe, não
o que o cliente paga — é isso que faz a pessoa decidir.

> **Cicatriz (28/08):** um pedido de lavagem de vinte euros gerou um aviso que dizia zero
> euros, porque ninguém punha o campo lá dentro.

### 1.14 Tocar no aviso abre o ecrã da categoria certa, no trabalho certo

Um gancho **único** com a categoria no argumento (`NotificationService.abrirTrabalho`),
registado no `main.dart` e não dentro de um ecrã.

> **Cicatriz (20/08):** o gancho do "A caminho" da reserva vivia no `initState` de um ecrã;
> com outro ecrã por cima ficava a `null` e a navegação nunca abria.
> **Cicatriz (28/08):** tocar num aviso de lavagem só trazia a app à home.

### 1.15 Rotação entre prestadores — e as tarefas agendadas a chamá-la

Não basta escrever as funções de rotação. **Alguém tem de as chamar.** Categoria nova sem
`cron.job` é código morto com aspecto de funcionalidade. Ao lançar, comparar com a limpeza,
que é o molde mais completo: tempo esgotado da oferta, nova tentativa, expirar sem ninguém,
lembretes, alerta de preso, acerto semanal.

E os tempos de espera vivem em `platform_settings`, nunca cravados no corpo da função.

> **Cicatriz (28/08, Lavagem Auto):** as funções `_carwash_cron_offer_timeout`,
> `_carwash_cron_retry_unoffered` e `_carwash_cron_stuck` existiam há dias e **não havia uma
> única tarefa agendada a chamá-las**. A limpeza tinha oito, a lavagem tinha zero. Um pedido
> de vinte euros foi oferecido às 06h24, a oferta expirou às 06h34, e ficou parado seis horas
> porque não havia nada a olhar para ele.

### 1.16 O nome que a pessoa lê nunca é o nome técnico do papel

`driver`, `delivery`, `cleaner`, `washer` são nomes de base de dados. No ecrã aparece
"Corridas de passageiros", "Entregas", "Limpeza", "Lavagem de carros". O caso de recurso de
um tradutor **nunca devolve o nome cru** — devolve um rótulo neutro e um teste rebenta.

> **Cicatriz (28/08):** apareceu "delivery", em inglês e minúsculas e sem descrição, no ecrã
> do Danilo. O papel entrou na base antes de alguém lhe dar nome, e o recurso do tradutor
> mostrava o que vinha da base.

### 1.17 O cartão copia-se do que já está provado, não se prova outra vez

Cartão, MB Way e dinheiro continuam obrigatórios (ver 1.1). O que muda é a **prova**: o
caminho do cartão já está provado no delivery e no motorista. Categoria nova aplica esse
caminho tal e qual, e a prova é mostrar que é o mesmo caminho — não repetir o teste do zero.
Onde houver diferença entre categorias, alinha-se pelo que já está provado.

### 1.18 Ao tirar uma escolha antiga, apagá-la mesmo

Substituir um menu por outro e deixar o antigo vivo noutro caminho é criar gémeos com
atraso: dois sítios que dizem a mesma coisa e se podem contradizer. Apaga-se o antigo, e
apaga-se também quem escrevia por ele.

> **Cicatriz (28/08):** os quatro interruptores novos entraram, mas o menu velho das duas
> opções ficou vivo num caminho de recurso, a escrever `drivers.work_mode` à mão — o mesmo
> campo que passara a ser projecção da preferência.


### 1.19 O texto de marketing bate certo com a base de dados, ao pormenor

Nunca se escreve uma promessa mais generosa do que o produto. Antes de publicar o
site, o cartaz ou a descrição da loja, lê-se o que está na base — nome, preço,
quantidades, o que está incluído e o que se paga à parte — e o texto diz **isso**,
com números. "Os que quiseres" e "todos incluídos" são promessas sem número e não
se usam.

E vale nos dois sentidos: também não se pode sugerir menos do que o produto é. Um
texto que faça parecer que o bowl vem só com açaí afasta quem queria os
acompanhamentos.

> **Cicatriz (28/08, Goola Açaí):** o topo do site dizia "com os acompanhamentos
> que quiseres — todos incluídos no preço", e as meta-descrições diziam "com 17
> acompanhamentos incluídos". A verdade, que já estava correcta na base de dados
> desde o primeiro dia, é 3 acompanhamentos no Goola Bowl e 4 no Big Bowl, à
> escolha entre 17, mais 3 extras pagos à parte. Cinco sítios do mesmo site
> prometiam a mais. **Foi o próprio dono da loja a apanhar**, ao ler o cartaz,
> antes de aquilo chegar ao público — e teria dado reclamação ao balcão nos dois
> sentidos: quem esperasse toppings à vontade e quem julgasse que era açaí puro.

---

### 1.20 Função de acerto semanal **e** a tarefa agendada que a chama

Uma categoria que paga a alguém precisa das duas coisas: a função que fecha a
semana e a tarefa que a chama à segunda-feira. Uma sem a outra não paga nada.

> **Cicatriz (29/08):** a Lavagem Auto não tinha **nenhuma das duas**. A tabela
> `washer_weekly_settlements` existia, o cron da Limpeza existia, e a lavagem
> não tinha nem função nem agendamento. Um carro lavado nunca entraria em
> acerto nenhum e nunca seria pago. Ninguém deu por isso porque a tabela vazia
> parece "ainda não houve lavagens", não "não há quem calcule".

**Lei que daqui sai:** uma tabela de dinheiro sempre vazia é suspeita, não é
prova de calma. Procura quem lá escreve; se ninguém escreve, está partido.

### 1.21 O ganho recebido em mão não volta a ser pago no acerto

Quando o cliente paga **em dinheiro**, quem recebe a nota é o prestador: fica
com o que é dele e com a parte da Bora. O acerto da semana tem de pagar só os
trabalhos em que a Bora recebeu, e cobrar a parte dela dos que foram a dinheiro.

> **Cicatriz (29/08):** `compute_cleaner_weekly_settlement` fazia
> `net := total_earnings` — o ganho de todas as limpezas, sem olhar a como
> foram pagas. Em duas limpezas de vinte euros, uma a cartão e outra a dinheiro
> com cinco de taxa, a fórmula antiga pagava **quarenta euros** onde devia pagar
> **quinze**.

### 1.22 O cliente é avisado em TODAS as mudanças de estado, e o aviso vai à tabela certa

Não chega avisar ao aceitar e ao concluir. Cada passo do meio é um aviso, com o
nome de quem lá vai e não com o nome do estado na base.

E o aviso tem de ir buscar o aparelho à tabela **do destinatário**: o cliente
não tem linha em `provider_push_tokens`.

> **Cicatriz (29/08), e é das piores:** `_carwash_notify_user` mandava tudo pela
> função de aviso do lavador — incluindo os avisos dirigidos ao CLIENTE — e essa
> função só procurava aparelhos na tabela dos prestadores. **Nenhum cliente
> recebeu um único aviso por telemóvel da Limpeza ou da Lavagem, desde sempre.**
> Ficava só o aviso dentro da app, que ele só vê se a abrir. Prova do antes e
> depois no mesmo registo: `{"ok":false,"reason":"no_fcm_token"}` às 18h14,
> `{"ok":true,"enviados":2,"aparelhos":7}` às 18h51.

### 1.23 A rotação não gasta a vez com quem não pode ser avisado

Quem não tem aparelho registado vai atrás na ordem e recebe uma janela curta,
não a janela inteira. Não se salta de todo — há quem trabalhe com a app aberta —
mas não se para o trabalho dez ou trinta minutos à espera de quem não foi
chamado.

E cada oferta deixa registo: para quem foi, se tinha aparelho, quanto tempo teve
e como acabou. Sem isso não há como ver onde o trabalho emperra.

> **Cicatriz (29/08):** duas ofertas seguidas foram para prestadores sem nenhum
> aparelho registado. Esperaram a janela toda e só depois passaram adiante. Foi
> preciso ir à mão às tabelas para descobrir porquê.

### 1.24 O trabalho aceite manda no ecrã até estar terminado

Depois de aceitar, a pessoa fica dentro do trabalho. Sai da app e volta: cai
outra vez lá dentro, não no ecrã do papel principal. Enquanto durar, há um
caminho de volta visível em qualquer ecrã. Ao terminar, volta sozinha.

A verdade de "há trabalho a meio" vem do **servidor**, nunca da memória local:
estado guardado só no telemóvel morre quando o Android mata a app, que é
precisamente quando faz falta.

> **Cicatriz (29/08):** o Danilo aceitou uma lavagem, saiu da app, voltou, e
> caiu no ecrã de motorista. **Julgou que tinha perdido a lavagem.**


### 1.25 Uma conta, uma pessoa, todos os perfis

**Quem tem conta no Bora pode ser tudo o que quiser ser, com o mesmo email e a
mesma palavra-passe.** Estafeta que quer pedir o jantar. Lojista que quer fazer
uma entrega. Faxineira que quer lavar carros. Ninguém cria uma segunda conta,
e nenhuma porta expulsa quem entra por ela.

Três coisas que daqui saem, e que são regra:

**Nunca se faz `signOut` por causa de papel.** A pessoa autenticou-se com a
palavra-passe certa; pô-la fora porque o perfil não bate é dizer-lhe que a
palavra-passe está errada quando não está. Se lhe falta o perfil dessa porta,
diz-se isso — não se corta a sessão.

**A verdade de quem é o quê vive em `user_roles`, nunca no `bora_role`.** O
`user_metadata.bora_role` é um campo **único**: guarda o modo em que a app
ficou da última vez, e é substituído a cada troca. Só `user_roles` aguenta
acumulação, porque é uma linha por papel.

**Cliente não tem candidatura.** Quem tem conta pode ser cliente. Se lhe falta
a linha, cria-se (`add_client_role_to_me`) e segue-se — não se pergunta nada.

> **Cicatriz (28–29/08), e custou um cliente real:** um estafeta com
> candidatura em análise tentou usar a app como cliente. Nos `auth_logs`, o
> mecanismo repetido quatro vezes: `Login 200` às 23:11:33, `logout` às
> 23:11:41. Outra vez às 23:13:58, às 23:15:45, às 23:16:17. A palavra-passe
> estava certa em todas. Era a app que o deitava fora. Teve de lhe ser criada
> uma conta com `+cliente` no email para poder experimentar o Bora.
>
> **Cicatriz gémea, no mesmo dia:** o ecrã de escolha de perfil fazia
> `logout()` em **todos** os botões, mesmo com sessão aberta. Quem já estava
> dentro e queria só mudar de perfil era posto fora e obrigado a escrever a
> palavra-passe. Corrigir só o login não teria chegado.
>
> **Cicatriz irmã:** "Candidatura em análise" era uma parede com um único
> botão: "Sair". O perfil que está a ser revisto é **um**; a app é a mesma. Um
> pedido pendente nunca bloqueia os outros perfis.

E as portas do arranque dizem **a quem se destinam**. Uma pessoa sozinha caiu
nas três numa noite porque "Sou Estafeta" e "Sou Parceiro" não explicavam nada.
As três são iguais nisto, e as três têm caminho de volta — a do parceiro não
tinha.

### 1.26 Nenhum ecrã fica preso à espera de uma permissão

Toda a espera por uma permissão ou por hardware tem **limite de tempo**, e toda
a recusa tem **ecrã que explica**, em português, com o que fazer a seguir.

Um `try/catch` com recurso **não chega e engana**: parece coberto.

> **Cicatriz (29/08):** o ecrã do estafeta bloqueia a render até ter uma
> posição de GPS. O código tinha `try/catch` e caía no centro da Guarda — mas
> `Geolocator.getCurrentPosition()` **não devolve e não rebenta** quando a
> posição nunca chega (no browser, ou com o pedido de permissão por responder).
> O `catch` nunca corria, a variável nunca deixava de ser nula, e o carregador
> rodava **para sempre**, sem uma palavra. Quem instala, recusa o GPS e vê
> isto, desinstala e não volta.
>
> **Cicatriz gémea:** o mesmo `await` sem limite no ecrã do motorista TVDE,
> onde prendia o arranque do fluxo de posição inteiro.

**Lei que daqui sai:** procura `await` sobre hardware ou permissões sem
`.timeout(...)`. Cada um é um ecrã que pode ficar preso.


## 2. ONDE CADA COISA VIVE — A REGRA DOS GÉMEOS

**O maior gerador de erros do mês foi a mesma verdade escrita em vários sítios que podem
divergir.** Não é um bug de cada vez: é um padrão. Sempre que uma informação vive em mais
do que um lugar, um dos lugares acaba por ficar por preencher, e o sintoma aparece longe da
causa.

**Regra geral:** quando encontrares uma verdade duplicada, escreve aqui quais são os sítios,
diz qual é a fonte, e **preenche todos** até a unificação existir. Não escolhas um em
silêncio.

### 2.1 O papel do utilizador vive em quatro sítios

1. `users.role`
2. o metadata da conta de acesso, em **dois campos**: `role` e `bora_role`
3. `user_roles` (uma linha por papel — é a única que aguenta acumulação)
4. a tabela do próprio papel (`drivers`, `cleaners`, `washers`, `restaurants`…)

**A app lê o papel de um sítio só:** `userMetadata['bora_role']` (`auth_store.dart`,
constante `_kRole`). O `user_roles` é para a RLS, para o admin e para o interruptor do
prestador. `users.role` é histórico.

**Ao criar uma conta, preenchem-se os quatro.** Existe agora guarda na base
(`trg_parceiro_registos_completos` e `trg_parceiro_papeis_completos`) que preenche o que
falta sozinha, mas a guarda é rede, não é desculpa.

> **Cicatriz (27–28/08):** três dias a apanhar contas partidas por faltar um deles. Contas
> de parceiro caíam no ecrã de criar conta.
>
> **Cicatriz gémea, e a mais cara:** a ligação loja↔parceiro era feita por
> `restaurants.email` comparado com o email do login. A Goola nasceu com essa coluna
> **vazia** e o dono caía no assistente de criar conta. **O email da loja é um campo de
> contacto, não uma chave de ligação.** A ligação verdadeira é `restaurants.user_id` (e
> `restaurants.user_`, que o servidor usa para a RLS — são **duas** colunas de dono e
> escrevem-se sempre as duas). No código, procurar sempre por `restaurantByOwner(userId)`
> primeiro; o email é só recurso para as lojas antigas.

### 2.2 As imagens de um parceiro vivem em três sítios

1. o Storage do Supabase (balde `restaurant-assets`)
2. as colunas da base que apontam para elas (capa, logótipo, imagem de topo, foto do produto)
3. o mini-site

> **Cicatriz (27–28/08, Goola):** o site ficou lindo e **a loja dentro da app ficou sem
> logo, sem capa e sem foto nenhuma**. Site e loja são dois destinos diferentes e a foto tem
> de entrar nos dois.

Regista na base a **origem** de cada foto (site oficial da marca, fotografia do cliente,
etc.) para daqui a seis meses ninguém ter de adivinhar de onde veio aquilo.

### 2.3 Os valores de negócio vivem em `platform_settings`, nunca cravados no código

Preços, percentagens, durações, raios, tectos, o valor do token, o que está ligado e
desligado. Se o valor aparece na app, vem de lá. O cálculo local só entra quando ainda não é
possível pedir o valor ao servidor — e mesmo aí lê das definições, nunca de um número
escrito à mão.

> **Cicatriz (13/08):** o valor do token cravado a **5 cêntimos em vez de 0,5**. A definição
> passou a ser a fonte única em todo o lado (commit `297b76e`).
> **Cicatriz (27/08):** a taxa de pedido pequeno era calculada na app. Passou a vir do campo
> `small_order_fee` que o servidor devolve no orçamento — que é exactamente o mesmo número
> que entra no total, no valor a cobrar e no que vai para a Stripe.

### 2.4 Gémeos que já nos morderam e vale a pena conhecer

- **`copyWith` incompleto.** O `copyWith` do modelo da loja não passava o `ownerId` adiante
  — bastava uma cópia do modelo para o defeito do parceiro-no-wizard voltar. Pior: ao
  editar o perfil, o código reconstruía o modelo **campo a campo à mão** e tudo o que
  ninguém se lembrou de escrever desaparecia — capa, logótipo, dono, "em breve".
  *(28/08)* **Campo novo no modelo entra também no `copyWith`.**
- **Tabela nova e o tempo real.** Uma tabela que a app acompanhe em tempo real **tem de
  entrar na publicação `supabase_realtime`**. Criar a tabela e subscrever no Dart não chega:
  o Postgres não emite um único evento e o ecrã fica parado **sem erro nenhum** — parece bug
  de Flutter e não é. *(27/08, Lavagem Auto. As tabelas da Limpeza estavam lá desde que
  nasceram; as do carwash não. O teste por API passava a 100% e escondia isto.)*
- **Ordem das guardas.** A validação do tecto de dinheiro corre **antes** do trigger que
  tira o saco, por isso usa o total com saco. *(25/08, Festas — só afecta pedidos entre
  39,70 € e 40,00 €, mas está escrito para ninguém o descobrir outra vez.)*
- **Repo e cópia de execução.** O loop autónomo corre de cópias (`hermes-bridge\` no PC,
  `/root/orquestracao` na VPS). Antes de declarar um conserto vivo, compara o `sha256` dos
  dois lados.

---

### 2.5 Um ecrã novo que não substitui o antigo deixa dois vivos — e abre-se o velho

Construir a versão nova e deixar a antiga ligada ao sítio de onde as pessoas
entram é a pior forma do problema: o trabalho está feito e ninguém o vê.

> **Cicatriz (28→29/08):** construí a vista unificada do acerto **e um ecrã novo
> de Ganhos** que a lia. Não liguei esse ecrã ao sítio de onde o Danilo abre os
> Ganhos. No dia seguinte ele abriu, viu só as entregas, e teve razão — o que
> ele abria era o antigo. Dois ecrãs de ganhos vivos ao mesmo tempo.

**Lei:** ao criar a versão nova de alguma coisa, o mesmo trabalho apaga a antiga
e reaponta **todos** os chamadores. `git grep NomeAntigo` tem de dar zero antes
de se dizer feito.

### 2.6 Um botão novo tem de estar no ecrã que a pessoa vê mesmo

Não basta existir e estar ligado. Tem de estar no caminho por onde ela passa.

> **Cicatriz (29/08):** pus o botão de "trabalhar noutra coisa" na barra de topo
> do ecrã do estafeta — mas o ecrã do estafeta tem **dois** desenhos, e a barra
> que editei é a do que só aparece **quando há pedidos**. No dia-a-dia o
> estafeta vê o mapa, e lá o botão não existia. Só se descobriu ao abrir mesmo o
> ecrã, pela web.
>
> **Cicatriz gémea, no mesmo sítio:** o botão novo tinha o mesmo ícone de setas
> do "Mudar modo" que já lá estava. Ao carregar no que julgava ser o meu, saí da
> conta. Dois botões com o mesmo ícone e significados diferentes são um botão só,
> aos olhos de quem usa.


## 3. REGRAS DE PROVA — isto é lei, não é conselho

**3.1 A verdade é o SELECT e o endereço público.** Nunca o ficheiro local, nunca a versão
deployada assumida, nunca a palavra de quem fez. Se dizes que gravou, lê de volta e mostra.
Se dizes que está no ar, puxa o endereço público e mostra o que veio.

**3.2 Purga a cache antes de auditar, e audita uns segundos depois do deploy.** Uma cópia na
borda da Cloudflare dura sete dias. Sem purga, estás a auditar o passado.

**3.3 O Cloudflare Pages devolve `200` com a página do site para endereços que não existem.**
Portanto o código de resposta **mente**. Olha o corpo: procura no conteúdo o que esperas
encontrar (ou o que esperas não encontrar). *(28/08 — foi assim que se distinguiu um `.env`
realmente exposto de três alarmes falsos.)*

**3.4 Nunca dizer que está feito sem a captura, o SELECT ou a saída literal do comando.**
Proibido "assumido", "deve estar", "provavelmente", "deve ter corrido bem". Se falhou,
diz-se que falhou, com o erro real.

**3.5 Cuidado com o falso positivo por baixo do invólucro.** Um `200` não prova que o
trabalho por dentro correu. Verifica o **efeito**, não o invólucro.
*(28/08: o pedido de recuperação de palavra-passe devolvia `200` e o email nunca chegava.)*

**3.6 Uma tabela vazia não prova que a coisa não aconteceu.** Prova que aquele registo não
está a ser escrito. *(28/08: `auth.audit_log_entries` tem zero linhas **de tudo** — nem os
logins lá estão. Quem parasse aí ia procurar o problema no sítio errado.)*

**3.7 Erro à primeira não é prova.** Numa repetição automática, a guarda só se prova se
aparecer **na repetição**. À primeira, o erro quer dizer o que diz. *(20/08)*

**3.8 Testar a app da loja não prova o conserto de hoje.** Se o que está instalado no
telemóvel é a versão publicada, o teste prova a app velha e dá uma resposta falsa. A ordem
não se salta: sobe, o CI constrói, actualiza-se pela Play Store, entra-se uma vez com o
papel certo, **e só aí** o teste tem sentido. *(28/08, duas vezes.)*

**3.9 Diz logo no início do relatório o que NÃO foi feito.** Antes de qualquer coisa boa.
Para o Danilo não ter de o descobrir no fim.

**3.10 Deixa o artefacto.** Nunca apagues o registo, a captura ou o ficheiro de prova de um
teste ao vivo. Sem ficheiro não é verificável.

**3.11 Teste anti-mentira.** Quando não tens a certeza de que uma ferramenta correu mesmo,
põe um ficheiro com um nome esquisito numa pasta e pede o nome. Se não disser, não correu.

**3.12 Recuperação de senha e deep links: um link por email que exige troca de código (PKCE)
só se prova abrindo-o num sítio SEM o segredo local de quem pediu.** O fluxo PKCE (default do
pacote `gotrue`) guarda o `code_verifier` só no storage de quem chamou
`resetPasswordForEmail` — quem pede no telemóvel e abre o link no browser do telemóvel (ou
outro dispositivo) cai sempre em `400 code challenge does not match previously saved code
verifier`, **mesmo com o email a chegar certo e o `redirectTo` correto**. Isto é invisível a
quem testa a pedir e a redefinir na MESMA app/aba (o storage bate por coincidência) — só
aparece com o email a sério, ou simulando outro storage. Prova-se assim, sem precisar de
inbox real: gera-se o link a sério pela Admin API (`/auth/v1/admin/generate_link`,
`type=recovery`, com `service_role`) — é o mesmo link que o email levaria — e segue-se com
`curl -D -` (sem `-L`) para ver o `Location` do 303: se tiver `?code=` é PKCE (frágil entre
dispositivos); se tiver `#access_token=…&refresh_token=…` é implícito (o token já vem pronto,
sem segredo local nenhum a validar). O conserto é `authFlowType: AuthFlowType.implicit` em
`Supabase.initialize` — só vale a pena se a app não usar OAuth nem magic-link (aqui não usa).
Fecha-se o ciclo com o `refresh_token` extraído: `POST /token?grant_type=refresh_token` (o
passo que antes dava 400 e passou a 200), depois `PUT /user` com a senha nova, depois
`POST /token?grant_type=password` com a senha nova (200) e com a antiga (400, confirma que
mudou mesmo). *(Cliente Junior ficou de fora do próprio email a 28/08; fix e prova E2E via
Admin API a 29/08 — commit `693036ea`.)*

### 3.9 Provar contra o endereço público, os dois lados, e o texto TODO

Uma alteração de texto num site só está feita quando se puxa o HTML **servido pelo
endereço público** e se prova, ponto a ponto e com a linha colada, que o texto novo
lá está **e** que o antigo não aparece em lado nenhum. Procurar só a frase nova
prova metade.

E prova-se **o texto todo**, não só as frases que se mudou: uma frase errada que
nunca se tocou continua errada, e a lista do que se mudou não é a lista do que
está mal.

Três armadilhas concretas:

- **Quebra-cache mente-te nos dois sentidos.** Pedir com `?x=123` pode dar-te a
  versão nova enquanto o mundo vê a velha. Compara sempre o endereço limpo com o
  quebrado; se diferirem, é cache e purga-se.
- **A publicação leva tempo a propagar.** Chamadas seguidas logo a seguir a
  publicar podem devolver versões diferentes de nós diferentes. Puxa meia dúzia
  de vezes e confirma que o resumo do ficheiro é o mesmo antes de auditar.
- **Bytes não são caracteres.** `len(bytes)` e `len(texto)` diferem numa página em
  português, e a diferença parece uma versão diferente quando não é.

> **Cicatriz (28/08, Goola Açaí):** disse que tinha corrigido cinco sítios e
> verificado pelo endereço público. Eram **sete**, e as fichas dos dois bowls, que
> eu nunca tinha tocado, continuavam a dizer "sem pagar nada por isso" sem
> mencionar que os acompanhamentos se escolhem de entre dezassete. A minha
> verificação procurou as frases que eu tinha mudado e deu-as por boas — não
> procurou o que estava mal e eu não tinha visto. Foi o Danilo a puxar o site de
> fora e a colar as linhas que faltavam.

---

### 3.10 A prova de ecrãs faz-se pela WEB. "Falta o cabo" não é razão.

A app corre inteira em `app.boraguarda.com` — os mesmos ecrãs, os mesmos fluxos,
os mesmos botões. Entra-se pelo browser e testa-se lá.

O cabo só é preciso para o que é mesmo do aparelho: o som a tocar, o aviso com o
ecrã bloqueado, e a app fechada. **Tudo o resto não tem desculpa.**

> **Cicatriz (27, 28 e 29/08):** três missões seguidas a escrever "não consigo
> provar, o cabo está desligado", com a app inteira disponível no browser o
> tempo todo. Foi o Danilo que teve de corrigir.

**Como se faz, para não se voltar a descobrir isto do zero.** Está guardado em
`.claude/.ai/provas/web-2026-08-29/_ferramentas/`. Três coisas são a diferença
entre funcionar e não funcionar:

1. **O GPS tem de vir do contexto do browser**, fixado na Guarda. Sem posição, o
   ecrã do estafeta fica no carregador **para sempre** — ele bloqueia a render
   até ter uma, e no browser essa posição nunca chega sozinha.
2. **O consentimento grava-se ANTES de a app arrancar.** Recusá-lo tem o mesmo
   efeito: o ecrã do estafeta nunca abre.
3. **Escrever em campos:** o Flutter desenha em canvas e o `input` do DOM só
   NASCE quando o campo ganha foco. Clica-se primeiro, e depois dispara-se o
   evento `input` a sério — escrever no `.value` sozinho não move nada no ecrã.

Para entrar sem saber a palavra-passe de ninguém, gera-se um link de uma vez
(`admin/generate_link`) ou cria-se uma conta de prova que se apaga no fim.
**Nunca se muda a palavra-passe de uma conta real para poder testar.**

### 3.11 Quando o Danilo e eu vemos coisas diferentes no mesmo endereço, o desencontro resolve-se primeiro

Antes de mexer em código, percebe-se porque é que as duas leituras divergem:
cache, propagação a meio, endereço diferente, sessão diferente, versão diferente.
Mexer no código enquanto as leituras não batem certo é arranjar o que talvez não
esteja partido.

> **Cicatriz (28/08):** uma tarde inteira a discutir se o site estava certo. Ele
> via o texto novo, a minha leitura devolvia uma cópia velha. Seis dos oito
> pontos já estavam corrigidos e eu estava a olhar para uma versão anterior.

### 3.12 Procurar o que está mal, não confirmar o que se mudou

Verificar as frases que eu próprio mudei prova que as mudei. Não prova que
estava tudo mal e ficou tudo bem. A varredura faz-se pelo problema — todos os
sítios onde ele pode estar — não pela lista das minhas alterações.

> **Cicatriz (28/08):** corrigi cinco sítios do site da Goola e verifiquei os
> cinco. Eram sete. As fichas dos dois bowls, que eu nunca tinha tocado,
> continuavam a prometer a mais, e foi o Danilo que as encontrou.


## 4. PUBLICAÇÃO E SEGREDOS

**4.1 Publica-se sempre pelo `deploy-cloudflare.sh`, nunca a pasta em bruto.** Para os
outros sites, monta-se antes uma cópia filtrada com lista branca: `index.html`,
`robots.txt`, `sitemap.xml`, `media/`. Nunca a pasta de trabalho.

> **Cicatriz (27–28/08):** publicar `bora-site` com o `wrangler` apontado à raiz da pasta pôs
> o `.env` — com os **dois tokens da Cloudflare em texto simples** — a ser servido em
> `boraguarda.com/.env`, público, durante várias horas. O `.env` nunca entrou em git; a fuga
> foi só pelo deploy. A remediação real não é apagar o ficheiro: é **rolar os tokens**, o que
> foi feito.

**4.2 O `.gitignore` protege o nome exacto, não nomes parecidos.** Nada de `.env.bak`,
`.env.old`, `.env.copia`. Um segredo copiado para um nome novo deixa de estar protegido.

**4.3 Um endereço só fica vivo com as duas metades.** O CNAME proxied no DNS (token
`CLOUDFLARE_DNS_TOKEN`) **e** o domínio próprio registado do lado do projecto Pages (token
`CLOUDFLARE_API_TOKEN`). Falta uma metade e fica eternamente pendente. *(27–28/08)*

**4.4 Ao mudar endereços, arranja também os geradores.** `site_base.py`, `build.py` e os
modelos. Senão a próxima construção repõe os endereços velhos. *(28/08 — foram 102 moradas
em 30 ficheiros.)*

**4.5 Push é publicação.** Um push na branch de produção dispara a compilação Android **e** o
deploy web, e o CI publica em `internal`, `alpha` **e produção**. O `paths-ignore` avalia
**todos** os commits do push, por isso um commit só de documentação **leva o código pendente
de boleia**. Vê sempre o que viaja junto antes de empurrar.

**4.6 `git add` caminho a caminho, nunca `-A`.** Já arrastou a edição de outro executor.
Se o repo principal tiver coisas por committar de outra sessão, trabalha numa worktree.

**4.7 O `versionCode` é do CI.** Nunca se toca no `pubspec`.

**4.8 Segredos que o CI usa também mudam.** Ao rolar um token, lembra-te dos
`secrets.*` no GitHub — um token novo no `.env` e velho no CI parte o deploy automático.

---

## 5. COMO O DANILO TRABALHA

**5.1 Ele não mexe em painéis web.** Tem agente de clique e deu permissão total para entrar
e executar em Cloudflare, Supabase, Stripe, Resend, Google e GitHub. **Faz tu**, por API
sempre que der; se a API não chegar, usa o navegador com a sessão já autenticada.

**5.2 Nunca lhe escrever caminhos de menus.** "Vai a Caching, depois Configuration, depois
carrega em Purge" é falha. *(Corrigido a 28/08, depois de dois relatórios seguidos o
fazerem.)*

**5.3 Quando sobra um botão que só a pessoa dele pode carregar** — uma autorização, uma
palavra-passe, um pagamento — **deixa-se a página certa aberta no ecrã, com só o clique por
fazer**, e sem instruções de navegação.

**5.4 A linha vermelha mantém-se:** nunca escrever palavras-passe, dados de cartão ou
credenciais em formulários. Aí a página fica aberta e o clique é dele.

**5.5 Relatórios em texto corrido.** Sem tabelas, sem símbolos, sem listas de setas — ele
ouve em voz alta. Português simples.

**5.6 Os acessos vão sempre no topo do relatório.** Emails das contas envolvidas, e o que
foi criado nesta sessão.

**5.7 Nunca lhe pedir tarefa manual técnica.** Excepções: decisões legais e financeiras, e
actos que as travas de segurança exigem que sejam humanos.

**5.8 Ele decide, os agentes executam.** Tarefas normais decidem-se e executam-se
ponta-a-ponta, sem menus de escolha e sem parar a meio. A única travagem é dinheiro real.

---

## 6. ZONAS QUE NÃO SE TOCAM

Sem ordem explícita, e mesmo com ordem, com aviso escrito no relatório:

`pricing_service.dart` · comissões e percentagens · `bora_tokens` e os triggers de tokens ·
`dispatch_engine` · `quote_order_pricing` · `partner_shelf_price` · `finalizePurchase` ·
o webhook da Stripe · a RLS de `orders`, `wallets` e `ledger` · `versionCode` ·
`.claude/settings.json` (a Trava).

Quando o trabalho tocar numa destas, faz-se **toda a preparação** e escreve-se no relatório,
em português claro:

> ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

E só se aplica depois do "vai".

> **Nota sobre a Trava (27/08):** ela recusa qualquer alteração cujo **texto** mencione
> `add_tokens`, e não distingue "chamar" de "alterar". Isso **não se contorna**: deixa-se a
> migration pronta como proposta no repo e o Danilo aplica. Foi o que se fez com
> `20260827102000_PROPOSTA_carwash_tokens.sql`.
>
> **Nota sobre alternativas aditivas:** quando a Trava bloqueia reescrever uma função
> canónica de dinheiro, um **trigger aditivo** entrega o mesmo efeito e é permitido por
> desenho — mas a versão canónica fica no repo como proposta, para ser absorvida depois.
> Foi o que se fez com o saco das Festas (`festas_sem_saco_trigger` aplicado,
> `festas_money_patch` por aplicar).

**Duas regras de servidor que custaram tempo e ficam aqui:**

- **`REVOKE` tem de ser `FROM PUBLIC`.** Revogar de `anon` e `authenticated` **não fecha** a
  função, porque a permissão vem herdada de `PUBLIC`. Confirma com `has_function_privilege`.
  *(27/08: 42 funções do carwash ficaram chamáveis por anónimos; a primeira correcção não
  funcionou.)*
- **`EXCEPTION WHEN OTHERS THEN NULL` numa função com efeito colateral é falha invisível
  permanente.** Captura e regista; não descartes.

---

## 7. INVENTÁRIO — o que falta a cada categoria já existente

**Fotografia tirada a 2026-08-29**, com a lista fechada já com vinte e quatro pontos. É
levantamento, não é correcção: é daqui que sai o trabalho das próximas missões. O que
mudou desde a fotografia de 28/08 vem marcado.

### 7.1 LIMPEZA

Aberta. Papel `cleaner` no `user_roles`, com 3 pessoas. Tarefas agendadas: oito, das mais
completas da casa.

**Fechado desde ontem:** entrada de candidatura visível pela porta "Quero trabalhar no
Bora"; acerto semanal unificado; avisos ao cliente em todos os passos; o dinheiro em mão
deixou de ser pago duas vezes; o trabalho aceite manda no ecrã; botão "Abrir rota".
**Provado pela web a 29/08, com fotografias.**

**Falta:**

1. **Pagamentos:** o dinheiro continua **sem aparecer no ecrã de escolha** — o servidor
   trata `cash` como pago no local mas o cliente não o pode escolher. Falta decidir se a
   Limpeza aceita dinheiro. Nenhum dos três tem teste real registado.
2. **Morada:** o assistente ainda **não usa o `AutoAddress`** — só copia a morada do
   carrinho. Quem entra na Limpeza sem passar pela home fica com o campo vazio.
3. **Rotação:** falta a **nova tentativa** (a lavagem tem, a limpeza não).
4. **Prova no aparelho:** o som e o ecrã bloqueado continuam por provar. É a única parte
   que precisa mesmo do cabo.
5. **Mapa:** o botão de rota abre a app de mapas; **mapa dentro da app não há**, e para a
   limpeza vai só pela morada escrita porque o modelo não traz coordenadas.

### 7.2 LAVAGEM AUTO

Aberta. Papel `washer` com 3 pessoas. Motor clonado do da Limpeza.

**Fechado desde ontem:** candidatura de lavador (não existia de todo); o gatilho que dá o
papel a quem se inscreve (não existia, e por isso um lavador estava sem papel); **a função
de acerto semanal e o seu cron, que não existiam** — uma lavagem feita nunca seria paga;
avisos ao cliente em todos os passos; rotação que não gasta a vez com quem não tem
aparelho; registo de ofertas com painel.

**Falta:**

1. **Pagamentos:** **cartão** provado até ao PaymentIntent — o PaymentSheet exige dados de
   cartão e é acto do Danilo. **MB Way** recusado pelo provedor; confirmar se o 937501673
   tem MB Way associado.
2. **Rotação:** faltam **expirar sem ninguém** e **lembretes** (as funções não existem).
3. **Tokens de fidelização:** a migration `20260827102000_PROPOSTA_carwash_tokens.sql`
   continua **por aplicar** — é acto do Danilo.
4. **Marcar um pedido como teste:** a tabela `carwash_bookings` **não tem `is_test_order`**,
   ao contrário da limpeza. Descoberto a 29/08 ao montar a prova: uma lavagem de teste conta
   nos ganhos como se fosse real.
5. **Prova no aparelho:** igual à limpeza.
6. **Só interior:** desligado de propósito.

### 7.3 FESTAS

Aberta em código desde 25/08. Um pedido de festa é um pedido de restaurante parceiro com
`scheduled_for` — não abriu caminho novo de dinheiro nem de dispatch, e por isso os pontos
novos 1.20 a 1.24 quase todos **não se lhe aplicam**: quem recebe é o parceiro, pelo fecho
semanal de parceiro que já existia.

**Falta, e é o mesmo de ontem — não lhe mexi:**

1. **Pagamentos:** só o dinheiro foi testado a sério. Cartão e MB Way passam pelos caminhos
   do delivery mas **não há teste real de festa** com nenhum dos dois.
2. **Ladrilho:** `cat_festas.png` está **1024×1024 com canal alfa**, fora do padrão dos
   irmãos. Regenerar em 512×512 com fundo cheio.
3. **Dinheiro por absorver:** `20260825091000_festas_money_patch.sql` **não aplicada**. O
   efeito está entregue por um trigger aditivo; ficam dois restos conhecidos (o tecto conta
   um saco que não é cobrado, entre 39,70 € e 40,00 €; o orçamento devolve 0,30 € que a
   cobrança não usa).
4. **Acessibilidade:** botões, dias do calendário e chips de hora sem rótulos.
5. **Estado da loja da Keli:** confirmar se saiu de `coming_soon`.

### 7.4 RESERVA DE MESA

Sistema antigo e completo. Sinal de 3,00 €. Cinco tarefas agendadas próprias.

Os pontos novos também quase não se lhe aplicam: quem recebe é o parceiro.

**Falta, e é o mesmo de ontem:**

1. **Pagamentos:** não tem dinheiro, **de propósito** — um sinal pré-pago não pode ser em
   dinheiro. É a excepção justificada à regra 1.1, escrita aqui para não voltar a ser
   levantada como defeito.
2. **Toque persistente:** os tipos de push das reservas de mesa **não estão** em
   `_kPersistentCategoryTypes` (lá estão os das marcações). Confirmar que tipo o servidor
   emite e, se for próprio, acrescentá-lo. **Continua por confirmar.**
3. **Parceiros a usar:** nenhuma loja tem reservas ligadas (`reservations_enabled = false`
   em todas). Decisão comercial, não defeito técnico.

### 7.5 Achados transversais, revistos a 29/08

- **O painel admin dos papéis já existe** (feito a 28/08) — deixa de ser buraco.
- **O acerto semanal por pessoa e o registo de ofertas já existem** e estão no painel.
- **Quatro ladrilhos continuam a ser WebP com extensão `.png`:** `cat_encomenda.png`,
  `cat_farmacia.png`, `cat_restaurantes.png`, `cat_supermercados.png`.
- **O mini-site do Mr Kebab continua sem vídeo e sem o botão do site.** É o único dos cinco
  fora do padrão da regra 1.11.
- **O ecrã do estafeta não abre sem posição de GPS.** Descoberto a 29/08 ao provar pela web:
  `_buildIdleMapScaffold` devolve um carregador enquanto `_initialGpsCenter` for nulo, e não
  há limite de tempo nem caminho alternativo. Quem recusar o consentimento de localização, ou
  estiver num sítio sem GPS, fica com um ecrã em branco a rodar **para sempre**, sem uma
  palavra a dizer porquê. Não é defeito da web: é o mesmo código no telemóvel.
- **A barra do trabalho em curso só se actualiza no arranque, ao voltar à app, e ao fechar o
  ecrã do trabalho que ela própria abriu.** Quem aceita um trabalho e depois sai daquele ecrã
  pelo seu próprio caminho não vê a barra até a app ir a segundo plano e voltar. Visto na
  prova de 29/08.
- **A prova no aparelho continua em dívida**, mas agora reduzida ao que é mesmo do aparelho:
  o som a tocar, o aviso com o ecrã bloqueado, e a app fechada. Todo o resto passou a
  provar-se pela web (regra 3.10).

---

## 8. MODELO DE PROMPT CURTO

Isto é tudo o que o Danilo precisa de escrever para uma categoria nova. **Tudo o resto vem
deste documento.**

```
Categoria nova: <nome>.
Serviços e preços: <serviço> <preço>, <serviço> <preço>.
Quem presta: <papel novo, ou "parceiro">.
Segue o PADRAO_BORA.md — lista fechada inteira.
```

Exemplo real, se hoje fosse a Lavagem Auto:

```
Categoria nova: Lavagem Auto.
Serviços e preços: lavagem exterior 12 euros, lavagem completa 20 euros,
só interior 12 euros e nasce desligado.
Quem presta: lavador.
Segue o PADRAO_BORA.md — lista fechada inteira.
```

**O que o agente tem de fazer sem que lhe digam:** os três pagamentos, a morada automática,
o ladrilho no padrão, o papel no `user_roles`, o registo do aparelho, o toque persistente, a
entrada de candidatura, o interruptor a partir dos papéis reais, a entrada no acerto único, o
painel admin completo, e o mini-site com vídeo e os dois botões quando houver parceiro.

E, no fim, o relatório da secção 5: acessos no topo, o que não foi feito logo a seguir, e
prova de tudo o resto.

---

*Escrito a partir dos relatórios de Agosto de 2026 em `.claude/.ai/reports/` e dos commits do
mês. Última consolidação: 2026-08-28.*
