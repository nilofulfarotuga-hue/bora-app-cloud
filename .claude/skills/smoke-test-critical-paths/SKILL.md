---
name: smoke-test-critical-paths
description: Verifica (read-only / health) os caminhos críticos do Bora sem afetar produção — Edge Functions alcançáveis (OPTIONS), RPCs críticos presentes, realtime channels declarados, contagens sãs. ZERO escrita, ZERO pagamentos, ZERO pedidos reais.
metadata:
  type: qa
  category: readiness
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

# Smoke Test Critical Paths (read-only)

Confirma que os caminhos críticos estão **vivos** sem tocar em nada. Não cria pedidos,
não cobra, não escreve. Bom para correr antes de um build/deploy.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/06-flows.md`
2. `bora-knowledge/knowledge/08-edge-functions.md`
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (leitura).

## Uso
```bash
python scripts/smoke.py            # relatório PT-BR + _preview/smoke.md
python scripts/smoke.py --json
```

## O que verifica (tudo read-only)
| Check | Como | Critério |
|-------|------|----------|
| Edge Functions vivas | **OPTIONS** a `functions/v1/<fn>` (CORS preflight) | 200/204 = viva |
| RPCs críticos presentes | `information_schema.routines` | ❌ se faltar |
| Tabelas-chave acessíveis | `count=exact` HEAD | ✅ responde |
| Realtime channels | declarados (orders_channel, public:drivers) | info (verificar app) |
| pg_cron | não exposto via REST | info → verificar via MCP |

Edge Functions verificadas: `dispatch-engine`, `create-payment-intent`, `stripe-webhook`,
`create-mbway-payment-intent`, `refund`, `notify-driver`, `notify-partner`.
RPCs verificados: `is_admin`, `pricing_calculate` (+ outros configuráveis).

## Salvaguardas
- **ZERO escrita**: só `OPTIONS`/`GET count`/leitura de catálogo de sistema.
- **Nunca** invoca uma Edge Fn com corpo real (só preflight OPTIONS — não executa lógica).
- Não cria pedidos nem pagamentos. (Regra do projeto: testes de pagamento = cash; aqui nem isso.)
- Exit 1 se algum check crítico falhar (útil em CI/pré-build).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
