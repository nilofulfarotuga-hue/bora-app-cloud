# 🚦 APROVADOR-VERMELHO — Relatório FALLBACK 30MIN (2026-07-22, 3ª corrida, ~22:12 UTC)

Addendum ao mesmo dia (`aprovador-vermelho-2026-07-22-fallback30min.md` ~08:14 UTC e
`aprovador-vermelho-2026-07-22-fallback30min-2a-corrida.md` ~09:23 UTC). Gatilho recorrente: item
`nova` mais antigo reportado parado 1202+min (confirmado ao vivo: **1205 min**), `count=2`.

## Estado da fila confirmado ao vivo (22:12:26 UTC) — sem mudança face às corridas anteriores
| id | dedup_key | created_at | idade |
|---|---|---|---|
| `1efa3e60-10de-423c-97fb-8a21148de370` | `marcacoes:liberar-slots-orfãos-ttl` | 2026-07-22 02:07:13 | 1205 min |
| `47a4a9e6-07c7-4846-864a-e400064c9b0a` | `marcacoes:ttl-pending-payment` | 2026-07-22 06:07:13 | 965 min |

Ambos `status='nova'` (confirmado por SELECT direto). Evidência idêntica: `appointments.id =
7c61663d-ec39-48a2-83b4-5e4cc081794f`, `status='pending_payment'`, `deposit_status='pending'`,
`deposit_pi='pi_3TvmY8GlT3R2jCYp1thQswqy'` (PaymentIntent Stripe real, sem mudança). `proposta`
relida fresco: item 1 propõe automação para libertar slots de marcações órfãs (escrita nova sobre
status/agenda); item 2 propõe ajustar TTL para expirar `pending_payment` mais rápido (mesma
escrita). Nenhuma das duas traz prova de só-leitura.

## Triagem — sem mudança de veredito
- **Balde A: 0 itens.**
- **Balde B: 2 itens** — mesma família já reconhecida e reconfirmada em corridas anteriores
  (marcação órfã com PaymentIntent Stripe real emitido, `deposit_status='pending'`; propostas
  criam escrita nova sobre `deposit_cents`/`deposit_pi`/`deposit_status`/agenda — sem prova de
  só-leitura). Não re-derivado do zero; ver `permanente/procedural/aprovador-vermelho-triagem.md`.
  - `1efa3e60` — Libertar slots de marcações órfãs.
  - `47a4a9e6` — Ajustar TTL para marcações pendentes de pagamento.
  - ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram — reenviado (gap grande, não spam)
Último envio real registado em `admin_audit_log` para esta família: **2026-07-22 10:14:20 UTC**
(corrida anterior). Gap até agora (22:12:26 UTC) = **718 min** — muito acima do checkpoint de
~60 min → **reenviado** (não suprimido). Confirmado por output real via ponte SSH PC→VPS:
`Sent to telegram home channel (chat_id: 6731890157)`, exit 0.

## Auditoria (`admin_audit_log`, INSERT direto espelhando a RPC — `log_admin_action` exige
`auth.uid()` que o MCP não tem: `ERROR P0001 not authenticated` confirmado nesta corrida)
- id `6f1ddfe7-6d8f-49d4-a38e-3996da180492` — `robot_suggestion_baldeB_reconfirmado`,
  `entity_id=1efa3e60-10de-423c-97fb-8a21148de370`, `22:14:34 UTC`.
- id `699299e7-d229-49e0-8c3c-46f018ef05ae` — `robot_suggestion_baldeB_reconfirmado`,
  `entity_id=47a4a9e6-07c7-4846-864a-e400064c9b0a`, `22:14:34 UTC`.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA = true` (ligado, confirmado por SELECT direto) —
irrelevante nesta corrida (0 itens Balde A).

## Nenhuma alteração de lógica de dinheiro/dispatch/pricing. Nenhum `UPDATE` em `robot_suggestions`
(ambos os itens continuam `status='nova'`, aguardando decisão humana do Danilo). Nenhum commit/push.
