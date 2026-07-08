---
id: adr-evoluir-knowledge-como-cortex
tipo: decisao
origem: [fase0_auditoria_blueprint.md, decisão Q1 do Danilo]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# ADR — Evoluir `.claude/.ai/knowledge/` como o Córtex (não criar `.cortex/` paralelo)

**Contexto.** A Fase 0 propôs uma estrutura `.cortex/`. A auditoria revelou que
`.claude/.ai/knowledge/` **já é** um cérebro Karpathy ~80% pronto (INDEX + PROTOCOLO +
`permanente/{semantica,episodica,procedural}` + `sessao` + `_arquivo`, 47 .md).

**Decisão (Danilo, Q1).** **Evoluir o existente.** Não se cria um `.cortex/` paralelo.
As camadas novas (`inbox/`, `wiki/{decisoes,licoes}`, `schema.md`, `_debt.md`, `_tools/`)
nascem **dentro** de `.claude/.ai/knowledge/`.

**PORQUÊ.**
- Evita um **terceiro** cérebro descoordenado (já houve 3 fontes: vault canónico, vault velho, knowledge).
- Zero migração destrutiva; o INDEX/PROTOCOLO já respeitam o invariante ~24 KB.
- Menos retrabalho: só se **acrescenta** as peças em falta, não se reconstrói.

**Consequências.** O nome "Córtex" refere-se a `.claude/.ai/knowledge/`. A blueprint da Fase 0
que dizia `.cortex/` fica **superada** por esta ADR.
