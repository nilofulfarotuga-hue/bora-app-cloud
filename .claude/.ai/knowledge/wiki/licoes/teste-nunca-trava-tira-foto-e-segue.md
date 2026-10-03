---
id: licao-teste-nunca-trava-tira-foto-e-segue
tipo: licao
origem: [testes-e2e/runner.py · flows/cliente/delivery-mercado-cash.yaml]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# Lição — o teste E2E NUNCA trava em silêncio: falhou → tira foto + regista + segue

**Problema (observado pelo Danilo ao vivo, 2026-07-11).** O Maestro, ao não encontrar um
elemento (ex.: o botão de adicionar ao carrinho = um "+" PEQUENO, ícone sem texto, no canto
inferior direito do card), **abortava o fluxo inteiro** e ficava preso sem deixar pista visual.
O Claude.ai não conseguia perceber o que estava no ecrã nesse momento — só via "element not found".

**Regra de ouro.** Sempre que o teste NÃO conseguir encontrar/tocar algo, ele deve, em vez de
travar/voltar atrás/abortar:
1. **TIRAR UM SCREENSHOT** nesse exato momento (guardar em `gravacoes/` com nome do passo);
2. **ESCREVER no `e2e_log`** (diário) o passo que falhou + o caminho do screenshot + o elemento
   procurado;
3. **SEGUIR** para a próxima estratégia ou o próximo passo — nunca crashar.

Assim o Claude.ai abre a foto e percebe o ecrã, e o teste nunca fica preso mudo.

## Como está implementado (2026-07-11)

**Nível YAML (dentro de 1 fluxo Maestro) — a granularidade fina.**
Maestro pára o fluxo no primeiro comando que falha. Para "falhar → foto → seguir":
- comandos arriscados levam `optional: true` (falha = não-fatal, segue para o próximo);
- `takeScreenshot:` **antes** de cada passo arriscado (e do estado final), com nome descritivo;
- estratégias em **ladder** com `runFlow: when: notVisible: "<prova>"` — a estratégia B só corre
  se a A não deu prova de sucesso (ver `delivery-mercado-cash.yaml`: (a) tocar o "+" por id
  `btn_add_carrinho`; (b) fallback = abrir detalhe e usar o botão de texto "Adicionar ao carrinho").
- a **prova** de sucesso é um sinal do próprio app (aqui: o botão fixo "Ver carrinho · €X", que
  só existe com ≥1 item), não o "toque não deu erro".

**Nível runner (Python, `corre_maestro`) — a rede de segurança por fluxo.**
Quando um passo Maestro devolve `rc != 0`, o runner corre `screenshot_falha()`:
`adb -s <serial> exec-out screencap -p` → `gravacoes/falha-<slug>.png` + `e2e_diario.registar(...)`
com o caminho da foto. Best-effort (uma foto que falhe nunca afunda o teste). Complementa os
frames que já eram extraídos do vídeo — a foto é o ecrã EXATO do momento da falha.

## Estratégia para elementos pequenos/ícone sem texto (o botão "+")

Ordem de tentativas (a dica do Danilo, generalizável a qualquer botão-ícone):
1. **por id** — pedir ao código Flutter um `Semantics(identifier: '<id>')` estável no botão
   (feito: `btn_add_carrinho` em `store_products_screen.dart` `_QtyButton` e
   `market_product_card.dart` `_AddButton`) e tocar por `tapOn: id:`.
2. **por coordenada relativa** — canto inferior direito do card (fallback se não houver id).
3. **por ícone/texto** — `tapOn` no "+", ou abrir o detalhe e usar o botão de TEXTO
   "Adicionar ao carrinho" (mais fácil de casar).
Depois de adicionar, **confirmar que o carrinho aumentou** (prova real) antes de prosseguir.

## Regra generalizável
Um passo de teste que "aborta em silêncio" custa uma noite inteira de diagnóstico às cegas.
Um passo que **fotografa + regista + segue** transforma cada falha em evidência acionável e deixa
o fluxo chegar ao fim (ou o mais longe possível), revelando TODOS os problemas de uma vez em vez
de parar no primeiro. Prova de sucesso vem sempre de um sinal do app, nunca de "o toque não deu erro".
Ver [[classificador-zona-menos-sensivel-a-palavras]] (mesma filosofia: menos fricção, mais sinal).
