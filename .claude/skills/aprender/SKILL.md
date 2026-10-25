---
name: aprender
description: Usa NA HORA sempre que o Danilo te corrigir (um "não é assim", "já te disse", "errado", "outra vez isto", ou uma regra nova dita em tom de correção). Grava uma linha no fim da página erros-aprendidos do livro comum (public.claude_ai_memoria), que todos os agentes leem ao acordar — Claude.ai, Hermes, Claude Code, ChatGPT, OpenCode. Só acrescenta, nunca apaga.
---

# aprender — gravar uma correção do Danilo no livro comum

> Missão `livro-comum-2026-10-23`. A mesma função serve o Hermes (comando `aprender`) e a
> Claude.ai. Errou uma vez, nunca mais.

## Quando

- O Danilo corrige-te ou repete uma regra que já devias saber.
- A correção é duradoura (vale para as próximas vezes), não um detalhe só desta tarefa.
- Grava ANTES de continuar a tarefa, não no fim da sessão.

## Como (MCP Supabase, projeto `ojykpzwqrtusfeakzrna`)

```sql
select public.livro_aprender(
  'claude-code',
  '<o que errei, numa frase curta, sem nomes de clientes>',
  '<a regra certa, numa frase que outro agente perceba sozinho>'
);
```

Devolve a linha gravada, por exemplo:
`- 25/10 (claude-code): publiquei só na Play Store → publicar sempre nas 3 (Android, iPhone, web)`

Prova: mostra essa linha devolvida no relatório. Se der erro, mostra o erro real.

## Regras

- `p_quem` é quem errou: `claude-code` (tu), ou `hermes`, `claude-ai`, `chatgpt`, `opencode`,
  `codex` quando estás a registar uma correção dirigida a outro agente.
- Máximo 400 caracteres em cada parte. Português simples.
- Nunca segredos (a função recusa chaves), nunca dados pessoais de clientes, nunca páginas
  `[PESSOAL]`.
- Não reescrevas a página `erros-aprendidos` à mão nem com UPDATE: só por esta função.
- Fora do MCP (script na VPS): `python3 /opt/data/bin/livro_gravar.py` grava páginas inteiras;
  para uma correção usa o comando `aprender` do contentor do Hermes.

## Depois

- A linha entra no SOUL do Hermes na renovação seguinte (de 30 em 30 minutos) e no gancho de
  arranque do Claude Code na próxima sessão (cache de 1 hora).
- Se a mesma correção já aparece no caderno, a falha é grave: diz isso no relatório e
  considera propor uma skill (página `habilidades-propostas`).
