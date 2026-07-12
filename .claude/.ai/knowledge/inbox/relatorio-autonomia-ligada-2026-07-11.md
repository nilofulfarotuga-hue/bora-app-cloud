---
id: relatorio-autonomia-ligada-2026-07-11
tipo: relatorio
origem: [loop-noturno-executor, aprovador-vermelho]
data: 2026-07-11
zona: verde
confianca: auto
---

# Autonomia LIGADA — freio de mão solto (2026-07-11)

Pedido do Danilo: tirar o freio de mão da autonomia. As tarefas de **teste e leitura (Balde A)**
passam a seguir sozinhas; as de **dinheiro real (Balde B)** continuam a precisar do Danilo, que
agora confirma dizendo **"vai"** na conversa — **sem painel escondido**.

## PASSO 1 — Chave de auto-aprovação de Balde A ✅ (já estava ON)
- `platform_settings.aprovador_vermelho_auto_baldeA` = **`true`** (verificado em prod
  `ojykpzwqrtusfeakzrna`). Já estava ligada de corrida anterior (2026-07-10) — **nenhuma mudança
  necessária**, o estado pedido já é o estado atual.
- Efeito: o agente `aprovador-vermelho` **liberta sozinho** os itens de Balde A (leitura / falso-positivo
  / diagnóstico / flag-para-revisão) sem o Danilo aprovar um a um.
- **Balde B (dinheiro real) continua SEMPRE humano** — nada de auto. O Danilo confirma na conversa
  com "vai"; não precisa de aceder a nenhum painel.

## PASSO 2 — Loop automático a cada 10 min ✅ (já registado, confirmado na VPS)
Confirmado por SSH em `srv1786862.hstgr.cloud`:
- **Cron ativo:** `*/10 * * * * /usr/local/bin/hermes-aprovador-vermelho.sh # aprovador-vermelho-loop`
- **Script:** `/usr/local/bin/hermes-aprovador-vermelho.sh` (executável, 3917 B, `-rwxr-xr-x root`).
- Gate barato: lê o watermark `red_queue_watermark()` (só contagem + `newest`, zero dinheiro); só
  quando surge item **novo** injeta 1 ordem na fila → a campainha (inotify) acorda o carteiro → o PC
  corre o agente. Backlog já surfaçado **não re-dispara** (sem spam).
- **Não foi preciso criar nada** — o agendamento já existia da ligação de 2026-07-11.

## PASSO 3 — Corrida manual AGORA (libertar a fila) ✅
Triados os **12 itens `nova`** que estavam presos. Regra dos dois baldes aplicada com prova positiva
(dúvida → desce para Balde B).

**Balde A — auto-aprovados (3)** → `status = aprovada`:
| id | motivo (leitura/não-dinheiro) |
|---|---|
| `9d407492` | flag_products_review — só marca `needs_review` (produto `cnt-8053738`); **não altera preço/cobrança** |
| `a19429dd` | 3 motoristas online sem token FCM — **notificações, não-dinheiro** (precedente `75728e8b`) |
| `47e4486f` | diagnóstico de timeouts HTTP recorrentes — **infra/observabilidade, não-dinheiro** (precedente `d2838a6e`) |

**Balde B — ficam `nova`, decisão do Danilo (9)** — dispatch / no-show / pedidos presos (dinheiro/motor):
`268aad47` (otimizar `bora_dispatch_maintenance`), `abeca5d7` (cron `_appointment_cron_auto_no_show` —
depósitos), `9996b1fe` (reatribuir pedidos presos), `e8aabbcd` (resolver pedidos presos),
`adc2d2c8` (ajustar TTL de reatribuição), `a2da4c0c` (reduzir no-show — depósitos),
`12b0ce8b` (cancelamentos por timeout de dispatch), `ac406dde` (otimizar `_cron_check_orphan_orders`),
`488a6064` (otimizar `_cron_check_ghost_drivers`).
→ Estes só avançam depois do Danilo dizer **"vai"** na conversa.

- **Auditoria:** `admin_audit_log` id `7acba309-117e-4f08-a514-0088f5cbf147` (`action=red_queue_triage`).
- **Sobre a "auditoria geral prop-f8fe89eb":** procurei em `robot_suggestions`, `autonomy_backlog_items`,
  Córtex e no repo — **`f8fe89eb` não existe em lado nenhum**. Não há proposta presa com esse id na
  fila atual (já foi processada numa corrida anterior ou o id mudou). A fila está triada e sem
  bloqueios de leitura pendentes. Se o Danilo tiver o id/título certo, reponho-o.

## PASSO 4 — Kill switch (freio de emergência) ✅ intacto
- **"PARAR TUDO":** `platform_settings.robot_b_enabled` = **`true`** (loop ligado). Para suspender
  tudo já, basta pôr **`false`** — o loop autónomo para na hora.
- **Dial de confiança:** `platform_settings.robot_b_auto_level1_enabled` = **`false`** (continua
  **cauteloso** — N1 auto só se o dial permitir; hoje não permite). Envelope de 5 paredes intacto
  (Trava · Juiz · Tetos · Humano-acima-do-L1 · Kill switch).

## Conclusão
A partir de agora as **tarefas de teste/leitura (Balde A) seguem sozinhas** — via chave ON + loop
`*/10`. As de **dinheiro (Balde B) esperam o "vai" do Danilo na conversa**, sem painel escondido. O
**kill switch** continua a existir para parar tudo quando quiser.

## Ficheiros/objetos tocados
- **DB (`ojykpzwqrtusfeakzrna`):** 3 linhas `robot_suggestions` → `status=aprovada`
  (`9d407492`, `a19429dd`, `47e4486f`) + 1 linha `admin_audit_log` (`7acba309…`). Nada de dinheiro
  alterado; `aprovador_vermelho_auto_baldeA` já estava `true`.
- **Repo:** `.claude/.ai/knowledge/inbox/relatorio-autonomia-ligada-2026-07-11.md` (este).
- **VPS:** apenas leitura (confirmação do cron + script). Nada criado/alterado.

## Nota honesta
- Nenhuma lógica de dinheiro/dispatch foi tocada — só roteamento de aprovação (Balde A) e leitura.
- Não enviei Telegram (executor headless, sem canal com o Danilo). Os Balde B novos são surfaçados
  pelo próprio cron `*/10` na VPS na próxima passagem (watermark avançou).
- Handoff pendente ao `bibliotecario-cerebro` (escopo `agente:aprovador-vermelho` + `loops`).
