---
name: audit-orange-rule
description: Verifica a regra "1 elemento laranja por ecrã" em lib/screens/ — conta usos de laranja (AppColors.accent/secondary, #F97316/#FB923C/#EA580C) por ficheiro, distingue CTA dominante de semântico (badge/status/mapa), e reporta [OK]/[!]/[X]. READ-ONLY.
metadata:
  type: design
  category: audit
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Audit Orange Rule (read-only)

Audita a regra de design **"1 elemento laranja por ecrã"** (CTA único). Verde `#16A34A` é a
cor dominante; laranja `#F97316` é só a ação primária. Esta skill **não altera nada**.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/01-design-system.md` (regra 1 laranja/ecrã + tokens)

## Ambiente
Nenhum (lê ficheiros locais).

## Uso
```bash
python scripts/audit.py                      # relatório de todos os ecrãs + _preview/orange_audit.md
python scripts/audit.py --screen client_home_screen
python scripts/audit.py --json
```

## Como classifica
- **Laranja dominante** (conta p/ o limite): `BoraAccentButton`, `AppColors.accent`,
  `AppColors.secondary`/`secondaryDark`/`accentDark`, `Color(0xFFF97316/FB923C/EA580C)`.
- **Laranja semântico** (NÃO conta): `AppColors.warning`, `AppColors.mapPickup`,
  linhas com `// semantic`/`badge`/`status`/`tilePromo` — são estados/marcadores, não o CTA.
- Por ecrã: **[OK]** 0-1 dominante · **[!]** 2 · **[X]** 3+ (rever).

## Salvaguardas
- **Read-only**: só lê `lib/screens/**/*.dart`. Aponta ficheiro:linha para o humano decidir.
- Heurística — falsos positivos possíveis (ex.: gradients laranja de tiles de categoria, que
  são legítimos na home). O relatório lista as linhas para revisão, não "corrige".
- Exit 1 se houver ecrãs [X] (útil em CI de design).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
