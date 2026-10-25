---
name: bash-heredoc-aspas-windows
description: >
  Usa esta skill sempre que o Bash tool devolver 'Exit code 2 ... unexpected EOF while looking for matching' — erro de aspas/heredoc mal fechado no Git Bash deste PC Windows. Visto 3x em 2 sessões/3 dias. Confere aspas simples/duplas emparelhadas e heredocs antes de repetir o comando; nunca reenviar o mesmo comando sem corrigir a sintaxe. REFORCO 23/09: Reforço: este erro voltou a acontecer depois de a skill já existir (mais 2 sessões/2 dias) — insistir em confirmar aspas/heredoc ANTES de reenviar, nunca repetir o comando idêntico à espera que passe.
metadata:
  versao: 1.0
  criada: 2026-09-21
  criada_por: vigia-habilidades (corrida 2026-09-21_2330)
  tema: "Erro de aspas/heredoc mal fechado no Bash tool (unexpected EOF)"
  origem_literal:
    - "corpus §2: 3x em 2 sessoes/3 dias: Exit code 2 /usr/bin/bash: -c: line 1: unexpected EOF while looking for matching `''"
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# bash-heredoc-aspas-windows

> Criada pelo vigia a 21/09/2026 porque o Danilo disse: corpus §2: 3x em 2 sessoes/3 dias: Exit code 2 /usr/bin/bash: -c: line 1: unexpected EOF while looking for matching `''

# Erro de aspas/heredoc no Bash (Git Bash Windows)

"Exit code 2 /usr/bin/bash: -c: line 1: unexpected EOF while looking for matching `''" significa aspas ou heredoc mal fechados — comum ao colar comandos multi-linha ou heredocs no Bash tool deste PC (Git Bash sobre Windows).

## O que fazer
1. Antes de repetir o comando, conta as aspas: cada `'` ou `"` aberta tem de fechar na mesma linha lógica.
2. Em heredocs, o delimitador de fecho (`EOF`, etc.) tem de estar sozinho na linha, sem indentação.
3. Strings com `$`, crase ou aspas dentro: usa aspas simples para literal, ou escapa dentro de aspas duplas.
4. Prefere escrever para ficheiro com Write/Edit em vez de heredocs longos dentro do Bash tool — evita este problema todo.
5. NUNCA repetir o mesmo comando exactamente igual depois deste erro — corrige a sintaxe primeiro.

## Porquê
Visto 3x em 2 sessões/3 dias sem correcção da causa (aspas), só repetição do mesmo comando.


## Reforco 23/09/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: 2x em 2 sessões/2 dias: Exit code 2 /usr/bin/bash: -c: line 96: unexpected EOF while looking for matching `''

## Reincidência confirmada (2 sessões/2 dias adicionais)

O mesmo erro (`Exit code 2 ... unexpected EOF while looking for matching`) voltou a aparecer depois desta skill já existir. Antes de repetir qualquer comando com heredoc (`<<'EOF' ... EOF`) ou aspas aninhadas no Git Bash deste PC: conta as aspas simples/duplas e confirma que o delimitador do heredoc fecha exatamente na mesma forma em que abriu (`'EOF'` vs `EOF`), sozinho numa linha, sem espaços à frente. Nunca reenviar o comando idêntico sem corrigir a sintaxe primeiro.
