---
name: auto-rules-sync
description: >
  Sincroniza regras de negócio do Bora App entre três fontes: código/docs
  (CLAUDE.md, PROJECT_CONTEXT.md, enums em lib/models/), a skill CEO-AI
  (.claude/skills/ceo-ai/SKILL.md) e o vault Obsidian em
  C:\Users\danil\Desktop\bora\rules-history\. Detecta mudanças via git diff
  ou input manual, propõe o update ao Danilo (MODO PROTECÇÃO TOTAL), aplica
  após aprovação, e regista a mudança com timestamp no Obsidian. Triggers:
  "regra mudou", "rule changed", "actualizar business rules",
  "/auto-rules-sync", "sync CEO-AI rules", "business rule update".
metadata:
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Auto Rules Sync — Skill

## Propósito

Garantir que as **regras de negócio** do Bora App estão sincronizadas em três fontes que tendem a divergir:

1. **Código + docs** — `CLAUDE.md`, `PROJECT_CONTEXT.md`, enums em `lib/models/` (ex.: `OrderStatus`, `OrderServiceType`, `PaymentMethod`, `VehicleType`, `BusinessCategory`)
2. **CEO-AI skill** — `.claude/skills/ceo-ai/SKILL.md` (secções `Current System State`, `Architecture Awareness`, `Launch Readiness Checklist`)
3. **Obsidian** — `C:\Users\danil\Desktop\bora\rules-history\` (histórico cronológico)

A fonte de verdade **activa** é o código. O CEO-AI deve reflectir o código. O Obsidian guarda o **histórico** de como chegámos aqui.

---

## Quando esta skill dispara

- Trigger manual: `/auto-rules-sync`, "regra mudou", "actualizar business rules"
- Trigger automático (hook `PostToolUse` em git commits): apenas **notifica** que foi detectada mudança em ficheiros-chave. A execução real continua a exigir invocação explícita (MODO PROTECÇÃO TOTAL).

---

## Inputs (obrigatórios)

| Campo | Exemplo |
|-------|---------|
| `rule_type` | `status-flow` \| `pricing` \| `roles` \| `launch` \| `tech-rule` \| `other` |
| `description_before` | "6 status: created → ... → delivered" |
| `description_after` | "7 status: created → scheduled → ... → delivered" |
| `files_affected` | `["lib/models/order_model.dart", "CLAUDE.md"]` |
| `reason` | "Pedidos agendados exigem novo estado intermédio" |
| `commit` | hash curto ou `manual` |

Se input vier em linguagem natural, a skill extrai estes campos e confirma com o Danilo antes de avançar.

---

## Fluxo de execução (5 fases)

### Fase 0 — Detecção

**Modo automático (via hook)**:
```bash
git diff HEAD~1 HEAD --name-only
```
Se tocar em: `CLAUDE.md`, `PROJECT_CONTEXT.md`, ou qualquer `lib/models/*.dart` → dispara notificação.

**Modo manual**: Danilo descreve a mudança. A skill pergunta os campos em falta.

### Fase 1 — Validação & Mapeamento

1. Ler o ficheiro actual do CEO-AI: `.claude/skills/ceo-ai/SKILL.md`
2. Identificar a secção exacta a actualizar (ver tabela abaixo)
3. Construir o diff proposto (antes/depois, linha a linha)
4. Mostrar ao Danilo em formato:
   ```
   REGRA: {rule_type}
   FICHEIRO CEO-AI: .claude/skills/ceo-ai/SKILL.md
   SECÇÃO: {ceo_ai_section}
   DIFF:
     - linha antiga
     + linha nova
   OBSIDIAN: rules-history/YYYY-MM-DD-{slug}.md
   ```

### Fase 2 — STOP: aprovação Danilo

**MODO PROTECÇÃO TOTAL**. Nunca avançar sem `"aprovo"` / `"sim, aplica"` explícito. Uma única aprovação cobre **uma** regra, não um lote.

### Fase 3 — Escrita no CEO-AI

- Usar **Edit tool** (não Write) para edição cirúrgica
- Só tocar na linha/bloco mapeado
- Preservar formatação, indentação, emojis existentes
- Após escrita, reler o ficheiro e confirmar que o diff corresponde ao proposto

### Fase 4 — Registo no Obsidian

Criar `C:\Users\danil\Desktop\bora\rules-history\YYYY-MM-DD-{slug}.md` com o template:

```markdown
---
date: 2026-04-24
type: status-flow
files_affected:
  - lib/models/order_model.dart
  - CLAUDE.md
commit: a1b2c3d
ceo_ai_section: Architecture Awareness
approved_by: Danilo
tags: [rules, {rule_type}]
---

# {Título curto da regra}

## Antes
{descrição do estado anterior}

## Depois
{descrição do novo estado}

## Motivo
{porquê mudou}

## Impacto
{o que pode quebrar, que componentes PRONTOS são afectados}

## Ficheiros
- `path/to/file.dart` — que alteração
- `CLAUDE.md` — que secção
```

Slug: `kebab-case` curto (≤ 5 palavras). Ex.: `order-status-add-scheduled`.

---

## Mapeamento regra → secção CEO-AI

| `rule_type` | Secção em `.claude/skills/ceo-ai/SKILL.md` |
|-------------|---------------------------------------------|
| `status-flow` | `## Architecture Awareness` → bloco "Order Status Flow" |
| `pricing` | `## Current System State` → bloco PRONTO/PARCIAL (Pricing engine) |
| `roles` | `## Architecture Awareness` → bloco "Roles" |
| `launch` | `## Launch Readiness Checklist` |
| `tech-rule` | `## Architecture Awareness` → bloco "Key Technical Rules" |
| `other` | Perguntar ao Danilo antes de mapear |

Se a mudança afecta **2 ou mais** secções → escalation (ver abaixo).

---

## O que esta skill NÃO faz

- NÃO edita código fonte (`lib/`, `backend/`, `supabase/`)
- NÃO edita `CLAUDE.md` nem `PROJECT_CONTEXT.md` (esses são a fonte — são **lidos**, não escritos)
- NÃO edita outras skills (`market-data-sync`, `category-mapper-v2`, etc.)
- NÃO faz commit automático
- NÃO envia notificações para fora do ambiente local

Escopo total: `.claude/skills/ceo-ai/SKILL.md` + `C:\Users\danil\Desktop\bora\rules-history\*.md`.

---

## Casos edge

- **Regra ambígua** (ex.: muda pricing E launch criteria ao mesmo tempo) → criar **duas notas** no Obsidian, pedir aprovação dupla no CEO-AI.
- **Regra reverte mudança anterior** → ligar a nota nova à antiga via campo `reverts: rules-history/YYYY-MM-DD-old-slug.md` no frontmatter.
- **Commit detectado mas sem mudança semântica** (ex.: rename de variável) → skill deve abortar na Fase 1 com `"sem mudança de regra detectada"`.
- **Ficheiro CEO-AI não tem a secção mapeada** → parar e perguntar ao Danilo onde criar.

---

## Escalation (pedir confirmação dupla)

Disparar aviso extra quando:
- Mudança afecta ≥ 2 secções do CEO-AI
- Regra toca em componente marcado como **PRONTO** no CEO-AI
- Regra toca em `payment` / `stripe` / `order status flow` / `driver capacity`
- Diff proposto > 20 linhas

---

## Critério de feito

Para uma invocação estar concluída:

1. Ficheiro `.claude/skills/ceo-ai/SKILL.md` actualizado na secção correcta
2. Nota criada em `C:\Users\danil\Desktop\bora\rules-history\YYYY-MM-DD-{slug}.md`
3. Diff real === diff proposto (verificado por releitura)
4. Mensagem final ao Danilo com os dois paths + 1 linha resumo

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
