# Aprovador-Vermelho — Triagem FALLBACK_30MIN (2026-07-19, corrida 9)

**Gatilho:** FALLBACK_30MIN — fila `robot_suggestions` reportada com 2 item(ns) parado(s) há 642+ min.
**Hora da corrida:** 2026-07-19 ~20:12-20:13 UTC.

## 0. Config
- `platform_settings.aprovador_vermelho_auto_baldeA` = **true** (auto-Balde-A ligado).

## 1. Estado real da fila no momento da triagem
`SELECT * FROM robot_suggestions WHERE status='nova'` devolveu **apenas 1 item** (não 2). O
número "2" do gatilho é o mesmo snapshot já explicado na corrida anterior (`fallback30min-8`,
~20:08 UTC): o segundo item (`29ea4b41`, variante `-v2`) já tinha sido fechado às 19:54:47 UTC
como `rejeitada` (dedupe contra `77c31fff`) por outra corrida concorrente, antes deste disparo
ler o watermark.

| id | categoria | nível | título | status |
|---|---|---|---|---|
| `77c31fff-0330-4981-813a-f2268c6f7bbe` | infra_cron | 3 | Investigar e otimizar queries lentas de cron | nova |

Confirmado também (fora da fila `nova`, só para registo): `29ea4b41` (`-v2`) = `rejeitada`
19:54:47 UTC; `01a67895` (`-v3`) = `aprovada` 11:09:00 UTC por decisão humana real do Danilo
(`robot_approve_plan`, não por este agente).

## 2. Triagem — corpo lido, não só título/categoria
Item já triado **13x hoje antes desta corrida** (ver `admin_audit_log`). Corpo (`evidencia`,
`proposta`) relido nesta corrida, não assumido do histórico:

- `evidencia.slow_queries_top3` idêntica desde a criação (09:07:13 UTC): `_cron_check_orphan_orders`
  (140 calls, 65.4ms), `_appointment_cron_auto_no_show` (3885 calls, 63.5ms),
  `_cron_check_ghost_drivers` (139 calls, 61.5ms). Zero prova nova.
- **Regra do item agrupado:** `_cron_check_orphan_orders` e `_cron_check_ghost_drivers` são Balde A
  puro (só `SELECT` + `notify_admin_event`, confirmado por `pg_get_functiondef` em corridas
  anteriores). `_appointment_cron_auto_no_show` faz `UPDATE appointments SET status=no_show,
  deposit_status=retained` quando `paid` — decide reter depósito real de cliente no-show = Balde B
  sempre. Como as 3 funções estão citadas numa única linha da fila, **o item inteiro cai em Balde
  B** — sem aprovação parcial (regra confirmada 14x, incluindo esta corrida).

**Resultado: Balde A = 0. Balde B = 1 (`77c31fff`).**

## 3. Anomalia (recorrência, já conhecida — não corrigida por mim)
Às 19:54:41 UTC de hoje a RPC `robot_emerson_decide` voltou a aprovar este mesmo item
incorretamente (`status='aprovada-emerson'`) — gap já documentado em memória
(`project_robot_emerson_decide_gap_nivel_evidencia`): a RPC não verifica `nivel` nem `evidencia`,
só regex em título/categoria/proposta. Uma corrida anterior do fallback já reverteu para `nova`
às 20:01:55 UTC. **Não mexi na RPC** — correção de código sensível é Balde B (só proposta),
aguarda "vai" do Danilo. Nada novo além do já registado nas corridas -6/-7/-8 do mesmo dia.

## 4. Telegram
**Suprimido.** Último envio real foi na reconfirmação nº12 (20:02:58 UTC); a reconfirmação nº13
(corrida anterior, `fallback30min-8`, 20:09:17 UTC) já tinha suprimido por falta de prova nova.
Esta corrida roda ~4-5 min depois, mesma evidência estática — reenviar seria spam. Registei só o
audit log.

## 5. Ações realizadas
- `SELECT` em `robot_suggestions` (fila + dedup_key das 3 variantes), `platform_settings`,
  `admin_audit_log` (read-only).
- 1x `INSERT` em `admin_audit_log` (id `3a795302-cf69-4333-8152-15fcd756c906`,
  `created_at=2026-07-19 20:13:43.440034 UTC`) — reconfirmação nº14, `status_mantido=nova`,
  `telegram_enviado=false` com motivo.
- **Nenhuma alteração de status** em `robot_suggestions` (nada Balde A para promover) e
  **nenhuma alteração de lógica de dinheiro/dispatch/RPC**.

## 6. Pendente para o Danilo
- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO: item `77c31fff` (retenção de depósito no-show via
  `_appointment_cron_auto_no_show`) continua a aguardar decisão humana — mesma pendência das 13
  corridas anteriores, sem novidade.
- Correção da RPC `robot_emerson_decide` (falta checar `nivel`/`evidencia` antes de auto-aprovar)
  continua pendente, Balde B, aguarda "vai" — já ocorreu 2x hoje (07-18 já tinha o padrão, hoje
  reincidiu às 19:54:41 UTC) e continuará a acontecer enquanto o código não for corrigido.
- Sinal operacional (não é dinheiro, mas também não executado por mim — fora do meu mandato de
  roteamento): pelo menos 4 corridas do FALLBACK_30MIN (6, 7, 8, 9) dispararam no mesmo item em
  menos de ~20 minutos, todas concorrentes/quase simultâneas. O backoff exponencial já existe no
  repo (`.claude/scripts/hermes-aprovador-vermelho.sh`) mas segue **pendente de deploy manual** na
  VPS (`/usr/local/bin/hermes-aprovador-vermelho.sh`) — é por isso que o espaçamento real entre
  disparos continua bem abaixo dos 30 min esperados.

## 7. Handoff ao bibliotecario-cerebro
Não escrevi memória nova nesta corrida — o ficheiro
`permanente/procedural/aprovador-vermelho-triagem.md` já cobre a regra do item agrupado (14x
confirmada agora), a anomalia da RPC (2ª ocorrência hoje) e o padrão de corridas concorrentes.
Sinalizo ao `bibliotecario-cerebro` (escopo `agente:aprovador-vermelho`) que pode, quando conveniente,
consolidar as corridas 6-9 (mesmo item, zero factos novos) numa única linha da tabela "Histórico de
corridas", em vez de manter relatórios redundantes — não é urgente, é só housekeeping.
