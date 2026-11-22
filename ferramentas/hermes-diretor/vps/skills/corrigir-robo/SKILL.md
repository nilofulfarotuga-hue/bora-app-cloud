---
name: corrigir-robo
description: >
  Usar quando um robo (suporte, Amigo Bora, WhatsApp da loja) respondeu mal a um cliente: inventou um botao,
  um preco, um horario, ou contrariou uma regra. Confirma o erro, grava a licao e o caso de teste, e corre a
  regressao antes de mudar o robo.
version: 1.0.0
author: missao hermes-diretor-2026-11-20
license: MIT
platforms: [linux]
category: operacao
---

# Corrigir um robo

1. CONFIRMA o erro com um facto: a base de dados, o `/opt/data/CONTEXT-BORA.md`, uma licao que ja existe, ou o
   mapa da app (um botao so existe se la estiver). O que nao consegues conferir nao e erro: e "por conferir".
2. Grava a licao (o que errou + a regra certa, 1 a 2 frases, SEM dados pessoais):
   `python3 /opt/data/bin/porta.py rpc '{"funcao":"licao_robo_gravar","args":{"p_robo":"suporte","p_errou":"...","p_regra":"...","p_origem":"hermes"}}'`
   Se ja existir, a porta soma as vezes. Robos: `suporte`, `amigo`, `whatsapp`, `hermes`.
3. Grava o caso de teste: a pergunta real (generica), o que a resposta DEVE ter e o que NAO PODE ter.
4. Antes de mudar a alma, uma skill ou o prompt de um robo: pede ao `fiscal`, pelo despacho, a regressao desse
   robo (todos os casos). Se algum piorar, NAO se publica e volta ao fiscal.
5. O juiz diario (03:30) le todas as conversas da vespera e faz isto sozinho; tu usas esta skill quando o Danilo
   ou um cliente apontam o erro na hora.

Uma licao nunca proibe o robo de dizer uma coisa verdadeira. Em duvida, a licao fica desligada para rever no painel.
