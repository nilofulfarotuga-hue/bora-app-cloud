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

Uma categoria só está **lançada** quando os onze pontos abaixo estão feitos. Se faltar um,
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

---

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

---

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

**Fotografia tirada a 2026-08-28.** Isto é levantamento, não é correcção. É daqui que sai o
trabalho das próximas missões. Cada categoria é passada pelos onze pontos da secção 1.

### 7.1 LIMPEZA

Aberta (`cleaning_enabled = true`, `cleaning_stripe_enabled = true`). Papel `cleaner` aceite
no `user_roles`, com 2 pessoas. É a categoria mais antiga das quatro e a que tinha o buraco
mais grave.

**Falta:**

1. **Pagamentos:** o fluxo tem cartão e MB Way; **o dinheiro não aparece no ecrã de escolha**
   (o servidor trata `cash` como pago no local, mas o cliente não o pode escolher). Falta
   decidir se a Limpeza aceita dinheiro e, se aceitar, mostrá-lo. Nenhum dos três tem teste
   real registado.
2. **Morada:** o assistente (`cleaning_wizard_screen.dart`) só copia a morada do carrinho —
   **não usa o `AutoAddress`**. Quem entre na Limpeza sem passar pela home fica com o campo
   vazio.
3. **Ladrilho:** correcto (512×512, sem alfa).
4. **Papel em `user_roles`:** feito.
5. **Token do aparelho:** a canalização está feita e há **uma linha registada** desde
   28/08 às 12:06. **Falta a prova no telemóvel** — o toque a chegar mesmo.
6. **Toque persistente:** `cleaning_offer` e `cleaning_status` estão no conjunto. Feito.
7. **Entrada de candidatura:** **falta**. O `CleanerApplyScreen` só é alcançável de dentro do
   `CleanerHomeScreen` — ou seja, de quem já lá está.
8. **Interruptor do prestador:** feito (lê de `user_roles` desde 28/08).
9. **Acerto semanal:** a vista que junta as três está feita e é **só de leitura**. Faltam o
   ecrã do prestador, o painel com o botão de pagar, a exportação para a contabilidade e o
   abate da dívida. Essa parte **espera "vai"** porque mexe em dinheiro que sai para pessoas.
10. **Admin:** existe (`admin_cleaning_bookings_screen`, `admin_cleaning_cleaners_screen`).
    Falta o **painel admin dos papéis** — ver e mudar os papéis de qualquer pessoa.
11. **Mini-site:** não se aplica (não é parceiro de loja).

### 7.2 LAVAGEM AUTO

Aberta (`carwash_enabled = true`, `carwash_stripe_enabled = true`), build 551 e seguintes
publicados. Motor clonado do da Limpeza, 33 verificações provadas a 27/08.

**Falta:**

1. **Pagamentos:** dinheiro provado. **Cartão:** o caminho está provado até ao PaymentIntent,
   mas o PaymentSheet exige introduzir dados de cartão — **é acto do Danilo**. **MB Way:**
   foi recusado pelo provedor ("declined by the provider"); a suspeita é o número 937501673
   não ter MB Way associado. **Confirmar o número.**
2. **Morada:** feito, usa o `AutoAddress`.
3. **Ladrilho:** feito a 28/08 (512×512, sem alfa, nome em duas linhas).
4. **Papel em `user_roles`:** feito — o `CHECK` já aceita `washer`, com 2 pessoas.
5. **Token do aparelho:** canalização feita, **uma linha registada** a 28/08. Falta a prova
   no telemóvel.
6. **Toque persistente:** feito a 28/08 (`carwash_offer`, `carwash_status`).
7. **Entrada de candidatura:** **não existe de todo.** Não há `washer_apply_screen`. Um
   lavador novo não tem por onde se inscrever.
8. **Interruptor do prestador:** feito.
9. **Acerto semanal:** igual à Limpeza — vista de leitura feita, o resto espera "vai".
10. **Admin:** existe e é o mais completo dos quatro (`admin_carwash_screen`, com
    reatribuição desde o nascimento). Falta o painel dos papéis.
11. **Mini-site:** não se aplica.
12. **Tokens (fidelização):** a migration `20260827102000_PROPOSTA_carwash_tokens.sql` está
    pronta e **não aplicada** — a Trava bloqueia. É acto do Danilo.
13. **Só interior:** `carwash_interior_enabled = false`, desligado de propósito.

### 7.3 FESTAS

Aberta em código desde 25/08. A loja da Keli (`sabores-brasil-guarda`) estava
`coming_soon = true` à espera de a app chegar à Play Store — **confirmar o estado actual**.
O desenho não abriu caminho novo de dinheiro nem de dispatch: um pedido de festa é um pedido
de restaurante parceiro normal com `scheduled_for`.

