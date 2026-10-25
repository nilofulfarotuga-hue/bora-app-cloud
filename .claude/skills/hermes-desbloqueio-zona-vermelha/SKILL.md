---
name: hermes-desbloqueio-zona-vermelha
description: "Protocolo para lidar com tarefas que tocam a Lista Vermelha (dinheiro/Stripe/pagamentos/RLS/auth/dispatch/pricing/ledger). O comando `ordem` recusa criar ordem para estas tarefas (exit 4). O fluxo correto: preparar PROPOSTA completa em texto, apresentar ao Danilo, aguardar 'vai' explícito, só então executar via PC/Claude Code ou aplicar via MCP direto."
tags: [zona-vermelha, lista-vermelha, dinheiro, pagamentos, stripe, governanca]
related_skills: [hermes-operacao-confiavel, socio-ai-onboarding]
---

# Desbloqueio de Zona Vermelha — Protocolo Operacional

## Princípio
**Nada que toque dinheiro real, Stripe, pagamentos, RLS/auth, dispatch_engine, pricing_service, finalizePurchase, bora_tokens, ledger, wallets, payouts, platform_settings de preços, ou migrações destrutivas vira ordem automática.** O comando `ordem` detecta estas palavras-chave e recusa (exit code 4).

## Fluxo Obrigatório

1. **Detectar** — o `ordem` devolve `ZONA_VERMELHA` + mensagem
2. **Preparar proposta** — texto completo com:
   - O que está pronto (migrações, código, colunas em produção, diffs no stash)
   - O que a proposta faz (resumo técnico)
   - Risco/impacto (zero regressão, só completa o que já existe)
   - Confirmação de que Lista Vermelha continua intacta
3. **Apresentar ao Danilo** — formato padrão: "⚠️ ISTO MEXE EM DINHEIRO. [resumo]. Responde 'vai' para eu aplicar."
4. **Aguardar "vai" explícito** — escrito nesta conversa
5. **Executar** — via `pc` (Claude Code no PC do Danilo) ou MCP direto (Supabase), **nunca** via `ordem`

## Palavras-chave que disparam Zona Vermelha (no script `ordem`)
```
dispatch_engine|pricing_service|finalizePurchase|bora_tokens|stripe|payment|webhook|wallet|ledger|refund|payout|commission|platform_settings|disable row level|force.?push
```

## Lição desta sessão (2026-09-22)
- A ordem 8448 (2 bugs TVDE) tinha **Bug #2 = Zona Vermelha** (bora_tokens + Stripe + tvde-plan-payment)
- O `ordem` recusou corretamente (exit 4)
- Preparei a proposta completa com tudo o que o veredito do Juiz + conselho confirmaram pronto
- O Danilo respondeu "vai" → agora posso executar via `pc` (não via `ordem`)

## Execução pós-"vai"
```bash
# Via PC (Claude Code no PC do Danilo) — preferido para tarefas complexas
pc "aplica migration tvde-plan-payment v10 tokens, deploy Edge Function tvde-plan-payment, reactiva toggle tokens ida-e-volta online"

# Ou via MCP direto se for só SQL/Deploy simples
```

## Erro Comum a Evitar
❌ Tentar contornar com `ordem "enfileira..."` ou `ordem "executa..."` — o script **sempre** vai recusar.
❌ Dizer "já apliquei" sem ter o "vai" do Danilo.
✅ Preparar proposta → aguardar "vai" → executar via `pc` ou MCP.