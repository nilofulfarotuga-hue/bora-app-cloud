---
id: inbox-camada
tipo: conceito
origem: [prompt Danilo Fase Final Bloco 2, schema.md]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 📥 INBOX — memória descartável (antes do permanente)

> Camada **antes** do `permanente/`. Aqui nascem sessões cruas, experimentos, notas
> temporárias e relatórios de sessão. **Nada nasce direto no permanente** — passa por aqui.
> Regra herdada do [[schema]]: **toda página paga aluguel.** Só sobe ao `wiki/` o que tem
> `origem` verificável **ou** vira regra generalizável.

## A regra dos 14 dias (o coração do inbox)
- Uma entrada que **ninguém promove** ao `wiki/` (permanente) em **14 dias** é **movida** para
  `inbox/_descartado/` (recuperável **30 dias**), **nunca apagada**.
- Quem promove/descarta **não é o humano** — é a **consolidação noturna**
  ([[_tools/cortex_nightly]]), que corre em modo **dry-run por defeito** (propõe; só aplica com `--apply`).
- Promover = mover para `permanente/` **e** carimbar frontmatter de identidade completo.
- Descartar ≠ apagar. `_descartado/` guarda 30 dias; findos os 30, o Bibliotecário decide arquivar em `_arquivo/`.

## O que entra aqui
- Relatórios de sessão (os que antes nasciam em `sessao/` / `sessions/`).
- Experimentos e rascunhos de regra ainda **não confirmados**.
- Achados de auditoria que ainda não viraram decisão ([[wiki/decisoes]]) nem lição ([[wiki/licoes]]).

## O que **não** entra aqui
- Factos já confirmados com fonte → `permanente/semantica/`.
- Decisões com PORQUÊ → `wiki/decisoes/`. Lições generalizáveis → `wiki/licoes/`.
- Zona 🔴 (dinheiro/RLS/dispatch/pricing/tokens/stripe) — **nunca** auto-promovida; só proposta.

## Estado inicial (2026-07-08)
Semeado com **9 registos de sessão** re-alojados de `knowledge/sessions/` (que era um duplicado
tracked do `sessao/` efémero). O relógio dos 14 dias começa na primeira corrida do `cortex_nightly`.
