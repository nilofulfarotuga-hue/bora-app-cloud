---
id: memoria-claude-ai-livro-areas-conectores-claude-ai
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Conectores MCP da Claude.ai do Danilo — estado, senhas, e a REGRA de verificar o conselho antes de responder

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-conectores-claude-ai`, origem `claude-ai`, atualizada em 2026-10-23T05:41:51.734424+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas conectores claude ai · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/conectores-claude-ai.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: conectores-claude-ai
description: Conectores MCP da Claude.ai do Danilo — estado, senhas, e a REGRA de verificar o conselho antes de responder
sources: [chat]
aliases: [conector, Conselho Bora, Cortex Bora, conectores]
---

🔴 REGRA OBRIGATÓRIA (Danilo, 2026-08-11, dita com firmeza depois de eu andar a dar palpites em vez de consultar):
- ANTES de qualquer resposta que envolva análise/decisão do Bora, VERIFICAR se o conselho está acessível (tool_search por "Conselho Bora" / go_conselho). Se NÃO estiver, dizer-lhe logo "o conselho não está a chegar-me" e MANDAR CORRIGIR — nunca continuar a adivinhar em silêncio
- NUNCA dizer "deve ser" ou "é isso mesmo" sobre algo que não vi. Se não vi: digo "não sei" e mando verificar com prova (código, medição, log). Ele apanhou-me a fazer isto e tem razão
- Ele não tem de me lembrar do que está certo — o que der errado, eu corrijo por iniciativa própria

SENHAS DOS CONECTORES (dele, para reautorizar em claude.ai/settings/connectors):
- Conselho Bora — `https://conselho.srv1786862.hstgr.cloud` — senha `[REMOVIDO]`
- Cortex Bora — senha `[REMOVIDO]`

PROBLEMA ABERTO 2026-08-11: o conector Conselho Bora aparece ligado mas NÃO serve ferramentas à Claude.ai (tool_search três vezes só devolve as do Córtex). O Córtex ANTES também caía a toda a hora e deixou de cair depois de mexermos nele — logo há uma diferença concreta entre os dois que resolve isto. Ordem `ordem-20260811153316-3882` criada para: verificar o conselho-mcp vivo, testar initialize→tools/list de fora, COMPARAR com o cortex-mcp que funciona, corrigir a diferença e provar com tools/list a devolver as 3 ferramentas
✅ 17/09 RESOLVIDO E ALARGADO
- O Córtex volta a servir-me tools (cortex_buscar / cortex_ler / cortex_propor / cortex_propostas_pendentes provados nesse dia) e aparece ligado na claude.ai. ATENÇÃO: os conectores MUDARAM DE SÍTIO na claude.ai — agora em **Personalizar > Conectores**, já não em Configurações (claude.ai/settings/connectors só mostra um aviso a remeter para lá)
- O Córtex ficou também ligado ao **ChatGPT Plus** dele: conector em modo de programador (criado 14/09, URL https://cortex.srv1786862.hstgr.cloud/, OAuth), autorizado 17/09 com a senha `[REMOVIDO]`, já a listar as ferramentas. Foi preciso carregar em "Atualizar" e recarregar a página para as ações aparecerem. DEIXEI as permissões no pedido-de-autorização por defeito, de propósito: o `cortex_aprovar_proposta` cria ordens a sério na fila do loop, não é coisa para ficar automática
- HISTÓRICO (já resolvido) — 13/09 O CÓRTEX NÃO ME SERVIA TOOLS (tool_search "Córtex Bora" só carregava o Conselho) desde pelo menos 09/09 — coincide com a VPS desligada por falta de pagamento (09→13/09) e com a regra conhecida "o OAuth do cortex-mcp perde-se em cada redeploy". Caminho: o executor confirma o contentor cortex-mcp vivo e initialize→tools/list de fora, e depois o Danilo reautoriza o conector em claude.ai/settings/connectors (senha [REMOVIDO]) — é o único clique dele. Enquanto isso, fontes de verdade = Supabase por MCP + Gmail

