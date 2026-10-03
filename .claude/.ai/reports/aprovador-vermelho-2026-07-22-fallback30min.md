# 🚦 APROVADOR-VERMELHO — Relatório FALLBACK 30MIN (2026-07-22, ~08:14 UTC)

## Gatilho
`FALLBACK 30MIN`: item mais antigo da fila `robot_suggestions` (status='nova') parado 366+ min
(desde 2026-07-22 02:07:13 UTC). Triagem completa de toda a fila `nova` disparada.

## Estado da fila no momento da triagem
2 itens em `status='nova'`, ordenados por `created_at`:

| id | created_at | categoria | nível | título |
|---|---|---|---|---|
| `1efa3e60-10de-423c-97fb-8a21148de370` | 2026-07-22 02:07:13 UTC | marcacoes | 2 | Libertar slots de marcações órfãs |
| `47a4a9e6-07c7-4846-864a-e400064c9b0a` | 2026-07-22 06:07:13 UTC | marcacoes | 2 | Ajustar TTL para marcações pendentes de pagamento |

Flag `platform_settings.aprovador_vermelho_auto_baldeA = true` (confirmada por SELECT direto antes
da triagem) — mas ambos os itens caem em Balde B, então a flag não se aplica nesta corrida.

## Triagem

### Balde A — 0 itens
Nenhum.

### Balde B — 2 itens (sempre humano)

**1) `1efa3e60-10de-423c-97fb-8a21148de370` — "Libertar slots de marcações órfãs"**
- Faz: cria automação de escrita nova sobre `appointments` (status/deposit_status) para libertar
  slots de marcações `pending_payment` que expiraram, motivada pelo agendamento órfão
  `7c61663d-ec39-48a2-83b4-5e4cc081794f` (status `pending_payment`, `deposit_status='pending'`,
  `deposit_pi='pi_3TvmY8GlT3R2jCYp1thQswqy'` — PaymentIntent Stripe já emitido, confirmado por
  SELECT direto na tabela `appointments`).
- Risco: sem prova positiva de "só leitura" (a escrita ainda não existe no código — não há função
  cron equivalente hoje, confirmado por `pg_proc`); risco de dessincronizar o cancelamento local
  com o estado real no Stripe (o PI já existe e pode estar `succeeded`/`processing` do lado Stripe
  no momento em que a automação "liberta" o slot localmente).
- Status: **RECONFIRMADO** (já triado 2026-07-22 05:50:47 UTC pela mesma razão, `admin_audit_log`
  id `55213561-43b9-440a-8d71-3b17eebe0a1d`). Gap desde o último Telegram: **143 min** — acima da
  janela de supressão de ~60 min → Telegram **reenviado** (não suprimido).
- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

**2) `47a4a9e6-07c7-4846-864a-e400064c9b0a` — "Ajustar TTL para marcações pendentes de pagamento"**
- Faz: propõe reduzir/ajustar o TTL de `appointments.status='pending_payment'` para expirar mais
  depressa e libertar o slot — motivada pela **mesma** marcação órfã `7c61663d-ec39-48a2-83b4-
  5e4cc081794f` (mesmo `deposit_pi` Stripe já emitido).
- Risco: 1ª ocorrência analisada do zero. Verificado via `pg_proc` (busca por `pending_payment` e
  `appointment%ttl/expir/cron`) que **não existe hoje nenhuma função cron** que trate expiração de
  `pending_payment` — só `_appointment_cron_auto_no_show` (trata `confirmed`→`no_show`, já Balde B
  conhecido) e os 2 crons de lembrete (`_appointment_cron_send_reminders_24h/2h`, sem escrita
  financeira). Esta proposta cria uma automação de escrita **nova** sobre `appointments.status` /
  `deposit_status`, mesma família de risco Stripe-PI-já-emitido do item 1. Sem prova de
  somente-leitura → **Balde B pela regra de dúvida**.
- Status: **NOVO** — 1ª vez na fila (`dedup_key marcacoes:ttl-pending-payment`, distinto de
  `marcacoes:liberar-slots-orfãos-ttl`). Telegram **enviado** (nunca notificado antes).
- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram
Enviado com sucesso via ponte SSH PC→VPS (`docker exec ... hermes send -t telegram`), confirmado
por output real `Sent to telegram home channel (chat_id: 6731890157)`. Mensagem única cobrindo os
2 itens (reconfirmação do item 1 + primeira notificação do item 2).

## Auditoria (`admin_audit_log`, via UPDATE/INSERT direto — MCP sem JWT admin para RPC)
- `9b2159d1-27ca-46ba-8913-cbbe79942cf9` — `robot_suggestion_baldeB_reconfirmado` (item 1)
- `34717260-f60d-4532-a2b4-74bb9dd6d64b` — `robot_suggestion_baldeB_surfaced` (item 2)

## Auto-Balde-A
`DESLIGADO` para esta corrida (não aplicável — 0 itens caíram em Balde A).
`platform_settings.aprovador_vermelho_auto_baldeA = true` (ligado globalmente, confirmado).

## Nenhuma alteração de lógica de dinheiro/dispatch/pricing foi feita. Nenhum commit/push.
