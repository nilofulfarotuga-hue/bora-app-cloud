---
name: migrate-screen-to-design
description: Re-skin de 1 ecrã para o design system (MODO A patch generator) — substitui hex de marca/semânticos por AppColors tokens, sinaliza AppBar custom→BoraScreenAppBar e accent rows. Gera diff em _preview/; NÃO toca lib/ sem --apply. Não altera lógica/Stripe/realtime.
metadata:
  type: design
  category: codegen
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

# Migrate Screen to Design (Modo A)

Migra 1 ecrã para o design system **gerando um diff para revisão**. **Não edita `lib/`** sem
`--apply`. Replica o protocolo cirúrgico da Fase 4: só cores/estética, **nunca** lógica.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/01-design-system.md` (tokens + regra 1 laranja)
2. `bora-knowledge/knowledge/04-widgets-bora.md` (BoraScreenAppBar etc.)
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Uso
```bash
python scripts/analyze_screen.py --screen cart_screen          # tabela de mudanças propostas
python scripts/generate_patch.py --screen cart_screen          # gera _preview/cart_screen.diff
python scripts/generate_patch.py --screen cart_screen --apply  # backup + escreve + flutter analyze
```

## Transformações (só as seguras/automáticas)
Substitui literais de cor **inequívocos** por tokens (mapa de marca/semânticos):
`#16A34A→primary`, `#065F46→primaryDark`, `#F97316→accent`, `#EA580C→accentDark`,
`#F0F2EF→background`, `#6B7280→textSecondary`, `#111111→textPrimary`, `#E5E7EB→divider`,
`#DC2626→error`, `#F59E0B→warning`. **Não** substitui branco/preto (ambíguos) — só sinaliza.
Sinaliza (não auto): AppBar custom→`BoraScreenAppBar`, `_SummaryRow` accent, import de `app_colors`.

## Modos
- **DEFAULT (gerar)**: `analyze_screen` (tabela) / `generate_patch` (diff em `_preview/`). NÃO escreve em `lib/`.
- **`--apply`**: backup em `_preview/backup/` → escreve → `flutter analyze` (best-effort).

## Salvaguardas
- MODO A: diff primeiro, `--apply` explícito. Só toca **literais de cor** + adiciona import se preciso.
- **NÃO** altera lógica, Stripe, realtime, dispatch, strings, nem fotos.
- Garante `import '.../app_colors.dart'` se introduzir `AppColors.`.
- Branco/preto e hex fora do mapa → só sinalizados (decisão humana).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
