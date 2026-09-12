---
id: tools-cortex-nightly
tipo: conceito
origem: [prompt Danilo Fase Final Bloco 5]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 🌙 `_tools/` — o cérebro cuida-se sozinho (com trava humana)

## `cortex_nightly.py`
Manutenção noturna do Córtex, **repo-side** (é onde o cérebro vive — ver [[wiki/decisoes/2026-07-08-manutencao-cerebro-repo-side]]).

- **DRY-RUN por defeito.** `python cortex_nightly.py` → só **propõe**, escreve `inbox/_reports/nightly-<hoje>.md`.
- **`--apply`** → move inbox vencido (>14d, não referenciado) para `inbox/_descartado/` (movido, **não apagado**) e reescreve `_debt.md`.
- **Nunca** toca páginas `zona: vermelha` — só as lista como proposta. Aditivo e reversível.

Faz: (1) confiança derivada por decaimento; (2) regenera [[_debt]]; (3) inbox aging (regra dos 14 dias); (4) *contradiction scan* (stub).

## Como ligar (cron) — **começa cauteloso** (dry-run)
- **PC / repo (recomendado):** Task Scheduler do Windows OU um cron do WSL a correr `python cortex_nightly.py` diário. Começa **sem `--apply`** (só relatório); ativa `--apply` quando confiares.
- **Dependência 🟡 aberta (contradiction engine):** precisa dos **sinais de negócio** do VPS. Duas vias possíveis (a decidir):
  1. o `daily_pulse.py` do Hermes exporta `inbox/_signals.json` (cancel_pct, GMV, crashes) via a ponte; ou
  2. estende-se a sync para levar `knowledge/` ao VPS. Sem os sinais, o scan corre em **modo parcial** (não falha).
