---
id: adr-evolution-engine-governado
tipo: decisao
origem: [missão noturna 2026-07-09/10 — Fase 5]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# ADR — Evolution Engine GOVERNADO (não plataforma paralela)

**Data:** 2026-07-10 · **Estado:** aceite (execução da missão noturna; ratificação do Danilo pendente no relatório)

## Contexto
A Fase 5 da missão noturna pede um motor de evolução de skills: telemetria universal +
capacidade de criar/reescrever/arquivar/fundir/dividir skills com base em dados.
Estudado `github.com/sentient-agi/EvoSkill` (Apache 2.0, v1.3.0 jun/2026, ~1k stars).

## Decisão 1 — EvoSkill: opção (b), só conceitos nativos
- **Porquê não adotar (a):** exige Python 3.12+/uv, Docker/Daytona, benchmark holdout e um
  loop autónomo Proposer→Generator→Avaliador→Frontier que muta prompts/skills sozinho —
  **caixa preta em cima do loop de autonomia do Bora**, contra o envelope de segurança
  (Trava · Juiz · Tetos · Humano · Kill switch). O Bora não tem benchmark de skills; o
  "conjunto de validação" aqui é o Juiz + o Danilo.
- **O que se adota nativamente:** Proposer → propostas com evidência (evolution-report);
  Frontier/versionamento → `versao` v+1 no frontmatter + git; Avaliador → **o Juiz**
  (anti-trapaça + camadas), não um score automático.
- **Custo:** zero runtime novo (stdlib), zero dependências.

## Decisão 2 — Estender bibliotecário+Juiz, NÃO criar plataforma paralela
O ciclo de evolução usa as instituições que já existem: telemetria no frontmatter das
skills (padrão diretor-criativo) + `wiki/skills-metrics.md` (consolidação) + propostas no
inbox + gate do Juiz + lições via `bibliotecario-cerebro`. Nenhum banco novo, nenhum
segundo inbox (guardrail do Danilo).

## Decisão 3 — Proposta > auto-aplicação
- 🟢 zona verde: draft OBRIGATORIAMENTE via Juiz antes de aplicar.
- 🔴 dinheiro/auth: SÓ PROPOSTA — a Trava bloqueia; o Danilo dá o "vai".
- O evolution-engine **nunca se auto-modifica** (nem skill nem agente próprios).
- Rejeitada → registada em `state/propostas.json`, não se repropõe. Aprovada → lição/ADR.

## Consequências
- 3 agentes novos no exército (26→29): `diretor-criativo`🟢, `social-media`🟢,
  `evolution-engine`🟡 (ver `permanente/semantica/exercito.md` + CLAUDE.md).
- Meta-skill `.claude/skills/evolution-engine/` (SKILL.md + scripts/evolution_engine.py).
- Daily-pulse ganha passo `evolution-report` (contagem de propostas no Telegram).
- Telemetria universal: 49 skills com frontmatter padrão (46 rollout 2026-07-10 + 3 nativas).
