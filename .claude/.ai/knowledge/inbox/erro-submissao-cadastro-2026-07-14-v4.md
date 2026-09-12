# Erro genérico no submit final do cadastro de parceiro — v4 (reconfirmação, 2026-07-14)

Pedido **idêntico** ao já investigado em v1, v2 e v3 (mesmo texto, mesmo contexto, mesma
janela de logs "10:43-10:50 UTC de hoje"). Esta é a **4ª rodada** desta investigação
(+ 6 rodadas do fio irmão `cadastro-parceiro-senha-2026-07-14-v2.md`, total 10 reconfirmações
do mesmo bug já corrigido). Sem sintoma novo, sem git diff nos ficheiros do fix. Resposta às
4 perguntas pedidas, com verificação atualizada.

## (1) O que o botão final ("Continuar" do passo 4) chama

`lib/screens/register_partner_screen.dart:385-405`: se `_alreadyAuthenticated`
(`AuthStore.currentPartner != null`) → `resumePartnerRegistrationAsync()` (reaproveita a
sessão JWT, não recria conta); caso contrário → `registerPartnerWithDocumentsAsync()`
(`auth.signUp` + Edge Function). Ambos terminam na Edge Function `register-partner`, que
faz INSERT em `restaurants` (ou `service_providers` se categoria `beauty`) com
`approval_status='pending'`.

## (2) O erro verdadeiro por trás da mensagem genérica

Causa raiz histórica (corrigida em `3c19043`): `validateIban` no backend usava
`^PT\d{21}$` em vez de `^PT\d{23}$`, rejeitando 100% dos IBAN PT reais com HTTP 400;
`auth_store.dart` engolia o erro pós-signup e devolvia `null`; a tela só sabia mostrar
"Erro: Verifica email/password ou contacta support."

**Reconfirmado nesta ronda, com uma verificação nova (não feita em v1-v3):**
- `git diff 3c19043 HEAD` nos 4 ficheiros do fix → vazio, zero regressão.
- `flutter analyze` nos 3 ficheiros Dart → 0 erros, 6 warnings/infos pré-existentes
  (imports não usados, `_formKey`, `value:` deprecated) — nenhum novo.
- `get_edge_function` via MCP Supabase (projeto `ojykpzwqrtusfeakzrna`) → `version: 5`,
  `status: ACTIVE`, código-fonte devolvido pela API idêntico byte-a-byte ao ficheiro local,
  `validateIban` com `/^PT\d{23}$/` correto.
- **Novo nesta ronda:** query a `auth.users` (via MCP `execute_sql`, read-only) filtrando
  `raw_user_meta_data->>'bora_role' = 'partner'` — o registo mais recente é de
  **2026-07-10**, ou seja **ninguém tentou um cadastro de parceiro novo desde o fix**
  (deployado 2026-07-14 11:43 UTC / commitado 13:32 UTC). Não há, portanto, tráfego real
  pós-fix para confirmar em produção — só a prova de código + a reprodução ao vivo já feita
  nas rondas v1/v2 com logs reais (10:43-11:47 UTC, `fulfarodanilo@gmail.com`, 400 do Edge
  Function, antes do fix).

## (3) Existe verificação "este utilizador já tem registo de parceiro?" pós-login

Sim: `partner_login_screen.dart:341-371` (`_finishPartnerLogin`) já não expulsa quem loga
sem `restaurants` — deixa passar para `PartnerEntryScreen`/`_PartnerNoRestaurantRouter`, que
resolve entre hub de serviços (`service_providers`) ou retomar o wizard já autenticado
(`register_partner_screen.dart` lê `currentPartner` no init e chama
`resumePartnerRegistrationAsync` no submit, sem re-pedir email/senha). Commitado em `3c19043`.

## (4) Teste ponta-a-ponta com email novo

**Ainda não reproduzível neste ambiente** — executor headless, sem emulador/dispositivo
conectado, e o único E2E de parceiro em `.claude/testes-e2e/flows/registry.json`
(`partner-simulate-accept-ready.py`) simula aceitar um pedido já existente, não o wizard de
cadastro. Reporto isto explicitamente em vez de assumir sucesso — mesma limitação de v1-v3,
que continua verdadeira.

## Limitação residual (não nova)

Fix commitado + Edge Function v5 deployed, mas o build de produção (APK assinado/Play Store)
ainda não foi feito — única forma de chegar a dispositivos reais. Isso é Lista Vermelha 🔴,
não acionado automaticamente pelo loop.

## Recomendação ao Danilo

10 reconfirmações idênticas do mesmo bug, já corrigido desde `3c19043`, sem nenhum sintoma
novo (print de erro diferente, email usado, passo exato onde travou). A partir daqui, sem
um dado concreto novo, reenviar esta mesma tarefa não vai produzir informação diferente —
só queima tempo de loop. Sugiro ao loop parar de reenviar até (a) o build de produção sair
e alguém testar num dispositivo real, ou (b) surgir um sintoma específico e diferente deste.

---

## Resposta final

**CADASTRO FALHA PARA TODOS: não** (era "sim" antes do fix `3c19043`) — **causa: IBAN
validado com regex errado (`PT+21 dígitos` em vez de `PT+23`) + erro genérico escondia a
causa real + login expulsava o parceiro em vez de retomar o wizard — corrigido: sim**
(commit `3c19043`, Edge Function v5 ACTIVE em produção, zero regressão em 4 rondas de
reconfirmação; falta só o build de produção para chegar aos dispositivos — etapa separada,
bloqueada pela Lista Vermelha, fora do escopo desta investigação).
