# "Esqueci a palavra-passe" — auditoria + implementação

**Data:** 2026-07-31 · **Branch:** `autonomous-night-2026-04-29`
**Zona:** auth (protegida, **não-dinheiro**) → CEO-AI §1.6: executar ponta-a-ponta.

---

## 1. Estado do GitHub

### 1.1 CI

| Item | Valor |
|---|---|
| Último run Android **bem-sucedido** | `30665071744` — **success**, 8m56s, 2026-07-31 21:01Z |
| Commit | `6943639` *fix(ci): remove changesNotSentForReview* |
| versionCode publicado | **506** (bump automático `8fe84b5`) |
| Job | `Build AAB & upload (Closed Testing — alpha)` → success |
| Tracks no workflow | `internal,alpha,production` · `status: completed` |

O upload é **um só**, atribuído aos três tracks em simultâneo (`tracks:` plural).
Confirma-se, portanto, que subiu para `internal` **e** `production`.

**Runs falhados na mesma janela** (todos já ultrapassados por commits posteriores):

| Run | Commit | Resultado |
|---|---|---|
| `30663180518` | `6255ebf` feat(lancamento) | failure — era o `changesNotSentForReview` expirado, corrigido em `6943639` |
| `30669276911` / `30669277353` | `be8c193` fix(notificacoes) | failure — **ver §5.1, é o incidente do dia** |
| `30669844090` | `fb19ad3` | em curso à hora do relatório |

Evidência: [`screens/github-actions-2026-07-31.txt`](screens/github-actions-2026-07-31.txt)

### 1.2 Mensagens por ler

| Item | Resultado |
|---|---|
| Notificações não lidas | **42** — *todas* `reason: ci_activity` |
| Assuntos distintos | 2: "Build Android … workflow run failed" e "build_web_deploy.yml … workflow run failed" |
| Issues abertas | **0** |
| PRs abertos | **0** |
| Reviews pendentes / comentários por responder | **0** |
| Dependabot | **desativado no repositório** (HTTP 403) |
| Code scanning | sem análise configurada (HTTP 404) |

Não há nada humano por responder. As 42 notificações são ruído de builds
falhados acumulado — nenhuma exige ação além de marcar como lidas.

Evidência: [`screens/github-notificacoes-2026-07-31.txt`](screens/github-notificacoes-2026-07-31.txt)

### 1.3 Divergência local ↔ remoto

O `git fetch` por **SSH falhou** (`Permission denied (publickey)`) — confirma a
lição já registada: nesta máquina o SSH não serve, o caminho é HTTPS +
credential manager. Refeito por HTTPS:

```
git -c credential.helper=manager fetch https://github.com/…/bora-app-cloud.git
git log FETCH_HEAD..HEAD   → vazio
git log HEAD..FETCH_HEAD   → vazio
```

**Não havia commits locais por enviar.** O `origin/…` local estava apenas
desatualizado (rasto do SSH partido), o que dá a falsa impressão de 20 commits
pendentes se olharmos só para `git log origin/…..HEAD` sem fetch.

### 1.4 Screenshots

Não foram gravados PNG. As ferramentas de browser disponíveis devolvem a
imagem para a conversa mas **não escrevem ficheiro em disco**, e as páginas do
GitHub exigem sessão autenticada. Em vez de um print, gravei a mesma
informação em **texto verificável** vinda do `gh` CLI (a fonte autoritativa,
que um screenshot só reproduziria) nos dois ficheiros acima, em
`.claude/.ai/reports/screens/`.

---

## 2. Auditoria — o que já existia

O prompt partia do princípio de que era preciso implementar de raiz. **Não era.**
A maior parte do fluxo já estava construída (trabalho de 2026-07-14).

### Já existia e funciona

| Peça | Onde |
|---|---|
| Link "Esqueci…" nos 3 logins | `client_login_screen.dart`, `driver_login_screen.dart`, `partner_login_screen.dart` |
| Link no diálogo multi-papel | `services/multi_role_signup.dart:119` |
| `resetPasswordForEmail` com `redirectTo` | `auth/auth_store.dart` |
| Resposta neutra (não revela contas) | os 3 ecrãs |
| Deep link Android | `AndroidManifest.xml:117-122` (`pt.boraapp.bora://reset-password`) |
| Captura de `PASSWORD_RECOVERY` | `main.dart:232-238` |
| Ecrã de nova palavra-passe | `screens/reset_password_screen.dart` |
| Edge Fn de reset pelo admin | `supabase/functions/support-password-reset` (v10) |

### Não existia — os 8 buracos reais

