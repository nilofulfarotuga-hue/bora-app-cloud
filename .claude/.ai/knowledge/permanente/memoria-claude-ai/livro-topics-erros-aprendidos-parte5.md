---
id: memoria-claude-ai-livro-topics-erros-aprendidos-parte5
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-07
zona: verde
confianca: alta
estado: atual
---

# Registo de erros que o Danilo já corrigiu — o que errei, a regra certa e a data; ler antes de agir em qualquer área onde já houve erro (parte 5 de 5)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-topics-erros-aprendidos-parte5`, origem `claude-ai`, atualizada em 2026-11-07T19:13:35.912488+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro topics erros aprendidos parte5 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /topics/erros-aprendidos.md, parte 5 de 5), copiada a 05/11/2026 21:12 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

- [stated] 05/11 20:16: disse-lhe que os pedidos do McDonald's e do Jyosmi não tinham talão registado e calculei o lucro com o preço de balcão da app; ele corrigiu "o talão do McDonald's eu registei sim, tirei foto" — tinha razão: a minha consulta com várias instruções devolveu só o resultado da última e eu nem vi a tabela order_receipts_v2 → regra: ver sempre uma consulta de cada vez (ou conferir que todos os resultados vieram) e, antes de dizer que falta talão, ler order_receipts_v2 e o bucket receipts; conta de lucro de pedido não-parceiro usa o valor do TALÃO (driver_typed_total_cents), nunca o preço da app
- [stated] 07/11 18:42: ele perguntou quanto o Valdemir lhe devia e eu respondi €3,24 (banco: €1,77 pendente + €1,47 meu cálculo) sem ter perguntado/lido se já tinha pago; ele corrigiu "o Valdemir já pagou tudo, não deve nada" → regra: dívida do Valdemir (e de qualquer motorista) só se lista se a conversa confirmar; o banco mostra "pendente" mesmo quando o Danilo já recebeu à mão — ele marca o pagamento por voz e o banco fica desatualizado. Ao responder "quanto deve", dizer o que o banco mostra e perguntar logo se já pagou, ou ver as conversas antigas primeiro

