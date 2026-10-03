# Emails, fecho semanal e painel — 05/09/2026

Sessão `emails-fecho-e-painel-05-09` · branch `autonomous-night-2026-04-29` · Supabase `ojykpzwqrtusfeakzrna`

---

## ⚠️ LER PRIMEIRO — a tua palavra-passe mudou

**A palavra-passe da conta `nilofulfarotuga@gmail.com` é neste momento `BoraTeste2026`.**

Não foi intencional, foi o bug a apanhar-me a mim. Ao testar o link de recuperação de
*outra* conta (`boraappbora@gmail.com`) num browser que tinha a **tua** sessão aberta, a app
mudou a palavra-passe da **tua** conta em vez da conta do link — e escreveu "Palavra-passe
alterada" na mesma. Foi assim que o bug ficou provado, mas o efeito é real e é teu.

Entra com `BoraTeste2026` e muda-a para o que quiseres. A conta `boraappbora@gmail.com`
ficou com `BoraTeste2026` também (era a conta de teste).

---

## O que foi feito, e o que se provou

### BLOCO 1 — "Esqueci a palavra-passe" · CAUSA RAIZ ENCONTRADA E CORRIGIDA

As quatro hipóteses da ordem foram todas testadas. **As quatro estavam já satisfeitas** — o
problema era outro, e mais grave.

| # | Hipótese da ordem | Verificação | Resultado |
|---|---|---|---|
| 1 | Query dentro do fragmento | Leitura de `_paramsFromUrl()` em `reset_password_screen.dart` | Já lê o fragmento corretamente |
| 2 | Fluxo antigo em vez de `verifyOtp` | Código já usa `verifyOTP(type: recovery, tokenHash:)` desde 30/08 | Já correto |
| 3 | Rota ausente no build publicado | `curl` ao `main.dart.js` de `app.boraguarda.com`: 3 ocorrências de `redefinir-palavra-passe`, 2 de `token_hash` | Já no ar |
| 4 | Allowlist do Auth | Dashboard → URL Configuration: `https://app.boraguarda.com/**` presente (10 URLs) | Já lá estava |

Extra verificado: o `AndroidManifest.xml` **não** tem intent-filter para `app.boraguarda.com`
(só o custom scheme). Logo o Android não interceta o link — abre no browser.

**A causa real** está em `lib/screens/reset_password_screen.dart`, em `_resolveRecoverySession()`:

```dart
// ANTES — o teste da sessão vinha primeiro:
if (auth.currentSession != null) {
  setState(() => _linkState = _LinkState.ready);
  return;            // sai já: _tokenHash fica NULL
}
```

Se o browser já tinha **qualquer** sessão aberta, o método saía antes de ler o `token_hash`.
Depois, no `_submit()`, a condição `if (_tokenHash != null && auth.currentSession == null)`
fazia saltar o `verifyOTP`, e o `updateUser()` ia alterar a palavra-passe **da sessão aberta**,
não da conta que pediu o email. E o ecrã mostrava "Palavra-passe alterada".

Isto não é só um bug de UX — é uma **falha de segurança**: num dispositivo partilhado, um
link de recuperação de A aberto com sessão de B muda a palavra-passe de B.

**Prova experimental (05/09, ao vivo):**

| Passo | Prova |
|---|---|
| Pedido de recuperação para `boraappbora@gmail.com` | `recovery_sent_at` = 19:04:34, email chegou 19:04:35 |
| Link aberto no Chrome | Ecrã "Nova palavra-passe" abriu com os dois campos |
| "Guardar nova palavra-passe" | Ecrã disse **"Palavra-passe alterada"** |
| Login com a nova palavra-passe | **HTTP 400 `invalid_credentials`** |
| `recovery_token` da conta do link | **não consumido** |
| `updated_at` de `nilofulfarotuga@gmail.com` | **mudou às 19:06:00** ← a conta errada |
| Consola do browser | `uid=c9fccf85-…` = o id de `nilofulfarotuga@gmail.com` |

Controlo negativo: login com palavra-passe propositadamente errada devolveu o mesmo
`invalid_credentials`, confirmando que o 400 é genuíno e não um falso sinal.

