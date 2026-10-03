---
tema: auth
data: 2026-07-14
autor: executor-autonomo (SONNET)
estado: atual
---

# Recuperar senha + Confirmação de email — diagnóstico e implementação (2026-07-14)

## PARTE A — Recuperar senha (Esqueci a senha)

### Estado ANTES

Os 3 ecrãs de login (`client_login_screen.dart`, `driver_login_screen.dart`,
`partner_login_screen.dart`) **já tinham** o botão "Esqueceu a palavra-passe?"
implementado, chamando `AuthStore.resetPassword` / `resetDriverPassword`, que
por sua vez chamavam `supabase.auth.resetPasswordForEmail(email)`.

Mas o fluxo estava **incompleto** em 3 pontos:

1. `resetPasswordForEmail` era chamado **sem `redirectTo`** → o Supabase
   reencaminhava o clique no email para o "Site URL" default do projecto
   (normalmente uma página web), **não de volta para a app**.
2. **Não existia nenhum ecrã** no app para o utilizador definir a nova
   palavra-passe (nem `reset_password_screen.dart` nem equivalente).
3. **Não havia deep link configurado** no `AndroidManifest.xml` nem no
   `Info.plist` — mesmo que o Supabase reencaminhasse para um esquema custom,
   o Android não saberia abrir a app com esse link.

Havia até um ficheiro `docs/SIGNUP_SOCIAL_SETUP.md` a documentar um
intent-filter `pt.boraapp.bora://login-callback` para login social
(Apple/Google) — mas isso é uma feature diferente (ainda não activada) e o
intent-filter **nunca chegou a ser aplicado** no `AndroidManifest.xml` real.

Ou seja: o botão existia, o email seria "enviado", mas o utilizador não tinha
como completar o reset dentro da app.

### Implementado agora

1. `lib/auth/auth_store.dart` — `resetPassword` e `resetDriverPassword` passam
   agora `redirectTo: 'pt.boraapp.bora://reset-password'`.
2. `lib/screens/reset_password_screen.dart` (novo) — ecrã com campo de nova
   palavra-passe + confirmação (mínimo 6 caracteres, igual à regra já usada no
   cadastro de estafeta), chama `supabase.auth.updateUser(UserAttributes(password: ...))`,
   depois `signOut()` e devolve o utilizador ao login para entrar com a nova
   palavra-passe.
3. `android/app/src/main/AndroidManifest.xml` — novo `intent-filter` na
   `MainActivity` para `scheme="pt.boraapp.bora" host="reset-password"`.
4. `ios/Runner/Info.plist` — `CFBundleURLTypes` com o mesmo esquema (paridade
   iOS, app é maioritariamente testada em Android).
5. `lib/auth/auth_store.dart` — `_onAuthStateChange` agora **ignora**
   `AuthChangeEvent.passwordRecovery` (não hidrata conta / não "loga"
   automaticamente o utilizador no ecrã principal do seu papel antes de ele
   escolher a nova palavra-passe — isso seria um bug de segurança/UX sério).
6. `lib/main.dart` — novo listener em `onAuthStateChange` que, ao ver
   `AuthChangeEvent.passwordRecovery`, abre `ResetPasswordScreen` via
   `NotificationService.navigatorKey` (mesmo padrão já usado para deep links
   de notificações push).

`flutter analyze` limpo nos ficheiros tocados (0 issues).

### ⚠️ 2 passos manuais no Supabase Dashboard (fora do alcance do código)

Não há ferramenta MCP disponível neste projecto para ler/escrever a config de
Auth do Supabase (só há SQL + Edge Functions + logs). Por isso **preciso que
confirmes/apliques manualmente**:

1. **Authentication → URL Configuration → Redirect URLs**: adicionar
   `pt.boraapp.bora://reset-password` à allow-list. Sem isto, o Supabase
   pode recusar o `redirectTo` e cair de novo no Site URL default.
2. **Ver secção seguinte — SMTP/Resend está em modo sandbox e bloqueia o
   envio real do email de recuperação para qualquer conta que não seja a
   tua.** Isto tem de ser resolvido antes do fluxo funcionar em produção.

### 🔴 Achado crítico durante o diagnóstico: envio de email está QUEBRADO agora

Nos logs do Auth (`get_logs auth`, hoje) encontrei:

```
"msg":"500: Error sending recovery email"
"path":"/recover"
error: "You can only send testing emails to your own email address
(nilofulfarotuga@gmail.com). To send emails to other recipients, please
verify a domain at resend.com/domains, and change the `from` address to
an email using this domain."
```

O provedor SMTP configurado é **Resend**, mas está em **modo sandbox/teste**
(domínio não verificado) — só consegue entregar emails para o teu próprio
email de conta Resend (`nilofulfarotuga@gmail.com`). **Para qualquer cliente,
estafeta ou parceiro real, o email de recuperação de senha falha com erro
500 agora mesmo**, independentemente do código do app estar correcto.

