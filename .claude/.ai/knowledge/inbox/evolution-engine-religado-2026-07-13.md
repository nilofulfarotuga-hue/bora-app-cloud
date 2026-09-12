---
id: evolution-engine-religado-2026-07-13
tipo: relatorio
origem: [pedido direto do Danilo — religar o evolution-engine de forma segura, reativa, sem spam]
ultima_confirmacao: 2026-07-13
zona: verde
confianca: auto
---

# Evolution Engine religado — reativo, sem spam de ordens (2026-07-13)

## RESUMO EXECUTIVO
O `evolution-engine` (agente + skill) estava desligado desde que o cron
`hermes-evolution-trigger.sh` (host, `*/5min`) gerou um loop autorreferencial de ordens `-evol`
(contava as próprias saídas como "travadas novas" → ~30+ ordens em cadeia). Nesta sessão: (1)
confirmei o desenho já religado no working tree (trabalho de sessão anterior, ainda por
commitar) está correto e é genuinamente reativo; (2) verifiquei estaticamente que o motor
mecânico (`evolution_engine.py`) nunca escreve `ordem-*.md` — só `inbox/evolution-report-*.md` +
`scripts/state/propostas.json`; (3) escrevi as 2 lições permanentes que faltavam no Cérebro
(o ficheiro `licao-spam-ordens-autoreferencial.md` era referenciado por 3 ficheiros diferentes
mas não existia); (4) consolidei as lições da semana (pipe SSH, falso rate-limit, RAM/lock,
juiz mudo, timeout de mega-ordem) numa lição agrupada, para o evolution-engine (e qualquer
agente futuro) nunca as repetir.

## 1 — Diagnóstico da causa do spam (confirmado, não re-investigado do zero)
`hermes-evolution-trigger.sh` disparava 1 ordem `ordem-<ts>-evol.md` na fila sempre que via uma
ordem `travada` nova ou a mesma `nota` de erro repetida 2×/2h. Como as próprias ordens `-evol`
também ficavam `travada` (o executor delas não fazia trabalho "normal" que fechasse limpo), cada
tick de 5 min via mais `-evol` travadas e gerava mais `-evol` — loop autorreferencial. A guarda
EVOL-1 (`*-evol|*-aprv|*-e2e` ignoradas no scan, commit `10ea1b8`, 2026-07-12) reduziu o volume
mas não elimina o vetor: qualquer "cron que injeta ordem a cada sinal" é spam por construção,
guarda ou não. Confirmado **já retirado do crontab da VPS** antes desta sessão.

## 2 — Desenho novo, reativo (o que já estava no working tree, verificado por mim)
- `.claude/scripts/hermes-evolution-trigger.sh` — endurecido para **stub inerte**: early-exit
  logo na linha 1 do corpo executável (só regista no log que foi retirado), código legado mantido
  abaixo comentado para grep/histórico, nunca executa. Defesa em profundidade: se alguém repuser
  a linha no crontab por engano, não acontece nada.