**Falta:**

1. **Pagamentos:** **só o dinheiro foi testado a sério.** Cartão e MB Way passam pelos
   caminhos do delivery, que funcionam — mas não há teste real de festa com cartão nem com
   MB Way registado.
2. **Morada:** herdada do carrinho e da home, que já preenchem sozinhas. Feito.
3. **Ladrilho:** **fora do padrão.** O `cat_festas.png` é **1024×1024 com canal alfa**
   (5.641 píxeis não-opacos, alfa mínimo 60); todos os irmãos são 512×512 em paleta, sem
   alfa. Foi composto à mão porque o gerador estava sem quota. **Regenerar em 512×512 com
   fundo cheio quando a quota voltar.**
4. **Papel em `user_roles`:** não se aplica — a parceira é `partner`, que já existia.
5. **Token do aparelho:** usa o caminho do parceiro, que já funcionava.
6. **Toque persistente:** usa os tipos do parceiro, já cobertos.
7. **Entrada de candidatura:** não se aplica (parceiro entra por convite).
8. **Interruptor do prestador:** não se aplica.
9. **Acerto semanal:** entra no fecho semanal de parceiro, que já existia.
10. **Admin:** `scheduled_for` e `prep_time_minutes` visíveis e editáveis no detalhe do
    pedido, com auditoria. Feito.
11. **Mini-site:** o `sabores-do-brasil` tem vídeo e os dois botões. Feito.
12. **Dinheiro por absorver:** `20260825091000_festas_money_patch.sql` **não aplicada** — a
    versão canónica do "sem saco" dentro do `create_order`/`quote_order_pricing`. O efeito
    está entregue por um trigger aditivo. Enquanto não for absorvida, ficam dois restos
    conhecidos: o tecto do dinheiro conta o saco que não vai ser cobrado (só afecta pedidos
    entre 39,70 € e 40,00 €), e o orçamento do carrinho devolve 0,30 € de saco que a
    cobrança real não usa.
13. **Acessibilidade:** na demo, os botões, os dias do calendário e os chips de hora não
    expõem rótulos. Não bloqueia nada, mas vale uma passagem.

### 7.4 RESERVA DE MESA

Sistema antigo e completo (Reservas Pro). Sinal de 3,00 € (`reservation_prepayment_cents`),
2,00 € para o parceiro e 1,00 € para a Bora.

**Falta:**

1. **Pagamentos:** **não tem dinheiro, e é de propósito** — um sinal pré-pago não pode ser
   em dinheiro. Fica **cartão e MB Way**, e é a excepção justificada à regra 1.1. Escrito
   aqui para não voltar a ser levantado como defeito.
2. **Morada:** não se aplica — a mesa é no restaurante.
3. **Ladrilho:** `cat_reservar_mesa.png` correcto (512×512, sem alfa).
4 a 9. **Papel, token, toque, candidatura, interruptor, acerto:** não se aplicam — quem
   recebe é o parceiro, por caminhos que já existiam.
   **Excepção a verificar:** os tipos de push das reservas de mesa **não estão** em
   `_kPersistentCategoryTypes` (lá estão os das marcações — `appointment_new`,
   `appointment_cancelled`, `appointment_rescheduled`). Confirmar que tipo o servidor emite
   para as reservas de mesa e, se for um tipo próprio, acrescentá-lo.
10. **Admin:** completo — `admin_reservations_screen`, `_config`, `_metrics`.
11. **Mini-site:** nenhuma loja tem reservas ligadas na base
    (`reservations_enabled = false` em todas, Goola incluída). A categoria está construída e
    **sem nenhum parceiro a usá-la** — é decisão comercial, não é defeito técnico.

### 7.5 Achados transversais deste levantamento

- **Quatro ladrilhos são ficheiros WebP com extensão `.png`:** `cat_encomenda.png`,
  `cat_farmacia.png`, `cat_restaurantes.png`, `cat_supermercados.png`. O Flutter aguenta
  (identifica pelo conteúdo), por isso não parte nada — mas qualquer ferramenta que confie
  na extensão vai enganar-se. Vale renomear ou reconverter um dia.
- **O mini-site do Mr Kebab não tem vídeo e não tem o botão do site** — só o da Play Store.
  É o único dos cinco fora do padrão da regra 1.11.
- **O painel admin dos papéis não existe** para nenhuma categoria.
- **A prova no telemóvel está em dívida desde 27/08** e é a mesma para a Limpeza e para a
  Lavagem: falta o Danilo actualizar a app pela Play Store e entrar uma vez como faxineiro.

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
