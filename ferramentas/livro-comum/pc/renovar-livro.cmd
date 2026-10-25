@echo off
rem Renova as copias do livro que o CLAUDE.md global importa e envia a memoria do Claude Code para o livro
rem (missao livro-comum-2026-10-23). Correr a mao ou por tarefa agendada, se o Danilo a aprovar (docs/TRANCAS.md).
"C:\Program Files\nodejs\node.exe" "C:\Users\danil\.claude\livro\livro-ao-acordar.mjs" erros forcar > nul 2>&1
"C:\Program Files\nodejs\node.exe" "C:\Users\danil\.claude\livro\livro-ao-acordar.mjs" regras forcar > nul 2>&1
"C:\Program Files\nodejs\node.exe" "C:\Users\danil\.claude\livro\livro-claude-code-aprendeu.mjs" > nul 2>&1
"C:\Program Files\nodejs\node.exe" "C:\Users\danil\.claude\livro\espelhar-skills.mjs" > nul 2>&1
