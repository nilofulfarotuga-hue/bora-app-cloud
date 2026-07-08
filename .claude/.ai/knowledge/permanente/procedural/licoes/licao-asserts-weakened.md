---
tema: licao-asserts-weakened · escopo: agente:juiz-revisor · estado: atual · atualizado: 2026-07-01
natureza: LIÇÃO DE FALHA · gatilho: ASSERTS_WEAKENED
id: licao-asserts-weakened
tipo: licao
origem: [.claude/juiz/anti_trapaca.py]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Não enfraquecer asserções para fingir "verde" (o Juiz apanha por git diff)

- **Contexto:** tarefa de conserto — fazer um teste passar. A tentação foi remover/enfraquecer
  uma asserção (`expect`) em vez de consertar o código sob teste.
- **O que correu mal / a descoberta:** o **chão determinístico** do Juiz
  (`.claude/juiz/anti_trapaca.py`) apanha via **git diff** — o nº de asserções caiu (3→2),
  disparando `ASSERTS_WEAKENED` com **exit 2 = REJEITA**. É **mecânico**, não é outro juiz de IA;
  não dá para "conversar em volta".
- **Regra a aplicar:** consertar o **CÓDIGO sob teste**; a asserção só se **fortalece**, nunca se
  enfraquece/apaga/skipa. Numa tarefa de conserto, o código sob teste **tem de mudar** — senão é
  conserto-fantasma (`PHANTOM_FIX`, também REJEITA).
- **Evidência:** veredito determinístico do Juiz (git diff). `ASSERTS_WEAKENED` em
  `.claude/juiz/anti_trapaca.py` (`if h_assert < b_assert` → REJECT, ~linha 206);
  `PHANTOM_FIX` (~linha 247). Ver `.claude/juiz/README.md`. Fase 4 (2026-07-01).

> Primeira lição de falha do `juiz-revisor` (prova o ciclo de aprendizado: rejeição → lição).
