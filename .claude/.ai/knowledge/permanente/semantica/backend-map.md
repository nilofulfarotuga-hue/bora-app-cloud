---
tema: backend-map · escopo: projeto · estado: atual · atualizado: 2026-07-05
id: backend-map
tipo: conceito
origem: [Supabase project ojykpzwqrtusfeakzrna (schema public), MCP list_edge_functions 2026-07-05]
ultima_confirmacao: 2026-07-08
zona: vermelha
confianca: auto
---

# Backend Map — Cérebro do Bora (Fase 2)

Mapa do estado ATUAL do backend Supabase (`project_id=ojykpzwqrtusfeakzrna`, schema `public`).
Objetivo: os agentes "já chegam sabendo" o que existe. NÃO é auditoria — só o inventário do banco.
🔴 = zona de dinheiro (existe; a lógica interna NÃO é descrita aqui).

## Contagens globais

| Item | Total |
|---|---|
| Tabelas (schema public) | 146 (verificado 2026-07-05; inclui 5 `cleaning_*`/`cleaners` + 67 backup/staging) |
| Edge Functions (ACTIVE) | 55 (verificado 2026-07-05) |
| Funções/RPCs (`information_schema.routines`) | ~487 (inclui triggers-fn `_*` e overloads; verificado 2026-07-05) |
| Triggers (schema public) | ~77 (rows em `information_schema.triggers`) |
| RLS | ATIVO em 100% das 146 tabelas |

## Sub-ficheiros (nenhum > ~20 KB)

- **[backend-map-tabelas.md](./backend-map-tabelas.md)** — tabelas agrupadas por domínio (pedidos/financeiro, tokens/wallet, dispatch, favores/errand, TVDE, serviços/agendamentos, reservas, suporte/robot, admin/auditoria, push, catálogo/mercados, backup/staging).
- **[backend-map-rpcs.md](./backend-map-rpcs.md)** — funções/RPCs por domínio, com 🔴 nas de dinheiro (~55 marcadas).
- **[backend-map-edge-functions.md](./backend-map-edge-functions.md)** — as 55 edge functions, 1 linha cada, com `verify_jwt` e 🔴.
- **[backend-map-triggers-rls.md](./backend-map-triggers-rls.md)** — triggers por tabela + RLS (rowsecurity + contagem de policies).

## Notas de topo

- **Zona-dinheiro blindada**: `pricing_*`, `create_order`, `*settlement*`, `*payout*`, `refund*`, `wallet_*`, `*token*`, `finalize_*`, ledger/order-financials + edge fns `dispatch-engine`, `create-payment-intent`, `stripe-webhook`, `refund`. Ver marcas 🔴 nos sub-ficheiros.
- **TVDE** (`tvde_*`) é vertical ISOLADA de orders/dispatch-engine.
- **LIMPEZA** (`cleaners`/`cleaning_*`, 2026-07-05) é vertical ISOLADA (mesmo padrão TVDE) — detalhe em [vertical-limpeza.md](./vertical-limpeza.md).
- **Backups**: 67 tabelas `_backup_*` / `_*_price_sources_*` / `continente_price_staging` — dados históricos de crawls; RLS on, 0 policies (efetivamente fechadas exceto service_role).
