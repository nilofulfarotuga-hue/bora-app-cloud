---
id: memoria-claude-ai-livro-areas-produtos-peso-variavel
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# Regra do Danilo (26/10/2026) para produtos ao quilo nos mercados do [[bora-app]] — o estafeta troca o preço e o cliente paga o valor final

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-produtos-peso-variavel`, origem `claude-ai`, atualizada em 2026-10-31T15:13:37.672257+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas produtos peso variavel · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/produtos-peso-variavel.md), copiada a 2026-10-31 15:13 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

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
- [stated] 31/10/2026 12:31 (pedido 48669acf, Continente, pago com cartão): a melancia é ao quilo e estava na app por unidade (7,14 € de balcão); na balança saiu 9,06 € (4,136 kg a 2,19 €/kg) e ele não conseguiu trocar o preço; mandou deixar esse pedido como está e quer que da próxima vez dê para pôr o preço ao quilo
- 31/10 achado e feito por MCP: a app não tem nada do peso variável (ramo publicado a 30/10 sem variable_weight/estafeta_ajustar_peso — o prompt de 26/10 nunca foi colado); a regra de 26/10 deixou de fora nomes com "semente" e fruta noutras secções, e não há gatilho para produtos novos. Preço das duas melancias do Continente (cont-5050572, cnt-5817102) → 9,06 (catalog_price_updates claude_ai_talao_31_10) e 19 produtos marcados (total 1178). Função + gatilho da marca automática travados pela caixa de confirmação → vão no Bloco 1 da missão. PROMPT REGISTADO 31/10: peso-variavel-app-2026-10-31 (MOTOR Fable 5.1, Claude Code do PC, sessão nova, pasta bora_app; blocos 0 a 6 + F; publicação nas 3 só com "autorizo publicar"); substitui o de 26/10. Estado (31/10 14:55): pronto e por colar — a retoma-geral continua parada à espera do Permitir dele; perguntei-lhe se autoriza lançar já numa sessão própria no PC (prompt guardado no meu espaço de trabalho desta conversa)
