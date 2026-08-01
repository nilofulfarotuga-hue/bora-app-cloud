---
id: evolution-report-2026-07-13
tipo: relatorio
origem: [evolution-engine — corrida fora-de-ciclo, gatilho hermes-evolution-trigger.sh]
ultima_confirmacao: 2026-07-13
zona: verde
confianca: auto
---

# 🧬 Evolution Report — 2026-07-13 (fora-de-ciclo)

> Gatilho: `erro repetido 2x+/2h: "⏱️ TIMEOUT-900s x2 — tarefa grande demais; DIVIDIR em passos
> menores (convencoes.md). Não re-tento a mesma coisa."` · sem ordem `travada` nova associada.

## 🎯 Caso concreto — MESMO padrão do `CASO CONCRETO 4` de `evolution-report-2026-07-12.md`

**Não é um caso novo.** É a **≥5.ª repetição** do padrão já diagnosticado ontem (3 repetições
registadas no próprio `evolution-report-2026-07-12.md`, agora +1 hoje). Confirmado por leitura
direta do ficheiro-fonte, que **continua por corrigir**:

`.claude/.ai/hermes/orquestrador-carteiro/missoes/missao-plano-mestre-2026-07-12.md:9` — o passo
**B** ainda mistura, na mesma tarefa síncrona:
- (a) ação rápida — powercfg + `adb kill-server/start-server` (cabe em 900s), com
- (b) uma janela de observação contínua — **"provar 30 min sem queda"** (excede por definição
  o teto de 900s do executor).

Cada vez que esta ordem (ou uma repetição dela) é (re)disparada, bate no mesmo teto, gera
`TIMEOUT-900s` ×2, e o carteiro trava corretamente (nunca re-tenta cegamente) — mas o padrão
**volta a acontecer no próximo disparo** porque a causa-raiz na missão nunca foi editada.

**Não gero propostas novas** — `TPROVA-1/2/3` (já em `evolution-report-2026-07-12.md`) cobrem
este caso por completo. Governança: proposta pendente **não se reproprõe** (evita ruído no
inbox); o que falta é **aplicação**, não mais análise.

### O que muda hoje: draft pronto a aplicar de TPROVA-2 (para acelerar o gate do Juiz)

Ontem o TPROVA-2 ficou descrito em conceito. Para reduzir o atrito de aplicação, deixo aqui o
**patch literal** do passo B → B1+B2 (ainda **não aplicado** — zona 🟡 governança/orquestração,
`propose-only`, precisa do `juiz-revisor` + "vai" do Danilo antes de editar o ficheiro real):

```diff
- passo: B | modelo: SONNET | paralelo: sim | depende: - | propose_only: nao | estado: pendente | tarefa: Estabilidade adb/USB: desligar USB selective suspend (AC+DC) no esquema de energia ativo via powercfg; fixar a autorizacao adb dos 2 telemoveis (incluindo N75LTG5X5DSKDMV4) via adb kill-server/start-server reusando o adbkey; provar 30 min sem queda. Relatorio curto em inbox/.
+ passo: B1 | modelo: SONNET | paralelo: sim | depende: - | propose_only: nao | estado: pendente | tarefa: Estabilidade adb/USB: desligar USB selective suspend (AC+DC) no esquema de energia ativo via powercfg; fixar a autorizacao adb dos 2 telemoveis (incluindo N75LTG5X5DSKDMV4) via adb kill-server/start-server reusando o adbkey. Arrancar um log de observacao em background (ex.: adb logcat para ficheiro, ou heartbeat leve) e fechar concluida logo apos aplicar — NAO esperar os 30 min dentro desta ordem. Relatorio curto em inbox/.
+ passo: B2 | modelo: SONNET | paralelo: nao | depende: B1 | propose_only: nao | estado: pendente | tarefa: So disparar depois de decorridos 30 min sobre a conclusao de B1. Ler o log/marcador deixado por B1 e confirmar "sem queda" (procurar desconexoes/erros registados). Relatorio curto em inbox/.
```

E ajustar o passo `E` (que hoje depende de `A,B,C`) para depender do novo passo final da cadeia:

```diff
- passo: E | modelo: SONNET | paralelo: nao | depende: A,B,C | propose_only: nao | estado: pendente | tarefa: ...
+ passo: E | modelo: SONNET | paralelo: nao | depende: A,B2,C | propose_only: nao | estado: pendente | tarefa: ...
```

