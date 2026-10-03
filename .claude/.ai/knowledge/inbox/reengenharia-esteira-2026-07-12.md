---
id: reengenharia-esteira-2026-07-12
tipo: relatorio
origem: [MODO PROTECÇÃO TOTAL — missão do Danilo 2026-07-12 tarde; base inbox/diagnostico-esteira-2026-07-12.md]
zona: verde (infra de orquestração; nada de dinheiro tocado)
---

# Reengenharia da esteira de orquestração — 2026-07-12

**Decisões aprovadas pelo Danilo no arranque:** (1) FASE 1 endurecer+testar, **segurar a missão
A-E** (não disparar hoje); (2) task C (TVDE) = **PROPOSE-ONLY** quando a missão correr.
Tudo feito com o loop **pausado** primeiro (kill switch), para o executor não varrer a árvore.

Prova ponta-a-ponta no fim: ✅ passou. Selftest do carteiro: ✅ TODOS OK.

---

## O que mudou (ficheiro por ficheiro)

| Ficheiro | Onde corre | Mudança |
|---|---|---|
| `deploy/carteiro.sh` (repo) → `/root/orquestracao/carteiro.sh` (VPS) | HOST VPS | **reescrito** sobre a versão viva. Nota nunca vazia · rate-limit inteligente · TIMEOUT não re-tenta 5x · STOP `.pausa-total` · encadeamento de missão · Telegram só nos 3 casos · `--selftest` · `--iniciar-missao`. |
| `deploy/campainha.sh` (repo) → `/root/orquestracao/campainha.sh` (VPS) | HOST VPS | respeita `.pausa-total`; coalesce rajadas (1 carteiro/8s). Serviço `orq-campainha` reiniciado. |
| `hermes-bridge/run-claude-loop.cmd` (+ espelho `deploy/`) | PC | modelo por tarefa (`[MODELO: OPUS]`→opus; senão **Sonnet** default); saída `stream-json`→parser→`bora-live.log`. CRLF preservado. |
| `hermes-bridge/bora-live-parser.ps1` (+ espelho `deploy/`) | PC | **novo**. Lê o stream-json, escreve linhas legíveis no `bora-live.log`, emite só o resultado final no stdout (carteiro/juiz recebem texto igual). |
| `assistir.cmd` (raiz do projeto) | PC | **novo**. `Get-Content -Wait` do `.claude/bora-live.log`. |
| `hermes-{evolution-trigger,e2e-vigia,aprovador-vermelho,carteiro-vigia,watchdog}.sh` (repo `.claude/scripts/` + VPS `/usr/local/bin/`) | HOST VPS | guard `.pausa-total` inserido após o shebang (idempotente). |
| `orquestrador-carteiro/CONVENCOES.md` | doc | **novo**. Regra de tamanho de ordem (1.7) + comandos do Danilo. |
| `orquestrador-carteiro/missoes/missao-plano-mestre-2026-07-12.md` (+ fila VPS `orquestracao/missoes/`) | doc+fila | **novo**. Missão A-E, todos os passos `pendente` (SEGURA, não disparada). |
| `permanente/semantica/loops.md` | doc | nota de reengenharia. |
| `.gitignore` | repo | ignora `.claude/bora-live.log` (runtime). |

Backups no VPS: `carteiro.sh.bak-20260712`, `campainha.sh.bak-20260712`, `*.bak-20260712` para cada cron.

---

## As 5 causas (do diagnóstico) → o que as fecha

- **(A) rate-limit da conta** → deteção `is_rate_limit()`; NÃO gasta tentativa; cria `.pausa-rate-limit`
  com epoch de reset (parseia "resets 5pm (Europe/London)"; defensivo now+1h); avisa 1x; retoma sozinho.
- **(B) timeout 900s** → saída vazia grava `nota: ⏱️ TIMEOUT-900s`; ao 2.º timeout **trava** com sugestão
  de dividir — nunca re-tenta a mesma coisa 5×.
