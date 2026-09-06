---
name: seed-demo-data
description: Cria dados de demonstração isolados e reversíveis (clientes + pedidos DEMO_) para testes. Pagamentos sempre cash, NUNCA Stripe real. orders marcados is_test_order=true. cleanup remove tudo por prefixo DEMO_. Dry-run default.
metadata:
  type: devops
  category: data
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

# Seed Demo Data

Gera dados fake para testar, de forma **isolada e 100% reversível**. Não toca em dados reais.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/07-database-key-tables.md`
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Uso
```bash
python scripts/seed.py --clients 3 --orders 5             # dry-run (plano)
python scripts/seed.py --clients 3 --orders 5 --commit    # cria DEMO_
python scripts/cleanup.py                                  # dry-run (lista o que removeria)
python scripts/cleanup.py --commit                         # remove tudo DEMO_
```

## Convenção de isolamento (limpeza fácil)
- Clientes: `users` com `name` `DEMO_<n>` e `email` `demo_<n>@bora.test`.
- Pedidos: `orders` com **`is_test_order=true`** + `customer_name` `DEMO_*` + `payment_method='cash'`.
- `users` **não tem** coluna demo → o prefixo no nome/email é o marcador (pendência: coluna `is_demo`).

## Salvaguardas
- **Pagamentos só `cash`** (regra do projeto). **NUNCA** cria payment intents / Stripe.
- Tudo prefixado `DEMO_` / `is_test_order=true` → `cleanup` remove com segurança.
- `cleanup` só apaga linhas com o marcador DEMO_ (nunca dados reais).
- Não dispara dispatch/notificações reais (status inicial `created`, sem driver).
- Dry-run default; `--commit` explícito.

## Pendências
- Coluna `is_demo` em `users`/`drivers` (hoje só `orders.is_test_order`) — migration futura.

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
