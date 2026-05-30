---
name: prompt-blindado-validator
description: Camada de verificação obrigatória invocada pelo CEO-AI antes de cada tarefa — valida que o prompt recebido respeita as regras do Bora App (MODO PROTECÇÃO TOTAL, CEO-AI, business_rules, git push, /ctx, admin, zonas protegidas). Se encontrar violações, reporta e pára; não executa.
metadata:
  type: validator
  category: governance
  depends_on: bora-knowledge
  version: 1.0.0
---

# SKILL: prompt-blindado-validator
**Versão:** 1.0.0
**Criada em:** 2026-05-18
**Invocada por:** CEO-AI orchestrator (automaticamente no início de cada tarefa)

---

## O QUE ESTA SKILL FAZ

Esta skill é uma camada de verificação obrigatória.
É invocada pelo CEO-AI **antes de executar qualquer tarefa**.
Verifica se o prompt recebido respeita todas as regras do projecto Bora App.
Se encontrar violações, reporta e pára — não executa.

---

## QUANDO INVOCAR

O CEO-AI deve invocar esta skill **sempre** — sem excepções.
Mesmo em tarefas simples.
Mesmo em tarefas de 1 linha.

---

## CHECKLIST DE VERIFICAÇÃO (executar por ordem)

### ✅ BLOCO 1 — Estrutura obrigatória
- [ ] O prompt contém "⚠️ MODO PROTECÇÃO TOTAL ⚠️"?
- [ ] O prompt invoca o CEO-AI em `.claude/skills/ceo-ai/`?
- [ ] O prompt termina com `/ctx doctor` e `/ctx stats`?
- [ ] O prompt inclui `git push origin <branch>` como PASSO FINAL?

### ✅ BLOCO 2 — Regras de negócio
- [ ] A tarefa toca em: cancelamentos, pagamentos, dispatch, tokens, comissões, fees, reembolsos, Stripe, wallet?
  - SE SIM → verificar se o prompt instrui consultar `bora_app/.claude/.ai/business_rules.md` antes de executar
  - SE NÃO → passar ao próximo bloco

### ✅ BLOCO 3 — Parceiro vs Não-parceiro
- [ ] A tarefa envolve comissões, preços, taxas, entregas ou restaurantes?
  - SE SIM → verificar distinção partner/non-partner:
    - RESTAURANTES: podem ser parceiro (10%+5%+5%) ou não-parceiro (base+15%)
    - MERCADOS: TODOS são sempre não-parceiros, sem excepção
  - SE NÃO → passar ao próximo bloco

### ✅ BLOCO 4 — Admin panel
- [ ] A tarefa cria ou altera uma feature (nova tabela, novo flow, nova UI, novo RPC)?
  - SE SIM → verificar se o prompt menciona correspondência no painel admin
  - SE NÃO → passar ao próximo bloco

### ✅ BLOCO 5 — Protecção de código
- [ ] O prompt instrui a ler o ficheiro completo antes de editar?
- [ ] O prompt instrui edições cirúrgicas (só tocar no necessário)?
- [ ] O prompt instrui a NÃO tocar em: dispatch engine, pricing_service, triggers DB, Stripe — a menos que seja exactamente essa a tarefa?

### ✅ BLOCO 6 — Bug reporting
- [ ] O prompt instrui a reportar qualquer bug/anomalia encontrada, mesmo fora do scope?

---

## RESULTADO DA VERIFICAÇÃO

### SE todos os blocos passaram:
```
✅ PROMPT VALIDADO — prosseguir com execução normal
```

### SE algum bloco falhou:
```
❌ VIOLAÇÃO DETECTADA

Bloco: [número do bloco]
Problema: [descrever o que falta]
Acção: [o que precisa de ser adicionado ao prompt]

NÃO executar a tarefa.
Reportar ao Danilo para corrigir o prompt.
```

---

## REGRAS DESTA SKILL

1. Nunca saltar a verificação — nem em tarefas simples
2. Nunca executar se houver violação no Bloco 1 (estrutura)
3. Blocos 2, 3, 4 só aplicam se a tarefa for relevante — mas verificar sempre
4. Reportar de forma clara e simples — Danilo não é programador
5. Depois de validar → devolver controlo ao CEO-AI para execução normal
