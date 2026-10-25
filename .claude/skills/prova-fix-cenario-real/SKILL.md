---
name: prova-fix-cenario-real
description: >
  Usa esta skill SEMPRE que vais declarar 'corrigido', 'pronto' ou 'fechado' um bug relatado pelo Danilo. Gatilho: a prova de fecho é um teste diferente do cenário original (ex.: testaste no Chrome/web um bug relatado no telemóvel/app real, ou testaste um endereço genérico em vez do endereço exato citado). Nunca fechar sem reproduzir a MESMA entrada, no MESMO ambiente do relato original. Se não conseguires reproduzir esse ambiente exato, dizer isso no relatório em vez de fechar como resolvido.
metadata:
  versao: 1.0
  criada: 2026-09-17
  criada_por: vigia-habilidades (corrida 2026-09-17_1141)
  tema: "Bugs 'corrigidos' reabrem porque o teste de fecho não bate com o cenário real relatado (autocomplete de endereço da Guarda)"
  origem: texto-automatico-nao-fala-do-danilo
  origem_corrigida_em: 2026-09-17
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# prova-fix-cenario-real

> Criada pelo vigia a 17/09/2026 a partir de texto automatico (ordens/despacho/memoria), nao de uma fala literal do Danilo - origem corrigida a 17/09/2026 (ver seccao Origem). A regra mantem-se porque foi validada.

# Prova de Fix no Cenário Real

## Quando usar
Antes de marcar qualquer bug, ordem ou pedido do Danilo como corrigido/pronto/fechado — sobretudo bugs de UI, autocomplete, mapas ou qualquer coisa testada primeiro no Chrome/web ou emulador.

## Por que existe
O bug do autocomplete de endereço da Guarda (digitar 'Continente' mostra cidade errada, digitar 'Lavie' não encontra o shopping real) foi mandado corrigir pelo menos 14 vezes entre 05/09 e 17/09/2026 com o MESMO texto de ordem. A causa apontada em cada ordem é sempre a mesma: "a versão anterior foi aprovada só com teste no Chrome/web, não pegou o erro real".

## Regra de fecho
1. Identifica o cenário EXATO do relato original: dispositivo, app (mobile vs web), dado de entrada literal (ex.: a palavra 'Continente', a palavra 'Lavie').
2. Reproduz a correção nesse MESMO cenário — não um substituto mais fácil de testar.
3. Se só conseguires testar num substituto (ex.: só tens Chrome/web disponível), diz isso explicitamente no relatório: "testado só em X, NÃO testado em Y (cenário original)" — nunca digas apenas "corrigido".
4. Antes de reabrir uma ordem já dada antes, verifica no e2e_log ou no relatório anterior se ela já foi "fechada" sem prova no cenário certo — se sim, o problema não é o bug, é o critério de fecho.
5. Grava a prova (screenshot/vídeo/output) do cenário exato, não de um teste genérico.

## Exemplo do Bora
Bug: autocomplete de Guarda. Cenário original: app real, escrever 'Continente' e 'Lavie'. Prova inválida: só testar no Chrome/web com outra cidade. Prova válida: mesma app, mesmas palavras, resultado certo, captura guardada.

## Origem (corrigida a 17/09/2026)
texto da ordem 'AUTOCOMPLETE DE GUARDA QUEBRADO NA PRATICA' repetido por sessoes automaticas do carteiro (06:30/06:33 de 06/09 a 16/09) - NAO e fala literal do Danilo; a regra (fechar um bug so reproduzindo o cenario original) e da Claude.ai/Danilo e foi validada pela Claude.ai a 17/09 (a decisao ganho-motorista-numero-grande cita esta skill).
