# Erro na submissão final do cadastro de parceiro (2026-07-14, 10:43-10:50 UTC)

## 2ª reconfirmação (nova sessão do loop, tarefa idêntica recebida de novo)
Mesmo pedido literal recebido outra vez ("investigar se é estrutural").
Verificação rápida sem repetir todo o trabalho: `git diff HEAD` nos 4
ficheiros do fix (`auth_store.dart`, `register_partner_screen.dart`,
`partner_login_screen.dart`, `register-partner/index.ts`) está **vazio** —
working tree idêntico ao commit `3c19043` (13:32 UTC), zero regressão desde
a reconfirmação anterior. Este ficheiro de relatório continua **não
commitado** (`??` no git status) — decisão consciente das rondas anteriores
(não misturar com CI/main.dart/manifests pendentes de outras tarefas), não
esquecimento. Não repeti a extração de logs do Supabase (`get_logs`/
`get_edge_function`) porque: (1) já foi feita 2x nesta mesma janela de
incidente com prova real, (2) ambiente headless não gera tentativas novas
de submissão para haver logs novos a ver, (3) o único facto que podia
mudar — o código ter regredido — já foi descartado pelo diff vazio acima.
Conclusão inalterada: ver linha final. **Ver memória
`project_erro_submissao_iban_generico_resolvido` — não reinvestigar do
zero se pedido de novo sem indício de regressão real (ex.: novo erro nos
logs, diff não-vazio).**

## Reconfirmação (mesma sessão, após o commit 3c19043)
Este relatório já existia com a causa raiz provada por logs reais. Nesta
passagem: (1) `git status`/`git diff HEAD` confirmam que os 4 ficheiros do
fix (`auth_store.dart`, `register_partner_screen.dart`,
`partner_login_screen.dart`, `register-partner/index.ts`) estão **commitados**
desde `3c19043` (13:32 UTC) — já não é "pendente de commit" como a secção (4)
original dizia. (2) `mcp__Supabase__get_edge_function` confirma a Edge
Function `register-partner` continua na **v5 ACTIVE**, com
`validateIban` = `^PT\d{23}$` (formato correto), byte-a-byte igual ao
ficheiro local. (3) `mcp__Supabase__get_logs` (edge-function, últimas 24h):
os únicos `400` de `register-partner` são de **antes** do deploy da v5
(`deployment ..._4`, timestamps 10:44 e 10:57 UTC) — **zero falhas depois**
do deploy da v5 (11:43:47 UTC). Nenhuma tentativa nova de submissão
aconteceu desde então (ambiente headless, sem dispositivo/emulador para
gerar uma), mas não há regressão nem novo erro. Conclusão inalterada, só
mais confirmada: causa raiz provada, backend corrigido e ativo, app Flutter
agora corrigido **e commitado** — falta só o build de produção (Lista
Vermelha) para chegar a utilizadores reais.

## Resumo
**Bug estrutural real, reproduzido nos logs de produção, e já corrigido — mas
a correção do lado do app (Flutter) ainda não chegou a um APK instalado.**
Não foi um problema pontual de uma tentativa: qualquer submissão com IBAN
preenchido (formato real português) era **sempre** rejeitada pelo backend, e
qualquer falha nesse último passo escondia a causa atrás de uma mensagem
genérica que prendia o utilizador num loop sem saída.

## (1) O que o botão "Continuar" do último passo chama

`lib/screens/register_partner_screen.dart` → `_submit()`:
1. Faz upload de logo/documentos (`upload-restaurant-asset`, opcional).
2. Chama `AuthStore.registerPartnerWithDocumentsAsync()` (conta nova) ou
   `resumePartnerRegistrationAsync()` (conta já existe/autenticada), em
   `lib/auth/auth_store.dart`.
3. Esse método faz `Supabase.auth.signUp(...)` (cria a conta) e depois invoca
   a Edge Function `register-partner` (`supabase/functions/register-partner/index.ts`)
   com o JWT da sessão — ela insere a linha em `restaurants` (ou
   `service_providers` p/ categoria beauty) com `approval_status='pending'`.

Se `result == null`, o ecrã mostra o fallback genérico: **"Erro: Verifica
email/password ou contacta support. Detalhes nos logs."** — exatamente a
mensagem reportada.

## (2) Causa raiz confirmada nos logs reais (project `ojykpzwqrtusfeakzrna`)

Cruzando `auth` logs + `edge-function` logs + estado da BD:

- **10:43:58 UTC** — signup bem-sucedido (`200`, `immediate_login_after_signup:true`)
  para `fulfarodanilo@gmail.com` (user_id `fa849dd6-…`). Confirma o relato:
  "a conta de autenticação foi criada com sucesso".
- **10:44:00 UTC** (2s depois) — chamada a `register-partner` devolve **400**
  (`execution_time_ms: 1301`), na deployment `..._4` (versão *antiga* da
  função, ainda sem o fix).
- A versão antiga (`validateIban`) exigia `^PT\d{21}$` — ou seja, **PT + 21
  dígitos = 23 caracteres totais**. Um IBAN português real tem **PT + 2
  dígitos de controlo + 21 do NIB = 23 dígitos depois do "PT" = 25
  caracteres totais**. Isto significa que a validação **rejeitava sempre
  todos os IBAN portugueses reais e corretos**, 100% determinístico — não
  depende de sorte nem de qual conta testa.
