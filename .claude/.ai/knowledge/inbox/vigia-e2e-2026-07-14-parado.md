---
id: vigia-e2e-2026-07-14-parado
tipo: relatorio
origem: [vigia-e2e (checagem de saude do loop noturno)]
ultima_confirmacao: 2026-07-14
zona: verde
confianca: auto
---

# VIGIA E2E — 2026-07-14: loop parado DE PROPÓSITO, não é queda

## Gatilho
Última escrita em `e2e_log` há ~24min (>20min, dentro da janela ativa <90min) —
disparou checagem de saúde do loop noturno.

## Achado
Não é uma queda a meio. Achei o ficheiro `.claude/testes-e2e/PARAR` (criado hoje,
2026-07-14) com o conteúdo:

> PARADO A PEDIDO DO DANILO EM 2026-07-14 — Danilo vai testar manualmente.
> NAO REMOVER sem autorizacao explicita.
> Tarefa agendada BoraE2E_LoopNoturno foi desativada (Disable-ScheduledTask) alem deste ficheiro.

Confirmado de forma independente:
- Nenhum processo `python.exe` a correr `loop-noturno.py` ou `runner.py` (só
  `tail_e2e_log.py`, que é só leitura de monitor, e processos `graphify-mcp`
  sem relação).
- `Get-ScheduledTask -TaskName "BoraE2E_LoopNoturno"` → **Disabled** (bate certo
  com o ficheiro PARAR).
- Último evento no `loop-noturno-2026-07-14.json`: device adb caiu e "NÃO voltou
  após 15 tentativas" → o próprio loop fez limpeza pós-ciclo e não reagendou
  (coerente com paragem intencional logo a seguir).

## Ação tomada
Nenhuma. Não retomei o loop, não removi o PARAR, não reativei a scheduled task —
o ficheiro é explícito ("NAO REMOVER sem autorizacao explicita") e o Danilo está
a testar manualmente. Só registo aqui para o próximo VIGIA/loop noturno não
tentar "consertar" isto de novo.
