# Aprovador-Vermelho — Triagem FALLBACK_30MIN (2026-07-19, corrida 8)

**Gatilho:** FALLBACK_30MIN — fila `robot_suggestions` reportada com 2 item(ns) parado(s) há 642+ min.
**Hora da corrida:** 2026-07-19 20:08 UTC.

## 0. Config
- `platform_settings.aprovador_vermelho_auto_baldeA` = **true** (auto-Balde-A ligado).

## 1. Estado real da fila no momento da triagem
`SELECT * FROM robot_suggestions WHERE status='nova'` devolveu **apenas 1 item** (não 2 — o
segundo, `29ea4b41` variante duplicada, já tinha sido fechado às 19:54:47 UTC como `rejeitada`
por outra corrida, motivo "duplicado de 77c31fff"). O número "2" do gatilho reflete o instante em
que o watermark foi lido, ligeiramente antes desse fecho.

| id | categoria | nível | título | status |
|---|---|---|---|---|
| `77c31fff-0330-4981-813a-f2268c6f7bbe` | infra_cron | 3 | Investigar e otimizar queries lentas de cron | nova |

## 2. Triagem
Este item **já tinha sido triado 12x hoje** (ver `admin_audit_log`, ação
`robot_suggestion_baldeB_reconfirmado`/`_correcao_reversao`) e confirmado na memória
`project_aprovador_vermelho_central`. Não reanalisado do zero — só reconfirmado.

- **Evidência** (`evidencia.slow_queries_top3`): idêntica desde a criação (09:07:13 UTC) —
  `_cron_check_orphan_orders` (140 calls, 65.4ms), `_appointment_cron_auto_no_show` (3885 calls,
  63.5ms), `_cron_check_ghost_drivers` (139 calls, 61.5ms). Nenhuma prova nova.
- **Regra do item agrupado (2026-07-18):** as 2 primeiras funções são Balde A puro (leitura/notify,
  precedente confirmado várias vezes), mas `_appointment_cron_auto_no_show` faz
  `UPDATE appointments SET status=no_show, deposit_status=retained` quando `paid` — decide reter
  depósito real de cliente no-show. Por estar tudo numa única linha da fila, **o item inteiro cai
  em Balde B**, sem aprovação parcial.
- **Anomalia relacionada (já resolvida nesta corrida anterior, não desta):** às 19:54:41 UTC a RPC
  `robot_emerson_decide` aprovou este mesmo item incorretamente como `aprovada-emerson` (gap
  conhecido: a RPC não olha `nivel` nem `evidencia`, só regex em título/categoria/proposta — já
  registado em memória `project_robot_emerson_decide_gap_nivel_evidencia`). Uma corrida anterior
  do fallback já reverteu para `nova` às 20:01:55 UTC e citou a anomalia. **Não mexi na RPC** — é
  Balde B (correção de código sensível), fica como proposta pendente aguardando "vai" do Danilo.

**Resultado: Balde A = 0. Balde B = 1 (`77c31fff`).**

## 3. Telegram
**Suprimido.** Último envio real foi há 5min28s (reconfirmação nº12, 20:02:58 UTC,
`telegram_enviado=true`), mesma evidência estática, sem novidade nenhuma. Reenviar agora violaria
o protocolo anti-spam já aplicado nas corridas anteriores do mesmo dia (gaps de 30-60min antes de
reenviar). Registei apenas o audit log.

## 4. Ações realizadas
- `SELECT` em `robot_suggestions`, `platform_settings`, `admin_audit_log` (read-only).
- 1x `INSERT` em `admin_audit_log` (id `e6269b79-3367-4279-a8c7-e5bcd3a6084b`, 20:09:17 UTC) —
  reconfirmação nº13, `status_mantido=nova`, `telegram_enviado=false` com motivo.
- **Nenhuma alteração de status** em `robot_suggestions` (nada para promover) e **nenhuma alteração
  de lógica de dinheiro/dispatch/RPC**.

## 5. Pendente para o Danilo
- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO: item `77c31fff` (retenção de depósito no-show via
  `_appointment_cron_auto_no_show`) continua a aguardar decisão humana — mesma pendência das 12
  corridas anteriores, sem novidade.
- Correção da RPC `robot_emerson_decide` (não verificar `nivel`/`evidencia`) continua pendente,
  Balde B, aguarda "vai" — não é urgente (o buraco já foi tapado manualmente 2x hoje por corridas
  do fallback, mas volta a acontecer enquanto o código não for corrigido).
- Sugestão operacional (não executada, é dinheiro/infra-crítica: alteração ao próprio gatilho): o
  backoff exponencial do `hermes-aprovador-vermelho.sh` já existe no repo mas não está deployado na
  VPS — é por isso que o FALLBACK_30MIN continua a disparar a cada ~10-30min sobre o mesmo item.
