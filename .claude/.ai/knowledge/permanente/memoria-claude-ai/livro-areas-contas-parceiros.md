---
id: memoria-claude-ai-livro-areas-contas-parceiros
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Como se calcula e se paga o dinheiro das lojas parceiras do Bora (ledger vs registo do pedido), erros corrigidos a 22/09 e a decisão em aberto da taxa de pedido pequeno

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-contas-parceiros`, origem `claude-ai`, atualizada em 2026-10-23T05:40:25.497254+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas contas parceiros · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/contas-parceiros.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

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

