---
id: memoria-claude-ai-livro-areas-recibo-cliente-produto-falta
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regras que o Danilo fixou para mexer no conteúdo de um pedido já feito (produto em falta, acrescentar produto) e para o recibo do cliente — ler antes de mexer em totais, talão ou recibo do cliente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-recibo-cliente-produto-falta`, origem `claude-ai`, atualizada em 2026-10-23T05:34:06.23654+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas recibo cliente produto falta · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/recibo-cliente-produto-falta.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: recibo-cliente-produto-falta
description: Regras que o Danilo fixou para mexer no conteúdo de um pedido já feito (produto em falta, acrescentar produto) e para o recibo do cliente — ler antes de mexer em totais, talão ou recibo do cliente
sources: [chat]
aliases: [recibo do cliente, produto em falta, item indisponível, talão do mercado, recibo da compra]
---

- [stated] produto que falta na compra tem de sair do total: o cliente NÃO paga o que não recebeu
- [stated] a foto do talão do mercado que o estafeta tira é só interna — NUNCA vai para o cliente
- [stated] o recibo do cliente é o do [[bora-app]]: exatamente os produtos que ele levou, ao preço que vê na app, mais a entrega (2,50), mais a taxa de serviço, mais o saco, e mais nada; se um produto saiu da compra, tem de sair também do recibo
- [stated] REGRA NOVA (22/09): o PARCEIRO tem de poder acrescentar e tirar produtos de um pedido já feito, pelo painel dele — caso típico: o cliente compra e depois pede mais alguma coisa, ou falta produto e tem de sair. A conta tem de se refazer sozinha e bater certo (subtotal, taxa de serviço, comissão, markup, saco, entrega). Hoje não existe em lado nenhum para loja parceira; só há o caminho do talão dos mercados não-parceiros, onde é o estafeta que compra
- [stated] 22/09: o dono da loja quer também um CAMPO DE PESQUISA no painel dele (a loja já passa dos 100 produtos e procurar à mão não dá). PROMPT REGISTADO: `PROMPT_parceiro_edita_pedido_2026-09-22.md`, entregue 22/09, MOTOR FABLE (OPUS em alternativa), SESSÃO NOVA no Claude Code pasta bora-app-cloud, run_id `parceiro-edita-pedido-2026-09-22`. Blocos: acrescentar produto ao pedido (com pesquisa), tirar produto em falta, conta a refazer-se ao cêntimo, cliente aceita a diferença antes de ser cobrado, painel admin com histórico e estorno, provas + push. Estado: entregue como ficheiro, por rodar
- [stated] 22/09, caso que deu origem a isto: pedido da Sabores de Casa já pago por MB Way (40,02 €) em que o dono criou um produto novo e quis acrescentá-lo. O Danilo decidiu NÃO acrescentar nesse pedido
- [stated] REGRA (25/09): recibo ao cliente NÃO vai sozinho quando o pedido/corrida termina — só se envia quando o Danilo mandar ("manda o recibo pra tal cliente"). O recibo fica guardado no sistema. Aplicado: setting `tvde_recibo_email_auto`=false (era o único envio automático; reenviar à mão por `admin_tvde_recibo_reenviar`)

