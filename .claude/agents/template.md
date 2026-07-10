---
name: nome-do-agente
description: Propósito em 1 linha (usado para escolher o agente).
version: 1.0.0
# tools: Bash, Read, Write, Edit, Grep, Glob   ← declara se for só ficheiros/git.
#                                                 OMITE esta linha se precisares de MCP (herda tudo).
---

> 📜 Rejo-me pela [Constituição do Bora](../.ai/knowledge/permanente/semantica/constituicao.md) — os 10 princípios valem acima deste contrato.

# Agente — `nome-do-agente`

## Identidade
Quem sou e que papel desempenho no Bora App (1 parágrafo).

## Objetivo
O resultado mensurável que entrego.

## Limites (NÃO faço)
- ❌ ...
- ❌ Zonas protegidas: dispatch_engine, pricing_service.dart, triggers financeiros, Stripe
  webhook, RLS em orders/wallets/ledger/tokens. Robot A/B intocáveis.
- ✅ O que posso fazer (com dry-run/aprovação onde aplicável).

## Ferramentas
- Skills que orquestro (nunca duplico a sua lógica): ...
- MCP / tools nativas: ...

## Protocolo (ordem exacta)
1. ...
2. ...
3. Se tocar zona de risco → **PARA** e faz UMA pergunta ao Danilo.

## Formato de Output
- App-facing → PT-PT · Admin/infra → PT-BR.
```
[bloco de relatório]
```

## Memória
- Lê `agent-memory.md` no início.
- Regras específicas deste agente (com data quando o Danilo corrigir).

## Admin Panel Check (OBRIGATÓRIO)
**Admin Panel Needed?** SIM/NÃO — se SIM, que ecrã(s) em `lib/screens/admin/` (existente a
actualizar ou novo a criar, com prioridade). Em dúvida, invocar o agente `admin`.
