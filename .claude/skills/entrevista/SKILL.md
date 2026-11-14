---
name: entrevista
description: "Entrevista antes de agir: uma pergunta de cada vez, cada uma com a resposta recomendada, até ~95% de certeza sobre o que se quer. Usar com um pedido vago, um plano a afinar ou antes de missão grande (modo Diretriz por voz)."
---

# Entrevista — afinar o pedido antes de mexer

> 14/11/2026 (missão `sistema-conteudo-14-11`, bloco 2-bis): junta numa só as antigas
> `grilling`, `grill-me`, `grill-with-docs` e `interview-me` (originais em `_arquivo/`).

## Regra do Bora (manda sobre o resto)

A entrevista **nunca se vira para o Danilo**. Quem responde é a Claude.ai ou o executor, com o
Córtex, o livro (`claude_ai_memoria`) e o código. O que só ele pode decidir vai para o bloco
**"PARA O DANILO"** no fim do relatório (ou para o quadro Sim/Não, skill `quadro-sim-nao`),
e o trabalho segue. Exceção: o modo Diretriz, quando é ele que pede para ser entrevistado.

## Como se faz

1. **Hipótese primeiro**: escreve o que achas que se quer e a tua certeza (ex.: 60%).
2. **Árvore de decisões**: cada decisão abre outras. A "fronteira" são as perguntas que já
   se podem fazer sem adivinhar respostas que ainda não chegaram. Pergunta a fronteira toda
   numa ronda, numeradas, cada uma com a resposta recomendada:
   `❓ Q1 — título: pergunta` e por baixo `➡️ resposta recomendada`.
3. **Factos procuram-se, não se perguntam**: o que está no disco, no banco, no livro ou no
   Córtex vai-se buscar (subagente se for largo). Só as **decisões** são de quem responde.
4. **Querer vs. "devia querer"**: ouvir o que a pessoa quer de facto, não o que acha que
   devia pedir. Repetir a intenção pelas palavras dela.
5. **Parar a ~95%**: quando a fronteira está vazia e a intenção foi confirmada com um "sim"
   claro (não "faz como achares"). Só então se age.

## Modo com documentos (antigo `grill-with-docs`)

Se a entrevista fixar termos ou decisões de arquitetura, usar também `domain-modeling`
(mantém o `CONTEXT.md`, decisões marcadas "POR CONFIRMAR" quando deduzidas).

## Modo Diretriz (entrevista por voz)

Para uma missão grande que o Danilo quer arrancar a falar: perguntas curtas, uma de cada vez,
em português simples, para ouvir em voz alta (sem tabelas nem jargão). No fim, devolver a
**Diretriz** numa página: objetivo, o que fica fora, condição de fim verificável por máquina,
o que trava (dinheiro só com "autorizo"). A Diretriz vira o prompt da missão
(`protocolo-missao-bora`). Esqueleto: falta ligar à voz do Telegram (porteiro) — ver
`docs/propostas/sistema-conteudo-14-11/skills-inventario.md`.

## Sinais de que está a correr mal

- Perguntar ao Danilo uma coisa que está no livro ou no código.
- Várias perguntas dependentes na mesma ronda.
- Agir antes do "sim" claro.
