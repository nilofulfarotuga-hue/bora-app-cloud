---
name: python-nao-encontrado-windows
description: >
  Usa esta skill sempre que um comando ou script invocar `python`/`python3` no PC do Danilo (Windows) e devolver 'Exit code 49 ... Python was not found; run without arguments to install from the Microsoft Store'. É o atalho (App Execution Alias) do Windows a interceptar o comando porque não há `python.exe` real no PATH — nunca é falta de instalação de verdade se já houve Python instalado antes. REFORCO 23/09: Reforço: usa também esta skill quando um script Python no PC do Danilo (Windows) rebentar com traceback a meio de 'Lib\\encod...' (UnicodeEncodeError) ao tentar imprimir texto em PT com acentos — não só quando o Python 'não é encontrado'. REFORCO 06/10: Reforço: o Bash deste PC pode arrancar sem PATH. 'ls: command not found' ou 'python: command not found' (exit 127) significa PATH vazio. Faz export PATH="/usr/bin:/bin:/mingw64/bin:$PATH" e repete; não reenvies o mesmo comando.
metadata:
  versao: 1.0
  criada: 2026-09-18
  criada_por: vigia-habilidades (corrida 2026-09-18_2330)
  tema: "Python not found no Windows (exit code 49, atalho da Microsoft Store)"
  origem_literal:
    - "periodo 2026-09-17→2026-09-18 (corpus secao 2): 3x em 3 sessoes/3 dias: Exit code 49 Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app setti"
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# python-nao-encontrado-windows

> Criada pelo vigia a 18/09/2026 porque o Danilo disse: periodo 2026-09-17→2026-09-18 (corpus secao 2): 3x em 3 sessoes/3 dias: Exit code 49 Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app setti

## python-nao-encontrado-windows

Sintoma: qualquer script que chame `python ...` falha com `Exit code 49` e a mensagem sobre instalar pela Microsoft Store, mesmo havendo Python instalado.

Causa: o Windows regista um 'App Execution Alias' chamado `python.exe`/`python3.exe` que intercepta a chamada quando o Python real não está à frente no PATH da sessão atual.

O que fazer, por ordem:
1. Testar `py -3 --version` (o launcher `py` normalmente resolve mesmo quando `python` não resolve).
2. Se existir venv do projeto, chamar o interpretador pelo caminho completo (`.venv\Scripts\python.exe`) em vez de `python`.
3. Se nada resolver, verificar `where python` e `where python3` — se apontarem só para `WindowsApps\python.exe`, o alias está a tapar o real; usar o caminho absoluto do Python real (normalmente em `C:\Users\danil\AppData\Local\Programs\Python\PythonXX\python.exe`).
4. Nunca pedir ao Danilo para desativar o alias manualmente em Definições — se for preciso mexer nessa definição, fazer via `Get-AppxPackage`/registo pelo próprio executor, nunca like tarefa manual dele.
5. Scripts novos que chamem Python devem preferir `py -3` a `python` cru, precisamente por causa deste alias.


## Reforco 23/09/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: 3x em 2 sessões/2 dias: Exit code 1 Traceback (most recent call last):\r   File \"<string>\", line 5, in <module>\r   File \"C:\\Users\\danil\\AppData\\Local\\Programs\\Python\\Python312\\Lib\\encod

## Erro de encoding (UnicodeEncodeError / traceback ao imprimir acentos)

Visto 3x em 2 sessões/2 dias: `Exit code 1 Traceback ... Lib\\encod...` ao correr scripts Python no PC do Danilo — a consola do Windows usa cp1252 por omissão, não UTF-8.

Antes de correr qualquer script Python que imprima texto em PT (acentos, ç, ã, õ): define `PYTHONIOENCODING=utf-8` no ambiente do comando (ou `chcp 65001` antes de chamar o Python) em vez de deixar o traceback rebentar a meio do script. Nunca reenviar o mesmo comando sem tratar a codificação — o erro é sempre o mesmo e nunca se resolve sozinho.


## Reforco 06/10/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: 

## Reforço 06/10/2026: PATH vazio no Bash

Erro visto 2x em 2 sessões/2 dias: `Exit code 127 /usr/bin/bash: line 1: ls: command not found`. A lição vinda do digest `digest-2026-10-06-jai-formatura-fix`: o Bash deste PC arranca sem PATH.

- Na primeira linha do comando: `export PATH="/usr/bin:/bin:/mingw64/bin:$PATH"`
- Se continuar, usa a ferramenta PowerShell, ou as dedicadas (Glob em vez de `ls`, Read em vez de `cat`).
- Não reenvies o mesmo comando sem corrigir o PATH.
