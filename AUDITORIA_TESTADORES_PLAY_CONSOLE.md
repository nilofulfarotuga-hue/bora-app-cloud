# Auditoria — Testadores do Teste Fechado (Play Console)

**Data:** 2026-07-07 (auditoria) · **Atualizado:** 2026-07-07 (consolidação executada)
**App:** `pt.boraapp.bora` — Bora App Guarda (developer `5372142912736686834`)
**Conta Play Console:** `boraappbora@gmail.com`

---

## ✅✅ ATUALIZAÇÃO 2 — Mecanismo confirmado + verificação dos 4 emails (3ª sessão, mesmo dia)

### A. Os teus 4 emails — todos já estão no grupo (nenhum precisou de ser adicionado)

Comparei carácter a carácter com a lista real do `bora-app-testers@googlegroups.com` (membros +
convites pendentes):

| Email | Está no grupo? | Estado | Ação tomada |
|---|---|---|---|
| `boraappbora@gmail.com` | ✅ Sim | **Membro confirmado** (desde a criação do grupo) | nenhuma — já lá estava |
| `nilofulfarotuga@gmail.com` | ✅ Sim | **Membro confirmado** (é a conta dona/proprietária) | **testado ao vivo agora — ver secção B, já é "You are a tester"** |
| `fulfarodanilo@gmail.com` | ✅ Sim | Convite pendente (enviado na sessão anterior, ainda não aceitou) | nenhuma — já convidado |
| `nilofulfaro@gmail.com` | ✅ Sim | Convite pendente (enviado na sessão anterior, ainda não aceitou) | nenhuma — já convidado |

**Conclusão:** não faltava adicionar nenhum dos 4. Os 2 que já eram membros diretos (`boraappbora`,
`nilofulfarotuga`) e os 2 que foram convidados na sessão anterior (`fulfarodanilo`, `nilofulfaro`)
estão todos representados no grupo. `nilofulfaro@gmail.com` e `dani01fulfaro@gmail.com` **não são a
mesma conta** — comparei os textos, são endereços diferentes (`nilofulfaro` vs. `dani01fulfaro`), os
dois estão na lista separadamente.

### B. Confirmação dos nomes "Daniela" e "Valdemir Vasconcelos"

- **Valdemir Vasconcelos** → é quase de certeza `valdemirvasconcelos28@gmail.com` (o email já bate
  literalmente com o nome). Está na lista como **convite pendente**, enviado na sessão anterior.
- **Daniela** → é muito provavelmente `dani01fulfaro@gmail.com` (o email de família que adicionámos
  na sessão anterior, na altura mal identificado como "Diogo"). O Google resolveu uma foto de perfil
  real para esta conta ao adicioná-la, o que confirma que é uma conta genuína de alguém — mas como
  ainda não aceitou o convite, o Google não me mostra o nome completo, só o email. Também está como
  **convite pendente**.

### C. Mecanismo definitivo — confirmado na documentação oficial da Google E testado ao vivo

Fui à documentação oficial (`support.google.com/googleplay/android-developer/answer/9845334`) e
testei na prática com a conta `nilofulfarotuga@gmail.com` (que já era membro do grupo há 24h, mas
**ainda não era testador**). Resultado inequívoco:

> **Entrar no Google Group NÃO é suficiente sozinho.** A documentação da Google diz literalmente:
> *"If you're running a closed test with a Google Group, users need to join the group before opting
> into your test."* — ou seja, entrar no grupo é só o PRIMEIRO passo. Depois é preciso abrir o link de
> adesão e clicar em "Become a tester" / "Tornar-se testador".

**Prova ao vivo:** abri `https://play.google.com/apps/testing/pt.boraapp.bora` com a conta
`nilofulfarotuga@gmail.com` (membro do grupo há 24h) — a página mostrou o botão **"Become a tester"**
por clicar, confirmando que só estar no grupo não bastava. Cliquei no botão e a página passou a
mostrar **"You are a tester."** — confirmado, é este o link real e funcional
(`https://play.google.com/apps/testing/pt.boraapp.bora`), e `nilofulfarotuga@gmail.com` **já é agora
um testador de verdade, ao vivo, confirmado por mim nesta sessão.**

