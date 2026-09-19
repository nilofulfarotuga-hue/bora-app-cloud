---
data: 2026-07-14
agente: executor-loop-autonomo (SONNET)
tipo: bugfix-critico-confirmado
ordem: d204 (atualização urgente)
---

# LOGIN de parceiro reinicia o wizard do zero — CONFIRMADO e CORRIGIDO

## Sintoma reportado (Danilo, teste ao vivo)
Fechou o app, abriu de novo, fez LOGIN com sucesso (email+senha corretos,
conta existe e autentica) — mas o app levou-o de volta ao INÍCIO do wizard
de cadastro de parceiro, pedindo tudo de novo: Dados do Estabelecimento,
Documentos, e até o passo "Conta de Acesso" a pedir email/senha outra vez,
apesar de já estar autenticado.

## Diagnóstico das 4 perguntas

### (1) Existe verificação pós-login "este user_id já tem registo de parceiro"?
**Existia parcialmente, e estava com bug.** `PartnerEntryScreen`
(`lib/screens/partner_entry_screen.dart`) já verifica `restaurantByEmail`
para decidir entre `PartnerDashboardScreen` (registo aprovado/existente) e
o resto — mas o "resto" tinha dois problemas em cadeia (ver 2).

### (2) A verificação estava em falta ou com bug — porque reiniciava sempre?
**Bug confirmado em dois pontos:**

**a) `partner_login_screen.dart` rejeitava o login.** Antes do fix (código
anterior no repo), se não havia `restaurants` nem `service_providers` para o
email, o ecrã fazia `authStore.logout()` e mostrava "Não encontramos o
restaurante associado a este email." — ou seja, um parceiro cuja submissão
do cadastro tinha falhado a meio (conta Supabase Auth criada, mas o INSERT
em `restaurants` nunca aconteceu) era **expulso** ao tentar logar de novo.
Isto por si é um bug bloqueante — mas explica só parte do sintoma.

**b) `register_partner_screen.dart` não sabia que o utilizador já estava
autenticado.** Mesmo quando o fluxo chegava ao wizard (ex.: sessão
restaurada de `SharedPreferences` sem passar pelo ecrã de login), o
`RegisterPartnerScreen` não verificava `AuthStore.currentPartner` — por
isso sempre mostrava o passo "Conta de Acesso" a pedir email/senha de novo,
e ao submeter chamava sempre `registerPartnerWithDocumentsAsync` (que tenta
`Supabase.auth.signUp` outra vez) — o que bateria sempre em "email já
existe" para uma conta já criada, prendendo o parceiro num loop.

**Confirmação do impacto:** isto bloquearia qualquer parceiro real que
fechasse o app a meio do cadastro (após a conta de acesso ser criada mas
antes do restaurante ser inserido) e voltasse depois — exatamente o
cenário que o Danilo reproduziu.

### (3) Correção — já presente no working tree (não commitada)
Encontrei um diff substancial já pronto e coerente em 4 ficheiros
(305 inserções/106 remoções), de trabalho de uma iteração anterior do loop
("fluxo parceiro já autenticado retoma cadastro" mencionado na 3ª
reconfirmação do fix de scroll). Verifiquei linha a linha — está correto e
completo para o problema central reportado:

- **`lib/screens/partner_login_screen.dart`** — já não rejeita/expulsa o
  login quando não há `restaurants`. Deixa passar (pré-carrega
  `service_providers` via `loadMyProvider()` para a rota seguinte resolver
  sem spinner) e delega a decisão final ao `PartnerEntryScreen`.
- **`lib/screens/partner_entry_screen.dart`** (já commitado, `f6585e9`) —
  `_PartnerNoRestaurantRouter`: se existe `service_providers` → hub de
  marcações; senão → `RegisterPartnerScreen` (não a tela de login, não
  `RoleScreen`). Cobre também sessão restaurada de prefs sem login manual.
