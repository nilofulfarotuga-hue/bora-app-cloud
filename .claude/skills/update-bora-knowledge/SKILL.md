---
name: update-bora-knowledge
description: Deteta drift entre a skill bora-knowledge e a realidade do repo (Edge Functions em supabase/functions vs 08-edge-functions.md; pastas de skill vs INDEX.md + contagem). READ-ONLY sobre a knowledge — escreve uma PROPOSTA em _preview/, NUNCA edita os docs (Knowledge Protocol: propor ao Danilo).
metadata:
  type: meta
  category: consolidation
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Update Bora Knowledge

Mantém a `bora-knowledge` honesta. Compara o que os docs afirmam com o que existe
mesmo no repositório e gera uma **proposta** de actualização para revisão.

## Knowledge Protocol (obrigatório)
Esta skill **nunca** escreve em `bora-knowledge/`. Segue o protocolo do CEO-AI:
detecta → **propõe diff ao Danilo** (`_preview/`) → Danilo aprova → edição manual +
entry em `decisions/`. Sync Obsidian fica a cargo do Danilo.

## O que verifica (repo-only, sem credenciais DB)
1. **Edge Functions** — pastas em `supabase/functions/` vs nomes citados em
   `knowledge/08-edge-functions.md`, nos dois sentidos:
   - em código mas não documentadas → sugerir documentar;
   - citadas no doc mas sem pasta → confirmar (renomeada / remota / planeada).
2. **Skills** — pastas reais vs tabela do `INDEX.md` + contagem declarada (`**N skills**`).

## Uso
```bash
python scripts/detect_drift.py            # relatório + _preview/knowledge-drift-<data>.md
python scripts/detect_drift.py --no-file  # só terminal
```

## Saída
- Terminal: relatório PT-PT.
- Ficheiro: `_preview/knowledge-drift-<data>.md` (proposta para o Danilo rever).
- Exit code sempre 0 (informativo; read-only não falha builds).

## Salvaguardas
- **Nunca** edita `bora-knowledge/` nem qualquer doc — só lê e propõe.
- Não toca DB, Stripe, Edge Functions, `lib/`.
- Stdlib-only; reusa o motor meta de `skills-doctor` (DRY).
- Limitação: settings de DB (`platform_settings`) e schema vivo não são verificados
  aqui (precisariam MCP/credenciais) — pendência documentada.
