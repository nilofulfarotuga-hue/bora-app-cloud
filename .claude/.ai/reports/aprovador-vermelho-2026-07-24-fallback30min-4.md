---
tema: aprovador-vermelho-relatorio · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-24
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-24, gatilho FALLBACK_30MIN, 6ª reconfirmação do lote)

## Gatilho
`FALLBACK_30MIN` — item `nova` mais antigo (`1efa3e60-10de-423c-97fb-8a21148de370`, criado
2026-07-22 02:07:13 UTC) parado 3240+ min sem decisão humana. Corrida às 2026-07-24 08:07:20 UTC.

## Fila `robot_suggestions` status='nova' (4 itens — todos já conhecidos, zero itens genuinamente novos)

Os 4 IDs batem exatamente com o lote `marcacoes:*` já triado 5x hoje (07:27:50, 07:39:28, 07:49:14
e 07:58:25 UTC). Confirmado por SELECT direto que os 4 continuam `status='nova'`, mesmos
`dedup_key`, mesmo `nivel`. Esta corrida é **pura reconfirmação** — nenhum item novo/diferente na
fila, nenhum ID fora dos 4 conhecidos.

| id | título | dedup_key | balde | motivo |
|---|---|---|---|---|
| `1efa3e60-10de-423c-97fb-8a21148de370` | Libertar slots de marcações órfãs | `marcacoes:liberar-slots-orfãos-ttl` | **B** | automatiza escrita/cancelamento sobre reservas com pré-pagamento Stripe real, sem regra de refund definida |
| `47a4a9e6-07c7-4846-864a-e400064c9b0a` | Ajustar TTL para marcações pendentes de pagamento | `marcacoes:ttl-pending-payment` | **B** | setting `reservation_pending_payment_ttl_minutes`, se acoplada a cron futuro, cancelaria reservas pagas sem regra de refund |
| `c068f901-e877-4df0-8b43-0ac1b1c04234` | Ajustar política de no-show para marcações | `marcacoes:ajustar-politica-no-show` | **B** | `deposit_required_threshold` = política nova de exigir depósito conforme taxa de no-show (dinheiro real, CLAUDE.md §5) |
| `7cf1a393-82b5-40d6-8738-7d300e73f85a` | Resolver marcações pendentes órfãs | `marcacoes:resolver-marcacoes-orfas` | **B** | `nivel=3` (o próprio maestro já classifica vermelho); pede cancelamento/reatribuição automática de marcação paga |

**Balde A: 0 itens.** Nenhum item de leitura/falso-positivo nesta fila.

## Verificação de prova fresca (não reanalisado do zero — só confirmado se mudou)
- `reservations.status='pending_payment'` → **0 linhas** (mesmo estado desde as corridas de
  07:27/07:39/07:49/07:58 UTC de hoje). Nenhuma prova nova.
- `platform_settings.aprovador_vermelho_auto_baldeA` = `true` (confirmado, irrelevante — 0 itens
  Balde A).
- Nenhum item novo na fila desde a corrida das 07:27:50 UTC; contagem `status='nova'` continua em 4.

## Telegram
**Suprimido.** Último envio real: 2026-07-24 07:27:50 UTC. Gap desde então até esta corrida
(08:07:20 UTC) = **~39,5 min < limiar de 60min**, e nenhuma prova nova (mesma evidência de
`reservations` vazia, mesmos 4 IDs, mesmos vereditos) — por protocolo, não reenviar.

## Auditoria
4 linhas gravadas em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`,
`entity_type='robot_suggestions'`, `reconfirmacao_numero=6`, `telegram_enviado=false`): ids
`ace48cf1-e6d2-4073-99ac-fea435b7e8f6` (`1efa3e60`), `a37b4726-aa5c-4144-b3d8-c83f6f8e4840`
(`47a4a9e6`), `1728f548-3321-4fa9-9e77-32d75e98c501` (`c068f901`),
`99a68b5f-3c95-4e6b-8c66-d2200a7e933f` (`7cf1a393`) — todas `created_at=2026-07-24 08:08:01.74984+00`.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **ligado** (confirmado ativo) — irrelevante
nesta corrida porque 0 itens caíram em Balde A.

## Nota operacional (não é nova — já documentada, só reforçada)
Gap de ~9min entre esta corrida (08:07 UTC) e a anterior (07:58 UTC) — dentro do mesmo padrão
curto (5-30min) já visto nas 5 corridas de hoje, em vez do 30→60→120→240min esperado pós-fix.
Reforça (não é achado novo) que o backoff exponencial do `hermes-aprovador-vermelho.sh` continua
sem deploy efetivo na VPS. Fora do mandato de roteamento deste agente — zero risco de dinheiro
(Balde B nunca promovido sozinho), só execução/ruído desperdiçados. Mesma recomendação já registada:
candidato a ordem para `maestro-autonomia` ou o Danilo (reimplementar via `git show
e4444a4:.claude/scripts/hermes-aprovador-vermelho.sh` + deploy manual à VPS).

## Handoff
Nenhum facto novo a consolidar — a memória (`permanente/procedural/aprovador-vermelho-triagem.md`
+ `aprovador-vermelho-historico-corridas.md`) já reflete os 4 itens desta fila e a anomalia de
backoff. Sem handoff ao `bibliotecario-cerebro` nesta corrida.