**Ação necessária (dashboard, não código):** verificar um domínio em
`resend.com/domains` e mudar o endereço `from` do Supabase Auth (Settings →
Auth → SMTP Settings) para usar esse domínio verificado.

## PARTE B — Confirmação de email (diagnóstico, sem alterar nada)

Consultei directamente `auth.users` via SQL (114 utilizadores):

| Métrica | Valor |
|---|---|
| Total de utilizadores | 114 |
| `email_confirmed_at` preenchido | 114 (100%) |
| `email_confirmed_at` vazio | 0 |
| `confirmation_sent_at` preenchido (email de confirmação disparado) | **0** |

Nos 15 registos mais recentes, `email_confirmed_at` fica **~50-90ms** depois
de `created_at` — confirmação instantânea, automática, sem envio de email.

**Conclusão: "Confirm email" está DESATIVADO.** Os utilizadores ficam
confirmados automaticamente no signup; nenhum email de confirmação é
disparado. Isto está coerente com o código (`signUp()` em `auth_store.dart`
não define `emailRedirectTo` nem espera um passo de confirmação).

### Recomendação: manter desativado

**A favor de manter desativado:**
- Apps de entrega (Glovo/Uber/Bolt/iFood) priorizam conversão rápida no
  cadastro — cada passo extra de fricção (esperar email → abrir → clicar)
  derruba conversão, especialmente em PT onde SMS/email podem demorar.
- O Bora já tem uma camada de confiança mais forte que "clicar num link":
  estafetas e parceiros passam por **aprovação manual do admin**
  (`approval_status`) antes de poderem operar — isso filtra contas falsas
  melhor do que confirmação de email.
- **Agora mesmo o SMTP está quebrado** (ver Parte A) — se ligasses "Confirm
  email" hoje, **100% dos cadastros ficariam bloqueados** (o email nunca
  chegaria a ninguém excepto a ti), o que seria pior que a situação actual.

**Contra (risco de manter desativado):**
- Emails inválidos/com erro de digitação entram no sistema sem validação.
- Não há forma de recuperar acesso por email verificado caso o utilizador
  perca o telefone (client login é por email+senha).

**Recomendação final:** manter desativado por agora. Se quiseres reduzir o
risco de emails inválidos sem adicionar fricção no cadastro, dá para no
futuro validar formato/MX do domínio no próprio formulário (client-side),
sem depender do fluxo de confirmação do Supabase. Reforça-se: **não fiz
nenhuma alteração na configuração de Auth** — decisão fica contigo.

### Templates de email / SMTP

- **SMTP:** configurado (Resend) mas em **sandbox** — ver achado crítico
  acima. Isto afecta tanto "Confirm email" (se algum dia for ligado) como
  o "Recuperar senha" (afecta AGORA).
- **Templates de email:** não consegui inspeccionar via API — o MCP deste
  projecto só expõe SQL/Edge Functions/logs, não a config de Auth
  (`Authentication → Email Templates` é dashboard-only). Recomendo
  confirmares manualmente lá que o template de "Reset Password" está em
  PT-PT (o default do Supabase vem em inglês).

## Ficheiros tocados

