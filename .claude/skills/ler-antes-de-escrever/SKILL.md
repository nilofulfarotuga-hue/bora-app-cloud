---
name: ler-antes-de-escrever
description: >
  Usa SEMPRE antes de Edit ou Write num ficheiro que já existe. Se aparecer 'File has not been read yet. Read it first before writing to it', faz Read desse ficheiro e repete a escrita. Não repitas o Edit/Write sem ler (visto 14x em 3 sessões/2 dias, 05-06/10/2026). REFORCO 17/10: Usa SEMPRE, SEM EXCEÇÃO, antes de qualquer Edit ou Write num ficheiro que já existe: faz Read primeiro nessa sessão. Erro 'File has not been read yet. Read it first before writing to it' visto 30x em 5 sessões/3 dias (15-17/10/2026), mesmo com esta skill ativa.
metadata:
  versao: 1.0
  criada: 2026-10-06
  criada_por: vigia-habilidades (corrida 2026-10-06_2332)
  tema: "Edit/Write sem ler o ficheiro antes"
  origem_literal:
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# ler-antes-de-escrever

> Criada pelo vigia a 06/10/2026 porque o Danilo disse: 

# Ler antes de escrever

Origem: erro técnico repetido do executor, `<tool_use_error>File has not been read yet. Read it first before writing to it.</tool_use_error>`. Visto 14x em 3 sessões/2 dias (05 e 06/10/2026).

## Regra
1. Antes de qualquer `Edit` ou `Write` sobre um ficheiro que já existe, faz `Read` desse ficheiro nesta conversa. Um Read de outra sessão, um grep ou um `cat` no Bash não contam.
2. Se o erro aparecer, faz `Read` e repete a escrita. Reenviar o mesmo Edit sem ler dá o mesmo erro.
3. Depois de o ficheiro mudar por fora (formatador, git, outro agente, script), lê outra vez antes de editar.
4. Ficheiro grande: `Read` com `offset`/`limit` na zona a mudar já conta.
5. Ficheiro novo que ainda não existe: `Write` direto, sem Read.
6. Ficheiro vários passos de edição seguidos: um Read inicial chega, desde que nada o altere entre as edições.

## Prova
Depois de escrever, lê de volta a zona alterada e mostra-a. Não digas 'gravado' sem isso.


## Reforco 17/10/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: 

## Reforço 17/10/2026
O erro `File has not been read yet. Read it first before writing to it` apareceu 30 vezes em 5 sessões e 3 dias depois de esta skill existir.

Regras:
- Antes de Edit/Write num ficheiro existente, faz Read desse ficheiro nesta sessão. Sem exceção, mesmo que o tenhas lido via ctx_execute_file ou Bash (isso não conta para o Edit).
- Se um Read ficou truncado ou foi feito antes de uma compactação, relê.
- Se o erro aparecer: Read, depois repete a escrita. Nunca repitas o mesmo Edit/Write sem ler.
- Para vários ficheiros, faz todos os Read em paralelo no início.
