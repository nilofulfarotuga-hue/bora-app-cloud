---
id: memoria-claude-ai-livro-areas-contas-parceiros
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Como se calcula e se paga o dinheiro das lojas parceiras do Bora (ledger vs registo do pedido), erros corrigidos a 22/09 e a decisão em aberto da taxa de pedido pequeno

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-contas-parceiros`, origem `claude-ai`, atualizada em 2026-11-11T05:12:59.521718+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas contas parceiros · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/contas-parceiros.md), copiada a 11/11/2026 05:13 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: contas-parceiros
description: Como se calcula e se paga o dinheiro das lojas parceiras do Bora (ledger vs registo do pedido), erros corrigidos a 22/09 e a decisão em aberto da taxa de pedido pequeno
sources: [cowork]
aliases: [pagamento aos parceiros, payout parceiro, comissão da loja, markup oculto, taxa de pedido pequeno]
---

- [stated] REGRA DELE (22/09, varredura pedida por ele: "tem que estar sempre exato, tem que estar certo"): quando eu achar erro nas contas dos parceiros, arrumo todos, e depois varro as outras lojas à procura do mesmo

Onde mora a verdade do dinheiro (verificado por SQL, 22/09)
- O que a loja recebe de facto sai do `ledger_entries` (`user_type='restaurant'`, `type='earning'`), e é isso que o acerto semanal (`compute_partner_weekly_settlement`) usa. Nos 5 pedidos entregues que existiam, o ledger tinha exactamente `partner_store_share` — a soma das etiquetas do dono. Nenhuma loja foi paga a mais nem a menos
- As colunas do pedido (`partner_commission_visible`, `partner_markup_hidden`) e o ecrã de pagamento do painel eram uma SEGUNDA contabilidade, e era aí que estava o erro — mesmo padrão das "duas verdades" da carteira

Corrigido por MCP a 22/09 (Claude.ai)
- `pricing_calculate`, ramo parceiro: o markup oculto era 5% do preço do CLIENTE; passou a 5% do preço de BALCÃO (`partner_store_share`), com a comissão a ser o resto, para os três pedaços somarem exactamente o subtotal. Antes registava 15% quando a margem real é 14,2857% (0,71% do subtotal a mais). Os 5 pedidos antigos foram corrigidos no registo. O que o cliente paga não mudou
- `admin_partner_payout_summary`: somava a coluna `price` (o total do cliente, com entrega, taxa de serviço e saco lá dentro) e só descontava comissão+markup+taxa de serviço — sobrava para a loja a ENTREGA e o SACO. Nos 5 pedidos entregues mandava pagar 15,12 € a mais (Goola 64,70 em vez de 52,50; Sabores de Casa 33,20 em vez de 30,28). Passou a bruto = soma dos subtotais e loja = `partner_store_share`
- `create_order`, ramo takeaway: tinha 10% e 5% cravados no código; passou a ler `platform_settings` e a usar a mesma fórmula do balcão

- [stated] DECIDIDO por ele 22/09: a taxa de pedido pequeno FICA e tem de ser cobrada — mas **só às lojas NÃO-PARCEIRAS**; loja parceira não leva taxa de pedido pequeno ("tem que ter a taxa aí de pedido mínimo... essa taxa de todo mundo não, não parceiro"). Supera a decisão que estava em aberto
- Histórico: a taxa (`small_order_fee_enabled=true`, abaixo de 15 € paga 1,39 €) era gravada mas não somada ao total do cliente entre 01/09 e 19/09 — 6 pedidos, 8,34 € que a Bora não cobrou e não se recuperam; o total já a inclui desde 20/09 (trabalho "contas claras"). FEITO por MCP 22/09 (migration `taxa_pedido_pequeno_so_nao_parceiro_2026_09_22`): `small_order_fee_calc` devolve 0 para loja parceira, `create_order` passa o id da loja (antes mandava NULL, por isso nem distinguia parceiro nem respeitava o mínimo próprio de cada loja) e o gatilho `fn_small_order_fee` idem. Provado: parceiros a 0, McDonald's/Auchan a 1,39, acima de 15 € a 0. ⚠️ A frase dele dava para os dois lados — foi levantado que, se o que ele queria era cobrar a TODA a gente, parceiro incluído, é uma linha a reverter
- Por varrer ainda: contas do lado do estafeta (ledger vs `driver_earnings`), pedidos de loja não-parceira (modelo dos 15% incluídos + taxa fixa), e serviços (barbearia/limpeza/lavagem, que no ramo final de `pricing_calculate` levam 10% do subtotal sem markup — pode ser outra regra, não confirmado)
- [stated] 15/10 "PARCEIRO CHAMA ESTAFETA" (botão no painel do parceiro, usado pelo Cauã do [[sabores-de-casa]]): mandou ligar ("Liga agora, arruma aí tudinho certinho") e deixou a escolha do fluxo comigo; disse que acha melhor o estafeta pagar lá na loja, receber o dinheiro do cliente e depois fazer o acerto
- [stated] 20/10/2026: mandou ESQUECER três achados de dinheiro — motorista que vai ao local e o cliente não aparece não ser pago, pedido pequeno a dar prejuízo à Bora, e a conta do estafeta que soma a dobrar; não mexer nem voltar a listá-los como pendência até ele trazer o assunto
- [stated] 10/11/2026 (pedido da Graça na Boom, a dinheiro, estafeta Valdemir): o Emanuel cobrou ao Valdemir na recolha. O Danilo acha que é assim que deve ser: em pedido de app a DINHEIRO numa loja PARCEIRA, o estafeta paga à loja na recolha e cobra ao cliente na entrega, para não ficar com muito dinheiro na mão. Pago com cartão/MB Way: o estafeta não paga nada na loja. Não-parceira: o estafeta faz a compra. Quer avisos grandes e claros no ecrã do estafeta (na loja e no cliente) e no painel do parceiro. Achado por MCP: o sistema ainda conta como se a Bora pagasse à loja no fecho (pagaria a dobrar) e o ecrã do estafeta diz "RECEBER … — entregar ao parceiro". PROMPT REGISTADO: missão pagar-na-loja-2026-11-10 (MOTOR Opus 5.5, sessão NOVA do Claude Code no PC, pasta bora_app), entregue no chat às ~21:35 para ele colar. Âmbito: servidor (valor a pagar à loja = preço de balcão, contas do fecho sem dobrar), ecrãs do estafeta, painel do parceiro, painel admin, publicar nas 3. 21:30: ele confirmou que o Valdemir pagou 13,80 € à Boom e recebeu 19,71 € (fica a dever 1,67 €; a Boom não recebe nada da Bora por este pedido) e disse "pode". O meu acerto por MCP foi travado pelo sistema de segurança, por isso o acerto do pedido 6d38f5e5 passou a Bloco 0 da missão (pedido marcado como pago na recolha, transação do estafeta 15,47→1,67, saldo +13,80, linha compensatória no livro de contas, fecho da loja a contar o pago na recolha). Prompt v2 entregue no chat às ~21:40. Estado 11/11 05:00: missão corrida no PC. Servidor feito e provado por mim por MCP (pedido da Graça: estafeta deve 1,67, Boom 0 a receber; colunas orders.loja_pagamento_estado/loja_pagar_valor). App pronta no ramo ai/2026-11-10-pagar-na-loja (pedido de revisão #10); a trava do PC não deixou publicar e o meu acesso de escrita ao GitHub foi travado — entreguei-lhe a linha para mandar o próprio Claude Code juntar o #10 e publicar nas 3
