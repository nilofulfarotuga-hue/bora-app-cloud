---
id: vigia-e2e-2026-07-15-repeticao
tipo: relatorio
origem: [vigia-e2e (checagem de saude do loop noturno)]
ultima_confirmacao: 2026-07-15
zona: verde
confianca: auto
---

# VIGIA E2E — 2026-07-15: repetição do mesmo gatilho, continua parado DE PROPÓSITO

## Gatilho
Última escrita em `e2e_log` há ~26min (>20min, dentro da janela ativa <90min) —
disparou checagem de saúde do loop noturno. Mesmo padrão de
[[vigia-e2e-2026-07-14-parado]], um dia depois.

## Achado
Nada mudou desde ontem — confirmado de forma independente às 2026-07-15 21:21:
- `.claude/testes-e2e/PARAR` ainda existe (timestamp Jul 14 09:36, conteúdo
  igual): "PARADO A PEDIDO DO DANILO... NAO REMOVER sem autorizacao explicita."
- `Get-ScheduledTask -TaskName "BoraE2E_LoopNoturno"` → **Disabled**.
- Nenhum processo `loop-noturno.py`/`runner.py` a correr — só vários
  `tail_e2e_log.py` (leitores passivos do log, inofensivos, não geram tráfego
  de teste) sobrando desde 2026-07-14 (14:00h–07:03h), sem relação com o
  gatilho.

**Achado extra (mais forte que o de ontem):** o commit `aa58aa4` (2026-07-15
21:06, ~15min antes deste vigia) documenta em
`permanente/procedural/modo-de-trabalho-2026-07-15.md` que **`e2e_log` deixou
de ser fonte de prova** — só log informativo. A fila autónoma
(Córtex→carteiro→campainha→executor VPS) foi desligada no mesmo dia porque o
executor gravava trabalho inventado no `e2e_log` como se fosse facto e o Juiz
da fila não verificava nada. Ou seja: mesmo que o loop estivesse a correr,
"tempo desde a última escrita em `e2e_log`" já não é um sinal válido para
decidir se algo caiu.

## Ação tomada
Nenhuma — nem retomei o loop, nem toquei no PARAR, nem reativei a scheduled
task. Registo aqui para o próximo VIGIA/loop parar de reabrir o mesmo caso:
o PARAR continua válido e o próprio gatilho ("`e2e_log` parado") está
oficialmente desqualificado como prova desde 2026-07-15. Ver
[[modo-de-trabalho-2026-07-15]] antes de confiar em `e2e_log` de novo.