- O `auth_store.dart` da versão antiga, em qualquer `response.status != 201`
  do Edge Function (400, 401, 500, timeout, exceção de rede), fazia
  `return null;` — sem propagar a mensagem real do backend. O ecrã só sabe
  mostrar o fallback genérico quando recebe `null`. **A causa real (erro de
  formato de IBAN) nunca chegava ao utilizador.**
- Pior: como a conta de autenticação já tinha sido criada no passo 1, uma
  nova tentativa (retry) chamava `registerPartnerAsync` outra vez com o
  mesmo email → Supabase devolve `422 user_already_exists` → a versão antiga
  também não tratava este caso → **loop sem saída**: qualquer retry falhava
  sempre com a mesma mensagem inútil, mesmo tendo corrigido o IBAN.
- Confirmado nos logs: entre **10:47:18 e 10:47:46 UTC**, 5 tentativas
  repetidas de signup do mesmo email (conta de teste
  `bora-qa-senha-test-20260714@bora-test.invalid`) todas batendo em
  `422: User already registered` — o loop real a acontecer.
- `auth.users`/`restaurants` não têm hoje nenhum registo desta janela
  (limpos por `delete-account` depois do teste) — não afeta a conclusão, só
  significa que não há "conta órfã" viva agora para inspecionar.

## (3) Teste ponta-a-ponta com email novo

Não foi possível correr um novo teste manual real neste ambiente headless
(sem emulador/dispositivo). Em vez disso, a prova foi feita com dados de
produção reais: os logs do Supabase mostram o bug a acontecer ao vivo às
10:43-10:44 UTC (não é uma reconstrução hipotética), e o código foi lido
ponta-a-ponta para confirmar que o caminho de falha é 100% determinístico
(regressão de regex, não uma condição de corrida ocasional).

`flutter analyze` nos 3 ficheiros tocados: **0 erros** (só 4 warnings de
import não usado + 1 campo não usado + 1 info de API deprecated,
pré-existentes, fora do escopo).

## (4) Estado da correção

**Backend (Edge Function `register-partner`) — JÁ CORRIGIDO E DEPLOYED.**
A versão viva no Supabase agora é a `v5` (deployed **11:43:47 UTC**, ~1h
depois do incidente) com `validateIban` a exigir `^PT\d{23}$` — formato
correto. Confirmado via MCP `get_edge_function`: o código deployed é
byte-a-byte igual ao ficheiro local `supabase/functions/register-partner/index.ts`.
Ninguém precisa de re-deployar nada aqui.

**App Flutter — corrigido no código-fonte, mas NÃO commitado nem builded.**
`lib/auth/auth_store.dart` e `lib/screens/register_partner_screen.dart` (+
`partner_login_screen.dart`) já têm, no working tree (não commitado):
- Nunca mais devolve `null` silencioso — toda falha do Edge Function chega
  ao ecrã com mensagem específica em PT ("A tua conta de acesso foi criada,
  mas houve um erro ao registar o estabelecimento. Contacta o suporte — não
  precisas de repetir o email/senha.").
- Deteta email duplicado explicitamente (`identities` vazio *e*
  `code == 'user_already_exists'`) e devolve `duplicatePartnerEmailMessage`
  claro, voltando o Stepper ao passo "Conta de Acesso".
- `resumePartnerRegistrationAsync()` novo: se o utilizador já está
  autenticado mas sem `restaurants`/`service_providers`, **não** tenta
  recriar a conta — só reenvia os dados do estabelecimento com a sessão
  atual. Fecha o loop de retry.
- `partner_login_screen.dart` deixa de rejeitar/deslogar quem não tem
  `restaurants` — encaminha para o wizard em modo retomada.

Esta é a mesma correção que resolve o bug provado nos logs. **Mas** este
código só existe no repositório — o APK/IPA que está instalado nos
dispositivos reais (e o que o utilizador usou às 10:43 UTC) ainda tem a
versão antiga do `auth_store.dart`. Padrão já visto neste projeto (ver
memória "Autocomplete Guarda = APK antigo"): o código muda, mas só chega ao
utilizador depois de um build de produção — que é item da Lista Vermelha.

## Sem push / sem build
Sem commit nem build nesta tarefa (fora do âmbito pedido; build de produção
é Lista Vermelha). O código já estava pronto no working tree antes desta
investigação (não é trabalho novo desta sessão) — só faltava confirmar a
causa raiz com prova de logs reais, o que ficou feito acima.

⚠️ Para o fix chegar a utilizadores reais falta: (1) commit destas
alterações, (2) novo build Android/iOS + submissão à loja. Ambos exigem
aprovação (push bloqueado por Lista Vermelha / build de produção).

---

**CADASTRO FALHA PARA TODOS: sim** (para qualquer submissão com IBAN real
preenchido — rejeição 100% determinística — e, de forma mais ampla, para
qualquer erro do Edge Function nesse passo final, cuja causa ficava sempre
escondida atrás de uma mensagem genérica e sem saída de retry) —
**causa: `validateIban` na Edge Function `register-partner` exigia formato
errado (PT+21 dígitos em vez de PT+23), combinado com `auth_store.dart` a
devolver `null` silencioso em qualquer falha do Edge Function e sem detetar
email duplicado no retry** — **corrigido: sim, no código e no backend**
(backend deployed e ativo em v5 desde 11:43:47 UTC, reconfirmado sem
nenhuma falha nova nos logs desde então; app Flutter corrigido **e
commitado** em `3c19043` nesta mesma sessão) — **falta só o build de
produção** (Android/iOS + submissão à loja) para o fix chegar aos
dispositivos reais dos utilizadores; isso é item da Lista Vermelha e
aguarda "vai" do Danilo.
