-- app-15-11 bloco A1: indexar a ajuda publica (docs/ajuda/*.md) para os robos.
-- PRECISA ANTES da migracao 20261115104000_conhecimento_tipos_ajuda.sql (a tabela so
-- aceitava obsidian/knowledge/business_rules). Um trecho por secao '## ', tipo 'ajuda'.
-- So insere (nada se apaga); salta trechos cujo content_hash ja existe -> pode repetir-se.
-- char_count e calculado pelo servidor. Os vetores gte vem do agendamento
-- embeddings-gte-manter (de 2 em 2 min). Gerado de docs/ajuda/*.md.
insert into public.support_knowledge_chunks (source_file, source_type, chunk_index, section_title, chunk_text, content_hash)
select v.f, 'ajuda', v.i, v.t, v.x, encode(extensions.digest(convert_to(v.x, 'UTF8'), 'sha256'), 'hex')
from (values
('docs/ajuda/ajuda-clientes.md', 0, $aj$Onde entregamos$aj$, $aj$Ajuda Bora (Clientes) — Onde entregamos

A Bora entrega na Guarda e arredores, até cerca de 15 km da cidade. Se a tua morada estiver mais longe, a app avisa antes de pagares e não deixa fazer o pedido.$aj$),
('docs/ajuda/ajuda-clientes.md', 1, $aj$Quanto custa a entrega$aj$, $aj$Ajuda Bora (Clientes) — Quanto custa a entrega

A entrega custa 2,50 € até 4 km e mais 0,50 € por cada quilómetro a mais. Os sacos pagam-se à parte: 0,30 € por pedido nos restaurantes e 0,10 € por saco nos mercados. Vês sempre o total antes de confirmar.$aj$),
('docs/ajuda/ajuda-clientes.md', 2, $aj$Formas de pagamento$aj$, $aj$Ajuda Bora (Clientes) — Formas de pagamento

Podes pagar com cartão, com MB WAY ou em dinheiro à porta. Em dinheiro o pedido pode ir até 40 €. Com MB WAY recebes o pedido de pagamento na app MB WAY do teu banco e tens 2 minutos para aceitar; se não aceitares, o pedido não avança e não pagas nada.$aj$),
('docs/ajuda/ajuda-clientes.md', 3, $aj$O pagamento MB WAY falhou$aj$, $aj$Ajuda Bora (Clientes) — O pagamento MB WAY falhou

Se o MB WAY falhar ou o tempo acabar, o pedido não é feito e o teu carrinho continua na app para tentares outra vez ou escolheres outro meio. Se o pedido antigo ainda aparecer na app MB WAY, recusa-o lá. Se o dinheiro tiver saído da tua conta, fala connosco no Suporte e vemos logo.$aj$),
('docs/ajuda/ajuda-clientes.md', 4, $aj$Tokens Bora$aj$, $aj$Ajuda Bora (Clientes) — Tokens Bora

Ganhas tokens em cada compra. Podes usar os tokens para pagar parte de um pedido: no máximo metade do valor dos tokens que tens. Por exemplo, se tens 5 € em tokens, podes usar até 2,50 € num pedido. Os tokens têm prazo de validade, que vês na tua carteira.$aj$),
('docs/ajuda/ajuda-clientes.md', 5, $aj$Carteira Bora$aj$, $aj$Ajuda Bora (Clientes) — Carteira Bora

A carteira guarda o teu saldo Bora (por exemplo, de um reembolso). Podes usar esse saldo em qualquer compra na app. Vês o saldo e o histórico na tua carteira, no Perfil.$aj$),
('docs/ajuda/ajuda-clientes.md', 6, $aj$Lojas abertas e horários$aj$, $aj$Ajuda Bora (Clientes) — Lojas abertas e horários

Cada loja e restaurante tem o seu horário. A app mostra se está aberto agora; quando está fechado, podes agendar o pedido para quando abrir, se a loja o permitir.$aj$),
('docs/ajuda/ajuda-clientes.md', 7, $aj$Cancelar um pedido$aj$, $aj$Ajuda Bora (Clientes) — Cancelar um pedido

Podes cancelar na página do pedido. Logo a seguir a pedir, antes de um estafeta aceitar, o cancelamento é grátis. Depois disso pode haver uma taxa de cancelamento, e a app mostra-ta antes de confirmares. Se o estafeta já recolheu o pedido, já não dá para cancelar.$aj$),
('docs/ajuda/ajuda-clientes.md', 8, $aj$Reembolsos: carteira ou meio de pagamento$aj$, $aj$Ajuda Bora (Clientes) — Reembolsos: carteira ou meio de pagamento

Quando há dinheiro a devolver, és tu que escolhes: (a) Carteira Bora, recebes o valor todo como saldo e podes usá-lo logo; ou (b) reembolso para o teu cartão ou MB WAY, o valor todo, que demora 5 a 10 dias úteis a aparecer na tua conta. Os tokens que usaste nesse pedido voltam para ti como tokens.$aj$),
('docs/ajuda/ajuda-clientes.md', 9, $aj$Acompanhar o pedido$aj$, $aj$Ajuda Bora (Clientes) — Acompanhar o pedido

No separador Pedidos vês o estado do teu pedido em tempo real: a preparar, à procura de estafeta, a caminho e entregue. Quando o estafeta sai, vês no mapa por onde ele vai.$aj$),
('docs/ajuda/ajuda-clientes.md', 10, $aj$Código de entrega$aj$, $aj$Ajuda Bora (Clientes) — Código de entrega

Alguns pedidos têm um código de 4 dígitos. Dá esse código ao estafeta só quando receberes o pedido na mão.$aj$),
('docs/ajuda/ajuda-clientes.md', 11, $aj$Pedidos agendados$aj$, $aj$Ajuda Bora (Clientes) — Pedidos agendados

Podes marcar um pedido para mais tarde, escolhendo a hora no carrinho. O estafeta só é chamado perto da hora marcada.$aj$),
('docs/ajuda/ajuda-clientes.md', 12, $aj$Favores (Comprar por mim, levar e trazer)$aj$, $aj$Ajuda Bora (Clientes) — Favores (Comprar por mim, levar e trazer)

Nos Favores um estafeta faz um recado por ti: comprar alguma coisa numa loja, levar ou trazer um objeto. O serviço Normal custa 6 € e o Expresso 10 €, mais o valor das compras. Se as compras passarem do orçamento que deste, o estafeta pede a tua autorização antes de pagar. Recebes a foto do talão.$aj$),
('docs/ajuda/ajuda-clientes.md', 13, $aj$Mercados e produtos ao quilo$aj$, $aj$Ajuda Bora (Clientes) — Mercados e produtos ao quilo

Nos mercados, os produtos ao quilo (fruta, carne, peixe) têm um preço estimado. O estafeta pesa e escreve o valor certo da etiqueta; pagas o valor real. Se ficar mais barato, a diferença volta para a tua carteira.$aj$),
('docs/ajuda/ajuda-clientes.md', 14, $aj$Reservas em restaurantes$aj$, $aj$Ajuda Bora (Clientes) — Reservas em restaurantes

Para reservar mesa pagas 3 € adiantados. Quando chegas, o restaurante desconta 2 € na tua conta; o resto é a taxa da reserva. Podes cancelar sem custo até 2 horas antes da hora marcada. Se cancelares com menos de 2 horas ou não apareceres, os 3 € não são devolvidos.$aj$),
('docs/ajuda/ajuda-clientes.md', 15, $aj$Limpezas$aj$, $aj$Ajuda Bora (Clientes) — Limpezas

Podes marcar uma limpeza em casa pela app, com preço fixo conforme o tamanho da casa. Os materiais custam 3 € a mais e as limpezas repetidas têm 10 % de desconto. Se cancelares nos primeiros 5 minutos depois de marcar, não pagas nada.$aj$),
('docs/ajuda/ajuda-clientes.md', 16, $aj$Mudar o nome do perfil$aj$, $aj$Ajuda Bora (Clientes) — Mudar o nome do perfil

O nome do teu perfil não se muda na app. Para mudar o nome, fala com o Suporte e a equipa trata disso. A foto podes mudar tu em Perfil > Editar perfil. O email é o teu acesso à conta e não se altera.$aj$),
('docs/ajuda/ajuda-clientes.md', 17, $aj$Mudar o telemóvel$aj$, $aj$Ajuda Bora (Clientes) — Mudar o telemóvel

Em Perfil > Editar perfil podes mudar o teu número de telemóvel.$aj$),
('docs/ajuda/ajuda-clientes.md', 18, $aj$Fatura com NIF$aj$, $aj$Ajuda Bora (Clientes) — Fatura com NIF

Antes de pagar podes pedir fatura com o teu NIF. Sem NIF, a fatura sai como consumidor final.$aj$),
('docs/ajuda/ajuda-clientes.md', 19, $aj$Falar com a equipa$aj$, $aj$Ajuda Bora (Clientes) — Falar com a equipa

Em Perfil > Suporte falas com o nosso assistente a qualquer hora. Se for preciso, ele passa a conversa a uma pessoa da equipa.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 0, $aj$Estafeta: ficar online$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Estafeta: ficar online

Para receber pedidos, abre a app de estafeta e liga o botão Online. Tens de ter os documentos aprovados e a localização ligada. Quando acabares, desliga o Online.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 1, $aj$Estafeta: aceitar um pedido$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Estafeta: aceitar um pedido

Quando chega um pedido, vês a loja, a distância e quanto ganhas antes de aceitar. Tens alguns segundos para aceitar; se não aceitares, passa a outro estafeta.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 2, $aj$Estafeta: entregar com código$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Estafeta: entregar com código

Em alguns pedidos o cliente tem um código de 4 dígitos. Pede-o na entrega e escreve-o na app para fechar o pedido.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 3, $aj$Estafeta: compras em mercados e Favores$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Estafeta: compras em mercados e Favores

Nos mercados e nos Favores compras os produtos, tiras foto ao talão e gravas na app. Nos produtos ao quilo escreves o valor da etiqueta da balança. Se a compra passar do orçamento do cliente, a app pede autorização ao cliente antes de pagares.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 4, $aj$Estafeta: ganhos e pagamentos$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Estafeta: ganhos e pagamentos

Os teus ganhos aparecem na app em cada pedido e no resumo da semana. O acerto de contas é semanal. Se recebeste dinheiro de clientes, o acerto desconta o que é da Bora.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 5, $aj$Estafeta: documentos e conta$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Estafeta: documentos e conta

Os documentos (identificação, carta, seguro do veículo, IBAN) enviam-se na app e são revistos pela equipa. Para mudar dados da conta, fala com o Suporte.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 6, $aj$Parceiro: receber e preparar pedidos$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Parceiro: receber e preparar pedidos

Os pedidos novos tocam na app do parceiro. Aceita, prepara e marca Pronto: o estafeta é chamado nessa altura. Se não puderes aceitar, recusa logo para o cliente não ficar à espera.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 7, $aj$Parceiro: falta de um produto$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Parceiro: falta de um produto

Se faltar um produto, marca-o como em falta no pedido. O cliente é avisado e o valor é acertado.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 8, $aj$Parceiro: menu, preços e horário$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Parceiro: menu, preços e horário

O menu, as fotos, os preços e o horário mudam-se no painel do parceiro. Mudanças grandes podem ser revistas pela equipa antes de aparecerem na app.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 9, $aj$Parceiro: pagamentos$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Parceiro: pagamentos

O acerto com os parceiros é semanal e o extrato fica no painel do parceiro. As condições do teu contrato estão no painel; para dúvidas, fala com a equipa pelo Suporte.$aj$),
('docs/ajuda/ajuda-estafetas-parceiros.md', 10, $aj$Parceiro: reservas$aj$, $aj$Ajuda Bora (Estafetas e parceiros) — Parceiro: reservas

Nas reservas o cliente paga 3 € adiantados. Quando o cliente chega, marca a chegada na app e descontas 2 € na conta dele. Se não aparecer ou cancelar com menos de 2 horas, não há desconto a fazer.$aj$)
) as v(f, i, t, x)
where not exists (
  select 1 from public.support_knowledge_chunks k
   where k.content_hash = encode(extensions.digest(convert_to(v.x, 'UTF8'), 'sha256'), 'hex'));
-- prova: select count(*) n, count(embedding_gte) com_gte from public.support_knowledge_chunks where source_type = 'ajuda';  -- espera 31
