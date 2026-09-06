# 🚦 APROVADOR-VERMELHO — Relatório FALLBACK 30MIN (2026-07-22, 2ª corrida, ~09:23 UTC)

Addendum ao relatório anterior do mesmo dia (`aprovador-vermelho-2026-07-22-fallback30min.md`,
~08:14 UTC). Gatilho recorrente: item `nova` mais antigo parado 432+min reportado (confirmado ao
vivo: 435 min), `count=2`.

## Estado da fila confirmado ao vivo (09:23 UTC) — sem mudança face à corrida anterior
| id | dedup_key | created_at | idade |
|---|---|---|---|
| `1efa3e60-10de-423c-97fb-8a21148de370` | `marcacoes:liberar-slots-orfãos-ttl` | 2026-07-22 02:07:13 | 435 min |
| `47a4a9e6-07c7-4846-864a-e400064c9b0a` | `marcacoes:ttl-pending-payment` | 2026-07-22 06:07:13 | 195 min |

Ambos `status='nova'` (confirmado por SELECT direto). Evidência idêntica: `appointments.id =
7c61663d-ec39-48a2-83b4-5e4cc081794f`, `status='pending_payment'`, `deposit_status='pending'`,
`deposit_pi='pi_3TvmY8GlT3R2jCYp1thQswqy'` (PaymentIntent Stripe real, sem mudança).

## Triagem — sem mudança de veredito
- **Balde A: 0 itens.**
- **Balde B: 2 itens** — mesma família já reconhecida (marcação órfã com PaymentIntent Stripe real
  emitido, `deposit_status='pending'`; propostas criam escrita nova sobre
  `deposit_cents`/`deposit_pi`/`deposit_status` — sem prova de só-leitura). Não re-derivado do zero;
  ver `permanente/procedural/aprovador-vermelho-triagem.md`.
  - `1efa3e60` — Libertar slots de marcações órfãs.
  - `47a4a9e6` — Ajustar TTL para marcações pendentes de pagamento.
  - ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram — reenviado (checkpoint periódico, não spam)
Último envio real registado em `admin_audit_log` para ambos os ids: **08:15:07 UTC** (corrida
anterior do mesmo dia). Gap até agora (09:23:18 UTC) = **68 min** — acima do checkpoint periódico
(~60 min) usado nesta família em corridas passadas → **reenviado** (não suprimido). Confirmado por
output real: `Sent to telegram home channel (chat_id: 6731890157)`, exit 0.

## Auditoria (`admin_audit_log`, via `log_admin_action` — RPC SECURITY DEFINER, MCP sem JWT admin
para `robot_approve_plan`/`robot_reject_suggestion`)
- ação `robot_suggestion_baldeB_reconfirmado`, `entity_type='robot_suggestions'`,
  `entity_id='1efa3e60-10de-423c-97fb-8a21148de370'`.
- ação `robot_suggestion_baldeB_reconfirmado`, `entity_type='robot_suggestions'`,
  `entity_id='47a4a9e6-07c7-4846-864a-e400064c9b0a'`.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA = true` (ligado, confirmado por SELECT direto) —
irrelevante nesta corrida (0 itens Balde A).

## Nenhuma alteração de lógica de dinheiro/dispatch/pricing. Nenhum `UPDATE` em `robot_suggestions`
(ambos os itens continuam `status='nova'`, aguardando decisão humana do Danilo). Nenhum commit/push.
