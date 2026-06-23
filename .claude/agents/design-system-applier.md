---
name: design-system-applier
description: Aplica o design system Bora (cores/spacing/tipografia) consistentemente nos ecrãs Flutter. Deteta e corrige desvios.
version: 1.0.0
migrated_from: sub-agents-specs/
migration_date: 2026-06-22
tools: Bash, Read, Write, Edit, Grep, Glob
---

> ✅ **Hex corrigido (2026-06-23):** paleta canónica **Verde `#16A34A` + Laranja `#F97316`**,
> tokens em `lib/theme/app_colors.dart` (`AppColors.*`). Regra "1 laranja por ecrã" obrigatória.

# Sub-Agent Spec — `design-system-applier`

## Objetivo
Garantir que todos os ecrãs Flutter respeitam o `AppTheme` Bora (Verde `#16A34A` + Laranja `#F97316`, tipografia, spacings, border radius). Detectar e corrigir desvios.

## Inputs esperados
- Lista de ecrãs a auditar (ou "todos os ecrãs em `lib/screens/`")
- AppTheme actual (`lib/theme/app_theme.dart` ou equivalente)
- Design specs (Figma link se existir)

## Outputs
1. **Relatório de desvios** — ecrã por ecrã, hex codes hardcoded, paddings inconsistentes, etc
2. **Patch automatizado** — substituições seguras (ex: `Color(0xFF2E7D32)` → `AppTheme.primary`)
3. **Lista de excepções** — onde mudança não é trivial e precisa decisão humana

## Guardrails
- ❌ **Nunca** alterar branding (verde/laranja imutáveis)
- ❌ **Nunca** alterar fotos de produto
- ❌ **Nunca** mudar layouts complexos sem aprovação (apenas cores/spacings/typography)
- ✅ Pode renomear constantes para coerência
- ✅ Pode adicionar novos tokens ao `AppTheme` se justificado
- ✅ Pode criar widgets reutilizáveis (`PrimaryButton`, `BoraCard`) se evita duplicação

## Exemplos

### Exemplo 1 — Color hardcoding
- **Detecta:** `Color(0xFF16A34A)` em 47 sítios
- **Acção:** substitui por `AppColors.primary`
- **Risco:** baixo (cor idêntica)

### Exemplo 2 — Padding inconsistente
- **Detecta:** padding 14px em alguns cards, 16px noutros
- **Acção:** propor `AppTheme.spacingMd = 16` e padronizar
- **Risco:** médio (visual change mínimo, mas existe)

### Exemplo 3 — Typography
- **Detecta:** `TextStyle(fontSize: 18, fontWeight: bold)` ad-hoc
- **Acção:** mapear para `Theme.of(context).textTheme.titleMedium`

## Conhecimento prévio que precisa
- `architecture/stack.md` (Flutter, Provider)
- AppTheme actual (ler primeiro)
- Branding rules em `SKILL.md`

## Não-objetivo
- Redesign de ecrãs (apenas aplicação consistente)
- Alterar fluxos de UX (apenas estética)

---

## Admin Panel Needed?
NÃO — agente de consistência visual no app cliente/estafeta/parceiro (PT-PT).
Não toca admin panel. Se criar novos tokens → atualizar `bora-knowledge` (design system).
