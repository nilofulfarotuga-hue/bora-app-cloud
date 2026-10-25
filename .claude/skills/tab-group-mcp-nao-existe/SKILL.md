---
name: tab-group-mcp-nao-existe
description: >
  Usa esta skill sempre que uma ferramenta de aba/navegador devolver 'No tab group exists for this session yet' ao chamar tabs_context_mcp ou equivalente. Visto 3x em 3 sessões/2 dias (23-25/09/2026). Regra: antes de qualquer outra chamada de aba nesta sessão, chamar tabs_context_mcp com createIfEmpty: true primeiro — isso cria o grupo da sessão e devolve os tab IDs. Não repetir a chamada original sem esse passo. REFORCO 18/10: Usa esta skill sempre que uma ferramenta de aba/navegador devolver 'No tab group exists for this session yet', 'Tab N is not in Claude's tab group for this session' ou 'not in the same group as the current...'. Primeiro chama tabs_context_mcp para listar as abas válidas, ou cria uma aba nova dentro do grupo. Nunca repitas navigate ou screenshot com o id de aba antigo.
metadata:
  versao: 1.0
  criada: 2026-09-25
  criada_por: vigia-habilidades (corrida 2026-09-25_2330)
  tema: "tabs_context_mcp sem tab group criado ('No tab group exists for this session yet')"
  origem_literal:
    - "periodo 23-25/09/2026: 3x em 3 sessoes/2 dias: No tab group exists for this session yet. Call tabs_context_mcp with createIfEmpty: true first — that creates this session's group and returns its tab IDs."
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# tab-group-mcp-nao-existe

> Criada pelo vigia a 25/09/2026 porque o Danilo disse: periodo 23-25/09/2026: 3x em 3 sessoes/2 dias: No tab group exists for this session yet. Call tabs_context_mcp with createIfEmpty: true first — that creates this session's group and returns its tab IDs.

Erro visto 3x em 3 sessões/2 dias distintos (23-25/09/2026):

```
No tab group exists for this session yet. Call tabs_context_mcp with createIfEmpty: true first — that creates this session's group and returns its tab IDs.
```

**Causa:** a sessão ainda não tem um grupo de abas registado no MCP de navegador.

**Fix:** antes de qualquer ação sobre abas (ler, clicar, selecionar), chamar `tabs_context_mcp` com `createIfEmpty: true`. Isso cria o grupo da sessão e devolve os tab IDs a usar nas chamadas seguintes.

**Não fazer:** repetir a chamada original (ex.: select_browser, click, read_page) esperando que passe sem primeiro criar o grupo — o erro é sempre o mesmo até esse passo ser feito.



## Reforco 18/10/2026 (vigia-habilidades)
> O Danilo corrigiu isto outra vez: 

## Reforço (vigia 18/10/2026): variante 'not in Claude's tab group'

O erro voltou noutra forma: 8x em 3 sessões/4 dias com `Tab <id> is not in Claude's tab group for this session. Tools can only target tabs inside the group`. Houve também 3x em 2 sessões/2 dias com `Failed to navigate: Tab <id> is not in the same group as the current...`, depois de um `tabs_close_mcp`.

O que fazer:
1. Chama `tabs_context_mcp` (criando o grupo se não existir) e usa só os ids que ele devolve.
2. Depois de fechar uma aba com `tabs_close_mcp`, não reutilizes o id dela nem o de abas anteriores. Relê o contexto das abas primeiro.
3. Numa ação com várias abas (`actions[...] navigate`), confirma que todas pertencem ao grupo atual.
4. Se continuar a falhar, abre uma aba nova no grupo. Nunca repitas o mesmo comando à espera que passe.
5. Escolhe o navegador pelo deviceId (ver contas-e-navegadores), nunca pelo nome 'Browser 1/2'.