- `.claude/agents/evolution-engine.md` — secção "Gatilhos" reescrita: **nunca dispara ordem
  nova**. 2 camadas: (a) fim de cada missão já deixa relatório em `inbox/` (convenção "Saída
  padrão") — o agente lê os relatórios recentes quando invocado, sem gatilho próprio; (b) 1×/dia
  o `hermes-daily-pulse.sh` corre `evolution_engine.py --dry-run` no espelho do container (camada
  barata, só conta para o Telegram, não persiste — o espelho é `reset --hard` diariamente). A
  análise REAL (sem `--dry-run`, escreve relatório+estado, commit+push) só corre numa sessão
  Claude Code de verdade (manual ou missão legítima), nunca auto-disparada.
- `.claude/skills/evolution-engine/SKILL.md` — secção "Integração daily-pulse" atualizada com o
  mesmo desenho de 2 camadas; telemetria da skill atualizada (9 execuções reais, 9 sucessos,
  0 falhas, `ultima_execucao: 2026-07-13`).
- `permanente/semantica/loops.md` — linha `evolution-trigger` marcada `estado: superado`
  (⚫), linha `evolution-report` atualizada para refletir o desenho de 2 camadas + garantia
  explícita "NUNCA cria ordem na fila"; nota histórica anexada explicando o religamento.
- `wiki/skills-metrics.md` — `execucoes: 9 / sucessos: 9 / falhas: 0` já refletido no frontmatter
  da skill; histórico completo das 9 invocações reais desta semana já registado na tabela.

## 3 — Verificação mecânica (sem spam) — estática, Python indisponível neste executor
Não há `python`/`python3`/`py` no PATH deste executor headless (mesma limitação já registada em
memória de uma sessão anterior nesta mesma máquina) — não consegui correr
`evolution_engine.py --dry-run` ao vivo. Em vez de assumir, li o script inteiro
(`.claude/skills/evolution-engine/scripts/evolution_engine.py`, 259 linhas) e confirmei
estaticamente:
- As únicas escritas em disco são `INBOX / "evolution-report-{data}.md"`
  (`out_path.write_text(...)`, linha 251) e `STATE_FILE` via `save_state()`
  (`scripts/state/propostas.json`, linha 252).
- **Nenhum caminho de código referencia `orquestracao/` nem escreve `ordem-*.md`.** As 5
  capacidades (padrões/reescrita/arquivo/fusão/divisão) só produzem entradas na lista `proposals`
  que vai para o relatório markdown — nunca para a fila de execução.
- `--dry-run` nem chega a escrever o relatório (`return 0` antes do `INBOX.mkdir`/`write_text`).
Conclusão: o motor é reativo **por construção do código**, não só por convenção documentada —
mesmo correndo sem supervisão, não há caminho para gerar spam de ordens.

## 4 — Lições da semana gravadas no Cérebro (permanente, não só relatório)
Criados 2 ficheiros novos em `permanente/procedural/licoes/` (indexados em `README.md` e
`INDEX.md`):

| Lição | Ficheiro | Resumo |
|---|---|---|
| (d) Spam de ordens autorreferencial | `licao-spam-ordens-autoreferencial.md` | cron que dispara ordem a cada sinal é spam por construção; agente de análise é reativo |
| (a) Pipe SSH sem EOF (Elo 6) | `licao-robustez-loop-autonomo-2026-07-13.md` §1 | `ReadLine()` não deteta EOF com `conhost.exe`; usar `StreamReader` + timeout do lado que espera |
| (b) Falso rate-limit | idem §2 | grep cego dispara ao citar a frase; exigir frase + saída ≤600 bytes |
| (c) RAM/concorrência | idem §3 | lock precisa estar deployado de facto, não só existir no repo |
| (e) "Juiz mudo" = lock, não visual | idem §4 | erro estrutural do orquestrador não deve ir ao avaliador como se fosse resultado; visual vs não-visual explícito; `VEREDITO:` nunca fica muda |
| (f) Mega-ordem estoura timeout | idem §5 | dividir >15min ANTES de começar; teto subiu 900s→2400s como rede de segurança |
| (g) LEI DO PRE-VOO | já vivia em `permanente/procedural/decision-brain.md` §"✈️ LEI DO PRE-VOO" — não duplicada, só referenciada |

Todas com evidência (ficheiro:secção, commit, relatório de origem) — nenhuma inventada, todas
apoiadas nos relatórios já produzidos esta semana (`inbox/cura-elo6-pipe-ssh-2026-07-13.md`,
`inbox/rate-limit-falso-corrigido-2026-07-13.md`, `inbox/juiz-tarefa-nao-visual-2026-07-13.md`,
`inbox/investigacao-cadeia-ordens-2026-07-13.md`, `inbox/lei-pre-voo-2026-07-13.md`, memórias
`project_ponte_ram_root_cause_2026-07-12` / `project_e2e_loop_ram_stall`).

## Ficheiros tocados nesta sessão
- `.claude/.ai/knowledge/permanente/procedural/licoes/licao-spam-ordens-autoreferencial.md` (novo)
- `.claude/.ai/knowledge/permanente/procedural/licoes/licao-robustez-loop-autonomo-2026-07-13.md` (novo)
- `.claude/.ai/knowledge/permanente/procedural/licoes/README.md` (índice atualizado)
- `.claude/.ai/knowledge/INDEX.md` (2 linhas novas apontando para as lições)
- `.claude/.ai/knowledge/inbox/evolution-engine-religado-2026-07-13.md` (este relatório)
- Confirmados (já modificados por trabalho anterior desta mesma sessão/semana, verificados e
  não alterados por mim): `.claude/agents/evolution-engine.md`,
  `.claude/scripts/hermes-evolution-trigger.sh`, `.claude/skills/evolution-engine/SKILL.md`,
  `.claude/.ai/knowledge/wiki/skills-metrics.md`, `.claude/.ai/knowledge/permanente/semantica/loops.md`

## Não tocado (fora do escopo)
`.claude/scripts/hermes-aprovador-vermelho.sh`, `.github/workflows/build_android.yml`,
`lib/screens/client/tvde/tvde_ride_tracking_screen.dart`, `lib/services/notification_service.dart`,
ficheiros de heartbeat-desktop/browser — mudanças pré-existentes no working tree de outras
frentes de trabalho nesta branch partilhada; não fazem parte desta tarefa e não foram commitados
por mim.

EVOLUTION-ENGINE religado (reativo, sem spam) + lições da semana gravadas.
