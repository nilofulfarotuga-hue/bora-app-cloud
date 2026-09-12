# Erro genérico no submit final do cadastro de parceiro — v2 (reconfirmação, 2026-07-14)

Pedido idêntico ao já investigado em `erro-submissao-cadastro-2026-07-14.md` (v1) e
reconfirmado 5x em `cadastro-parceiro-senha-2026-07-14-v2.md`. Esta ronda **não encontrou
código novo nem regressão** — respondo às 4 perguntas com prova atualizada, sem repetir a
extração de logs já feita nas rondas anteriores (o cenário já foi provado ao vivo em
produção em 2026-07-14 10:43–11:47 UTC).

## (1) O que o botão final ("Continuar" do passo 4) chama

`lib/screens/register_partner_screen.dart:385-405` — decide o caminho conforme o estado de
autenticação:

- Se `AuthStore.currentPartner != null` (utilizador já autenticado, ex.: retomando depois de
  fechar o app a meio) → `AuthStore.resumePartnerRegistrationAsync()` (reutiliza a sessão
  JWT existente, **não** chama `auth.signUp` de novo).
- Caso contrário → `AuthStore.registerPartnerWithDocumentsAsync()` (cria a conta via
  `auth.signUp` e depois chama a Edge Function `register-partner`).

Em ambos os casos o payload final vai para a Edge Function `register-partner`
(`supabase/functions/register-partner/index.ts`), que faz o INSERT em `restaurants`
(ou `service_providers` se `category == "beauty"`) com `approval_status = 'pending'`.

## (2) O erro verdadeiro por trás da mensagem genérica

Causa raiz histórica (já corrigida): a Edge Function validava IBAN com
`^PT\d{21}$` em vez de `^PT\d{23}$`, rejeitando 100% dos IBAN portugueses reais com HTTP
400. `auth_store.dart` engolia qualquer erro pós-signup devolvendo `null`, e a tela só sabia
mostrar "Erro: Verifica email/password ou contacta support." — escondendo a causa real.

**Confirmado nesta ronda que o fix continua ativo:**
- Código local `supabase/functions/register-partner/index.ts:34-37` — `validateIban` já usa
  `/^PT\d{23}$/` (correto).
- Edge Function **deployed em produção** (`get_edge_function` via MCP Supabase,
  projeto `ojykpzwqrtusfeakzrna`) — `version: 5`, `status: ACTIVE`, código-fonte devolvido
  pela API é **byte-a-byte igual** ao ficheiro local, incluindo o `validateIban` correto.
  Sem drift entre local e produção.
- `lib/auth/auth_store.dart` — `registerPartnerWithDocumentsAsync` (linha 1172) agora
  propaga o erro específico (`specificError`) para a tela em vez de `null` genérico;
  `register_partner_screen.dart:422` faz `debugPrint` do erro real e mostra-o ao utilizador.

## (3) Existe verificação "este utilizador já tem registo de parceiro?" pós-login

Sim, dois pontos em cadeia:
- `register_partner_screen.dart:72-75` — no build/init lê `context.read<AuthStore>().currentPartner`;
  se não for `null`, pré-preenche o email e esconde os campos de credenciais (não pede
  email/senha de novo).
- `partner_login_screen.dart` — login bem-sucedido **já não expulsa** o utilizador quando
  não há `restaurants` associado (cenário de conta criada mas INSERT falhado a meio); delega
  para `PartnerEntryScreen` / `_PartnerNoRestaurantRouter`, que decide entre retomar o wizard
  ou mostrar o estado "pendente aprovação" conforme o caso.

Este fix está commitado em `3c19043` (não é só working tree).

## (4) Teste do início ao fim com email novo

**Não foi possível reproduzir a UI Flutter completa neste ambiente** (executor headless, sem
emulador/dispositivo conectado nem harness E2E para o wizard de signup — o único script E2E
relacionado a parceiro em `.claude/testes-e2e/flows/registry.json` é
`partner-simulate-accept-ready.py`, que simula um parceiro a aceitar um pedido já existente,
não o cadastro). Reporto isto explicitamente em vez de assumir sucesso.

Em vez disso, a verificação desta ronda foi:
- `git diff 3c19043 HEAD` nos 4 ficheiros do fix (`lib/auth/auth_store.dart`,
  `lib/screens/register_partner_screen.dart`, `lib/screens/partner_login_screen.dart`,
  `supabase/functions/register-partner/index.ts`) → **vazio**, sem regressão.
- `flutter analyze` nos 3 ficheiros Dart → **0 erros** (5 warnings de import/campo não usados
  + 1 info de API deprecated, pré-existentes, não relacionados à lógica do fix).
- Edge Function deployed confirmada = v5, código idêntico ao local (ver secção 2).
- O cenário "IBAN real rejeitado + mensagem genérica + retry cria loop" já foi **provado ao
  vivo** com logs reais de produção nas rondas anteriores (10:43–11:47 UTC, 2026-07-14, ver
  v1), não é uma hipótese.

## Limitação residual conhecida (não nova)

O fix está commitado mas o build de produção (APK assinado / Play Store) ainda não foi feito
— isso é a única forma de o fix chegar a dispositivos reais dos parceiros. Build de produção
está na Lista Vermelha (🔴) deste projeto e não é acionado automaticamente pelo loop.

---

## Resposta final

**CADASTRO FALHA PARA TODOS: não** (era "sim" antes do fix; o fix já está commitado e o
backend v5 já está deployed em produção) **— causa: IBAN validado com regex errado
(`PT+21 dígitos` em vez de `PT+23`) + mensagem de erro genérica escondia a causa real +
login expulsava o parceiro em vez de retomar o wizard — corrigido: sim** (commit `3c19043`,
reconfirmado sem regressão nesta ronda; só falta o build de produção para chegar aos
dispositivos, que é uma etapa separada e bloqueada pela Lista Vermelha).
