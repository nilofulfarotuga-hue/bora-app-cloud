# Erro submissão parceiro — v5 (ronda 2026-07-16)

## Pedido recebido
Mesmo texto literal das rondas v1-v4 (2026-07-14): investigar se o erro
genérico "Verifica email/password ou contacta support. Detalhes nos logs."
no passo final "Logo & Confirmação" do cadastro de parceiro é estrutural
ou isolado, citando conta `fulfarodanilo@gmail.com` criada "hoje" às
10:43:58 UTC.

## O que mudou desde a v4 (2026-07-14)

Ao contrário das rondas v1-v4 (onde `git diff` estava sempre vazio), desta
vez **houve commits reais** nos ficheiros do fluxo desde `3c19043`:

```
f169f96 fix(parceiro): commita fixes do cadastro que ficaram só na working tree (Ronda 8)
4e0f0d8 fix(parceiro): register-partner idempotente — corrige duplicação de candidatura
a6e2c7b fix(parceiro): mostrar erro específico do backend no cadastro em vez de genérico
7e2c63f feat(parceiro): upload de logo e capa no wizard de cadastro
```

`a6e2c7b` é especialmente relevante: **já elimina a causa raiz da própria
pergunta**. Confirmado por leitura de código (`lib/auth/auth_store.dart`
`_submitRestaurantEdgeFunction`, linhas ~1296-1349):

- Status EF ≠ 201 → mostra `backendError` vindo do corpo da resposta, ou
  (se vazio) "A tua conta de acesso foi criada, mas houve um erro ao
  registar o estabelecimento. Contacta o suporte — não precisas de repetir
  o email/senha." (nunca null/vazio).
- Exceção de rede/parsing → "...erro de ligação ao registar o
  estabelecimento..." (idem, nunca null).
- `registerPartnerWithDocumentsAsync`/`resumePartnerRegistrationAsync`
  **nunca retornam `null`** — sempre um Map com `error` como String
  não-vazia quando há falha.

Em `register_partner_screen.dart` linha 509-529, o fallback genérico
("Verifica email/password...") só dispara se `result == null` OU
`result['error']` não for String — nenhum dos dois acontece nos caminhos
reais hoje. **A mensagem genérica está, na prática, morta** (unreachable)
para os erros de submissão do restaurante. O upload de logo/capa
(`7e2c63f`, novo passo "Logo & Confirmação") também não pode disparar essa
mensagem: cada upload (logo/capa/docs) tem o seu próprio try/catch que só
faz `debugPrint`, nunca propaga exceção para o catch externo — e o catch
externo (linha 566-571) mostra `'Erro: $e'`, uma mensagem diferente da
citada no pedido.

`7e2c63f` já está em `origin/autonomous-night-2026-04-29` (confirmado via
`git branch -r --contains 7e2c63f`).

## Prova por dados reais — não há incidente "hoje"

Query a `auth.users` (projeto `ojykpzwqrtusfeakzrna`) filtrando
`bora_role = 'partner'`, ordenado por `created_at desc`: **não existe
nenhuma conta criada em 2026-07-16.** A mais recente para
`fulfarodanilo@gmail.com` é de **2026-07-15 06:59:28 UTC** — não
"hoje 10:43:58" como o pedido descreve.

Cruzando com `restaurants`: essa conta (`user_id
752bbad4-3eb7-4d58-9292-9e3af5b7e521`) tem o restaurante "pizzaria
Paulista" criado **2 segundos depois** (06:59:30 UTC) com
`approval_status = 'approved'` — ou seja, **o cadastro completou com
sucesso ponta-a-ponta e já foi aprovado por um admin.** Não há sinal de
conta presa/falhada para este email em nenhuma tentativa recente.

## Conclusão

O pedido é uma repetição do relatório já resolvido em
[[project_erro_submissao_iban_generico_resolvido]] (v1-v4,
2026-07-14) — mesmo email, mesma janela horária "10:43-10:50 UTC"
citada de forma genérica, sem corresponder a nenhum registo real de hoje.
A causa raiz original (regex IBAN + mensagem genérica escondendo erro
real) foi corrigida em `3c19043` e reforçada por `a6e2c7b` (mensagem
específica do backend, câminho da mensagem genérica agora inalcançável) —
ambos já em produção (origin). A única tentativa real registada da conta
citada terminou em sucesso completo + aprovação.

**Recomendação:** não reabrir esta investigação sem um sintoma novo real
— idealmente um print de erro ou timestamp que bata com um registo
existente em `auth.users`/`restaurants`. Sinal para o carteiro/CEO-AI:
este é o 5º ciclo do mesmo pedido (contando v1-v4 + este); considerar
dedupe desta tarefa específica no orquestrador.
