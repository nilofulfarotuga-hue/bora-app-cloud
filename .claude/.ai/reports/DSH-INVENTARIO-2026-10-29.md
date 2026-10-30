# DSH — inventário do que o Claude Code tem (B0), 29-30/10/2026

Missão `dsh-harness-2026-10-29`. Medido no PC do Danilo; provas literais em `C:\BoraLocal\QG\provas\dsh-harness-2026-10-29\`.

## Máquina
- Node v24.19.0 (serve: o dsh pede ^22.19 ou >=24), npm 11.17.0, pnpm não instalado, Claude Code 2.1.293.
- RAM livre 2880 MB antes de instalar; 1691 MB com o `dsh web` a correr. Disco C: 614 GB livres.

## O que o Claude Code tem hoje (e o dsh tem de passar a ter)
| Coisa | Quantidade medida | Nota |
|---|---|---|
| CLAUDE.md global | 7755 bytes (8712 depois da secção 13) | importa `AGENTS.md` do repo e o livro (`erros.md`, `regras.md`) com `@` |
| CLAUDE.md + AGENTS.md do repo bora-app-cloud | existem | BoraStudio só tem AGENTS.md; jai-site e bora-site não têm nenhum |
| Skills em `~/.claude/skills` | 148 com nome válido + 3 com `_` (`decision_engine`, `decision_registry`, `learning_engine`) | o brief dizia ~85: são muitas mais |
| Skills em `.claude/skills` dos repos | bora-app-cloud 142+3, BoraStudio 5, jai-site 1, bora-site nenhum | quase tudo repetido do global |
| Agentes | 43 globais + 33 do repo = 42 distintos | o brief dizia ~44 |
| Comandos / regras (`.claude/commands`, `rules`) | nenhum | |
| MCP em `~/.claude.json` | `rea` (npx rea-agents 6.8.0) | ~300 ferramentas |
| MCP em `.mcp.json` do repo | `nano-banana` (npx), `cortex` (http, OAuth) | |
| MCP por plugin | `context-mode` | |
| Conectores da Claude.ai (não vivem no PC) | Supabase, Gmail, Calendar, Drive, Canva, Higgsfield, Conselho | |
| Extensão do Chrome | `claude-in-chrome` | |

## OmniRoute (missão de 23/10)
Contentor `omniroute` vivo na VPS (`Up 6 days (healthy)`), mas só em `127.0.0.1:20128`. Do PC a porta 20128 não responde
(`TcpTestSucceeded=False`). Fica fora da cadeia do dsh.

## Já existia e não se tocou
`~/.agents/skills` com 123 skills do `npx skills` (addyosmani). Pasta `.agents/skills` dentro de bora-app-cloud (58),
BoraStudio (2) e jai-site (1), todas cópias reais, nunca junções.
