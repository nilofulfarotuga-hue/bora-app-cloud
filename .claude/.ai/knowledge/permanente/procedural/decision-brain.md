---
tema: decision-brain · escopo: projeto · estado: atual · atualizado: 2026-07-13
id: decision-brain
tipo: procedimento
origem: [missão "Do Prompt ao Loop" 2026-07-10 — Fase 1.3; Lei do Pre-Voo 2026-07-13]
ultima_confirmacao: 2026-07-13
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

## ✈️ LEI DO PRE-VOO (2026-07-13) — simular ANTES de agir

> Pedido do Danilo depois de ordens que ficaram mudas/travadas por tentar a cegas: **prever o
> futuro antes de agir, nunca mais agir às cegas.** Aplica-se a QUALQUER executor (Claude Code,
> agente, script) antes de correr qualquer tarefa não-trivial.

**O protocolo:** antes de executar, o executor SIMULA mentalmente o resultado — *"se eu fizer por
este caminho, vai dar certo? vai estourar timeout? precisa de algo que não existe (device, ficheiro,
permissão)?"* Se a previsão é de falha, **muda a abordagem ANTES de começar**, ou reporta o
bloqueio em 1 linha em vez de tentar 5x a mesma coisa.

**Regras concretas (mecânicas, não opinião):**
- **Tarefa >15min estimados** → dividir ANTES de começar (sub-tarefas menores, cada uma verificável).
- **2 falhas iguais seguidas** → MUDAR de abordagem. Nunca há 3ª tentativa igual — se a 2ª falhou
  do mesmo jeito que a 1ª, o caminho está errado, não a sorte.
- **Antes de mexer num ficheiro** → verificar que existe (Read/ls) antes de Edit/Write assumir conteúdo.
- **Antes de chamar um device/emulador** → verificar que está ligado/disponível antes de tentar a
  captura ou o comando (evita ficar preso à espera do que nunca vai responder).
- Falhou a previsão e não há caminho alternativo óbvio → reportar o bloqueio em 1 linha (não é
  fraqueza, é sinal). Nunca ficar mudo, nunca travar em loop silencioso.

**Porquê:** ver `agente:juiz-revisor` — a investigação de 2026-07-13 (ordens "JUIZ-SEM-VEREDITO")
mostrou que agir sem prever (chamar captura visual numa tarefa de infra, tentar arrancar 2º executor
sem checar lock) causa travamento silencioso, não erro visível. Pré-voo é a prevenção.

## Quem referencia este procedimento
- `ceo-ai/SKILL.md` (protocolo de orquestração — antes de priorizar)
- `.claude/agents/maestro-autonomia.md` (ao decompor missões em ordens — Mission Engine)
- `.claude/agents/juiz-revisor.md` (Lei do Pre-Voo aplicada ao seu próprio protocolo de avaliação)