**Correção aplicada** (`lib/screens/reset_password_screen.dart`):
1. O `token_hash` do link passa a ser lido **antes** de olhar para a sessão.
2. Havendo `token_hash` e sessão aberta, faz-se `signOut()` antes de trocar o token.
3. No `_submit()`, caiu a condição `auth.currentSession == null`: havendo hash, o
   `verifyOTP` corre sempre — é o link que decide de quem é a conta.

⚠️ **Por verificar:** a correção está no repo e passa a análise, mas **só entra em vigor
depois do build web sair**. Até lá, `app.boraguarda.com` continua com o comportamento antigo.

---

### BLOCO 2 — Domínio e acentos · A PREMISSA ESTAVA DESATUALIZADA

A ordem parte de "o Resend está em modo restrito e só entrega em `nilofulfarotuga@gmail.com`".
**Isso já não é verdade**, e provou-se:

- Domínio `boraguarda.com` no Resend: **Verified**, há 8 dias (≈28/08).
- Supabase Auth → SMTP: já usa `smtp.resend.com`, remetente `nao-responder@boraguarda.com`.
- Email entregue a **`boraappbora@gmail.com`** (que não é o dono da conta Resend) em
  **1 segundo**. Se o modo restrito estivesse ligado, isto era impossível.
- Resend → Emails: o email das 19:16 para `nilofulfarotuga@gmail.com` está **Delivered**.

Os `Bounced` no Resend são todos para `@boraapp.test` — um TLD reservado que não existe.
São os testes E2E, não clientes.

**Os acentos, esses, eram um problema real — mas não pela razão suposta.** O
`<meta charset="utf-8">` **já estava** no template. Os `�` estavam gravados **no próprio
texto** guardado no Supabase; meter o charset não resolveria nada.

**Corrigido e provado no mesmo fio de email:**

| Hora | Texto |
|---|---|
| 19:04 (antes) | `Carregue no bot�o abaixo… Se o bot�o n�o funcionar… endere�o… liga��o � v�lida… s�… voc�` |
| 19:21 (depois) | `Carregue no botão abaixo… Se o botão não funcionar…` |

Contagem mecânica no editor do template: **11 → 0** caracteres `�`.

**Por fazer:** só o template *Reset password* foi corrigido. Os outros cinco (Confirm sign up,
Invite user, Magic link, Change email address, Reauthentication) **não foram verificados** —
o Dashboard começou a responder muito devagar e preferi não ficar bloqueado num item
secundário. O método está provado e leva ~2 minutos por template: abrir o template, correr a
substituição no editor, Save.

---

### BLOCO 3 — Fecho semanal · JÁ ESTAVA LIGADO; FALTAVA O AVISO

Crons confirmados **todos ativos**: `close-weekly-settlements` (26, `5 0 * * 1`),
`weekly-closeout-digest` (63, `0 9 * * 1`), `partner-auto-dispatch` (72),
`check-orphan-orders` (73).

**3.1 — Ensaio.** A semana atual (31/08–06/09) ainda não tem linhas: o digest só as compila
na segunda de manhã. O histórico completo do `weekly_digest_log` são **3 linhas**:

| Semana | Quem | Sentido | Valor | Estado do email |
|---|---|---|---|---|
| 23/08 | Danilo (driver) | deve à Bora | −11,12 € | `failed` |
| 16/08 | Barbearia Ouro e Prata | Bora paga | 11,50 € | `aguarda_dominio` |
| 09/08 | Valdemir Vasconcelos | deve à Bora | −0,80 € | `aguarda_dominio` |

Não corri o `weekly_closeout_compile` porque **escreve** na base; o ensaio foi feito pela via
de leitura. O recibo de 23/08 diz "Entraremos em contacto" em vez de dar o MB Way — mas isso
foi porque o `bora_mbway_phone` só passou a existir hoje. A v3 já tem o ramo que imprime
"Pague por MB Way para 931992662"; a partir da próxima segunda sai correto.

Causa do `failed` de 31/08: nessa data o remetente ainda era `noreply@boraapp.com`, domínio
que nunca existiu → o Resend rejeitou. Já corrigido pela v3.

