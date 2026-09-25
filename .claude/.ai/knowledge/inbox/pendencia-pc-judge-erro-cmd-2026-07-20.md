---
tema: pendencia-pc-judge-erro-cmd · escopo: projeto · estado: atual · atualizado: 2026-07-20
tipo: bug
origem: [C4 — provas reais do ciclo de licao, 2026-07-20]
zona: verde
confianca: verificado
---

# Pendência — `pc_judge` devolve erro de cmd quando chamado pelo C4

> **NÃO investigado.** Anotado a pedido do Danilo para ser tratado à parte.
> O C4 está a funcionar e degrada em segurança; isto afeta só a QUALIDADE da lição.

## O que se observa

Nas **três** provas reais do C4 (ordens `c4pv`, `c4pv2`, `c4pv3`), a chamada
`pc_judge` feita de dentro de `licao_de_falha()` devolveu a mensagem de erro do cmd
do Windows, em duas linhas:

```
'PONTE' não é reconhecido como um comando interno
ou externo, um programa operável ou um arquivo em lotes.
```

Consequência: o campo "O certo é" da lição fica sempre
`PENDENTE — a completar pelo bibliotecario-cerebro`. Os factos mecânicos
(tarefa + nota do veredito) continuam corretos.

## O que NÃO é

- **Não é o C4 partido.** O filtro de saída-inteira (commit `7d1d57a`) apanha o erro
  e cai para PENDENTE — nenhum lixo entra no Cérebro. Provado por 3 testes de regressão
  no `--selftest`.
- **Não parece ser a ponte do juiz partida em geral.** No mesmo período, ordens normais
  foram julgadas e ficaram `aprovada` (ex.: `ordem-20260720222620-5b3c`), o que exige um
  `VEREDITO:` válido devolvido pelo mesmo `pc_judge`.

## Pistas para quem investigar

1. Comparar o payload do caminho do veredito (`jinput`, montado com `printf`) com o do C4
   — o do C4 é multi-linha e tem acentos; o outro também, mas vale confirmar o que chega
   ao `pc-judge` do lado do PC (base64 + cmd).
2. `PONTE` aparece no cabeçalho de comentário do `run-claude-loop.cmd`
   ("PONTE BORA :: EXECUTOR..."). Verificar se o `run-claude-judge.cmd` perdeu o
   `@echo off` ou tem uma linha de comentário sem `REM` a ser executada.
3. Reproduzir isolado: `pc-judge "texto de teste"` a partir do container, e ver o stdout cru.

## Ficheiros

- `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh` — `pc_judge()` e `licao_de_falha()`
- `C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\run-claude-judge.cmd` (lado do PC)
- Ver `DEPLOY.md` do orquestrador para o mapa das pontes.
