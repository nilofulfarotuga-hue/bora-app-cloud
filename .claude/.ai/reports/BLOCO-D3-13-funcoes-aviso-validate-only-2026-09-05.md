# BLOCO D3 — as 13 funções de aviso, tentativa de `validate_only` FCM

**Data:** 2026-09-05 · **Agente:** `notificacoes` · **Repo:** `C:\BoraLocal\projetosflutter\bora_app`

**Regra seguida à letra:** nenhuma notificação real foi enviada a ninguém nesta sessão.
Nenhum segredo de produção foi extraído. Nenhuma zona protegida foi tocada
(dispatch/pricing/Stripe/tokens/RLS financeira).

---

## 1. As 13 funções — confirmadas

```
supabase/functions/notify-admin-reimbursement
supabase/functions/notify-admin-urgent
supabase/functions/notify-chat-message
supabase/functions/notify-cleaner
supabase/functions/notify-client
supabase/functions/notify-driver
supabase/functions/notify-partner
supabase/functions/notify-partner-low-rating
supabase/functions/notify-purchase-finalized
supabase/functions/notify-service-provider
supabase/functions/notify-tvde-client
supabase/functions/notify-tvde-driver
supabase/functions/notify-washer
```

`ls supabase/functions | grep -iE "^notify-" | wc -l` → **13**. Bate certo com o
`B.2` do relatório de ontem (`TUDO-04-09-NOITE-2026-09-04.md`, linha 111): *"as 13
funções passadas por um validador mecânico contra a allowlist da FCM"*. É o mesmo
conjunto — não há função nova nem função desaparecida desde ontem.

## 2. `validate_only` — o que é possível de verdade nesta máquina

O pedido descrevia "modo de validação do Firebase **Admin SDK**". Isso não se aplica
literalmente aqui: nenhuma das 13 usa o `firebase-admin` (Node SDK) — confirmado por
`grep -L "firebase-admin"` nos 13 ficheiros → zero ocorrências. Todas são Edge
Functions Deno que fazem `fetch()` directo ao endpoint REST:

```
https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send
```

A boa notícia: a **API REST v1 da FCM também aceita `validate_only: true`** como campo
irmão de `message` no corpo do pedido — não é exclusivo do Admin SDK
(https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send).
Verificado por grep (`validate_only\s*:\s*true`) nos 13 ficheiros: **nenhuma das 13
passa esse campo hoje** — todas enviam sempre a sério quando alcançam o `fetch`.

Para provar `validate_only` **a valer** (chamada real à FCM, sem entrega) seria preciso
uma de duas coisas, e nenhuma foi feita:

- **(a)** Alterar as 13 funções para incluir `validate_only: true` e fazer deploy —
  mexer em código de produção de notificações só para um teste é desproporcional e
  fica fora do que foi pedido (isto é validação, não um pedido de mudança).
- **(b)** Extrair o segredo `FIREBASE_SERVICE_ACCOUNT` de produção e montar uma chamada
  externa manual à FCM — **recusado deliberadamente**: é uma credencial de produção e
  extraí-la para um script ad-hoc é exactamente o tipo de risco que a tarefa pediu para
  evitar.

Confirmado também que a via "correr localmente" não existe nesta máquina:

```
$ which supabase   → não encontrado
$ which deno       → não encontrado
$ find . -iname "*.env*" | xargs grep -l FIREBASE_SERVICE_ACCOUNT   → nenhum ficheiro
```