1. **Os erros eram engolidos.** `resetPassword` fazia `catch (e) { debugPrint }`
   e devolvia `void`. O utilizador via sempre "enviámos-lhe um email", mesmo
   quando o servidor recusou por rate limit ou o SMTP rebentou. Era exatamente
   o que estava a acontecer em produção.
2. **`redirectTo` era só o deep link** `pt.boraapp.bora://…`. Quem abrisse o
   email no portátil, ou sem a app instalada, ficava sem caminho nenhum.
3. **Não havia ecrã dedicado** a pedir o email — reaproveitava o campo do login,
   e se estivesse vazio só dizia "escreva o email acima".
4. **Não havia rota web** `#/redefinir-palavra-passe`.
5. **Não havia tratamento de link expirado / já usado.**
6. **Painel admin não tinha botão nenhum** de reset.
7. **A Edge Fn `support-password-reset` não mandava `redirectTo`** — o email
   caía no Site URL genérico.
8. `client_login_screen` chamava `resetDriverPassword` (nome errado, funcionava
   por acaso).

### Configuração de servidor (dashboard)

**A premissa do prompt estava errada, e isso muda o diagnóstico.** O projeto
**não** usa o SMTP interno do Supabase — usa **Resend**, já ligado, mas em
**modo teste**. Confirmado no log `auth` de hoje:

```
550 "You can only send testing emails to your own email address
(nilofulfarotuga@gmail.com). To send emails to other recipients,
please verify a domain at resend.com/domains, and change the `from`
address to an email using this domain."
```

Consequência: **hoje nenhum utilizador real recebe o email** — nem o
`boraappbora@gmail.com`. Nos logs de hoje há `user_recovery_requested` para o
`boraappbora@gmail.com` que falhou com este 550.

O bloqueio é o Resend exigir um **domínio próprio verificado**. Verifiquei:
`boraapp.pt` está **livre**; `bora.pt` e `boraapp.com` têm dono.

---

## 3. O que foi implementado

### Flutter — apps (PT-PT)

| Ficheiro | Alteração |
|---|---|
| `lib/config/auth_links.dart` | **NOVO.** Fonte única da URL canónica `https://bora-app-web.pages.dev/#/redefinir-palavra-passe`. Documenta porque é https e não deep link. |
| `lib/auth/auth_store.dart` | `resetPassword` deixa de engolir erros: devolve `PasswordResetOutcome` (`ok` / `rateLimited` / `emailNotSent` / `failed`). Deteta 429 e falha de SMTP. `resetDriverPassword` passa a delegar. |
| `lib/screens/forgot_password_screen.dart` | **NOVO.** Ecrã dedicado: pede email, valida, e mostra estado de sucesso ("Verifique o seu email", validade 1 h, dica do spam). Mensagens PT-PT incluindo **"Já pediu há pouco. Tente daqui a alguns minutos."** |
| `lib/screens/reset_password_screen.dart` | Reescrito para servir **web e telemóvel**. Resolve a sessão de recovery a partir de `Uri.base` (PKCE `?code=` e implícito `#access_token=`), trata o duplo `#`, e distingue **link expirado** de **link já usado**. Estados: a resolver / formulário / inválido / concluído. Largura máxima 480 px para a web. |
| `client_login_screen.dart`, `driver_login_screen.dart`, `partner_login_screen.dart` | Link unificado para **"Esqueci-me da palavra-passe"** e passa a abrir o ecrã dedicado (com o email já preenchido). |
| `lib/services/multi_role_signup.dart` | Passa a usar a constante partilhada em vez do deep link à mão. |
| `lib/main.dart` | Regista `ResetPasswordScreen.routeName` nas rotas + reconhecimento por prefixo no `onGenerateRoute` (a rota chega "suja" com o token colado). |

### Painel admin (PT-BR)

| Ficheiro | Alteração |
|---|---|
| `lib/screens/admin/_admin_password_reset_dialog.dart` | **NOVO.** Diálogo reutilizável: mostra **último e-mail de recuperação** e **último envio pelo painel**, e o botão "Enviar link de redefinição de senha". |
| `admin_clients_screen.dart` | Item novo no menu de cada cliente. |
| `admin_driver_detail_screen.dart` | Botão novo nas Acções do entregador (`drivers.id` = `auth.users.id`, confirmado 2/2 em produção). |

### Servidor — **já aplicado em produção**