### A receita certa, passo a passo, para cada pessoa da família

1. Abrir o email de convite do grupo "Bora App Testers" (chega de `groups.google.com` /
   `Google Groups`) e clicar em **"Aceitar convite" / "Join group"**.
2. Com a MESMA conta Google, abrir este link no telemóvel ou computador:
   **`https://play.google.com/apps/testing/pt.boraapp.bora`**
3. Clicar no botão azul **"Tornar-se testador" / "Become a tester"**.
4. Vai aparecer a confirmação **"Já é testador" / "You are a tester."**
5. Instalar (ou atualizar, se já tiver) a app pela Google Play Store normalmente — pode demorar
   alguns minutos a aparecer a versão de teste.
6. Abrir a app e usar durante alguns minutos — mantém o opt-in "ativo" de forma genuína (reforça
   contra o risco do serviço pago descrito na secção 4).

**Sem o passo 3 (clicar no botão), a pessoa fica só "convidada" — não conta para os 12 do Google, por
mais que esteja no grupo.**

### D. Texto pronto para copiar e enviar à família

```
Olá! 👋 Estou a testar uma nova app que criei, o Bora App, e preciso da tua ajuda como testador
oficial no Google Play (é rápido, 2 minutos):

1. Aceita o convite que chegou no teu Gmail do grupo "Bora App Testers" (clica em "Aceitar" ou
   "Join group")
2. Depois abre este link com a MESMA conta Google:
   https://play.google.com/apps/testing/pt.boraapp.bora
3. Clica no botão azul "Tornar-se testador" / "Become a tester"
4. Quando aparecer "Já é testador", instala a app normalmente pela Google Play Store
5. Abre a app e usa uns minutinhos — só isso já ajuda imenso!

Qualquer dúvida ou se algo não aparecer, diz-me. Obrigado! 🙏
```

### E. Play Console — ainda não re-verificado ao vivo nesta sessão

Tal como na sessão anterior, não consegui confirmar ao vivo o checklist do Play Console porque o
Chrome não tinha o `boraappbora@gmail.com` disponível como conta secundária (`u/1` caiu no fluxo de
criar conta nova para `nilofulfarotuga`). Não mudei nada na configuração da faixa — só geri o Google
Group e fiz um opt-in real de teste. O estado da auditoria original (12 testadores ✅, relógio de 14
dias a contar desde 2026-07-07) deve continuar válido.

### ⚠️ Nota de segurança sobre esta sessão

A meio do trabalho, ao tentar trocar de conta no seletor do Google dentro do Chrome, cliquei sem
querer num link que **terminou sessão das duas contas Google no Chrome** (não apagou nada — passwords,
histórico e marcadores ficaram guardados no dispositivo, só a sincronização ficou em pausa). Pedi ao
Danilo para iniciar sessão de novo manualmente (eu não insiro passwords) e ele resolveu. Para o
futuro: trocar de conta pelo cantinho do avatar dentro de uma página normal (não pela ligação
"Contas Google" que aparece nalguns menus) evita este problema.

---

## ✅ ATUALIZAÇÃO — Consolidação executada (2ª sessão, mesmo dia)

Correção: o email da família não era "Diogo" — é **`dani01fulfaro@gmail.com`**.

Com o Chrome já logado como `nilofulfarotuga@gmail.com` (dona do grupo), adicionei ao grupo único
**`bora-app-testers@googlegroups.com`** os 5 emails da lista solta "testadores bora" que ainda não
eram membros + o `dani01fulfaro@gmail.com`. Um CAPTCHA do Google bloqueou o envio automático — o
Danilo resolveu-o manualmente e os **6 convites foram enviados com sucesso** (confirmado em
"Pending members": 6 pendentes, todos com estado "Pending", enviados há 1 minuto):

