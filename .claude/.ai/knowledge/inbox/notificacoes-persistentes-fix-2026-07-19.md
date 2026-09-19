---
id: notificacoes-persistentes-fix-2026-07-19
tema: notificacoes
tipo: relatorio-inbox
estado: aberta
data: 2026-07-19
agente: ceo-ai + notificacoes
ficheiro: lib/services/notification_service.dart
---

# Notificações persistentes — FIX 1 (TVDE oferta) + FIX 2 (categorias sem tratamento)

**Sintoma (confirmado ao vivo pelo Danilo):** a notificação chega mas desaparece
sozinha — não fica presa no ecrã até o utilizador tocar. Em foreground algumas nem
apareciam (só tocava o beep do catch-all `_sound.playOnce()`).

**Causa raiz:** dois padrões no ficheiro. O CORRETO (delivery estafeta/parceiro) usa
`ongoing:true + autoCancel:false`; o QUEBRADO ou não tinha esses flags, ou não tinha
tratamento nenhum — caía no auto-display nativo do Android (não-persistente) ou no
som silencioso em foreground.

> Nota de contexto: o grosso desta correção já estava na working tree (204 inserções
> não-commitadas — a ordem morreu 5× no loop autónomo por "saída-vazia" antes de
> commitar). Esta sessão interativa **verificou, completou os 2 buracos que faltavam,
> validou (`flutter analyze` limpo) e fechou** (commit + push + relatório).

---

## FIX 1 — TVDE oferta de corrida pro motorista (DOIS locais) ✅

Padrão replicado do delivery (`postWakeActivityNotification`): `ongoing:true`,
`autoCancel:false`, canal `bora_orders_urgent_v3`, `fullScreenIntent:true`.

| Local | Antes | Depois |
|---|---|---|
| `_firebaseMessagingBackgroundHandler` bloco `new_tvde_ride_offer` (~L207-271) | `fullScreenIntent:true` + `autoCancel:true`, SEM `ongoing` | `ongoing:true` + `autoCancel:false` + `timeoutAfter:45000` (limpa ~ao fim do TTL se ignorada) + `FLAG_INSISTENT` (som em loop) |
| `_showTvdeOfferNotification` foreground (~L1903-1958) | `fullScreenIntent:true`, SEM `ongoing`/`autoCancel:false` | `ongoing:true` + `autoCancel:false` |

Resultado: a oferta de corrida fica presa (som + ecrã aceso) até o motorista tocar,
igual à oferta de entrega.

---

## FIX 2 — categorias sem tratamento (dispatcher persistente único) ✅

Criado `_kPersistentCategoryTypes` (Set) + `_showPersistentCategoryNotification`
(switch por tipo) + `_showPersistentStatusNotification` (notif local genérica
`ongoing:true`/`autoCancel:false` + `BigTextStyleInformation` título+corpo do payload).
Ligado nos DOIS caminhos: handler BG (`_firebaseMessagingBackgroundHandler`) e listener
FG (`onMessage.listen`). Canal: `bora_orders_urgent_v3` para ofertas (som em loop),
`bora_orders` (importance high, sem loop) para os estados/informativos.

| Categoria | Canal | Persistente | Notas |
|---|---|---|---|
| `tvde_ride_status` | bora_orders | ✅ | id = rideId; título/corpo do payload |
| `cleaning_offer` | bora_orders_urgent_v3 (urgente) | ✅ | oferta = som em loop |
| `cleaning_status` | bora_orders | ✅ | estado da limpeza |
| `tvde_chat` | bora_orders | ✅ | **adicionado nesta sessão** — antes silencioso; nome do remetente no título |
| `admin_generic` | bora_orders | ✅ | route → /admin |
| `crosstalk_critical` | bora_orders | ✅ | route → /admin |
| `appointment_new` | bora_orders | ✅ | id = appointmentId |
| `low_rating` | bora_orders | ✅ | id = rating_id |
| `purchase_finalized` | bora_orders | ✅ | id = order_id |
| `admin_reimbursement` / `reimbursement` | bora_orders | ✅ | **alias `reimbursement` adicionado nesta sessão** (defensivo caso o backend envie o nome curto) |

### O que esta sessão acrescentou (2 buracos vs. a lista da ordem)
1. **`tvde_chat`** — a ordem listou-o, mas não estava no Set nem no switch → mensagem de
   chat da corrida caía no beep silencioso. Agora mostra notif persistente com o nome do
   remetente. (Nota: o tap abre a app na home via `_onLocalNotifTap`; não faz deep-link
   à thread específica — melhoria futura, mas já não é silencioso.)
2. **`reimbursement`** — a ordem nomeou `reimbursement`; o código só tinha
   `admin_reimbursement`. Adicionado como alias no Set e no switch (cobre ambos os nomes
   sem depender de saber exatamente o que o backend emite).

---

## Verificação
- `flutter analyze lib/services/notification_service.dart` → **No issues found!** (119.5s)
- Ordem de dispatch confirmada nos dois handlers: `tvde_chat` só casa com o Set
  persistente (não colide com os ramos `chat` / `new_tvde_ride_offer` anteriores).

## O que ficou por tratar / a confirmar
- **Deep-link do tap** para as categorias de estado (tvde_ride_status, cleaning_*,
  tvde_chat, appointment_new, etc.): hoje o tap só abre a app na home (`launchApp('/')`).
  Suficiente para "deixar de ser silencioso/efémero"; abrir o ecrã exato é melhoria futura.
- **Nome exato do tipo emitido pelo backend** para `reimbursement`/`admin_reimbursement`:
  cobrimos os dois no cliente por segurança, mas convém confirmar via MCP qual a Edge
  Function realmente envia (não foi tocado — backend já corrigido via MCP conforme a ordem).
- Não se mexeu no padrão que já funciona (delivery estafeta/parceiro) — só se replicou.
- Não se tocou em backend / Edge Functions nem se inventaram canais novos.

## Fecho
- Commit + `git push origin autonomous-night-2026-04-29`. CI faz o bump do versionCode
  (pubspec NÃO tocado).
