---
name: livro-comum
description: "Antes de qualquer tarefa do Bora, dos sites, do Studio ou do Danilo, consultar o livro comum (Córtex e AGENTS.md): o que o Danilo falou com a Claude.ai está lá. Serve ao Claude Code e ao dsh. Usar no arranque de qualquer tarefa e sempre que faltar contexto sobre decisões, regras ou conversas do Danilo."
---

# Livro comum: ler antes de inventar

O livro é a tabela `public.claude_ai_memoria` (Supabase `ojykpzwqrtusfeakzrna`), espelhada no Córtex em
`permanente/memoria-claude-ai/` de hora a hora. O que o Danilo falou com a Claude.ai chega aqui por esse espelho; nenhum
agente vê as conversas da Claude.ai diretamente.

## Antes de qualquer tarefa
1. `cortex_buscar` com 2 ou 3 palavras do tema e `cortex_ler` nas páginas que aparecerem.
2. Ler `AGENTS.md` do repo e, se existirem, `erros.md` e `regras.md` do livro (`~/.claude/cache/livro/`).
3. Páginas de partida: `erros-aprendidos`, `regras-do-danilo`, `livro-indice`, o `digest-*` mais recente.
4. Nunca inventar o que o livro pode responder. Nunca pedir ao Danilo para repetir o que já disse.

## Quando o Danilo corrigir
Gravar na hora: `select public.livro_aprender('<quem errou: claude-code | dsh>', '<o que errei>', '<a regra certa>');`
Só a correção e a regra; nunca segredos nem dados de clientes.

## Como saber se o espelho está vivo
O Córtex é espelhado em commits `cortex: espelho claude_ai_memoria <data> [skip ci]` no ramo de produção. Se o último tiver
mais de 24 h, reportar (não reescrever o espelho: é outra missão).

## No dsh
O dsh não segue as linhas `@ficheiro` do CLAUDE.md; o `~/.agents/AGENTS.md` manda ler os ficheiros acima. O MCP `cortex`
do dsh usa o token estático do servidor, guardado só para o utilizador em `~/.dsh/secrets`.