| Peça | Estado |
|---|---|
| Migration `admin_auth_recovery_status` | ✅ **APLICADA**. RPC read-only, `SECURITY DEFINER`, guardada por `_admin_op_guard` (o mesmo padrão de `admin_ban_client`). Lê `recovery_sent_at` de `auth.users`, que o Flutter não alcança. |
| Edge Fn `support-password-reset` | ✅ **DEPLOYED v11**, `verify_jwt=false` preservado. Passou a: aceitar **JWT de admin** além da service_role key (mantém o caminho `admin_approve_action` via pg_net intacto); mandar `redirectTo`; devolver `recovery_sent_at`; **registar em `admin_audit_log`** (`action='password_reset_sent'`). |

Ficheiro do guia: [`GUIA_DANILO_SUPABASE_PASSWORD_RESET.md`](GUIA_DANILO_SUPABASE_PASSWORD_RESET.md)

---

## 4. O que ficou por fazer

1. **Comprar `boraapp.pt` + verificar no Resend** — é do Danilo (pagamento).
   **Enquanto isto não estiver feito, o botão funciona mas o email não sai.**
   É o único bloqueio que resta.
2. **Site URL / Redirect URLs / template do email** — dashboard, exige o login dele.
3. **Android App Links** (o link https abrir a app em vez do browser) — **não feito
   de propósito**. Exigia o SHA-256 do certificado de assinatura do Play Console
   e um `assetlinks.json` publicado. Um `assetlinks.json` com fingerprint errado
   é pior que nenhum (a verificação falha e confunde). O comportamento entregue
   é: **o link abre sempre a página web**, em qualquer dispositivo, com ou sem
   app. O deep link antigo continua declarado e funcional para os emails já
   enviados. Fica documentado como melhoria opcional.
4. **iOS** — não verifiquei o `Info.plist`. A app não é distribuída em iOS hoje.
5. **Reset de parceiro pelo admin** — só 1 de 16 `restaurants` tem dono a bater
   certo com `auth.users` (os outros 15 são lojas não-parceiras semeadas, sem
   conta). O reset de parceiro faz-se pelo ecrã de clientes, que lista contas
   auth reais.
6. **Teste ponta-a-ponta real** — impossível hoje: o email não sai enquanto o
   Resend estiver em modo teste. Os passos estão no guia para o Danilo provar.

---

## 5. Bugs e achados fora do escopo

### 5.1 🔴 Executor concorrente arrastou trabalho a meio e partiu o build

Durante esta sessão, outro executor autónomo commitou e fez push **por cima do
meu trabalho em curso**:

- `be8c193` *fix(notificacoes)* — apanhou o meu `lib/main.dart` a meio (já com
  `ResetPasswordScreen.routeName`) **sem** apanhar o `reset_password_screen.dart`
  que define esse `routeName`. Resultado: **os dois builds falharam**
  (`30669276911` Android e `30669277353` web).
- `fb19ad3` — o executor "consertou" **removendo a minha rota**, em vez de
  trazer o ficheiro em falta.

É a repetição exata de uma lição já registada ("commit concorrente arrasta
edição de outro executor — nunca `git add -A`"). O envelope de segurança não a
está a impedir. **Recomendação: o executor deve stagear ficheiros explícitos,
nunca `-A`/`.`** — ou, no mínimo, recusar commit quando o working tree tem
ficheiros modificados fora do seu próprio conjunto.

O meu working tree ficou correto e completo; commitei apenas os meus ficheiros,
por caminho explícito, restaurando a rota que o `fb19ad3` removeu.

### 5.2 Outros

- **Dependabot desativado** no repositório. Vale a pena ligar — é um clique em
  Settings → Security.
- **42 notificações de CI por ler**, todas de builds falhados. Ruído acumulado;
  não há nada humano por responder.
- **SSH do git partido nesta máquina** (`Permission denied (publickey)`). O
  `git fetch`/`push` por SSH falha; funciona por HTTPS + credential manager.
  Confirma lição já registada — mas o `origin/…` local fica desatualizado em
  silêncio, o que faz `git log origin/…..HEAD` mentir.
- **`restaurants` com 15 de 16 linhas sem dono em `auth.users`** — esperado
  (lojas não-parceiras semeadas), mas convém não confundir com contas partidas.
- **A app anunciava "enviámos o email" mesmo quando o envio falhava** — era o
  §2.1. Já corrigido, mas explica porque o problema ficou invisível durante
  semanas: nem o utilizador nem os logs do app diziam nada.

---

## 6. Nota de dinheiro

Nada nesta sessão tocou em Stripe, preços, comissões, tokens, wallet ou
`platform_settings` financeiros. **A Lista Vermelha não foi acionada.**

A única despesa envolvida é a compra do domínio `boraapp.pt` (~€12/ano), que
é decisão e cartão do Danilo — está no guia, não foi executada.
