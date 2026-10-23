---
id: memoria-claude-ai-livro-areas-ganhos-prestador
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regra do Danilo para o ganho do dia do prestador no [[bora-app]] — total de todos os papéis em qualquer ecrã; estado da correção

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-ganhos-prestador`, origem `claude-ai`, atualizada em 2026-10-23T05:35:15.180454+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas ganhos prestador · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/ganhos-prestador.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: ganhos-prestador
description: Regra do Danilo para o ganho do dia do prestador no [[bora-app]] — total de todos os papéis em qualquer ecrã; estado da correção
sources: [chat]
aliases: [ganhos de hoje, ganho do dia, ganhos do estafeta, ganhos do motorista]
---

- [stated] REGRA (05/09): o prestador tem de ver SEMPRE o total do dia dele, somando tudo o que faz — entregas, corridas TVDE, limpeza, lavagem de carros — esteja no ecrã em que estiver (motorista, estafeta, limpeza, lavagem). Ele está cadastrado em vários papéis e não quer números diferentes conforme o ecrã
- [stated] Queixa que deu origem à regra: no ecrã de casa do TVDE o cartão "Ganhos de hoje" mostrava-lhe €4,00 quando o dia tinha €9,32; o ecrã Ganhos, esse, já mostrava o total certo
- [stated] Estado: FEITO e empurrado a 05/09 (commit `a1569eb`, build 593 do CI). A ordem `ordem-20260905145531-84c5-aprovado-chat` foi absorvida pela sessão `fila-ganho-05-09` para não correr duas vezes. `loadTodayEarnings()` passou a usar a RPC `meu_ganho_ao_vivo` (`hoje_cents`) com a soma antiga só como rede; cartão único `lib/widgets/ganho_de_hoje_card.dart` nos quatro ecrãs de casa; no painel admin nasceram a vista `v_ganho_diario_por_pessoa` e a RPC `admin_ganho_do_dia` (o admin só tinha o semanal). Verificado por mim via MCP e no GitHub, não pela palavra do executor

