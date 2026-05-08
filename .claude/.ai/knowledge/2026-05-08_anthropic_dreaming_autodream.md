# Anthropic Dreaming + AutoDream + Outcomes — 6-7 May 2026

> ⚠️ **Disclaimer**: conteúdo reportado pelo Danilo via prompt de
> 2026-05-08. Fontes citadas (`platform.claude.com/docs/...`,
> VentureBeat, 9to5Mac, TheNewStack, SiliconANGLE, the-decoder,
> Techzine, LetsDataScience) **NÃO foram verificadas independentemente
> nesta sessão**. Validar quando relevante para implementação.

---

## Resumo (conforme reportado)

A Anthropic terá lançado em 6-7 Maio 2026 três features no
**Claude Managed Agents** (não no Claude.ai/Claude Code que o
Bora usa actualmente):

### 1. Dreaming

Sistema permite agentes IA aprender com os próprios erros através
de "consolidação offline" entre sessões. O agente reprocessa
sessões anteriores, identifica padrões de erro, e ajusta-se sem
intervenção humana.

### 2. AutoDream

Comando `/dream` no Claude Code para consolidação automática.
O comando varre `.claude/skills/`, `.claude/.ai/knowledge/`, e
session transcripts para extrair lições reutilizáveis e
materializá-las em ficheiros markdown.

### 3. Outcomes

Padrão grader/rubric formal para avaliação de respostas. Em vez
de prompt engineering ad-hoc, define-se uma rubrica de pass/fail
e um agente grader separado avalia automaticamente cada resposta
do agente principal antes do envio ao user.

---

## Decisão estratégica para Bora — 2026-05-08

### NÃO aplicar agora.

Razões:

1. **Pré-launch sem tráfego real**. Bora ainda não tem orders
   reais à escala necessária para optimizar com grader/rubric.
   Aplicar Outcomes agora seria optimizar para data sintético.

2. **AutoDream toca em ficheiros do Claude Code**. As skills
   `.claude/skills/` são curadas manualmente. Migrar para fluxo
   automático antes de validar manualmente apresenta risco de
   regressão silenciosa em prompts críticos.

3. **Migrar AI support agent de Gemini → Managed Agents quebra
   modelo de custo**. Gemini Flash actualmente: 1500 chamadas/dia
   grátis. Managed Agents: pricing tier diferente, multi-agent em
   produção arde tokens rapidamente.

4. **Multi-agent em produção arde tokens**. Grader + agente
   principal em paralelo dobra (no mínimo) o custo por interacção.

---

## Roadmap pós-launch

### Sessão 5B WRITE shadow

Adoptar padrão grader/rubric formal **inspirado** em Anthropic
Outcomes (não necessariamente usando Managed Agents):
- Grader agent separado em contexto isolado avalia resposta antes
  do envio.
- Rubrica define pass/fail explícito (ex.: "resposta menciona
  fonte? sim/não", "resposta evita PII? sim/não").
- Implementação inicial pode ser segundo prompt no mesmo Gemini
  Flash (custo marginal baixo).

### AutoDream (`/dream`) no Claude Code

Testar em ambiente isolado antes de produção:
- Consolidação automática de `.claude/skills/`.
- Consolidação automática de `.claude/.ai/knowledge/`.
- Validar manualmente os primeiros 5-10 outputs antes de aceitar
  fluxo.

### Pedido de acesso ao Dreaming research preview

Link reportado: `platform.claude.com/docs/en/managed-agents/dreams`.
Quando submetido, preencher com:

- **Stack**: Flutter + Supabase
- **Use case**: AI support agent self-improvement
- **Volume estimado**: pós-launch (ainda desconhecido)
- **Role**: founder Bora App

---

## Validação arquitectural

O roadmap interno do Bora **5D → 5G** (auto-suggest → auto-impl →
cross-talk → inbox) já é uma versão DIY do que (segundo
reportado) a Anthropic lançou. Validação direccional **positiva**:

| Bora interno | Anthropic (reportado) |
|---|---|
| 5D auto-suggest | (ausente — Anthropic não tem equivalente reportado) |
| 5E auto-impl zonas seguras | AutoDream (consolidação automática) |
| 5F cross-talk Robô A↔B | Multi-agent Managed Agents |
| 5G inbox admin | Outcomes (grader/rubric) |
| §39 robot_crosstalk | Padrão similar |

Roadmap Bora pode continuar como está. Sessões futuras avaliam
substituição parcial por features Anthropic quando volume +
custos justificarem.

---

*Este documento é knowledge de referência — não é regra de
negócio. Actualizar apenas com nova informação verificada.*
