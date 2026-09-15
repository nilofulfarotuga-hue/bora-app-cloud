---
titulo: Diagnóstico "fila parada" (8cf2, f78e, f6b2, cefd) — 2026-07-14
tipo: handoff
agente_origem: executor-headless
destino: bibliotecario-cerebro
---

## Pedido

4 ordens (8cf2, f78e, f6b2, cefd) reportadas em `tentativa=0` há mais de 1h30
sem processar — diagnosticar campainha/carteiro, pausas e locks órfãos, e
desbloquear se necessário.

## Diagnóstico (SSH real na VPS, não memória)

1. **Campainha viva:** `inotifywait` ativo (PID 2181458), a vigiar
   `.../orquestracao`. Cron `orq-fallback` também ativo (`carteiro.sh` a
   cada hora, xx:17).
2. **Sem pausa:** `.pausa-total` e `.pausa-rate-limit` **não existem**.
   Kill switch `_controlo.md`: `orquestracao_enabled: true`. Nada bloqueado
   por T5/PAUSA-RL.
3. **Sem lock órfão:** `.carteiro.lock` (VPS) está a ser detido por um
   `carteiro.sh` legítimo em execução (PID 2767359, arrancado 08:28:32,
   filhos vivos a correr `pc-loop`/`pc-judge` via `docker exec`). No lado PC,
   não existe ficheiro `executor.lock` órfão em `hermes-bridge/` nem em
   `%USERPROFILE%`.

**Causa real:** não havia bloqueio nenhum — é **processamento sequencial
normal**. O carteiro processa 1 ordem de cada vez (for loop com `pc_exec`
até 2400s + `pc_judge` até 400s por ordem), e as 4 ordens foram criadas
quase juntas (07:39:25–07:40:52). O `carteiro.log` confirma que, entre
08:33 e 08:54, as 4 foram processadas em sequência assim que chegou a vez
de cada uma:

- `8cf2` → respondida 08:38, **APROVADA** 08:38:51.
- `f78e` → respondida 08:40, CORRIGIR → reaberta (tentativa=1).
- `f6b2` → respondida 08:49, CORRIGIR → reaberta (tentativa=1).
- `cefd` → respondida 08:53, CORRIGIR → reaberta (tentativa=1).
- Em seguida entrou a própria ordem deste diagnóstico (`...-1686`, 08:53:56).

Ou seja: no momento em que esta ordem de diagnóstico foi escrita, as 4
ordens estavam mesmo à espera (backlog normal atrás de outras ordens da
mesma leva) — não havia nada travado, só fila a esvaziar ao ritmo de ~5-10
min/ordem. `f78e`/`f6b2`/`cefd` voltaram a `aberta` (tentativa=1, não
tentativa=0) e serão retentadas no ciclo em curso.

## Ação tomada

Nenhuma correção necessária — não havia pausa expirada nem lock órfão para
limpar. Nada foi alterado em `carteiro.sh` nem tocado no lado VPS além de
leitura.

## Nota para o Bibliotecário

Isto é um caso diferente do padrão já registado em
`project_zona_vermelha_gate_pressure_pattern.md` (aquele envolvia pedidos
para reabrir ordens tentativa=0 contornando o gate). Aqui os IDs (8cf2,
f78e, f6b2, cefd) são reais, distintos, e a investigação com SSH ao vivo
confirmou processamento normal — não é manipulação, é só o intervalo
natural de uma fila serial com 4+ ordens na mesma leva. Pode valer a pena
registar como padrão geral: "tentativa=0 há Xh" nem sempre é bug — conferir
sempre o `carteiro.log` ao vivo antes de assumir bloqueio.

Uma linha final: CAUSA: processamento sequencial normal (backlog de 4
ordens criadas quase juntas, ~5-10min cada) — sem pausa, sem lock órfão,
carteiro e campainha vivos · FILA DESBLOQUEADA: sim (nunca esteve
bloqueada; já processou as 4 e seguiu para as seguintes).