**Ação recomendada (prioridade — dia 2 do mesmo desperdício):** aplicar este patch à missão ANTES
do próximo disparo/retry, para parar de queimar ciclos de 900s×2 na mesma ordem estruturalmente
impossível de fechar como está. TPROVA-1 (regra "prova assíncrona" em `CONVENCOES.md`) e TPROVA-3
(registo em `loops.md`) continuam pendentes e generalizam a correção para futuras missões com o
mesmo padrão ("provar/observar N min" embutido numa ordem síncrona).

## Análise mecânica (referência, sem propostas novas hoje)

`evolution_engine.py --dry-run` re-corrido: 50 skills analisadas, 26 candidatas por padrão de
tópico (mesma classe de achados do relatório de 07-12 — nenhuma delas relacionada com o caso do
gatilho de hoje). Não escrevi essas propostas aqui para não duplicar `evolution-report-2026-07-12.md`;
ver esse ficheiro para a lista completa.

## Nota operacional

Não editei `missao-plano-mestre-2026-07-12.md`, `CONVENCOES.md` nem `loops.md` — são atos de
orquestração/Córtex (zona 🟡, `propose-only`). Este relatório é a proposta; aplicação exige
`juiz-revisor` + "vai" do Danilo.

## 🎯 Atualização 2026-07-13T~00:14Z — achado novo: o próprio GATILHO dispara sem cooldown

Este disparo do evolution-engine aconteceu **~8 min depois** do disparo anterior (relatório
acima, escrito 00:06:45) — para a **mesma** `nota_repetida` ("TIMEOUT-900s x2..."), sem nada ter
mudado entretanto (`missao-plano-mestre-2026-07-12.md` continua com mtime de 07-12 19:25).

**Causa lida diretamente em `.claude/scripts/hermes-evolution-trigger.sh`:** o gatilho (a) —
"ordem travada nova" — tem watermark (`$STATE`, linhas 36-61) que impede reenvio da mesma ordem
travada. O gatilho (b) — "mesma nota repetida 2x+/2h" (linhas 63-72) — **não tem nenhum
watermark**. Enquanto os ficheiros de ordem que geraram a nota continuarem dentro da janela
`-mmin -120`, **todo tick do cron (a cada 5 min) volta a casar a condição e dispara uma ordem
`-evol` nova**, cada uma custando uma invocação de agente completa. É a mesma classe de
desperdício que já queimou o limite de sessão em 07-12 (ver `reengenharia-esteira-2026-07-12.md`),
agora a acontecer dentro do próprio mecanismo criado para vigiar esse desperdício.

**Proposta TPROVA-4 (🟡 governança-de-loop, propose-only → Juiz → Danilo aplica no VPS):**
adicionar cooldown ao gatilho (b), espelhando o padrão já usado no gatilho (a) — não disparar de
novo pelo mesmo motivo antes de decorrido um intervalo mínimo.

```diff
--- a/.claude/scripts/hermes-evolution-trigger.sh
+++ b/.claude/scripts/hermes-evolution-trigger.sh
@@
 FILA=/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao
 STATE=/root/orquestracao/evolution-trigger.watermark   # ids de 'travada' já disparados (1 por linha)
+NOTA_STATE=/root/orquestracao/evolution-trigger.nota-watermark  # "epoch<TAB>texto da nota" do último disparo por (b)
+NOTA_COOLDOWN_SECS=3600   # não repete o MESMO motivo (b) antes de 1h — dá tempo ao Juiz/Danilo agir
 LOG=/root/orquestracao/evolution-trigger.log
@@
   if [ -n "${cnt:-}" ] && [ "$cnt" -ge 2 ] 2>/dev/null; then
     nota_repetida=$(echo "$notas" | sed -E 's/^ *[0-9]+ *//')
+    # cooldown: já disparámos por este MESMO texto há menos de NOTA_COOLDOWN_SECS? então ignora (b) agora
+    if [ -f "$NOTA_STATE" ]; then
+      last_epoch=$(cut -f1 "$NOTA_STATE")
+      last_nota=$(cut -f2- "$NOTA_STATE")
+      now_epoch=$(date -u +%s)
+      if [ "$last_nota" = "$nota_repetida" ] && [ $((now_epoch - last_epoch)) -lt "$NOTA_COOLDOWN_SECS" ]; then
+        nota_repetida=""
+      fi
+    fi
   fi
 fi
@@
 for id in $travadas_novas; do echo "$id" >> "$STATE"; done
+[ -n "$nota_repetida" ] && printf '%s\t%s\n' "$(date -u +%s)" "$nota_repetida" > "$NOTA_STATE"
 log "DISPAROU $oid — $motivo"
```

