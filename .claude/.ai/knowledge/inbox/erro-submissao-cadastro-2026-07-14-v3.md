# Erro genérico no submit final do cadastro de parceiro — v3 (reconfirmação, 2026-07-14)

Pedido **idêntico** ao já investigado em `erro-submissao-cadastro-2026-07-14.md` (v1) e
`erro-submissao-cadastro-2026-07-14-v2.md` (v2), incluindo a mesma janela de logs citada
("10:43-10:50 UTC de hoje"). Esta é a **3ª rodada** da mesma investigação, sem sintoma novo
e sem git diff nos ficheiros do fix. Verificação rápida (sem repetir extração de logs já
feita nas rondas anteriores):

## Verificação desta ronda

1. `git log` nos 4 ficheiros do fix (`lib/auth/auth_store.dart`,
   `lib/screens/register_partner_screen.dart`, `lib/screens/partner_login_screen.dart`,
   `supabase/functions/register-partner/index.ts`) → último commit continua `3c19043`
   (`fix(parceiro): mensagem de erro real no submit + retomada sem recriar conta`). Nenhum
   commit posterior tocou estes ficheiros.
2. `git diff 3c19043 HEAD` nesses 4 ficheiros → **vazio**. Zero regressão.
3. `flutter analyze` nos 3 ficheiros Dart → **0 erros** (mesmos 5 warnings pré-existentes de
   import/campo não usados + 1 info `deprecated_member_use`, nada relacionado à lógica do fix).
4. `get_edge_function` via MCP Supabase (projeto `ojykpzwqrtusfeakzrna`, slug
   `register-partner`) → **version: 5, status: ACTIVE**, código-fonte devolvido pela API
   confirma `validateIban` com o regex correto `/^PT\d{23}$/` (linha `function validateIban`).
   Sem drift local↔produção.

## Causa raiz (histórica, já corrigida — não repetida a fundo)

Ver v1/v2: Edge Function validava IBAN com `^PT\d{21}$` (errado) em vez de `^PT\d{23}$`,
rejeitando 100% dos IBAN portugueses reais com HTTP 400; `auth_store.dart` engolia o erro
pós-signup devolvendo `null`; a tela só mostrava a mensagem genérica. Tudo corrigido em
`3c19043` + Edge Function v5 deployed desde 2026-07-14 11:43:47 UTC.

## Teste ponta-a-ponta com email novo

Não reproduzível neste ambiente (executor headless, sem emulador/dispositivo, sem harness
E2E para o wizard de signup de parceiro — só existe `partner-simulate-accept-ready.py`, que
simula aceitar pedido já existente). Mesma limitação reportada em v1/v2.

## Limitação residual (não nova)

Fix commitado + Edge Function v5 deployed, mas o **build de produção** (APK assinado / Play
Store) ainda não foi feito — única forma de chegar a dispositivos reais. Build de produção é
Lista Vermelha (🔴), não acionado automaticamente pelo loop.

---

## Resposta final

**CADASTRO FALHA PARA TODOS: não** (era "sim" antes do fix, já corrigido) — **causa: IBAN
validado com regex errado (`PT+21 dígitos` em vez de `PT+23`) + mensagem de erro genérica
escondia a causa real + login expulsava o parceiro em vez de retomar o wizard — corrigido:
sim** (commit `3c19043`, Edge Function v5 ACTIVE em produção, reconfirmado sem regressão
nesta 3ª ronda; falta só o build de produção para chegar aos dispositivos, etapa separada
bloqueada pela Lista Vermelha).
