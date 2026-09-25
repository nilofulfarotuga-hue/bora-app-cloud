# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-23, gatilho FALLBACK 30MIN)

## Gatilho
`hermes-aprovador-vermelho.sh` reportou: item `nova` mais antigo parado **1892+ minutos**
(~31.5h), `count=2`. Corre triagem completa sobre TODA a fila `nova`, independente do watermark.

## Fila real (SELECT direto, `robot_suggestions WHERE status='nova' ORDER BY created_at`)

| id | título | dedup_key | categoria | criado (UTC) | parado há |
|---|---|---|---|---|---|
| `1efa3e60-10de-423c-97fb-8a21148de370` | Libertar slots de marcações órfãs | `marcacoes:liberar-slots-orfãos-ttl` | marcacoes | 2026-07-22 02:07:13 | ~1d 07h34m |
| `47a4a9e6-07c7-4846-864a-e400064c9b0a` | Ajustar TTL para marcações pendentes de pagamento | `marcacoes:ttl-pending-payment` | marcacoes | 2026-07-22 06:07:13 | ~1d 03h34m |

Ambos os itens já eram conhecidos desta base de conhecimento como família Balde B recorrente
(`aprovador-vermelho-triagem.md` / histórico) — **não são genuinamente novos** (1ª surfaçagem foi
2026-07-22 10:14:20 UTC, `admin_audit_log` ids `3b563ca5-b1b3-4554-815c-9f3551d12280` /
`5a9d70f2-9013-47e9-94ba-99394df8f5e2`; 2ª reconfirmação 2026-07-22 22:14:34 UTC, ids
`6f1ddfe7-6d8f-49d4-a38e-3996da180492` / `699299e7-d229-49e0-8c3c-46f018ef05ae`). Esta corrida é a
**3ª reconfirmação** de ambos.

## Prova positiva revisitada (mesma marcação subjacente, 7c61663d)
`SELECT` direto em `appointments WHERE id='7c61663d-ec39-48a2-83b4-5e4cc081794f'`:
- `status = 'pending_payment'`
- `deposit_cents = 300` (depósito €3 de reserva)
- `deposit_pi = 'pi_3TvmY8GlT3R2jCYp1thQswqy'` (PaymentIntent Stripe **real**, já emitido)
- `deposit_status = 'pending'`
- `scheduled_at = 2026-07-23 12:30:00 UTC`

Confirmado também: **não existe** hoje nenhuma função `pg_proc` de TTL/expiração automática para
`appointments.status='pending_payment'` (`SELECT proname FROM pg_proc WHERE proname ILIKE
'%appointment%ttl%' OR ILIKE '%appointment%expire%'` → 0 linhas) — ambas as propostas pedem a
**criação** de um mecanismo de escrita novo (liberar slot / mudar TTL) sobre um registo com
depósito Stripe real pendente.

## Classificação — Balde B (ambos, sem mudança)
- **`1efa3e60` (Libertar slots de marcações órfãs):** proposta escreve em
  `appointments.status`/`deposit_status` para liberar automaticamente o slot — decide o destino
  de um depósito Stripe real (mesma família de `_appointment_cron_auto_no_show`, que já decide
  reter/não reter `deposit_status`). Sem prova de só-leitura.
- **`47a4a9e6` (Ajustar TTL para marcações pendentes de pagamento):** proposta cria/edita lógica de
  TTL que decide quando um depósito Stripe pendente expira — mesma zona protegida (ciclo de vida
  do pré-pagamento de reservas, ligado ao `stripe-webhook`).

**Nenhum dos dois cai em Balde A** — ambos são escrita nova sobre dinheiro real (depósito Stripe),
não leitura/diagnóstico. Regra de dúvida não se aplica aqui porque a dúvida já foi resolvida a
favor de Balde B nas corridas anteriores, com a mesma prova ainda válida.

## Ações desta corrida
1. `admin_audit_log` — 2 novos registos `robot_suggestion_baldeB_reconfirmado`
   (`reconfirmacao_numero=3`): id `a7cfe49e-ab0b-4f5e-9aa0-ec37be24afd0` (`1efa3e60`, 09:44:00 UTC)
   e id `176fe836-7f8c-43c9-8285-d78038d8ad2e` (`47a4a9e6`, 09:44:04 UTC).
2. **Telegram reenviado** (bridge SSH PC→VPS, `id_ed25519_vps` →
   `hermes-agent-fvnc-hermes-agent-1`): `Sent to telegram home channel (chat_id: 6731890157)`,
   exit 0. Gap desde o último envio real (2026-07-22 22:14:34 UTC) = **~11h29m (689 min)**, acima
   do limiar de ~60 min já usado nesta família para não suprimir — reenvio justificado.
3. `platform_settings.aprovador_vermelho_auto_baldeA = true` reconfirmado (SELECT direto) — sem
   efeito prático, 0 itens Balde A na fila.
4. Nenhuma alteração de código, migration, RPC ou lógica de dinheiro. Só roteamento/auditoria
   (UPDATE nenhum feito — `status` de ambos os itens continua `'nova'`, propositalmente).

## Resumo
```
🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-23, FALLBACK 30MIN)
   Balde A (leitura/falso-positivo) — recomendo aprovar:
     • (nenhum item nesta corrida)
   Balde B (dinheiro real — precisa de ti):
     • 1efa3e60 — faz: liberar automaticamente slot de marcação órfã | risco: decide destino de
       depósito Stripe real (pi_3TvmY8GlT3R2jCYp1thQswqy) sem humano
       ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
     • 47a4a9e6 — faz: ajustar TTL de marcações pending_payment | risco: muda quando um depósito
       Stripe pendente expira, mesma marcação 7c61663d
       ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
   Auto-Balde-A: ligado (platform_settings.aprovador_vermelho_auto_baldeA=true) — sem efeito, 0
   itens Balde A na fila.
```

## Handoff
`bibliotecario-cerebro` — escopo `agente:aprovador-vermelho`. Nada de novo a gravar como
conhecimento durável (mesma família já documentada); só actualizar o log de corridas com esta
3ª reconfirmação (2026-07-23, gap Telegram 689min, ids de auditoria acima) se o histórico ainda
não a tiver.
