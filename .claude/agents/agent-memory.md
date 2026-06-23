---
name: agent-memory
description: Memória partilhada — regras globais lidas por TODOS os agentes no início de cada sessão.
version: 1.0.0
updated: 2026-06-22
---

# 🧠 Memória dos Agentes — Bora App

> **ESTE FICHEIRO É LIDO POR TODOS OS AGENTES NO INÍCIO DE CADA SESSÃO.**
> **Actualizado automaticamente quando o Danilo corrige uma regra.**
> Os números (pricing/tokens/comissões) vivem em `business_rules.md` — este ficheiro guarda
> as regras de *comportamento* dos agentes. Em conflito, `business_rules.md` vence nos números.

## Regras iniciais (v1.0 — 2026-06-22)

1. **Nunca gerar imagens sobre fotos reais de produtos ou restaurantes.**
2. **Admin panel em PT-BR sempre; app (cliente/estafeta/parceiro) em PT-PT sempre.**
3. **Todos os mercados são NÃO-PARCEIRO — nunca confundir** (pricing e markup diferem; consultar `business_rules.md`).
4. **Toda correcção do Danilo → adicionar como nova regra aqui, com data.**
5. **Toda migration destrutiva → backup obrigatório antes** (`backup-restore-table`).
6. **Toda feature nova → invocar o agente `admin-sync` no final.**

## Zonas protegidas (nunca tocar sem aprovação explícita do Danilo)
`dispatch_engine` · `pricing_service.dart` · triggers financeiros · Stripe webhook (v17) ·
RLS em `orders` / `wallets` / `ledger_entries` / `bora_tokens`.

## Robot A / Robot B
- **Robot A** = `support-chatbot` (Edge Function). **Robot B** = `robot-b` (Edge Function).
- **Intocáveis.** Nenhum agente cria loops autónomos paralelos ao Robot B nem desliga os seus
  kill switches. Crosstalk A↔B é tratado pela skill `ask-knowledge-base`, não por estes agentes.

## Histórico de correcções
<!-- Formato: - [YYYY-MM-DD] Regra: ... · Contexto: ... · Origem: Danilo -->
- [2026-06-22] Criação do sistema de agentes (Lote 1). Regras 1–6 estabelecidas.
