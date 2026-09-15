---
title: Rules History
created: 2026-04-24
tags: [meta, rules, ceo-ai]
---

# Rules History — Bora App

Histórico cronológico de mudanças nas **regras de negócio** do Bora App.

## Propósito

Esta pasta é alimentada pela skill `auto-rules-sync`. Cada vez que uma regra muda (status flow, pricing, roles, launch criteria, tech rule), é criado aqui um ficheiro com o antes/depois, motivo e ficheiros afectados.

Fonte de verdade das regras activas: `.claude/skills/ceo-ai/SKILL.md` no repo `bora_app`.
Este vault guarda apenas o **histórico**.

## Convenção de nomes

```
YYYY-MM-DD-{slug-da-regra}.md
```

Exemplo: `2026-04-24-order-status-add-scheduled.md`

## Frontmatter padrão

```yaml
---
date: YYYY-MM-DD
type: status-flow | pricing | roles | launch | tech-rule | other
files_affected: [lib/models/order_model.dart, CLAUDE.md]
commit: <hash ou "manual">
ceo_ai_section: Architecture Awareness | Current System State | Launch Readiness Checklist
approved_by: Danilo
---
```

## Secções por nota

1. **Antes** — estado anterior da regra
2. **Depois** — novo estado
3. **Motivo** — porquê mudou
4. **Impacto** — o que pode quebrar
5. **Ficheiros** — lista concreta de paths afectados

## Como pesquisar

No Obsidian: usar `tags: rules` ou `type: status-flow` no campo de pesquisa. Smart Connections (plugin já instalado) indexa automaticamente.