- **(C) nota vazia sem causa** → por construção a nota é sempre preenchida num de: RATE-LIMIT / TIMEOUT-900s /
  SAIDA-VAZIA / JUIZ-SEM-VEREDITO / motivo-do-juiz. (Nota vazia só em `aprovada` — sucesso, é o correto.)
- **(D) 5 crons a bater na campainha** → guard `.pausa-total` em todos + campainha coalesce (1/8s).
  Nota: o `carteiro-vigia` **já tinha** log próprio (`/root/orquestracao/carteiro-vigia.log`); o diagnóstico
  reportou "sem log" por ter olhado o caminho errado. Corrigido aqui.
- **(E) STOP não propaga aos crons** → `.pausa-total`: um único ficheiro na fila que carteiro, campainha
  E os 5 crons verificam antes de agir. Testado: com a pausa, o `evolution-trigger` sai sem criar ordem e
  o carteiro loga `STOP-TOTAL`.

---

## Prova do teste ponta-a-ponta (FASE 3)

1. **STOP-total (1.5):** `.pausa-total` presente → `evolution-trigger` `EXIT=0`, ordens 161→161 (não criou);
   carteiro logou `STOP-TOTAL: .pausa-total presente — nada a fazer`. ✅
2. **Telegram:** envio de teste via Hermes → `TELEGRAM enviado OK`. ✅
3. **Ciclo inteiro (ordem-teste isolada, junk parqueado):** `ordem-…-tste` (sem tag) →
   executor correu **`--model sonnet`** (prova 1.3) → escreveu `bora-live.log` com linhas legíveis
   (prova 1.4: `tool Bash: mkdir…`, `tool Write: …teste-esteira…`, `fala OK-ESTEIRA-TESTE…`, `FIM turns=3`) →
   saída `OK-ESTEIRA-TESTE-2026-07-12` → juiz `VEREDITO: APROVADA` → `estado: aprovada` → **silêncio**
   (ordem normal, sem Telegram, como desenhado). ✅
4. **Selftest:** `carteiro.sh --selftest` → is_rate_limit, epoch-sempre-futuro, deps_ok, set_passo → **TODOS OK**. ✅

---

## Comandos do Danilo

- **Acompanhar ao vivo:** abrir `assistir.cmd` na raiz do projeto (tail de `.claude/bora-live.log`).
  Alternativa na VPS: `ssh … "tail -f /root/orquestracao/carteiro.log"`.
- **PARAR TUDO:** `touch /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total`
- **RETOMAR TUDO:** `rm -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total`
- **Disparar a missão A-E (quando quiseres):**
  `bash /root/orquestracao/carteiro.sh --iniciar-missao missao-plano-mestre-2026-07-12`
  → dispara A+B em paralelo; encadeia sozinha até E; task C pausa para o teu "vai" (PROPOSE-ONLY).

---

## Estado final do sistema

- Esteira **endurecida e a funcionar** (kill switch ON, `.pausa-total` removida, ops normais retomadas).
- Missão A-E **SEGURA** (`orquestracao/missoes/…`, todos os passos `pendente`) — só arranca com o teu comando.
- Default do executor agora **Sonnet** (económico); Opus só com `[MODELO: OPUS]`.

## Pendências / notas honestas

- **Encadeamento de missão** está construído + selftestado nas funções puras (deps_ok, set_passo,
  fire_next), mas **ainda não foi exercido com uma missão real** (por decisão de segurar A-E). Será
  provado no 1º arranque real. Guardei o risco aqui de propósito.
- **task C (TVDE)** entra PROPOSE-ONLY: o executor devolve proposta e não aplica. O juiz pode marcar
  CORRIGIR por "não aplicou" — comportamento esperado; a proposta fica na `.saida.txt` para o Danilo.
- Ruído cosmético no `bora-live.log`: linhas `warn` de stderr (regras de permissão) e alguns `�` de
  encoding — não afetam a saída real (o `clean()` do carteiro tira-as). Fica como afinação futura.

DIAGNOSTICO/REENGENHARIA COMPLETA — esteira endurecida (nota nunca vazia, rate-limit auto-pausa,
modelo por tarefa, STOP global, live-log, encadeamento) e provada ponta-a-ponta; missão A-E segura.
