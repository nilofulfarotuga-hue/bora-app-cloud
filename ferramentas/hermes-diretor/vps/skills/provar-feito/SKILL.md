---
name: provar-feito
description: >
  Usar SEMPRE antes de dizer "feito", "ligado", "publicado" ou "enviado". Junta a prova material
  (saida de comando, SELECT, ficheiro com hora, mensagem recebida) no formato que o fiscal confere.
version: 1.0.0
author: missao hermes-diretor-2026-11-20
license: MIT
platforms: [linux]
category: operacao
---

# Provar que esta feito

Nada e "feito" sem prova. O fiscal refaz a prova com contexto limpo; se nao bater, a tarefa volta.

1. Diz numa frase o que fizeste.
2. Mostra a prova LITERAL, nao um resumo. Tipos: `select` (linha da base), `log` (linha do registo),
   `ficheiro` (caminho + `ls -la` + `sha256sum`), `url` (endereco + o que la esta), `mensagem` (id recebido).
3. Diz como se refaz: o comando exato de LEITURA que o fiscal pode correr.
4. No despacho, a prova vai assim:
   `{"tipo":"ficheiro","conteudo":"<sha256> /opt/data/x.md","como_refazer":"sha256sum /opt/data/x.md"}`

Nao e prova: "deve estar", "provavelmente", "assumo", a palavra de outro agente, um HTTP 200 ou um
codigo de saida 0 (le o CONTEUDO da resposta). Antes de dizer que algo esta ligado ou desligado, le o valor real.

Sem prova, escreves "por confirmar" e o que falta. Falhou, diz-se que falhou, com o erro real.
