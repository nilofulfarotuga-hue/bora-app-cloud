---
tema: licao-spam-ordens-autoreferencial · escopo: projeto · estado: atual · atualizado: 2026-07-27
---
# Cron que injeta ordem na fila a cada sinal = spam por construção

- **Contexto:** `hermes-evolution-trigger.sh` (cron host `*/5min`) acordava o `evolution-engine`
  "na hora" injetando uma `ordem-*-evol.md` na fila sempre que via uma ordem `travada` nova ou
  a mesma `nota` de erro repetida 2×/2h.
- **O que correu mal / a descoberta:** o próprio scan do trigger contava as SAÍDAS do
  evolution-engine (`ordem-*-evol.md`, todas ficavam `travada` porque o executor delas não fazia
  o que uma ordem normal faz) como "ordens travadas novas" — um loop autorreferencial: cada
  ordem `-evol` gerava outra `-evol` no tick seguinte (~30+ em cadeia, 1/tick). A guarda EVOL-1
  (ignorar `*-evol|*-aprv|*-e2e` no scan, commit `10ea1b8`) reduziu mas não eliminou o vetor —
  mesmo sem o loop autorreferencial, "cron dispara ordem a cada sinal" continua sendo uma fonte
  de custo/spam por construção (qualquer sinal frequente vira ordem, sem cooldown por natureza).
- **Regra a aplicar:** um agente de análise/aprendizagem (evolution-engine ou qualquer futuro
  "meta-agente") **nunca dispara ordem nova na fila via cron**. Desenho correto, **reativo**:
  (1) cada missão já fecha com relatório em `inbox/` (convenção "Saída padrão") — o próximo passo
  lê os relatórios recentes, não precisa de gatilho próprio; (2) no máximo 1×/dia uma camada
  barata (`--dry-run`, só conta/soma para um resumo, não persiste) pode rodar num cron, mas a
  análise REAL (que escreve relatório + estado + faz commit) corre por invocação humana ou de
  missão legítima, nunca auto-disparada. Se um script existe só para "acordar" um agente na hora,
  o gatilho deve ser um relatório/sinal passivo que o próximo passo lê — não uma nova ordem-*.md.
- **Evidência:** `.claude/scripts/hermes-evolution-trigger.sh` (stub inerte desde 2026-07-13,
  early-exit + log, código legado mantido abaixo só para grep/histórico — nunca executa);
  `wiki/skills-metrics.md` (entradas evolution-engine 2026-07-12 "loop auto-referencial");
  `permanente/semantica/loops.md` (linha `evolution-trigger`, `estado: superado`);
  `.claude/agents/evolution-engine.md` (secção "Gatilhos — reativo, NUNCA disparo ordens novas").
- **Manifestação relacionada (2026-07-27, não idêntica — mesmo tema geral):** o GERADOR de
  `robot_suggestions` (não um cron de fila de ordens) duplicou 21 sugestões quase-idênticas (17×
  `marcacoes:ajustar-no-show-rate-threshold[-v2..-v17]` + 4×
  `marcacoes:resolver-marcacoes-pendentes-orfas[-v2/-v3]`/`2efe0a26901c`) reciclando evidência
  idêntica/stale em vez de conferir propostas recentes com o mesmo conteúdo antes de criar mais
  uma linha com `dedup_key` incrementado. Mesmo padrão geral ("gerador que não confere saída
  recente antes de duplicar"), mecanismo diferente (linhas de sugestão na fila `robot_suggestions`,
  não ficheiros `ordem-*.md`). Detalhe em `permanente/procedural/aprovador-vermelho-triagem.md`
  (secção "Achado 2026-07-27"). Fora do mandato do `aprovador-vermelho` corrigir (só roteamento) —
  candidato a ordem para `maestro-autonomia`/dono do gerador (evolution-engine ou robot-b) avaliar
  se é a mesma causa-raiz generalizada desta lição ou um bug distinto a documentar à parte.