- `eulineyafonsofernandes@gmail.com`
- `fulfarodanilo@gmail.com`
- `leticia.cosmo0397@gmail.com`
- `nilofulfaro@gmail.com`
- `valdemirvasconcelos28@gmail.com`
- **`dani01fulfaro@gmail.com`** ← o novo, pedido nesta sessão

**Estado agora:** 2 membros confirmados (Danilo + boraappbora) + 6 convites pendentes (aguardam a
pessoa aceitar). Ninguém foi adicionado diretamente — todos precisam de aceitar o convite por email
para contarem como opt-in real perante o Google. Ver números finais na secção 3-A.

`khadem-testers-service@googlegroups.com` continua sem acesso mesmo com a conta dona do
`bora-app-testers` logada — confirma que é um grupo 100% externo (do PrimeTestLab), não transferível,
não administrável pelo Danilo. Não há "aceitar transferência de posse" possível aqui — simplesmente
não é um grupo do Danilo.

**Play Console não foi re-verificado nesta sessão:** o browser estava logado só como
`nilofulfarotuga@gmail.com`, que não tem acesso ao Play Console (cai no fluxo de "criar conta de
developer nova" — não mexi nisso). Como nenhuma definição do Play Console foi alterada (só mexi em
Google Groups), o estado confirmado na auditoria original — checklist de 12 testadores ✅, relógio de
14 dias a contar desde 2026-07-07 — deve continuar válido. Para confirmar ao vivo, preciso que o
Chrome volte a logar como `boraappbora@gmail.com`.

---

## 🚨 O mais importante (auditoria original)

1. **O requisito de "12 testadores" JÁ ESTÁ CUMPRIDO** no checklist oficial do Play Console (✅ verde,
   riscado). O que falta é só **correr 14 dias seguidos** com esses 12+ testadores — esse relógio
   **começou hoje, 2026-07-07**.
2. **Mas quase nenhum desses testadores é "de verdade" (família/amigos).** O teu grupo pessoal
   `bora-app-testers@googlegroups.com` só tinha **2 membros** antes desta consolidação (tu próprio, em
   duas contas). O resto dos 12+ vem de um serviço pago externo
   (`khadem-testers-service@googlegroups.com`, ligado ao "PrimeTestLab" que compraste). Ver risco
   grave na secção 4.
3. ~~Não encontrei nenhum rasto do convite ao "Diogo"~~ — **era engano de nome; o email certo era
   `dani01fulfaro@gmail.com`, já convidado (ver atualização acima).**

---

## 1. Email ao Diogo — investigação

Procurei no Gmail `boraappbora@gmail.com` (é a conta que está autenticada nesta sessão, e é também a
conta dona do Play Console) por: `diogo`, variações de `dani`, `convite`, `testar`, `teste fechado`,
`opt-in`, tudo em `in:sent` e em qualquer pasta.

**Resultado: zero.** Os únicos emails enviados por esta conta relacionados com testes foram, em
maio/2026, **4 emails para `nilofulfaro@gmail.com`** (a tua própria conta alternativa) com um link de
**Teste Interno** (`play.google.com/apps/internaltest/...`) — não é o Teste Fechado (alpha), e não é
o Diogo.

**Conclusão:** o convite ao Diogo, se foi mesmo enviado, não saiu desta conta de email. Prováveis
explicações:
- Foi enviado pela tua conta pessoal `nilofulfarotuga@gmail.com` (não tenho acesso a essa caixa a
  partir desta sessão — a ferramenta de Gmail ligada aqui só vê `boraappbora@gmail.com`).
- Foi mandado por WhatsApp/SMS, não por email.
- Ainda não foi mandado de facto.

**Ação sugerida:** confirma tu próprio no Gmail pessoal ou WhatsApp qual é o email exato do Diogo — eu
não consegui descobri-lo em lado nenhum dos sítios a que tenho acesso.

---

## 2. O que está configurado no Play Console (Testes fechados → Alpha)

Faixa ativa: **"Testes fechados - Alpha"**, build 370 (1.0.1), lançada 6/07 18:31, 177 países/regiões.

