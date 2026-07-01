---
tema: convencoes · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# 🛠️ Convenções — ambiente, git, MCP, Windows

> Aprendizagens de processo/ambiente (não regras de negócio). Cresce via Bibliotecário.

## Repo & branch
- Git repo está em **`bora_app/`** (não na raiz `projetosflutter/`). Usar `git -C bora_app …`
  ou `cd bora_app`. Branch de trabalho: `autonomous-night-2026-04-29`. `estado: atual`
- **Push falha por commits remotos** (CI faz bump de versionCode no mesmo branch). Resolução:
  `git stash` do unstaged → `git pull --rebase` → `git push` → `git stash pop`. `estado: atual`
- CI (`build_android.yml`) auto-bumpa `versionCode` e publica Play Internal — **não** bumpar
  `pubspec` à mão; `versionCode` é por-build, não por-commit. `estado: atual`

## MCP & cwd
- **MCP carrega pelo cwd de arranque.** `claude mcp list` e os tools MCP só funcionam com a
  sessão a arrancar de **`bora_app/`** (onde está `.mcp.json`). Fora disso, executar o protocolo
  do agente inline. `estado: atual`
- O nome real do MCP Supabase nas settings do Danilo é **`mcp__claude_ai_Supabase__*`**
  (execute_sql/apply_migration/…), não o UUID efémero de cada sessão. `estado: atual`
- Supabase projeto: **`ojykpzwqrtusfeakzrna`**. `estado: atual`

## Windows / encoding
- **CRLF quebra bash.** Scripts `.sh` TÊM de ficar em LF → `.gitattributes` com `*.sh text eol=lf`.
  Verificar bytes CR com **python** (`open(f,'rb').read().count(b'\r')`), **não** com
  `grep -c $'\r'` (no Git Bash conta todas as linhas — não é fiável). `estado: atual`
- Hooks correm via `bash .claude/hooks/*.sh` com cwd = raiz do projeto; usam `python` para ler
  o JSON do stdin. `estado: atual`

## Build
- `flutter analyze` tem de dar 0 erros. Build local Windows: `flutter config --jdk-dir` JDK 17
  (não JBR 21) + `gradle.properties workers.max=1`. CI é a autoridade para release. `estado: atual`
- **44 Edge Functions locais** (contagem corrigida; a SKILL antiga diz 43 — stale). `estado: atual`