Sem Supabase CLI, sem Deno, sem o segredo em lado nenhum local — não há como correr
`supabase functions serve` nem invocar o handler directamente. Isto é a limitação
declarada, como o enunciado da tarefa previu ("se `validate_only` não for suportado...
explica a limitação").

## 3. O equivalente mais próximo usado: validação mecânica de schema

Como nenhuma chamada de rede real é possível sem um dos dois riscos acima, a validação
foi feita **estaticamente**: extraí o objecto JSON exacto que cada função monta antes do
`fetch()` e confirmei campo a campo contra o schema oficial da FCM HTTP v1
(`Message` / `AndroidConfig` / `AndroidNotification` / `ApnsConfig` / `Aps`). Isto
apanha a classe de erro mais comum que `validate_only` também apanharia — nome de campo
errado/typo — sem qualquer chamada de rede.

Primeira passagem foi automática (`.claude/.ai/tmp/validate_fcm_schema.py`, script
Python novo, stdlib only, zero rede). Deu **8 OK automático + 5 "erro"**. Todos os 5
"erros" foram investigados à mão e confirmados **falsos positivos do próprio parser**
— o mesmo tipo de falha que o validador de ontem teve (apanhar texto de comentário
como se fosse chave de objecto):

| Função | O parser apanhou | Realidade (lido à mão) |
|---|---|---|
| `notify-admin-urgent` | `Semnotificationaqui`, `dataonlynoiOS`, `igualaoAndroidcontent-available` | são pedaços de **comentários PT** dentro do bloco (`// Sem notification aqui:`, `// data-only no iOS: ... igual ao Android`), não chaves. Payload real: `android.priority`, `apns.payload.aps['content-available']` — válidos. |
| `notify-partner` | `isUrgent` dentro de `android.notification` e `apns.payload.aps` | é o operador de espalhamento condicional `...(isUrgent ? {...} : {})`, não uma chave literal. Campos reais por trás: `notification_priority`, `default_vibrate_timings`, `default_light_settings`, `visibility`, `interruption-level` — todos válidos. |
| `notify-tvde-client` | `dataOnly`, `DATAONLYtemdeserdataonlyaserio` | idem — ternário `...(dataOnly ? {} : {...})` + comentário PT. Campos reais: `notification` (condicional), `android.priority`, `android.notification.channel_id/sound`, `apns.*` — válidos. |
| `notify-admin-reimbursement` | (não extraiu nada — variável chama-se `payload`, não `message`) | lido à mão: `token`, `notification{title,body}`, `data{...}`, `android{priority, notification{channel_id, sound, tag, notification_priority}}`, `apns{headers, payload{aps{sound, badge, interruption-level:'critical'}}}` — todos válidos. |
| `notify-purchase-finalized` | idem (variável `payload`) | lido à mão: `token`, `notification{title,body}`, `data{type,order_id}`, `android{priority, notification{channel_id}}`, `apns{headers, payload{aps{sound,badge}}}` — válidos. |

Depois de corrigir manualmente os 5 falsos positivos, e de ler à mão `notify-cleaner` e
`notify-washer` (que usam um `baseMessage` partilhado com spread — o parser só via
`token`), e de fazer uma varredura adicional por nomes de campo mal escritos comuns
(`chanel_id`, `notifcation_priority`, `contentAvailable`, `apnsPriority`, etc. — zero
ocorrências nos 13 ficheiros):

## 4. Resultado — 13/13 estrutura válida

| # | Função | Status | Campos FCM v1 usados |
|---|---|---|---|
| 1 | `notify-admin-reimbursement` | ✅ válida | token, notification, data, android.notification{channel_id,sound,tag,notification_priority}, apns.aps{sound,badge,interruption-level} |
| 2 | `notify-admin-urgent` | ✅ válida | token, data, android{priority}, apns.aps{content-available} |
| 3 | `notify-chat-message` | ✅ válida | token, data, android, apns |
| 4 | `notify-cleaner` | ✅ válida | token, notification, data, android.notification{channel_id,sound}, apns.aps{sound,badge,content-available} |
| 5 | `notify-client` | ✅ válida | token, notification, data, android.notification{channel_id}, apns.aps{badge,content-available} |
| 6 | `notify-driver` | ✅ válida (+ prova real já existente) | token, notification, data, android.notification{channel_id,notification_priority:PRIORITY_MAX,default_sound}, apns.aps{content-available,interruption-level} |
| 7 | `notify-partner` | ✅ válida | token, notification, data, android.notification{channel_id,notification_priority,default_vibrate_timings,default_light_settings,visibility:PUBLIC}, apns.aps{sound,badge,content-available,interruption-level} |
| 8 | `notify-partner-low-rating` | ✅ válida | token, notification, data, android.notification{channel_id}, apns.aps{sound,badge,content-available} |
| 9 | `notify-purchase-finalized` | ✅ válida | token, notification, data, android.notification{channel_id}, apns.aps{sound,badge} |
| 10 | `notify-service-provider` | ✅ válida | token, notification, data, android.notification{channel_id,notification_priority}, apns.aps{badge} |
| 11 | `notify-tvde-client` | ✅ válida | token, notification (condicional dataOnly), data, android{priority,notification.channel_id}, apns.aps{sound,badge,content-available} |
| 12 | `notify-tvde-driver` | ✅ válida (4 pontos de envio no ficheiro, todos consistentes) | token, notification, data, android, apns.aps{content-available,interruption-level} |
| 13 | `notify-washer` | ✅ válida | token, data, android{priority}, apns.aps{content-available} |

**13 de 13 estruturalmente válidas.** Nenhum nome de campo, nenhum valor de enum
(`notification_priority`, `visibility`, `interruption-level`) fora do schema oficial da
FCM HTTP v1 em nenhuma das 13 funções.

Confirmação extra: o `B.1` de ontem (fix de `android.notification.priority` →
`android.notification.notification_priority: 'PRIORITY_MAX'` em `notify-driver`)
continua no código hoje (linha 228) — sem regressão.

## 5. `notify-driver` — não repetida

`notify-driver` já tinha prova de **envio real** confirmada pelo Danilo na sessão
anterior (`{"ok":true}`, versão v38 em produção). Repetir um envio real só para esta
tarefa dispararia uma notificação real a um estafeta sem necessidade — contra a regra
explícita da tarefa. Não foi repetida; a validação de schema acima cobre o código
actual (idêntico ao já provado).

## 6. Nenhuma das 12 restantes recebeu envio real

Consistente com a decisão já registada ontem em `B.3` do relatório anterior ("disparar
pushes reais para clientes, estafetas e parceiros às 23h para provar código que não
mudou faz mais mal que bem") — a mesma lógica aplica-se hoje. Nenhuma das 12 foi
invocada com um token real. `.claude/.ai/tmp/validate_fcm_schema.py` não faz nenhuma
chamada de rede (grep no próprio ficheiro confirma zero `fetch`/`http` — só leitura de
ficheiros locais e regex).

## 7. Limitação declarada (pedida explicitamente pelo enunciado)

`validate_only` real da FCM **não foi executado** para nenhuma das 13. Não há Deno nem
Supabase CLI nesta máquina, não há o segredo `FIREBASE_SERVICE_ACCOUNT` em lado nenhum
local, e extraí-lo de produção para montar uma chamada manual foi deliberadamente
evitado. O equivalente mais próximo — validação mecânica de schema campo-a-campo,
confirmada à mão contra falsos positivos do parser — foi o que se fez, e apanhou a
mesma classe de erro (nome de campo errado) que `validate_only` apanharia, sem
qualquer risco de entrega.

---

## Resumo

- **13/13** funções identificadas e confirmadas contra o relatório de ontem.
- **13/13** payloads FCM v1 estruturalmente válidos (schema completo, sem typos).
- **0** notificações reais enviadas nesta sessão.
- **0** segredos de produção extraídos.
- **0** zonas protegidas tocadas.
- `validate_only` real: **não executável** nesta máquina (sem Deno/Supabase CLI/
  segredo local) — limitação declarada, não escondida.
