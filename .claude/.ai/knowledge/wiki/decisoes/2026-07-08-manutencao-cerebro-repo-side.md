---
id: adr-manutencao-cerebro-repo-side
tipo: decisao
origem: [gather VPS 2026-07-08: /opt/data só tem obsidian-bora, não o knowledge/]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# ADR — Manutenção do cérebro (inbox/confiança/debt) corre **repo-side**, não no `daily_pulse.py` do VPS

**Contexto.** O Bloco 5 pediu "evoluir o `daily_pulse.py` do Hermes (VPS)" para promover inbox,
recalcular confiança e regenerar o debt. Mas a auditoria de estado (2026-07-08) mostrou que o
cérebro (`.claude/.ai/knowledge/`) **não está sincronizado no VPS** — o container só tem o **vault**
(`/opt/data/obsidian-bora`), não a pasta `knowledge/` com o `inbox/`, `wiki/`, `schema.md`.

**Decisão.** A manutenção **code-side** do cérebro (promover/descartar inbox, decaimento de
confiança, regenerar `_debt.md`) vive num script **repo-side**: [[_tools/cortex_nightly]].
O VPS `daily_pulse.py` continua dono do **pulso de negócio** e passa a **emitir os sinais**
(cancelamentos, GMV, crashes) que a *contradiction engine* repo-side consome.

**PORQUÊ.**
- Forçar a manutenção no VPS seria **trabalhar às cegas** — o script não veria as páginas que devia manter.
- Respeita o desenho **bicameral** da Fase 0: *código manda no repo; negócio manda no VPS*.
- Reversível e testável localmente (onde o cérebro vive), sem tocar produção.

**Consequência / dependência aberta 🟡.** Para a *contradiction engine* cruzar `wiki/codigo/` × pulso,
falta uma ponte que leve os **sinais de negócio** do VPS ao repo (ou o `knowledge/` ao VPS). Fica
**staged** — ver relatório `fase_final_completa.md` §Bloco 5.
