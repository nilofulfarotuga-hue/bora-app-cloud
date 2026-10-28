---
id: memoria-claude-ai-resposta-contabilista-iva-2026-10-28
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-28
zona: verde
confianca: alta
estado: atual
---

# Resposta do Hugo (DC Consultores): IVA normal trimestral, programa de faturação, modelo aceite — 28/10/2026

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `resposta-contabilista-iva-2026-10-28`, origem `claude.ai 28/10 15:45`, atualizada em 2026-10-28T15:40:26.64317+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: resposta contabilista iva 2026 10 28 · memoria claude.ai · claude_ai_memoria

28/10 15:07-15:10, grupo de WhatsApp "Contabilidade" (Hugo Carvalho):
1) A empresa Danilo Fulfaro da Silva - Unipessoal Lda (NIPC 519686233) está no regime NORMAL de IVA, periodicidade TRIMESTRAL. Não é isenta (o Danilo no nome individual é isento; a empresa não).
2) O escritório tem programa de faturação que a Bora pode usar. Falta saber qual e se liga à app (API) para emitir a fatura de cada pedido sozinha.
3) Modelo aceite ("pode ser uma solução"): a loja parceira fatura ao cliente o preço de balcão; a Bora fatura o resto (comissão, taxa de serviço, entrega, saco); os estafetas passam recibo à Bora.

Consequências:
- As faturas da Bora levam IVA 23% (serviços, continente). Preços ao cliente iguais (IVA já incluído por lei), por isso o IVA sai da parte da Bora: 23/123 = 18,7% do que a Bora fatura.
- Declaração periódica trimestral: entrega até dia 20 do 2.º mês a seguir ao trimestre, pagamento até ~dia 25. A 1.ª é out-dez/2026, em fevereiro de 2027. Deduz-se o IVA das despesas com fatura em nome da empresa (NIF 519686233).
- Exemplo verificado por SQL (pricing_calculate_loja, Boom, 3 km, 1 saco): 21,00 € de produtos -> cliente 24,85; loja 18,00; Bora 6,85 (IVA 1,28, líquido 5,57); estafeta 4,40 -> sobra 1,17 (sem IVA era 2,45). 30,00 € de produtos com entrega grátis -> cliente 31,80; loja 25,71; Bora 6,09 (IVA 1,14); estafeta 4,40 -> sobra 0,55 (sem IVA era 1,69).
- Ofício circulado AT 25062/2025: a isenção do art. 53 (até 15.000 €/ano; sai-se logo acima de 18.750 €) também vale para sociedades; quem opta pelo regime normal fica nele pelo menos 5 anos.
- Futuro: o fecho mensal e a ligação ao programa têm de separar base + IVA 23% nas faturas da Bora.
Pendente (só com o sim do Danilo): perguntar ao Hugo qual é o programa e se liga à app, e se compensava a empresa ficar isenta enquanto fatura pouco.