Evidência: dois disparos (00:06 e 00:14, ~8 min de intervalo) para a mesma nota, script lido
linha-a-linha confirma ausência de watermark em (b) vs presença em (a). Efeito sem fix: dispara
a cada 5 min *indefinidamente* enquanto a causa raiz (TPROVA-2, ainda pendente) não for aplicada
— podendo voltar a esgotar o limite de sessão da conta, o exato incidente que a reengenharia de
07-12 tentou fechar.

**Não editei** `hermes-evolution-trigger.sh` (vive no VPS, `/usr/local/bin/`, fora do mandato de
aplicar deste agente — zona 🟡 loop/orquestração). Draft acima pronto para o `juiz-revisor` avaliar
e o Danilo replicar ao VPS após "vai".

## 🎯 Atualização (nova corrida fora-de-ciclo, mesmo dia) — mais uma repetição, sem mudança de estado

Nova invocação para a **mesma** `nota_repetida` ("TIMEOUT-900s x2..."), sem ordem `travada` nova
associada. Verificado por leitura direta:
- `missao-plano-mestre-2026-07-12.md` — passo B **ainda** com mtime `2026-07-12 19:25`, linha 9
  **ainda** mistura powercfg/adb-key (ação rápida) com "provar 30 min sem queda" (janela >900s).
  TPROVA-2 (o patch B→B1+B2, já com diff literal acima) continua **não aplicado**.
- Nenhuma evidência de que TPROVA-4 (cooldown no gatilho `hermes-evolution-trigger.sh`, VPS) tenha
  sido aplicado — esta própria repetição, chegando de novo dentro da mesma janela de 2h da nota, é
  consistente com o diagnóstico de "sem cooldown em (b)" já registado acima.

**Não gero propostas novas** — TPROVA-1/2/3/4 já cobrem este caso por completo (governança: não
repropor o que já está pendente). Ação que efetivamente para o desperdício continua a ser a mesma:
aplicar TPROVA-2 (corta a causa-raiz na missão) e/ou TPROVA-4 (corta o re-disparo a cada 5 min no
gatilho) — qualquer um dos dois, isoladamente, já quebra o ciclo. Nenhum ficheiro de código/loop
editado por este agente (zona 🟡 propose-only); só este relatório foi atualizado.

## 🎯 Atualização 2026-07-13 (mais uma corrida fora-de-ciclo) — confirmado: nada aplicado ainda

Verificação direta do estado local antes de escrever mais uma linha:
- `missao-plano-mestre-2026-07-12.md` (linha 9, passo B) — **mtime ainda `2026-07-12 19:25`**,
  texto **idêntico** ao original (powercfg/adb-key + "provar 30 min sem queda" na mesma tarefa
  síncrona). TPROVA-2 **não aplicado**.
- `.claude/scripts/hermes-evolution-trigger.sh` (cópia local do repo, mtime `2026-07-12 20:58`,
  já inclui o guard EVOL-1 do commit `10ea1b8`) — `grep NOTA_STATE\|NOTA_COOLDOWN` **sem resultado**:
  o cooldown do gatilho (b) proposto em TPROVA-4 **não está no script local**. Se o script no VPS
  espelha este ficheiro (via deploy manual, não automático), o mesmo vale lá — ainda sem cooldown.

Confirma o diagnóstico: o disparo de hoje é esperado enquanto TPROVA-2 e/ou TPROVA-4 continuarem
por aplicar — não é um caso novo, é o sintoma já documentado a repetir-se. **Nenhuma proposta nova
gerada** (dedupe mantido). Nenhum ficheiro de código/loop editado por este agente.

## 🎯 Atualização 2026-07-13 (mais uma corrida) — confirmação curta, sem mudança

Reverificado: `missao-plano-mestre-2026-07-12.md` linha 9 continua com o texto original (mtime do
commit `2026-07-12 19:25`); `hermes-evolution-trigger.sh` local continua sem `NOTA_STATE`/
`NOTA_COOLDOWN`. Mesmo caso, TPROVA-2/4 continuam pendentes de aplicação pelo Danilo/Juiz — **sem
proposta nova** (dedupe mantido, para não inchar este ficheiro com repetições idênticas).
