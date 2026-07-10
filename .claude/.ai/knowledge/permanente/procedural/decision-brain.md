---
tema: decision-brain · escopo: projeto · estado: atual · atualizado: 2026-07-10
id: decision-brain
tipo: procedimento
origem: [missão "Do Prompt ao Loop" 2026-07-10 — Fase 1.3]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# 🧮 Decision Brain — pontuação antes de decisões não-triviais

> É um **CHECKLIST**, não um sistema. Quem consulta: **CEO-AI** e **maestro-autonomia**
> antes de qualquer decisão não-trivial (o que construir, em que ordem, vale a pena?).
> A saída (score + 3 linhas) fica REGISTADA na ordem/decisão correspondente.

## Os 8 critérios (pontuar 0 / 1 / 2 cada)

| # | Critério | 0 | 1 | 2 |
|---|---|---|---|---|
| 1 | **Impacto na receita** | nenhum | indireto | direto (pedido pago, novo parceiro) |
| 2 | **Impacto no lançamento** | irrelevante | ajuda | desbloqueia blocker |
| 3 | **Impacto UX** | invisível | melhora um fluxo | remove fricção de funil |
| 4 | **Risco técnico** (invertido) | alto/zona 🔴 | médio/zona 🟡 | baixo/zona 🟢 reversível |
| 5 | **Custo** (tokens/API/infra, invertido) | caro | moderado | barato |
| 6 | **Tempo** (invertido) | dias | horas | minutos |
| 7 | **Dívida técnica** (invertido) | cria dívida | neutro | paga dívida |
| 8 | **Reaproveitamento** | one-off | parcial | vira skill/loop reutilizável |

## Leitura do score (0–16)
- **12–16** → fazer JÁ (entra à frente da fila)
- **8–11** → fazer nesta semana / próxima janela
- **4–7** → backlog governado (registar com justificativa, não construir)
- **0–3** → recusar (registar porquê — não repropor sem dados novos)

**Desempate:** prioridades da constituição (Receita → UX → Estabilidade → Velocidade).
**Zona 🔴:** score alto NÃO anula a Lista Vermelha — continua proposta-apenas.

## Formato de saída (obrigatório, 3 linhas — registar na ordem/decisão)
```
DECISÃO: <o quê> · score N/16 (receita X, lançamento X, UX X, risco X, custo X, tempo X, dívida X, reuso X)
PORQUÊ: <1 frase com o fator dominante>
QUANDO: já | esta semana | backlog | recusado
```

## Quem referencia este procedimento
- `ceo-ai/SKILL.md` (protocolo de orquestração — antes de priorizar)
- `.claude/agents/maestro-autonomia.md` (ao decompor missões em ordens — Mission Engine)