Na aba **Testadores**, o método ativo e guardado é **"Grupos Google"** (não é "Listas de correio").
Estão configurados **dois grupos Google em simultâneo** — e isto confirma exatamente a tua suspeita de
que há mais do que uma lista espalhada:

| Grupo | Membros reais | Dono | O que é |
|---|---|---|---|
| `bora-app-testers@googlegroups.com` | **2** — `nilofulfaro...@gmail.com` (proprietário) e `boraappbora` (membro), ambos entraram há ~22h | `nilofulfarotuga` (pessoal) | O teu grupo "oficial" — mas com só as tuas próprias contas lá dentro |
| `khadem-testers-service@googlegroups.com` | **desconhecido — sem acesso** ("Não tem autorização para aceder a este conteúdo") | Externo (PrimeTestLab) | Grupo do serviço pago, controlado por eles, não por ti |

Existe ainda uma **lista de correio (mailing list) chamada "testadores bora" com 6 emails**, mas ela
**não está a ser usada agora** — o método ativo é "Grupos Google", não "Listas de correio". Ou seja,
estas 6 pessoas **não têm acesso real ao teste neste momento**, a não ser que também estejam nos
grupos Google ativos (e não estão, confirmei a lista do `bora-app-testers`):

- `eulineyafonsofernandes@gmail.com`
- `fulfarodanilo@gmail.com`
- `leticia.cosmo0397@gmail.com`
- `nilofulfaro@gmail.com`
- `nilofulfarotuga@gmail.com`
- `valdemirvasconcelos28@gmail.com`

**Nenhum destes é obviamente o "Diogo".**

Não fiz nenhuma alteração — abri a opção "Listas de correio" só para inspecionar e recarreguei a
página sem guardar, para não trocar o método ativo por engano.

---

## 3. Números reais vs. convidados

- **"Público-alvo com a app instalada" no Play Console: 2** — bate certo com os 2 membros reais do
  teu grupo `bora-app-testers`.
- **Checklist oficial do Play Console** (Painel de controlo → Candidatar-se à produção):
  - ✅ Publicar um lançamento de teste fechado — feito
  - ✅ **Ter pelo menos 12 testadores a participar** — feito (contagem confirmada pelo próprio Google)
  - ⭕ Correr o teste fechado com pelo menos 12 testadores durante pelo menos 14 dias — **em curso**,
    começou hoje

Como o teu grupo pessoal só tem 2 pessoas, os outros 10+ que fazem o "12" bater certo **vêm quase de
certeza do grupo pago `khadem-testers-service`**, não de família/amigos.

---

## 3-A. Números finais depois da consolidação

- **Membros confirmados no `bora-app-testers`:** 2 (Danilo + boraappbora) — inalterado, ninguém
  aceitou convite ainda.
- **Convites pendentes:** 6 (os 5 da lista antiga + `dani01fulfaro@gmail.com`), todos enviados agora,
  estado "Pending".
- **`dani01fulfaro@gmail.com`:** convite enviado, **ainda não aceitou**. Só conta como opt-in real
  para o Google depois de ele/ela aceitar o convite E visitar o link de opt-in do teste fechado no
  telemóvel/Play Store.
- **Faltam confirmar para reforçar os 12 "de verdade":** todos os 6 — nenhum é opt-in confirmado
  ainda, todos dependem de cada pessoa aceitar.
- **A contagem de 14 dias não foi interrompida por esta ação** — só enviei convites a um grupo que já
  estava ligado ao Play Console; não mexi na configuração da faixa nem removi ninguém do
  `khadem-testers-service` (que continua a segurar os 12+ confirmados atuais).

---

## 4. ⚠️ Risco sério — o serviço "PrimeTestLab" que compraste

Encontrei os emails da compra (2026-07-06/07) e quero alertar-te antes de continuares a confiar nisto:

- Encomenda **#P08075612**, pacote "Enterprise - 25 Testers", **US$21.49** (o recibo Stripe real mostra
  **US$21.48** cobrados pela empresa **"AEBU Technology, LLC"** — nome diferente da marca
  "PrimeTestLab" que aparece nos emails, o que é normal em serviços "white-label" mas vale a pena
  saberes com quem realmente estás a lidar).
