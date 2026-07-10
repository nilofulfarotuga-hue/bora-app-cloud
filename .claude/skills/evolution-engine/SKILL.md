---
name: evolution-engine
description: Meta-skill de evolução GOVERNADA de skills — lê a telemetria (frontmatter + skills-metrics.md) e o histórico (reports, git) e gera PROPOSTAS de criar/reescrever/arquivar/fundir/dividir skills, em inbox/evolution-report-<data>.md. Zona verde = draft que passa OBRIGATORIAMENTE no Juiz antes de aplicar; skill que toca dinheiro/auth = SÓ PROPOSTA (Danilo aplica). NUNCA modifica a própria evolution-engine. Análise mecânica em scripts/evolution_engine.py (stdlib, read-only sobre skills).
metadata:
  type: meta
  versao: 1
  execucoes: 1
  sucessos: 1
  falhas: 0
  ultima_execucao: 2026-07-10
  criada_por: missao-noturna-2026-07-10 (Fase 5)
---

# Evolution Engine — evolução governada de skills

> Dono agente: `evolution-engine` 🟡 (ver `.claude/agents/evolution-engine.md`).
> ADR: `wiki/decisoes/2026-07-10-evolution-engine-governado.md` — conceitos do EvoSkill
> adotados NATIVAMENTE (opção b): Proposer→propostas · Frontier→versao v+1 no frontmatter ·
> Avaliador→**o Juiz** (não benchmark holdout). Zero runtime novo, zero caixa preta.

## As 5 capacidades (o que o motor deteta)

| # | Capacidade | Gatilho | Saída |
|---|---|---|---|
| 1 | **Detetar padrões** | tarefa repetida ≥3× em reports/orquestração sem skill correspondente | proposta de skill nova + draft 🟢 |
| 2 | **Reescrever** | `falhas/execucoes > 30%` OU 2 rejeições do Juiz pelo mesmo motivo | draft v+1 (Juiz compara v vs v+1) |
| 3 | **Arquivar** | 90 dias sem uso (`ultima_execucao`) | mover p/ `_arquivo/` (NUNCA apagar) |
| 4 | **Fundir** | ≥2 skills com descrição >70% sobreposta | proposta de fusão |
| 5 | **Dividir** | SKILL.md >600 linhas ou responsabilidades misturadas | proposta de split |

## Governança (lei — igual para as 5)

- **🟢 zona verde:** a proposta inclui DRAFT; aplicar exige passar no **Juiz** (chão
  anti-trapaça + camadas). Sem Juiz, o draft não entra.
- **🔴 dinheiro/auth** (skill cujo domínio toca Stripe/pricing/tokens/refund/RLS/auth —
  ex.: refund-assistant, manage-promo-codes, run-weekly-payouts, update-platform-setting,
  deploy-edge-function): **SÓ PROPOSTA**, nunca draft aplicado — o Danilo dá o "vai".
- **Nunca auto-modificação:** propostas sobre `evolution-engine` (skill ou agente) são
  geradas mas marcadas `AUTO-MODIFICAÇÃO — só o Danilo`.
- Proposta **rejeitada** fica registada em `scripts/state/propostas.json` — não se repropõe.
- Proposta **aprovada** → lição/ADR via `bibliotecario-cerebro`.

## Execução

```bash
# análise completa (read-only sobre skills; escreve SÓ o relatório no inbox)
python .claude/skills/evolution-engine/scripts/evolution_engine.py

# sem escrever o relatório (pré-visualização)
python .claude/skills/evolution-engine/scripts/evolution_engine.py --dry-run
```

Saída: `.claude/.ai/knowledge/inbox/evolution-report-<data>.md` — cada proposta com
evidência (números, ficheiros, datas), classificação 🟢/🔴 e ação recomendada.
A parte NÃO-mecânica (drafts de reescrita, análise de responsabilidades misturadas)
é feita pelo agente `evolution-engine` a partir deste relatório — o script deteta,
o agente redige, o Juiz avalia.

## Integração daily-pulse (Hermes)

O daily-pulse ganha o passo `evolution-report` (modo análise, sem aplicar): corre o script,
conta as propostas novas e inclui no resumo do Telegram ("Evolução: N propostas no inbox").

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.

## Admin Panel Needed?
Ainda não — propostas vivem no inbox + Central (`AdminRobotSuggestionsScreen`) quando viram
itens. Sem segundo inbox (guardrail do Danilo).