- `lib/auth/auth_store.dart`
- `lib/main.dart`
- `lib/screens/reset_password_screen.dart` (novo)
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`

## Testado

- `flutter analyze` nos ficheiros tocados: 0 issues.
- **Não testei o fluxo ponta-a-ponta num dispositivo real** porque o SMTP
  está quebrado para qualquer email que não seja o teu (ver achado
  crítico) — não há como confirmar o clique no link/deep link sem isso
  resolvido primeiro no dashboard. Depois de verificares o domínio no
  Resend + adicionares a Redirect URL, testar: login → "Esqueceu a
  palavra-passe?" → email chega → clique abre a app em
  `ResetPasswordScreen` → nova senha → login com a senha nova.

---

RECUPERAR SENHA: existia parcialmente (botão+email) · implementado o resto
(deep link + ecrã de nova senha) — mas envio real de email está quebrado
agora (Resend em sandbox, precisa verificar domínio + Redirect URL no
dashboard). CONFIRMAÇÃO EMAIL: desativada — recomendo manter assim
(fricção alta + admin já aprova manualmente + SMTP quebrado bloquearia
cadastros se ligasses agora).

---

## Reconfirmação (mesma data, execução seguinte do loop)

Corri esta tarefa de novo (o prompt chegou uma 2ª vez ao loop autónomo) e
revalidei tudo acima sem encontrar regressão nem trabalho em falta:

- Código: os mesmos 5 ficheiros continuam no working tree, ainda não
  commitados. `flutter analyze` nos 7 ficheiros do fluxo: 0 erros (só avisos
  pré-existentes em `register_partner_screen.dart`, não relacionados a este
  fluxo).
- Confirmei via `auth.users` (114 utilizadores, 2026-04-17→2026-07-14) que
  100% continuam auto-confirmados e `confirmation_sent_at` sempre `NULL` —
  "Confirm email" continua desativada, nenhuma mudança desde o diagnóstico
  original.
- Confirmei nos logs de Auth das últimas 24h que o erro
  `500: Error sending recovery email` (Resend sandbox, `path:"/recover"`)
  **voltou a acontecer hoje às 2026-07-14T10:05:46Z** — ou seja, o bloqueio
  de SMTP não foi resolvido entretanto e continua a impedir qualquer email
  de recuperação real (exceto para `nilofulfarotuga@gmail.com`). Ação
  pendente continua a ser do Danilo no dashboard Resend/Supabase.

Não há nada novo para implementar — apenas reforço de que o diagnóstico e a
implementação de código continuam válidos e a pendência é 100% dashboard
(domínio Resend + Redirect URL), não código.

## Reconfirmação #3 (mesma data, 4ª execução do loop autónomo)

Prompt chegou uma 4ª vez. Seguindo a instrução deixada em
[[project_auth_recuperar_senha_ja_implementado]] ("se voltar uma 4ª vez, só
reconfirmar git status + flutter analyze"), fiz a reconfirmação rápida em vez
de reabrir a investigação:

- `git status`: os mesmos ficheiros continuam no working tree, não
  commitados (`auth_store.dart`, `main.dart`, `AndroidManifest.xml`,
  `Info.plist` modificados; `reset_password_screen.dart` ainda untracked).
- `flutter analyze` nos 6 ficheiros do fluxo: **0 issues**.
- `auth.users` (SQL directo): 114/114 utilizadores confirmados,
  `confirmation_sent_at` continua `NULL` em 100% — "Confirm email" continua
  desativada, sem mudança.
- `get_logs(auth)`, janela 24h: o erro `Error sending recovery email` /
  `resend.com/domains` (Resend sandbox) continua a aparecer — bloqueio de
  SMTP para destinatários reais permanece por resolver no dashboard.

Quarta vez confirmado sem mudança nenhuma. Nada para implementar; nada para
corrigir no código. A única pendência continua a ser 100% dashboard
(Danilo): domínio Resend + Redirect URL do Supabase Auth.

## Reconfirmação #2 (mesma data, 3ª execução do loop autónomo)

Prompt chegou uma 3ª vez ao loop. Revalidei tudo de novo, sem alterar nada:

- Código: os mesmos ficheiros continuam no working tree, não commitados
  (`git status`: `auth_store.dart`, `main.dart`, `AndroidManifest.xml`,
  `Info.plist` modificados; `reset_password_screen.dart` ainda untracked).
  `flutter analyze` nos 6 ficheiros do fluxo (incluindo os 3 ecrãs de login):
  **0 issues**.
- Confirmei de novo via SQL em `auth.users` (15 registos mais recentes,
  até 2026-07-14T09:10) que `email_confirmed_at` continua a ser preenchido
  em ~50-90ms após `created_at` e `confirmation_sent_at` continua `NULL` em
  todos — "Confirm email" continua desativada, nenhuma mudança.
- Reconfirmei nos logs de Auth (`get_logs auth`, janela 24h) o mesmo evento
  `500: Error sending recovery email` / `gomail: could not send email 1: 550`
  para `fulfarodanilo@gmail.com` às `2026-07-14T10:05:46Z` — é o **mesmo
  evento já registado na reconfirmação #1**, não um novo teste; ou seja,
  ninguém tentou "Esqueci a senha" de novo entretanto, e o bloqueio do
  Resend sandbox permanece por resolver no dashboard (não código).

Terceira vez que este diagnóstico é confirmado sem mudança nenhuma —
ver [[project_auth_recuperar_senha_ja_implementado]] no Cérebro: se a
tarefa voltar uma 4ª vez, basta reconfirmar `git status` + `flutter analyze`
antes de reabrir toda a investigação.

## Reconfirmação #4 (mesma data, 5ª execução do loop autónomo)

Prompt chegou uma 5ª vez. Reconfirmação mínima, como já indicado na memória:

- `git status`: os mesmos ficheiros continuam no working tree, não
  commitados (`main.dart`, `AndroidManifest.xml`, `Info.plist` modificados;
  `reset_password_screen.dart` ainda untracked). Nenhuma mudança.
- `flutter analyze` nos 6 ficheiros do fluxo: exit code 0, sem issues
  reportados.
- `auth.users` (SQL directo): 114 total / 114 confirmados / 0
  `confirmation_sent_at` — "Confirm email" continua desativada, sem
  mudança.

Quinta vez confirmado sem mudança nenhuma. Nada para implementar; nada
para corrigir no código. Pendência continua 100% dashboard (Danilo):
domínio Resend + Redirect URL do Supabase Auth. Não vou reabrir a
investigação completa se este prompt chegar de novo — só reconfirmação
mínima como esta, a menos que `git status` ou `flutter analyze` mostrem
algo diferente.