- O email de confirmação **enviou-te uma password em texto simples** (`FGZ5yLqXKZblL9S6`) para uma
  conta "criada automaticamente" em nome do teu email. Nunca reutilizes essa password em mais lado
  nenhum — é um sinal de serviço com práticas de segurança fracas.
- O email de "Testing Started" inclui um "screenshot do telemóvel do testador" — é uma imagem
  genérica/template, não uma prova verificável.
- O rodapé do email da fatura diz "© 2025 PrimeTestLab" apesar de a data ser julho de 2026 —
  inconsistência típica de template reciclado.
- **O ponto mais sério:** pagar por "testadores reais" só para bater a fasquia dos 12 opt-ins do Google
  é exatamente o tipo de "engagement fabricado/incentivado" que a política de programador do Google
  Play proíbe. Se o Google detetar isto (e eles têm deteção de fraude para testes fechados), o risco
  não é só reprovar a candidatura à produção — é a **conta de programador inteira ser suspensa/
  terminada**, o que travaria o lançamento definitivo, não só o teste. Já gastaste o dinheiro, não há
  como desfazer isso, mas **recomendo fortemente não repetires esta compra** e construíres a base de
  12 testadores com pessoas reais (família/amigos) como plano seguro em paralelo.

---

## 5. Próximos passos claros

1. **Pede a cada uma das 6 pessoas convidadas para aceitar o convite** do grupo "Bora App Testers"
   que chegou por email (`eulineyafonsofernandes`, `fulfarodanilo`, `leticia.cosmo0397`,
   `nilofulfaro`, `valdemirvasconcelos28`, **`dani01fulfaro`**) — sem aceitar, não contam como
   testador de verdade.
2. **Depois de aceitarem o convite do grupo**, cada um ainda precisa visitar o link de opt-in do
   teste fechado (Play Console → Testadores → "Adesão no Android"/"Adesão na Web") e instalar a app
   pelo link — só aí é que o Google conta como opt-in ativo.
3. **Não precisas de fazer mais nada no Play Console para bater os 12** — isso já está cumprido
   (mesmo que grande parte venha do serviço pago). O que falta é só esperar os **14 dias corridos**
   (a contar de hoje, 2026-07-07 → previsão de conclusão ~2026-07-21).
4. Ter estas 6 pessoas reais como opt-in confirmado é a tua rede de segurança caso o Google
   reveja/rejeite o grupo pago `khadem-testers-service` a meio do percurso.
5. Se quiseres que eu confirme ao vivo no Play Console que nada mudou (checklist dos 12, dias
   corridos), preciso que o Chrome volte a logar como `boraappbora@gmail.com`.

---

## 6. O que foi feito nesta sessão vs. o que ainda depende de ti

**Feito:**
- Adicionei os 5 emails da lista solta "testadores bora" + `dani01fulfaro@gmail.com` como convites ao
  grupo `bora-app-testers@googlegroups.com` (a partir da conta dona `nilofulfarotuga@gmail.com`).
  Convites enviados e confirmados em "Pending members" (6/6).
- Confirmei que `khadem-testers-service@googlegroups.com` é mesmo externo — sem acesso nem com a
  conta dona do outro grupo logada. Não há nada a "reclamar" aí, é do PrimeTestLab.
- Não mexi na configuração de "Grupos Google" vs "Listas de correio" no Play Console nem em nenhum
  outro ajuste da faixa — fiquei só na gestão do Google Group.
- Não contactei o PrimeTestLab nem comprei mais nada.

**Ainda depende de ti/deles:**
- As 6 pessoas aceitarem o convite do grupo (chega por email a cada uma).
- Cada uma delas visitar o link de opt-in e instalar a app — só isso conta como opt-in real para o
  Google.
- Se quiseres validação ao vivo do lado do Play Console, logar o Chrome de volta em
  `boraappbora@gmail.com`.
