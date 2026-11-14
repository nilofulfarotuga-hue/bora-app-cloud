---
name: aprender
description: "Usar NA HORA quando o Danilo te corrigir ('não é assim', 'já te disse', 'errado'): grava uma linha em erros-aprendidos do livro (livro_aprender). Também para retrospetiva de erros repetidos e propostas de evolução de skills."
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

## Padrões e evolução (absorvido a 14/11/2026 de `learning_engine` e `evolution-engine`)

- **Retrospetiva ("que erros se repetem?")**: ler `erros-aprendidos`, `.claude/.ai/knowledge/wiki/skills-metrics.md`
  e o `e2e_log` dos últimos dias; agrupar por causa. O que se repetiu 2+ vezes vira linha em
  `erros-aprendidos` (como acima) ou reforço de skill (o vigia das 23:30 já o faz sozinho).
- **Evolução de skills (criar, reescrever, arquivar, fundir)**: só PROPOSTAS. Motor mecânico:
  `python .claude/skills/evolution-engine/scripts/evolution_engine.py --dry-run` (o script fica
  nesse caminho de propósito: o daily-pulse da VPS chama-o lá). Saída em
  `inbox/evolution-report-<data>.md`; nada se aplica sem o Juiz; skills de dinheiro ou de
  publicação vão para a página `habilidades-propostas` do livro e nunca se ativam sozinhas.
- Originais em `.claude/skills/_arquivo/learning_engine/` e `_arquivo/evolution-engine/`.
