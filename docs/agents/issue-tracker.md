# Fila de trabalho: ficheiros locais (NAO GitHub Issues)

> Decidido na missao `skills-matt-pocock-2026-08-29`. Nao reabrir sem ordem nova.

## A regra que manda

**A fila real do Bora e o Cortex.** As skills nunca abrem uma segunda fila.
E proibido criar issues no GitHub, no Linear ou em qualquer tracker externo,
mesmo que o repo tenha remote de GitHub (`nilofulfarotuga-hue/bora-app-cloud`).

Quando uma skill disser "publica no issue tracker", escreve um ficheiro local.
Quando disser "abre um issue", escreve um ficheiro local. Nunca `gh issue create`.

## Onde ficam os ficheiros

- Um assunto por pasta: `.scratch/<slug>/`
- A especificacao: `.scratch/<slug>/spec.md`
- Os bilhetes: `.scratch/<slug>/issues/<NN>-<slug>.md`, numerados de `01`
- Estado no topo do ficheiro, numa linha `Status:`
- Conversa acrescenta-se no fundo, sob `## Comments`

`.scratch/` e area de trabalho efemera. **O que tem valor duradouro nao fica ali** —
sobe para `.claude/.ai/knowledge/` pela mao do `bibliotecario-cerebro`, que e o unico
agente que escreve na memoria permanente (ver `PROTOCOLO.md`).

## Skills que leem isto

`to-spec`, `to-tickets`, `triage` e `wayfinder` — **nenhuma esta instalada**, por decisao
da mesma missao, precisamente para nao existir uma segunda fila. Este ficheiro existe
para que, se alguma vier a ser instalada, ja encontre a regra escrita.

## Rotulos de triagem

Nao ha. A skill `triage` nao esta instalada, por isso a Seccao B do setup foi saltada e
`docs/agents/triage-labels.md` nao foi escrito. Se um dia for precisa, o vocabulario
minimo acordado e: `bug`, `feature`, `divida`.
