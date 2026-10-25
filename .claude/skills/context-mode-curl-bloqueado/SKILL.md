---
name: context-mode-curl-bloqueado
description: >
  Dispara sempre que fores correr curl/wget direto no Bash para buscar uma URL. O hook do context-mode bloqueia sempre (visto 3x/3 sessões/2 dias) e pede para usar ctx_execute/ctx_fetch_and_index — não insistas no curl cru, vai direto à ferramenta certa. REFORCO 21/10: Dispara SEMPRE que fores correr curl ou wget directo no Bash para buscar uma URL, ou quando vires 'PreToolUse:Bash hook error: context-mode: curl/wget redirected'. O hook bloqueia sempre. NUNCA corras o curl cru, nem uma segunda vez: vai logo para mcp__plugin_context-mode_context-mode__ctx_execute (código que faz o pedido) ou ctx_fetch_and_index. Visto em 5+ sessões; voltou a acontecer em 2 sessõe
metadata:
  versao: 1.0
  criada: 2026-09-28
  criada_por: vigia-habilidades (corrida 2026-09-28_2330)
  tema: "curl/wget direto bloqueado pelo hook do context-mode"
  origem_literal:
    - "2026-09 (3x/3 sessões/2 dias distintos): PreToolUse:Bash hook error: context-mode: curl/wget redirected. Call mcp__plugin_context-mode_context-mode__ctx_execute(language, code) to fetch the URL, derive"
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# context-mode-curl-bloqueado

> Criada pelo vigia a 28/09/2026 porque o Danilo disse: 2026-09 (3x/3 sessões/2 dias distintos): PreToolUse:Bash hook error: context-mode: curl/wget redirected. Call mcp__plugin_context-mode_context-mode__ctx_execute(language, code) to fetch the URL, derive

# Context-mode: nunca uses curl/wget direto para buscar URL

## Gatilho
Vais correr curl ou wget no Bash para buscar o conteúdo de uma URL (página, API, ficheiro remoto).

## Regra
Visto 3x em 3 sessões/2 dias distintos (2026-09): o hook do context-mode intercepta e devolve "context-mode: curl/wget redirected. Call mcp__plugin_context-mode_context-mode__ctx_execute(...) to fetch the URL, derive...". Não insistas no curl/wget original — usa diretamente:
- mcp__plugin_context-mode_context-mode__ctx_fetch_and_index para buscar e indexar uma página/URL (os bytes crus não entram na conversa, ficam pesquisáveis por ctx_search).
- mcp__plugin_context-mode_context-mode__ctx_execute(language: "shell", code: "curl ...") só se precisares mesmo de correr o curl dentro do sandbox para processar a saída.

## Como aplicar
1. Antes de qualquer curl/wget a uma URL, pergunta-te: preciso do conteúdo bruto na conversa, ou só de derivar uma resposta? Quase sempre é a segunda.
2. Usa ctx_fetch_and_index primeiro; depois ctx_search para extrair só o que precisas.
3. Nunca repitas o comando curl/wget idêntico à espera que o hook deixe passar — ele não deixa.


## Reforco 21/10/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: 

## Reforço (vigia, 21/10/2026)

O erro `PreToolUse:Bash hook error: context-mode: curl/wget redirected` voltou a aparecer em 2 sessões distintas e em 2 dias (corpus de 21/10), depois de esta skill já existir. Quer dizer que foi ignorada.

Regra sem excepção:
1. Antes de escrever `curl` ou `wget` no Bash, para. Não tentes 'só desta vez'.
2. Para obter o conteúdo de uma URL e extrair um dado: `ctx_execute(language, code)`, com o código a fazer o pedido e a imprimir só o que interessa.
3. Para ler uma página inteira e pesquisá-la depois: `ctx_fetch_and_index` e a seguir `ctx_search`.
4. Para provar um código HTTP (ex.: 'está no ar, 200'), faz o pedido dentro do `ctx_execute` e imprime o código de estado e o início do corpo. A prova continua a ser saída literal.
5. Se o hook bloquear mesmo assim, não repitas o mesmo comando. Muda de ferramenta.

Origem: erro repetido 2x em 2 sessões/2 dias, corpus do vigia de 21/10/2026.
