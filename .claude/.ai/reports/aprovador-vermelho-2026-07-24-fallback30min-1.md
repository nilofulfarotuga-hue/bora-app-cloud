---
tema: aprovador-vermelho-relatorio · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-24
---

# 🚦 APROVADOR-VERMELHO — TRIAGEM DA FILA 🔴 (2026-07-24, gatilho FALLBACK_30MIN)

**Motivo do disparo:** item mais antigo em `status='nova'` parado ≥3192 min (~53h) sem triagem —
gatilho independente do watermark, conforme rede de segurança de 30 min (ver agent card).
Estado real confirmado via `execute_sql` direto em `ojykpzwqrtusfeakzrna` (não assumido de memória).

## Fila `robot_suggestions` status='nova' no momento da corrida (4 itens)

| # | id | dedup_key | criado em (UTC) | minutos parado |
|---|---|---|---|---|
| 1 | `1efa3e60-10de-423c-97fb-8a21148de370` | `marcacoes:liberar-slots-orfãos-ttl` | 2026-07-22 02:07:13 | ~3195 |
| 2 | `47a4a9e6-07c7-4846-864a-e400064c9b0a` | `marcacoes:ttl-pending-payment` | 2026-07-22 06:07:13 | ~2955 |
| 3 | `c068f901-e877-4df0-8b43-0ac1b1c04234` | `marcacoes:ajustar-politica-no-show` | 2026-07-24 04:07:14 | ~195 |
| 4 | `7cf1a393-82b5-40d6-8738-7d300e73f85a` | `marcacoes:resolver-marcacoes-orfas` | 2026-07-24 05:07:16 | ~135 |

Itens 3 e 4 têm `dedup_key` **nunca visto antes** — analisados do zero (prova real via
`information_schema`, `pg_proc`, `cron.job`, `platform_settings`), não herdaram veredito por
categoria parecida.

## Balde A (leitura/falso-positivo) — recomendo aprovar
**Nenhum.** Os 4 itens desta corrida caem em Balde B.

## Balde B (dinheiro real — precisa do Danilo)

### 1) `1efa3e60` — Libertar slots de marcações órfãs [reconfirmado]
- **Faz:** `update_setting reservation_orphan_pending_ttl_minutes=15`.
- **Risco:** automatiza a libertação/write de reservas com pré-pagamento Stripe real
  (`reservations.prepayment_pi`), sem regra de refund definida no payload.
- **PROVA NOVA nesta corrida:** a reserva órfã original `7c61663d-ec39-48a2-83b4-5e4cc081794f`
  (com `prepayment_pi` real `pi_3TvmY8GlT3R2jCYp1thQswqy`, €3) **já não existe** em `reservations`
  (SELECT direto = 0 linhas) e **zero** reservas estão hoje com `status='pending_payment'`. O
  incidente concreto resolveu-se sozinho (provável `cancel_orphan_reservation()` acionada por
  webhook, ou ação manual) — não achado nenhum cron ativo que consuma esta setting hoje.
  Isto **não promove** o item a Balde A: a proposta continua a ser sobre automatizar
  escrita/cancelamento de reservas pagas, o que é dinheiro real por natureza.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

### 2) `47a4a9e6` — Ajustar TTL para marcações pendentes de pagamento [reconfirmado]
- **Faz:** `update_setting reservation_pending_payment_ttl_minutes=15`.
- **Risco:** mesma família do item 1 (praticamente duplicado — dedup por título, não por chave).
  Mesma prova nova (reserva órfã resolvida, zero pending_payment hoje).
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

### 3) `c068f901` — Ajustar política de no-show para marcações [NOVO]
- **Faz:** `update_setting reservation_no_show_policy = {reminder_2h:true, reminder_24h:true,
  reminders_enabled:true, deposit_required_threshold:0.5}`.
- **Risco:** o campo `deposit_required_threshold` é uma política nova de **exigir depósito**
  conforme taxa de no-show — toca diretamente a regra de dinheiro do pré-pagamento de reservas
  (CLAUDE.md §5: "no-show e cancel <2h = Bora 100%"). Prova: já existem crons ativos
  (`reservas_pro_reminders_24h`, `reservas_pro_reminders_2h`) que cobrem a parte de lembretes —
  logo o único ganho real da proposta é a parte de depósito, que é dinheiro. Evidência estatística
  é fraca (n=2, 1 no-show = 50%, amostra insignificante). Sem prova positiva de leitura/
  falso-positivo.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

### 4) `7cf1a393` — Resolver marcações pendentes órfãs [NOVO]
- **Faz:** investigação + "implementar mecanismo para cancelar automaticamente ou reatribuir"
  reservas órfãs. `nivel=3` (o próprio maestro já classifica como 🔴 dinheiro = só propõe).
  `payload_execucao=null` — sem execução automática anexada.
- **Risco:** as 2 reservas citadas na evidência (`7c61663d`, `091ac601`) já **não existem** em
  `reservations` (evidência stale — incidente já resolvido). Mesmo assim, o pedido em si é sobre
  automatizar cancelamento/liberação de slot com pré-pagamento Stripe real — dinheiro real.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Ações desta corrida
- Telegram consolidado enviado com sucesso (bridge PC→VPS, `id_ed25519_vps`, chat_id
  `6731890157`) — 1 mensagem cobrindo os 4 itens (reconfirmação 1&2 com prova nova + surface
  1ª vez de 3&4). Confirmado por output real `Sent to telegram home channel`.
- `admin_audit_log`: 4 linhas gravadas (`robot_suggestion_baldeB_reconfirmado` ×2,
  `robot_suggestion_baldeB_surfaced` ×2), cada uma com motivo/prova/dedup_key/telegram_enviado.
- Nenhuma escrita em `reservations`, `platform_settings` financeiros, `dispatch_engine`,
  `pricing_service` ou qualquer zona protegida — só roteamento de aprovação (`admin_audit_log`) e
  aviso Telegram.

Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA=true`) — mas sem
efeito nesta corrida porque não houve nenhum item Balde A a auto-aprovar.

## Nota para o próximo triador
Os 4 itens continuam `status='nova'` — aguardam decisão humana ("vai" na Central ou
`AdminRobotSuggestionsScreen`). Se reaparecer o gatilho FALLBACK_30MIN antes de o Danilo decidir,
NÃO reenviar Telegram a menos que o gap desde este envio (2026-07-24 ~07:2x UTC) passe de ~60min
sem supressão — e citar se há prova nova (ex.: nova reserva órfã real criada) ou apenas repetição.
