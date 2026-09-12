# Aprovador-Vermelho — Triagem FALLBACK_30MIN (2026-07-19, corrida 10)

**Gatilho:** FALLBACK_30MIN — fila `robot_suggestions` reportada com 1 item parado há 712+ min.
**Hora da corrida:** 2026-07-19 ~21:00-21:03 UTC.

## 0. Config
- `platform_settings.aprovador_vermelho_auto_baldeA` = **true** (auto-Balde-A ligado, confirmado por SELECT).

## 1. Estado real da fila no momento da triagem
`SELECT * FROM robot_suggestions WHERE status='nova'` devolveu **1 item**, batendo com o gatilho:

| id | dedup_key | categoria | título | criado | idade |
|---|---|---|---|---|---|
| `77c31fff-0330-4981-813a-f2268c6f7bbe` | `infra:otimizar-queries-cron-lentas` | infra_cron | Investigar e otimizar queries lentas de cron | 2026-07-19 09:07:13 UTC | ~11h54 |

Confirmado fora da fila (só registo, não decisão minha): `29ea4b41` (`-v2`) = `rejeitada`
19:54:47 UTC (dedupe); `01a67895` (`-v3`) = `aprovada` 11:09:00 UTC por decisão humana real do
Danilo (`robot_approve_plan`).

## 2. Triagem — corpo relido nesta corrida
Item já triado 16x hoje (`admin_audit_log`). Reli `evidencia`/`proposta` do zero:
- `evidencia.slow_queries_top3` idêntica desde a criação: `_cron_check_orphan_orders` (Balde A,
  só SELECT+notify), `_appointment_cron_auto_no_show` (Balde B sempre — `UPDATE appointments SET
  status=no_show, deposit_status=retained` quando `paid`, decide reter depósito real de cliente),
  `_cron_check_ghost_drivers` (Balde A, só SELECT+notify). Zero prova nova.
- **Regra do item agrupado** (17x confirmada): as 3 funções estão citadas na mesma linha da fila
  → o item inteiro cai em Balde B, sem aprovação parcial.

**Resultado: Balde A = 0. Balde B = 1 (`77c31fff`).**

## 3. Anomalia recente (já corrigida, não por mim nesta corrida)
Às 19:54:41 UTC a RPC `robot_emerson_decide` aprovou este mesmo item incorretamente
(`status='aprovada-emerson'`) — bug conhecido (`project_robot_emerson_decide_gap_nivel_evidencia`
na memória): a RPC não verifica `nivel` nem `evidencia`, só regex em título/categoria/proposta.
Revertido para `nova` às 20:01:55 UTC por uma corrida anterior. Confirmado nesta corrida por SELECT
direto: `status='nova'`, `reviewed_at=null`, `reviewed_by=null` — reversão intacta, zero dinheiro
perdido. **Não mexi na RPC** — correção é Balde B (só proposta), aguarda "vai" do Danilo.

## 4. Telegram
**Enviado.** Último envio real tinha sido na reconfirmação nº12 (20:02:58 UTC) — gap de ~59-60 min
até esta corrida, sem prova nova mas tempo suficiente para justificar um checkpoint (evita o
Danilo perder de vista o pendente por muito tempo, sem ser spam a cada poucos minutos como as
reconfirmações 13-16 corretamente suprimiram). Confirmado: `Sent to telegram home channel
(chat_id: 6731890157)`, exit 0, via bridge SSH PC→VPS (`id_ed25519_vps` →
`hermes-agent-fvnc-hermes-agent-1` → `hermes send -t telegram`).

## 5. Ações realizadas
- `SELECT` em `robot_suggestions` (fila + as 3 variantes), `platform_settings`, `admin_audit_log` (read-only).
- 1x Telegram enviado (bridge SSH).
- 1x `INSERT` em `admin_audit_log` (id `8c42fc15-11b9-4721-8727-a3439bb66d9d`,
  `created_at=2026-07-19 21:03:02.891 UTC`) — reconfirmação nº17, `status_mantido=nova`,
  `telegram_enviado=true`.
- **Nenhuma alteração de status** em `robot_suggestions` (nada Balde A para promover), **nenhuma
  alteração de lógica de dinheiro/dispatch/RPC**.

## 6. Pendente para o Danilo
⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO: item `77c31fff` (retenção de depósito no-show via
`_appointment_cron_auto_no_show`) continua a aguardar decisão humana — mesma pendência das 16
corridas anteriores hoje, sem novidade na evidência.

Correção da RPC `robot_emerson_decide` (falta checar `nivel`/`evidencia` antes de auto-aprovar,
já reincidiu 2x hoje) continua Balde B, pronta para propor, aguarda "vai".

## 7. Handoff ao bibliotecario-cerebro
Não escrevo memória diretamente — sinalizo escopo `agente:aprovador-vermelho`:
`permanente/procedural/aprovador-vermelho-triagem.md` já cobre a regra do item agrupado (agora
17x) e a anomalia da RPC; sugiro consolidar as corridas 6-10 do mesmo dia (mesmo item, zero factos
novos) numa única linha, quando conveniente — housekeeping, não urgente.
