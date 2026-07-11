---
id: licao-executor-vivo-mas-tarefa-pesada-esgota-tentativas
tipo: licao
origem: [orquestracao/carteiro.sh · hermes-bridge/run-claude-loop.cmd · missão "automação total" 2026-07-11]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: verificado
---

# Lição — "o carteiro morreu" e "o carteiro está vivo mas a tarefa não cabe no orçamento" são coisas diferentes

**Problema.** O Danilo reportou "o carteiro/ponte morreu de novo (ordens em `tentativa: 0` sem
serem apanhadas)". Investigação por SSH mostrou algo diferente do esperado: a campainha
(`inotifywait`) estava **viva** (PID de pé, log a registar eventos), o kill switch
`orquestracao_enabled: true`, e o `carteiro.sh` estava a **processar ordens continuamente** —
mas várias ordens (incl. a própria ordem desta missão, `ordem-...-fb7f`) ficavam em ciclo
`aberta → executando → respondida (SAIDA VAZIA) → CORRIGIR → reaberta` sem nunca fechar,
subindo `tentativa` a cada ~15 min até `travada` (5 tentativas).

**Causa real.** O executor (`pc-loop` → `run-claude-loop.cmd` → `claude.exe -p ... --output-format
text`, timeout 900s / 40 turns / $10) só imprime saída **no fim**. Se a tarefa é grande demais
para caber em 900s (ex.: pedir "faz 8 automações + regista + relatório + push" numa única
ordem), o processo é morto pelo `timeout` a meio e devolve **0 bytes** — o carteiro já sabe
disto e regista corretamente `⚠️ SAIDA VAZIA — ponte viva; tarefa não terminou em 900s`, MAS
isso não impede o padrão de se repetir: a MESMA ordem grande demais volta a `aberta`, é
apanhada de novo, e volta a esgotar o timeout — até travar. Confirmado mesmo em ordens
"pequenas" (ex. `e750`: só 3 comandos Windows) — sugerindo que passos que abrem janelas/GUI
(scrcpy, tasklist interativo) também podem ficar presos no transporte SSH-Windows, não só
tarefas grandes.

**Diagnóstico correto (ordem de verificação, mais rápido primeiro):**
1. `pgrep -f "inotifywait.*orquestracao"` no HOST da VPS — campainha viva?
2. `cat _controlo.md` — kill switch `orquestracao_enabled` ligado?
3. `tail /root/orquestracao/carteiro.log` — está a processar ordens (mesmo que sem fechar)?
4. Só DEPOIS de 1-3 confirmarem problema → suspeitar de carteiro/campainha morta de verdade.
Se 1-3 estão OK mas ordens não fecham → o problema é **orçamento do executor por tentativa**,
não a ponte. Testar isolado: `echo "<b64 tarefa trivial>" | timeout 90 cmd /c
run-claude-loop.cmd --b64stdin` — se isto responde rápido, o transporte está bom; o problema é
mesmo o tamanho/forma da tarefa.

**Mitigação aplicada 2026-07-11:** dividir missões grandes em ordens menores (uma automação por
ordem) em vez de "faz tudo numa ordem só"; e o `hermes-carteiro-vigia.sh` (cron */5, vigia do
vigia) só reinicia a campainha quando ela está **genuinamente morta** — não quando só há uma
ordem pesada a demorar dentro do timeout normal (ver `hermes-carteiro-vigia.sh`, condição
"campainha viva mas ordem parada — não reinicio").

## Regra generalizável
"Saída vazia" de um executor com timeout NÃO é o mesmo sintoma que "processo morto" — tratar os
dois da mesma forma (reiniciar tudo) esconde a causa real e não resolve nada (a próxima tentativa
falha pela mesma razão). Antes de assumir "morreu", separar: **o mensageiro está vivo?** vs **a
mensagem cabe no orçamento de uma entrega?** São dois problemas com soluções diferentes — o
primeiro pede reviver o processo; o segundo pede encolher a tarefa.
