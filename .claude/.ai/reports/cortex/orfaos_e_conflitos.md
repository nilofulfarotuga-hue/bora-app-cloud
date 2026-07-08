# Córtex — Mapa de Órfãos e Conflitos (Fase 1A · Passo 1)

> Read-only na origem. Comparação por **basename + hash SHA-256 + mtime** entre o vault **canónico**
> (`bora_app/.obsidian-vault/`, 116 .md) e o **velho** (`C:\Users\danil\Desktop\Bora`, 88 .md).
> O velho fica **intacto** até ao gate de aprovação. Gerado 2026-07-08.

## Contagens
| Métrica | Nº |
|---|---|
| .md no canónico | 116 (110 nomes) |
| .md no velho | 88 (83 nomes) |
| **Órfãos** (nome só no velho) | 38 (33 únicos por conteúdo) |
| **Conflito de conteúdo** (nome em ambos, hash difere) | **1** |
| Idênticos (já migrados) | 49 |
| Velho editado **depois** da migração (2026-05-04) | 33 |

## 🟢 Órfãos trazidos para o canónico (Passo 2 — cópia aditiva → `.obsidian-vault/_importado-velho/`)
O velho continua intacto; foi feita **cópia**. Deduplicado por conteúdo (5 pares idênticos no velho → 1 cópia).

| Grupo (origem no velho) | Ficheiros | Data | Valor |
|---|---|---|---|
| `Bora App/knowledge/` | 00-auto-facts, 01-design-system, 02-home-categories, 03-navigation, 04-widgets-bora, 05-business-rules, 06-flows, 07-database-key-tables, 08-edge-functions, 09-platform-settings, 10-protected-zones, 11-conventions, 12-recipes (13) | 2026-05-29→31 | Notas de conhecimento estruturado |
| `auditoria-2026-05-31/` + `Bora App/relatorios/` | AUDITORIA_GERAL, D3_COMPARACAO_KNOWLEDGE, DIVIDA_REPO_VS_PROD, PLANO_C4_C5_DETALHADO, PLANO_DISTANCIA_ESTRADA, PLANO_LOTE_C_PARTE2, PLANO_LOTE_D_KNOWLEDGE_OBSIDIAN, RELIGAR_SYNC_OBSIDIAN, 00-RESUMO (9) | 2026-05-31 | Histórico de auditoria |
| `audits/` | AUDITORIA_PARIDADE_360_2026-07-01 (22 KB) | 2026-07-01 | **Auditoria recente (Julho)** |
| raiz | 00_BORA_DNA (6.8 KB) | 2026-06-10 | DNA do produto |
| `benchmarks/` | delivery, reservas, servicos | 2026-06-10 | Benchmarks concorrência |
| `rules-history/` | 2026-06-10-robot-b-v4-motor-perfeicao | 2026-06-10 | Histórico de regras |
| `entregas/` | 05a1_agente_backend_report, 05a2_agente_frontend_audit/report, 05a2_beta_fab_apply_audit/report (5) | 2026-05-04 | Relatórios da migração |

**Duplicados no próprio velho (ignorados — mesmo conteúdo, copiado 1×):**
`AUDITORIA_GERAL_2026-05-31`, `D3_COMPARACAO_KNOWLEDGE_2026-05-31`, `PLANO_C4_C5_DETALHADO_2026-05-31`,
`PLANO_DISTANCIA_ESTRADA_2026-05-31`, `PLANO_LOTE_D_KNOWLEDGE_OBSIDIAN_2026-05-31` (existiam em
`auditoria-2026-05-31/` **e** `Bora App/relatorios/`).

## 🟠 Conflito de conteúdo (precisa de olhar humano — baixo risco)
| Ficheiro | Velho | Canónico | Recomendação |
|---|---|---|---|
| `negocios/visao-geral.md` | 2026-04-23 | **2026-05-08 (mais recente)** | **Manter o canónico** (é mais novo). A versão velha foi guardada lado a lado como `negocios/visao-geral.doVelho.md` para revisão — nunca se perde texto. |

Não há conflitos onde o velho seja mais recente que o canónico → **nenhuma perda de trabalho recente**.
Os 33 ficheiros "editados depois da migração" são exatamente os órfãos acima (notas novas que só
existiam no velho), todos já trazidos.

## Recomendação global
- ✅ Todos os órfãos com valor **já estão no canónico** (`_importado-velho/`).
- ✅ O único conflito tem o canónico como versão mais nova; o velho fica guardado `.doVelho.md`.
- 🚦 Nada do velho com valor fica por trazer → o `Desktop\Bora` pode ser arquivado **no gate final**
  (com aprovação do Danilo), não antes.
