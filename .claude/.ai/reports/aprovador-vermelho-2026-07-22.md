---
tema: aprovador-vermelho · corrida: FALLBACK 30MIN · data: 2026-07-22
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-22)

**Gatilho:** FALLBACK 30MIN do watchdog — item `nova` mais antigo reportado parado 212+ minutos,
`count=1`. Confirmado por SELECT direto: `robot_suggestions WHERE status='nova'` tem exatamente
**1 item** — nenhum acúmulo escondido, é um item genuinamente **novo** (nunca visto em corridas
anteriores; `admin_audit_log` sem nenhuma entrada prévia para este id/dedup_key).

## Fila lida (status='nova')

| id | dedup_key | categoria | nível | criado | minutos parado |
|---|---|---|---|---|---|
| `1efa3e60-10de-423c-97fb-8a21148de370` | `marcacoes:liberar-slots-orfãos-ttl` | `marcacoes` | 2 | 2026-07-22 02:07:13 UTC | ~218min |

**Título:** "Libertar slots de marcações órfãs". **Proposta:** "Uma marcação pendente de pagamento
está órfã, bloqueando um slot na agenda... o sistema deve libertar automaticamente slots de
marcações pendentes que expiram." **Evidência:** `appointments.id = 7c61663d-ec39-48a2-83b4-5e4cc081794f`.

## Investigação (prova positiva, obrigatória antes de classificar)

Consultei o registo de evidência diretamente:
- `status='pending_payment'`, `deposit_status='pending'`, `deposit_cents=300`.
- **`deposit_pi = 'pi_3TvmY8GlT3R2jCYp1thQswqy'`** — já existe um PaymentIntent Stripe real associado
  a esta marcação, mesmo com `deposit_status` local ainda em `pending` (nunca confirmado como pago
  no nosso lado).
- `scheduled_at = 2026-07-23 12:30:00 UTC` (marcação futura, ainda não aconteceu), `created_at =
  2026-07-21 22:54:07 UTC` — ou seja, mais de 24h com o slot preso porque o cliente nunca completou
  a confirmação de pagamento (`client_confirm_appointment_payment`).
- Não existe ainda nenhuma função no banco (`pg_proc`) que implemente esta liberação automática —
  a proposta é **criar uma automação de escrita nova**, não uma auditoria de código existente. Por
  isso não há `pg_get_functiondef` para provar "só SELECT/notify" — a prova positiva exigida pelo
  protocolo (Balde A só com confirmação de que não há escrita) **não pode ser dada** aqui, porque a
  própria proposta É uma escrita (`UPDATE appointments SET status=... `) sobre uma tabela com
  `deposit_cents`/`deposit_pi`/`deposit_status`.

## Triagem

### Balde A (leitura/falso-positivo) — nenhum item nesta corrida
0 itens.

### Balde B (dinheiro real — precisa do Danilo)

- **`1efa3e60-10de-423c-97fb-8a21148de370`** — "Libertar slots de marcações órfãs"
  **Faz:** cron novo que cancelaria/expiraria automaticamente marcações em `pending_payment`
  paradas há muito tempo, para libertar o slot na agenda.
  **Risco:** a marcação de evidência já tem um `deposit_pi` (PaymentIntent Stripe) emitido — o
  webhook pode ainda confirmar o pagamento mais tarde (race condition), e cancelar o slot
  automaticamente sem checar o estado real no Stripe pode dessincronizar cobrança vs disponibilidade
  (cliente cobrado depois de o slot já ter sido dado a outra pessoa, ou vice-versa). Toca
  `deposit_status`, o mesmo campo que a família `_appointment_cron_auto_no_show` já usa e que está
  sempre classificado como Balde B por decisão anterior — sem prova positiva de somente-leitura,
  qualquer dúvida desce para Balde B por regra do protocolo.

  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

  **Ação tomada:** encaminhado ao Danilo via Telegram (ponte SSH PC→VPS,
  `ssh -i /c/Users/danil/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud` →
  `docker exec -u hermes -i hermes-agent-fvnc-hermes-agent-1 hermes send -t telegram`), confirmado
  por output real `Sent to telegram home channel (chat_id: 6731890157)`, exit 0. Registado em
  `admin_audit_log` (`action='robot_suggestion_baldeB_surfaced'`, id
  `55213561-43b9-440a-8d71-3b17eebe0a1d`, `created_at=2026-07-22 05:50:47.92884 UTC`, confirmado por
  `RETURNING` real). `status` do item **não alterado** (continua `nova`).

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado, confirmado por SELECT
antes da triagem) — sem efeito prático nesta corrida (0 itens Balde A na fila).

## Anti-spam Telegram
**Não suprimido** — primeira ocorrência genuína deste id/dedup_key (nunca notificado antes; sem
entradas prévias em `admin_audit_log` para `marcacoes:liberar-slots-orfãos-ttl` ou para este id).
Regra (a) do protocolo aplica-se: item genuinamente novo → envia.

## Resumo
- Itens na fila `status='nova'`: **1**.
- Balde A auto-aprovados: **0**.
- Balde B encaminhados: **1** — `1efa3e60-10de-423c-97fb-8a21148de370` ("Libertar slots de
  marcações órfãs"), motivo: escrita nova sobre `appointments` com PaymentIntent Stripe já
  associado, sem prova positiva de somente-leitura.
- Telegram: **enviado** (confirmado, não suprimido).
- Nenhuma lógica de dinheiro, dispatch, pricing ou migration foi tocada ou aplicada.
