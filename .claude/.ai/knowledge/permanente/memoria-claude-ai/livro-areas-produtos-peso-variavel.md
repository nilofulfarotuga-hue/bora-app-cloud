---
id: memoria-claude-ai-livro-areas-produtos-peso-variavel
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-26
zona: verde
confianca: alta
estado: atual
---

# Regra do Danilo (26/10/2026) para produtos ao quilo nos mercados do [[bora-app]] — o estafeta troca o preço e o cliente paga o valor final

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-produtos-peso-variavel`, origem `claude-ai`, atualizada em 2026-10-26T13:29:33.677566+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas produtos peso variavel · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/produtos-peso-variavel.md), copiada a 2026-10-26 13:29 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: produtos-peso-variavel
description: Regra do Danilo (26/10/2026) para produtos ao quilo nos mercados do [[bora-app]] — o estafeta troca o preço e o cliente paga o valor final
sources: [chat]
aliases: [peso variável, preço por quilo, produtos ao quilo, banana por quilo, ajuste de peso, balança do mercado]
---

- [stated] 26/10/2026: nos produtos que se vendem ao quilo (frutas, legumes, carnes) o valor nunca bate certo com o pedido (ex.: pediram 4 bananas); o estafeta tem de poder tocar no preço do produto na lista de compras e trocá-lo pelo valor final que vai pagar depois de pesar
- [stated] O fluxo tem de chegar certo ao cliente: paga o valor final e recebe notificação de que o preço mudou por ser ao quilo
- [stated] 26/10/2026 10:16: "Autorizo" à proposta — cliente paga o valor final com a mesma margem do produto (mais barato paga menos), limite de 30% para cima ou para baixo, aviso ao cliente, dinheiro cobra o valor novo, cartão cobra a diferença no mesmo cartão, MB Way a Bora assume se subir, mais barato volta para a carteira, painel admin, produtos que o estafeta acrescenta passam a levar os 15%
- 26/10 13:05–13:11 servidor feito por MCP: migrações 20261026130514, 20261026130940, 20261026131049 (coluna products.variable_weight, 1159 produtos marcados, tabela order_weight_adjustments, RPC estafeta_ajustar_peso, talão a aplicar o peso e a margem dos acrescentados, cobrança no cartão desligada em weight_adjust_card_charge_enabled). PROMPT REGISTADO: página `prompt-peso-variavel-2026-10-26` em claude_ai_memoria, MOTOR OPUS 5.5, sessão "bora-app" do PC, run_id peso-variavel-2026-10-26 (repo e migrações, ecrã do estafeta, cliente, painel, cartão pronto e desligado, provas a dinheiro, fecho sem publicar — vai na publicação semanal). Estado: à espera do fim da missão melhorias-paridade para eu colar