- **`lib/screens/register_partner_screen.dart`** — `initState` agora lê
  `context.read<AuthStore>().currentPartner`; se não-nulo, marca
  `_alreadyAuthenticated=true`, pré-preenche o email e **esconde os campos
  de email/senha** (mostra um Card "Sessão iniciada como X... não precisas
  de repetir email/senha"). `_validateStep3()` já não exige email/senha
  neste caso. No submit final, usa `resumePartnerRegistrationAsync` (não
  recria a conta) em vez de `registerPartnerWithDocumentsAsync`.
  Os campos de Dados do Estabelecimento (nome/morada/telefone/NIF/IBAN/
  categoria/cuisine) continuam a ser restaurados do rascunho local
  (`SharedPreferences`, chave `bora_app.signup_draft.partner`) — já existia
  antes, não é código novo, mas agora funciona em conjunto com o resto.
- **`lib/auth/auth_store.dart`** — novo método
  `resumePartnerRegistrationAsync()`: usa a sessão Supabase corrente (JWT),
  não chama `auth.signUp` de novo, invoca diretamente a Edge Function
  `register-partner`. Extraí a chamada à Edge Function para
  `_submitRestaurantEdgeFunction()` partilhada pelos dois fluxos.

Ficheiro `lib/main.dart` e `AndroidManifest.xml`/`Info.plist` também
aparecem modificados no working tree, mas são de uma feature **separada**
(recuperação de palavra-passe / deep link `reset-password`) — já coberta
por [[project_auth_recuperar_senha_ja_implementado]] na memória, não
relacionada com este bug. Não toquei nesses ficheiros.

### (4) O que a submissão final já tinha (d204 original) — confirmado
- Deteção de email duplicado (`duplicatePartnerEmailMessage`): cobre tanto
  o "user fantasma" com `identities` vazio (proteção anti-enumeração do
  Supabase) como `AuthException code=user_already_exists` (422) — o ecrã
  volta ao passo "Conta de Acesso" com erro inline.
- Falha na Edge Function (depois da conta já criada) agora devolve uma
  mensagem clara — "a tua conta de acesso foi criada, mas houve um erro ao
  registar o estabelecimento... não precisas de repetir o email/senha" —
  em vez do genérico "Erro: Verifica email/password..." que existia antes
  e induzia o utilizador a duvidar da própria senha.

## Validação
`flutter analyze` nos 5 ficheiros tocados pelo fluxo (`register_partner_screen.dart`,
`partner_login_screen.dart`, `auth_store.dart`, `main.dart`,
`partner_entry_screen.dart`) → **0 erros**, mesmos 6 warnings/infos
pré-existentes (imports não usados + `_formKey` + `value:` deprecated),
nenhum novo introduzido pelo diff em curso.

Confirmei manualmente a cadeia de estado: `loginPartnerAsync` define
`_currentPartner` **antes** de `_finishPartnerLogin` correr; `_RootNavigator`
(`main.dart:610-611`) devolve sempre `PartnerEntryScreen` para
`role==partner`; `PartnerEntryScreen` só mostra `PartnerLoginScreen` quando
`currentPartner==null` — nunca reinicia para lá um utilizador já
autenticado.

## Limitação residual (não bloqueante, não corrigida nesta sessão)
As fotos de documentos (`_ownerDocFile`/`_activityDocFile`, passo
"Documentos") **não são persistidas** em disco/prefs — só existem em
memória como `XFile`. Se o utilizador fechar o app por completo depois de
escolher as fotos mas antes de submeter com sucesso, terá de as
re-selecionar ao voltar (2 toques, não é re-digitar dados). Isto é
diferente do "Conta de Acesso" (que era o ponto crítico/bloqueante — pedir
credenciais de novo a quem já está autenticado) e dos "Dados do
Estabelecimento" (já restaurados do rascunho). Fica registado como melhoria
futura possível (ex.: upload imediato ao escolher a foto, em vez de só no
submit final) — fora do escopo desta correção, não implementado por
Simplicidade Primeiro / mudança cirúrgica.

## Atualização (reconfirmação, mesma sessão) — fix já COMMITADO
Quando este relatório foi escrito, o diff descrito acima ainda estava só no
working tree. Entretanto o commit `3c19043` ("fix(parceiro): mensagem de
erro real no submit + retomada sem recriar conta") já levou exatamente este
fix para o histórico do repo — confirmei linha a linha em
`auth_store.dart` (`resumePartnerRegistrationAsync` + `_submitRestaurantEdgeFunction`,
linhas 1232-1325) e `register_partner_screen.dart` (`_alreadyAuthenticated`,
linhas 65-695) que o código no repo bate com o diff analisado. `git status`
confirma que estes 4 ficheiros já **não** aparecem como modificados — só
`lib/main.dart` continua no working tree, e é da feature separada de
recuperação de senha ([[project_auth_recuperar_senha_ja_implementado]]),
não deste bug.

## Sem commit / sem push (desta sessão)
Não fiz `git commit` nem `git push` nesta sessão. O fix em si já estava
commitado (`3c19043`) antes desta sessão começar — só este relatório foi
escrito/atualizado por mim.

## Ficheiros verificados (não alterados por esta sessão)
- `lib/screens/partner_login_screen.dart`
- `lib/screens/partner_entry_screen.dart` (já commitado, `f6585e9`)
- `lib/screens/register_partner_screen.dart`
- `lib/auth/auth_store.dart`
- `supabase/functions/register-partner/index.ts` (só validação de IBAN, não
  relacionado com este bug)

## 6ª verificação (2026-07-14, dado novo do Danilo: reproduziu AO VIVO)
Danilo reportou de novo, desta vez com teste real: fez login com sucesso
(autenticou) e o app voltou ao início do wizard pedindo tudo, incluindo
email/senha no passo "Conta de Acesso". Isto é literalmente o sintoma que
o fix `3c19043` já cobre (ver acima) — então a pergunta certa não é "o
código tem o bug" (não tem, releitura confirma) mas "porque é que o Danilo
continua a VER o bug num teste real".

**Causa raiz encontrada:** o commit `3c19043` (e o `494f1c0` antes dele)
**nunca foi enviado para o `origin`**. Confirmado com
`git branch -r --contains 3c19043` → vazio (não está em nenhum branch
remoto) e `git log origin/autonomous-night-2026-04-29..HEAD` → lista
`3c19043` e `494f1c0` como não enviados. O branch local está `ahead 37,
behind 2` do `origin/autonomous-night-2026-04-29`. Ou seja: o fix existe e
está correto no código local, mas nenhum build de CI o incluiu ainda —
o APK que o Danilo tem instalado no telemóvel é de **antes** do fix, por
isso continua a reproduzir exatamente o comportamento antigo. Não é
regressão de código; é gap de deploy (mesmo padrão de
`project_autocomplete_guarda_stale_apk` e `project_chat_guiado_p1_ja_feito`).

Zero diff nos 4 ficheiros desde a 5ª verificação (`bf9414a`):
`git log bf9414a..HEAD -- <4 ficheiros>` vazio, `git diff` vazio, `git
status` limpo. `flutter analyze` nos 4 ficheiros: 6 issues, 0 erros —
mesmos avisos pré-existentes, nenhum novo.

**Não fiz `git push`.** O branch `autonomous-night-2026-04-29` tem
`on: push: branches: [autonomous-night-2026-04-29]` no
`.github/workflows/build_android.yml` — ou seja, um push aqui dispara
automaticamente um **build de produção + upload ao Google Play**, que é
Lista Vermelha (🔴 "builds de produção"). Está tudo pronto (commits já
feitos, código validado, zero erros) — só falta o Danilo confirmar "vai"
para o push acontecer e um APK novo (com o fix) chegar ao dispositivo.

⚠️ ISTO PODE DISPARAR BUILD DE PRODUÇÃO (push do branch → CI → Google
Play). Está tudo pronto — confirma que eu aplico (`git push`).

**Conclusão desta ronda:** LOGIN PARCEIRO reinicia wizard: confirmado/corrigido
no código (commit `3c19043`, já 6x verificado sem regressão); o sintoma
que o Danilo ainda vê ao vivo é o APK instalado estar desatualizado, não
um bug no código atual. Recomendo não reabrir esta investigação sem um
sintoma novo — o próximo passo é só "vai" para o push/build.
