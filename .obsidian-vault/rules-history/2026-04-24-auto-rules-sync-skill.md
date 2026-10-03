---
date: 2026-04-24
type: tech-rule
files_affected:
  - .claude/skills/auto-rules-sync/SKILL.md
  - .claude/hooks/auto-rules-sync-notify.sh
  - .claude/settings.json
commit: manual
ceo_ai_section: Decision Rules > SEMPRE
approved_by: Danilo
tags: [rules, tech-rule, meta, skills, obsidian, ceo-ai]
---

# Skill auto-rules-sync criada + hook PostToolUse

## Antes

Não existia mecanismo formal para sincronizar regras de negócio entre:
1. Código + docs (CLAUDE.md, PROJECT_CONTEXT.md, enums)
2. CEO-AI skill (`.claude/skills/ceo-ai/SKILL.md`)
3. Histórico Obsidian

Mudanças de regras ficavam documentadas só onde foram feitas; o CEO-AI desactualizava-se silenciosamente e o Obsidian não tinha histórico cronológico.

Exemplo concreto: `PROJECT_CONTEXT.md` afirmava que pagamentos usavam `BACKEND_BASE_URL`, mas código Dart já tinha migrado para Supabase Edge Functions há meses. O CEO-AI herdava a informação errada.

## Depois

### Nova skill: `auto-rules-sync`

Localização: `.claude/skills/auto-rules-sync/SKILL.md`

Protocolo em 5 fases:
- **Fase 0:** detecção (via git diff em modo automático, ou input manual)
- **Fase 1:** validação + mapeamento (identificar secção CEO-AI + construir diff)
- **Fase 2:** STOP para aprovação explícita do Danilo (MODO PROTECÇÃO TOTAL — uma aprovação cobre uma regra)
- **Fase 3:** escrita no CEO-AI via Edit tool (cirúrgica, preserva formatação)
- **Fase 4:** registo no Obsidian em `rules-history/YYYY-MM-DD-{slug}.md` com frontmatter completo

Inputs obrigatórios: `rule_type` (status-flow | pricing | roles | launch | tech-rule | other), `description_before`, `description_after`, `files_affected`, `reason`, `commit`.

### Hook PostToolUse

- Ficheiro: `.claude/hooks/auto-rules-sync-notify.sh`
- Config: `.claude/settings.json` (hook PostToolUse em git commits)
- Comportamento: quando git commit toca em `CLAUDE.md`, `PROJECT_CONTEXT.md` ou `lib/models/*.dart`, apenas **notifica** que há potencial drift. Execução real continua a exigir invocação explícita da skill (MODO PROTECÇÃO TOTAL preserva-se).

### Regra no CEO-AI

Adicionada em `Decision Rules > SEMPRE`:
> Quando regra de negócio mudar: invocar `/auto-rules-sync` para sincronizar CEO-AI + Obsidian (rules-history/)

## Motivo

Eliminar drift silencioso entre fontes. Antes desta skill, o CEO-AI podia aconselhar decisões baseadas em realidade obsoleta (ex.: "Stripe requer BACKEND_BASE_URL" quando já não é verdade). Com auto-rules-sync + hook, a probabilidade de drift é baixa e detectável.

## Impacto

- **Meta:** esta própria nota foi criada usando a skill que ela documenta (primeiro uso real).
- **Não quebra:** nada — é puramente adicional, documentação e hooks.
- **Força nova disciplina:** qualquer mudança de regra passa a ter registo cronológico no Obsidian.
- **Requer invocação manual:** o hook só notifica, não executa. MODO PROTECÇÃO TOTAL preservado.
- **Custo de uso:** ~3-5 edits por regra (CEO-AI + 1 ficheiro Obsidian). Vale o tradeoff por ter histórico auditável.

## Ficheiros

- `.claude/skills/auto-rules-sync/SKILL.md` (skill definition, 6559 bytes)
- `.claude/hooks/auto-rules-sync-notify.sh` (hook script)
- `.claude/settings.json` (registo do hook PostToolUse)
- `.claude/skills/ceo-ai/SKILL.md` — secção SEMPRE actualizada
- `C:\Users\danil\Desktop\bora\rules-history\` — vault Obsidian (directório de destino)
