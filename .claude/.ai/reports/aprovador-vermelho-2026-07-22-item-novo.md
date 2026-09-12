# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-22, gatilho item-novo)

Watermark: newest=2026-07-22T10:07:15.073246+00:00 · count=3 (confirmado por SELECT direto em
`robot_suggestions status='nova'`, project `ojykpzwqrtusfeakzrna`).

## Balde A (leitura/falso-positivo) — recomendo aprovar
Nenhum. Os 3 itens da fila caem em Balde B (ver motivos abaixo).

## Balde B (dinheiro real — precisa de ti)

- **`1efa3e60-10de-423c-97fb-8a21148de370`** — "Libertar slots de marcações órfãs"
  (`dedup_key: marcacoes:liberar-slots-orfãos-ttl`, nível 2, severidade 4, criado 2026-07-22 02:07 UTC)
  faz: propõe INSERT em `platform_settings` de uma chave nova `reservation_orphan_pending_ttl_minutes=15`
  (ainda não existe na tabela nem é lida por nenhum código/migration hoje — confirmado por grep no
  repo). risco: a chave não é inerte por acaso — está na mesma família funcional da RPC
  `cancel_orphan_reservation` (`supabase/migrations/20260515100002_cancel_orphan_reservation.sql`),
  que **é chamada pelo stripe-webhook v24** quando o PaymentIntent do pré-pagamento €3 falha/cancela.
  Ativar este TTL implica decidir o ciclo de vida de reservas com pré-pagamento pendente — zona de
  dinheiro, não simples config de agenda.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`47a4a9e6-07c7-4846-864a-e400064c9b0a`** — "Ajustar TTL para marcações pendentes de pagamento"
  (`dedup_key: marcacoes:ttl-pending-payment`, nível 2, severidade 3, criado 2026-07-22 06:07 UTC)
  faz: propõe INSERT em `platform_settings` de `reservation_pending_payment_ttl_minutes=15` (mesma
  família do item acima, mesma reserva órfã citada como evidência: `7c61663d-ec39-...`). risco:
  idêntico ao item anterior — pré-pagamento/reserva, adjacente ao stripe-webhook.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`2be7732c-49f8-4d97-a6d4-8a7759c72cc0`** — "Otimizar queries de cron jobs lentas"
  (`dedup_key: performance:cron-queries-lentas`, nível 3, severidade 3, criado 2026-07-22 10:07 UTC)
  faz: pede otimização de 3 funções cron: `_cron_check_orphan_orders()` (Balde A confirmado — só
  SELECT+notify), `_cron_check_ghost_drivers()` (Balde A confirmado — idem), e
  `_appointment_cron_auto_no_show()` (**Balde B sempre**, confirmado em corridas anteriores — decide
  reter ou não o sinal/`deposit_status` do cliente). risco: regra já estabelecida
  (`aprovador-vermelho-triagem.md`, "Regra de item agrupado") — quando 1 linha da fila agrupa
  funções mistas, o item INTEIRO cai em Balde B; não há aprovação parcial de 2/3 funções.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Encaminhamento ao Danilo
Telegram enviado com sucesso (ponte SSH PC→VPS, `id_ed25519_vps` acessível nesta sessão):
`Sent to telegram home channel (chat_id: 6731890157)`. Mensagem cobriu os 3 IDs acima com motivo
resumido. Nenhum item pendente de canal alternativo.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA = true` (ligado) — confirmado por SELECT, mas
**irrelevante nesta corrida**: nenhum item classificou como Balde A, logo nada foi auto-aprovado
via `robot_emerson_decide`.

## O que MUDEI vs. o que NÃO mudei
- MUDEI: 3 linhas em `admin_audit_log` (auditoria da triagem — `robot_suggestion_baldeB_surfaced`,
  `telegram_enviado:true`, 1 por item). Nada em `robot_suggestions.status` (continuam `nova` —
  decisão fica com o Danilo). Nenhuma migration, RPC, `platform_settings` ou código de negócio
  tocado.
- NÃO mudei: `pricing_service`, `dispatch_engine`, `finalizePurchase`, `bora_tokens`, Stripe/webhook,
  RLS de orders/wallets/ledger, nem as chaves `reservation_*_ttl_minutes` propostas.

## Tabelas/ficheiros tocados
- `robot_suggestions` (SELECT apenas, projeto `ojykpzwqrtusfeakzrna`)
- `platform_settings` (SELECT apenas — confirmação do flag + inexistência das chaves propostas)
- `admin_audit_log` (INSERT — 3 registos de auditoria)
- `supabase/migrations/20260515100002_cancel_orphan_reservation.sql` (leitura, para prova positiva)
- `.claude/.ai/reports/aprovador-vermelho-2026-07-22-item-novo.md` (este relatório)