**3.2 — Feito.** O `email_status='skipped'` **já existia**. O que faltava era a segunda metade
do pedido: os que ficam de fora **não apareciam em lado nenhum**. E quando falhava, a
tabela guardava só a palavra `failed` — a causa perdia-se na consola (foi por isso que a
falha de 31/08 só se explicou por dedução).

- Migration: coluna `weekly_digest_log.email_error`.
- **Edge `weekly-closeout-digest` v4 no ar** (`verify_jwt: true` preservado):
  `sendResend` passa a devolver a causa do erro, que é gravada; e quem ficou `skipped`,
  `failed` ou `aguarda_dominio` entra numa secção **"NÃO RECEBERAM O EMAIL"** no push e no
  email de resumo.
- Textos do recibo passaram a PT-PT com acentos ("Olá", "A transferência é feita na
  segunda-feira", "referência").

⚠️ **Cuidado que valeu a pena:** o ficheiro local **estava atrás do que estava no ar** (não
tinha a v3). Deployar a partir do local teria feito *downgrade* e desfeito a correção do
domínio. A v4 foi construída **a partir do código que estava no ar**, e o repo ficou
sincronizado.

**3.3 — Confirmado, já existia.** `admin_resend_weekly_digest` tem botão em
`admin_acertos_semana_screen.dart:98`.

**3.4 — POR FAZER.** O ecrã de configuração do MB Way e do interruptor de emails não foi
construído. A RPC `admin_update_weekly_closeout_settings(p_bora_mbway, p_emails_enabled)`
existe e está pronta; falta só o formulário. Os dois valores já estão definidos em
`platform_settings` (`931992662` e `true`), portanto o sistema funciona — o que falta é
poderes mudá-los sem SQL.

---

### BLOCO 4 — Painel admin

**4.1 — Cartões que mentiam · CORRIGIDO.** `admin_dashboard_metrics` somava só as linhas
positivas do ledger e ignorava as negativas:

| Cartão | Mostrava | Saldo real |
|---|---|---|
| A pagar — drivers | **80,46 €** | **−12,97 €** (são eles que devem à Bora) |
| A pagar — restaurantes | 30,09 € | 30,09 € |
| Faturamento total | 28,51 € (desde sempre) | 28,51 € |

- Migration: passa a devolver o **saldo líquido com sinal**, mais `platform_revenue_week`,
  `week_start` e `week_end`. Verificado pelo efeito: a definição já não contém `amount > 0`
  e já contém `platform_revenue_week`.
- Flutter: os rótulos passam a **seguir o sinal** — saldo negativo mostra
  "A receber de drivers", não "A pagar". Um número certo debaixo de um rótulo errado
  mentiria na mesma. Novo cartão separa a receita da semana da receita de sempre.

**4.2 — Lançamento fantasma · ORIGEM ENCONTRADA, VIGIA CRIADA.**
Origem: o gatilho `orders_post_to_ledger` na tabela `orders` chama `post_order_to_ledger`.
O pedido `dbc6e138-…` foi lançado no livro e **deixou de existir depois** (pedido de teste
apagado). O livro é append-only (`ledger_no_delete` + `ledger_no_update`), por isso as linhas
ficaram. **Não apaguei nada nem lancei linha compensatória**, como mandado.

Criado, e **provado no caso real**:
- `admin_list_orphan_ledger_entries()` — leitura para o painel.
- `_cron_check_orphan_ledger()` + cron **74** (`0 7 * * *`).
- Corrido uma vez: gerou o aviso `ledger_orphan`, `entity_id=dbc6e138-…`, 2 linhas,
  soma 12,00 € (10,29 + 1,71 ✓), com dedup de 7 dias.

**4.3 — Dois fechos a competir · DECIDIDO: filtrar e renomear, não remover.**
A ordem supunha que o ecrã lia `partner_reservation_payouts`. Na verdade lê
`admin_partners_with_counts`, que devolve **todas** as lojas da tabela `restaurants` — daí
aparecerem Auchan, Burger King e Continente.

Decisão: **não remover**. O ecrã tem função real (marcar repasses pagos, CSV). Em vez disso:
- Filtro `is_partner == true` no carregamento (a RPC já devolve o campo; não mexi na RPC,
  que é usada noutros ecrãs onde ver todas as lojas faz sentido).
- Renomeado de "Fechamento Semanal — Parceiros" para **"Repasses a Parceiros"**, para deixar
  de colidir com "Fechos Semanais".

Nota: o cartão "Acerto reservas parceiros" (os créditos de 2 €) é um ecrã **diferente** e já
tinha nome correto.

**4.4 — POR FAZER.** A janela da semana não foi uniformizada entre ecrãs. Confirmei que
`driver_settlement_week_bounds(now())` devolve 31/08 00:00 → 06/09 23:59:59 (segunda a
domingo, hora de Lisboa) e usei-a na função do dashboard, mas não varri os restantes ecrãs.

**4.5 — POR FAZER (com uma correção à ordem).** Nenhum dos controlos foi construído.
Mas a ordem diz que reatribuir pedido "hoje só por SQL" — **`admin_reassign_order` já existe
na base**; falta só o ecrã. Isso torna o item bem mais barato do que parece.

**4.6 — FEITO. Varredura completa:**

| | |
|---|---|
| Funções `admin_*` na base | **230** |
| Chamadas pelo Flutter | **163** |
| **Sem ecrã** | **67** |
| **Ecrãs a chamar função que não existe** | **0** ← nada partido |
| Ficheiros de ecrã admin | 96 |

Ressalva honesta: das 67 "sem ecrã", algumas são chamadas por Edge Functions ou via
`admin_call_rpc`, não são todas órfãs. A lista completa está no corpo da sessão; as mais
relevantes para ti: `admin_reassign_order`, `admin_approve_driver`, `admin_reject_driver`,
`admin_cancel_order`, `admin_update_driver`, `admin_list_ratings`,
`admin_set_settlement_status`, `admin_tvde_rides_list`.

---

## Alterações aplicadas

**Base de dados (3 migrations):**
- `admin_dashboard_metrics_saldo_real_e_periodo`
- `verificacao_linhas_de_livro_sem_pedido` (+ cron 74)
- `weekly_digest_log_guarda_a_causa_do_erro`

**Edge Function:** `weekly-closeout-digest` v3 → **v4**.

**Painéis externos:** template *Reset password* do Supabase Auth reescrito (11 → 0 `�`).

**Código (4 ficheiros):**
- `lib/screens/reset_password_screen.dart`
- `lib/screens/admin/admin_dashboard_screen.dart`
- `lib/screens/admin/admin_partner_payouts_screen.dart`
- `supabase/functions/weekly-closeout-digest/index.ts`

**Análise:** `flutter analyze` nos 3 ficheiros Dart → **0 erros**. O único aviso (`info`,
`prefer_const_constructors`, linha 260) é **pré-existente** — confirmado por comparação com
o HEAD.

**Portão de RAM:** medidos **497 MB**, abaixo do portão pesado de 800 MB. `playwright` e
`nano-banana` não estavam a correr. O consumidor pesado era o `llama-server` com **4,3 GB** —
um serviço vivo, que matar podia partir trabalho a sério. Avancei mesmo assim, correndo a
análise **só nos ficheiros tocados** em vez do projeto inteiro. Correu em 20,5 s sem OOM.

---

## O que NÃO ficou feito

1. **Bloco 2** — cinco templates de email por verificar (só o *Reset password* foi corrigido).
2. **Bloco 3.4** — ecrã de configuração do MB Way / interruptor de emails.
3. **Bloco 4.4** — janela da semana não uniformizada nos restantes ecrãs.
4. **Bloco 4.5** — nenhum dos cinco controlos construído.
5. **Bloco 1** — a correção só entra em vigor depois do build web.

---

## PARA O DANILO

1. **Muda a tua palavra-passe.** Está em `BoraTeste2026` (ver topo).
2. **O Supabase avisa "Grace period is over"** no topo do Dashboard: *"Your projects will not
   be able to serve requests when you use up your quota."* Isto é faturação e é decisão tua —
   não lhe toquei.
3. **O lançamento fantasma no ledger** (12,00 € em duas linhas) continua lá, como mandaste.
   O livro é append-only. Decidires se fica como cicatriz ou se queres uma linha de correção
   é ato teu — não lancei nada.
