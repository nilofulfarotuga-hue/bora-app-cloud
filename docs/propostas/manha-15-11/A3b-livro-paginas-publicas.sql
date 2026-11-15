-- A3b — as duas páginas públicas do livro que os robôs podem ler (missão manha-15-11, 15/11/2026).
-- PROPOSTA: não foi aplicada. Aplicar DEPOIS da migração
-- supabase/migrations/20261115120000_robos_livro_publico.sql (é a lista fechada dela).
-- Não é uma migração: é conteúdo do livro (public.claude_ai_memoria), gerado de docs/ajuda/*.md
-- sem os comentários internos do topo.
--
-- Idempotente: se a página já existir, só é reescrita se ainda for desta origem ('claude-code')
-- e o texto for diferente; uma página editada à mão por outra origem não é pisada.
-- Para mudar as regras públicas que os robôs leem: editar estas duas páginas no livro (sem nomes
-- de pessoas, margens, comissões nem nomes internos — se tiverem, a função esconde a página).
--
-- POR CONFIRMAR (achado de 15/11): a secção "Reservas em restaurantes" da ajuda diz que os 3 €
-- são descontados na conta; as regras do negócio (docs/contexto/03-regras-de-negocio.md) e os
-- robôs dizem 2 € de desconto quando o cliente chega. Corrigir o texto da ajuda antes de aplicar
-- (A1 e A3b), se a regra certa for a dos 2 €.

begin;

insert into public.claude_ai_memoria (pagina, titulo, conteudo, origem) values
  ('ajuda-publica-clientes',
   'Ajuda pública da Bora — clientes (o que os robôs podem dizer)',
   $aj$# Ajuda Bora — clientes

## Onde entregamos
A Bora entrega na Guarda e arredores, até cerca de 15 km da cidade. Se a tua morada estiver mais longe, a app avisa antes de pagares e não deixa fazer o pedido.

## Quanto custa a entrega
A entrega custa 2,50 € até 4 km e mais 0,50 € por cada quilómetro a mais. Os sacos pagam-se à parte: 0,30 € por pedido nos restaurantes e 0,10 € por saco nos mercados. Vês sempre o total antes de confirmar.

## Formas de pagamento
Podes pagar com cartão, com MB WAY ou em dinheiro à porta. Em dinheiro o pedido pode ir até 40 €. Com MB WAY recebes o pedido de pagamento na app MB WAY do teu banco e tens 2 minutos para aceitar; se não aceitares, o pedido não avança e não pagas nada.

## O pagamento MB WAY falhou
Se o MB WAY falhar ou o tempo acabar, o pedido não é feito e o teu carrinho continua na app para tentares outra vez ou escolheres outro meio. Se o pedido antigo ainda aparecer na app MB WAY, recusa-o lá. Se o dinheiro tiver saído da tua conta, fala connosco no Suporte e vemos logo.

## Tokens Bora
Ganhas tokens em cada compra. Podes usar os tokens para pagar parte de um pedido: no máximo metade do valor dos tokens que tens. Por exemplo, se tens 5 € em tokens, podes usar até 2,50 € num pedido. Os tokens têm prazo de validade, que vês na tua carteira.

## Carteira Bora
A carteira guarda o teu saldo Bora (por exemplo, de um reembolso). Podes usar esse saldo em qualquer compra na app. Vês o saldo e o histórico na tua carteira, no Perfil.

## Lojas abertas e horários
Cada loja e restaurante tem o seu horário. A app mostra se está aberto agora; quando está fechado, podes agendar o pedido para quando abrir, se a loja o permitir.

## Cancelar um pedido
Podes cancelar na página do pedido. Logo a seguir a pedir, antes de um estafeta aceitar, o cancelamento é grátis. Depois disso pode haver uma taxa de cancelamento, e a app mostra-ta antes de confirmares. Se o estafeta já recolheu o pedido, já não dá para cancelar.

## Reembolsos: carteira ou meio de pagamento
Quando há dinheiro a devolver, és tu que escolhes: (a) Carteira Bora, recebes o valor todo como saldo e podes usá-lo logo; ou (b) reembolso para o teu cartão ou MB WAY, o valor todo, que demora 5 a 10 dias úteis a aparecer na tua conta. Os tokens que usaste nesse pedido voltam para ti como tokens.

## Acompanhar o pedido
No separador Pedidos vês o estado do teu pedido em tempo real: a preparar, à procura de estafeta, a caminho e entregue. Quando o estafeta sai, vês no mapa por onde ele vai.

## Código de entrega
Alguns pedidos têm um código de 4 dígitos. Dá esse código ao estafeta só quando receberes o pedido na mão.

## Pedidos agendados
Podes marcar um pedido para mais tarde, escolhendo a hora no carrinho. O estafeta só é chamado perto da hora marcada.

## Favores (Comprar por mim, levar e trazer)
Nos Favores um estafeta faz um recado por ti: comprar alguma coisa numa loja, levar ou trazer um objeto. O serviço Normal custa 6 € e o Expresso 10 €, mais o valor das compras. Se as compras passarem do orçamento que deste, o estafeta pede a tua autorização antes de pagar. Recebes a foto do talão.

## Mercados e produtos ao quilo
Nos mercados, os produtos ao quilo (fruta, carne, peixe) têm um preço estimado. O estafeta pesa e escreve o valor certo da etiqueta; pagas o valor real. Se ficar mais barato, a diferença volta para a tua carteira.

## Reservas em restaurantes
Para reservar mesa pagas 3 € adiantados. Quando chegas, 2 € são descontados na conta do restaurante; 1 € fica como taxa da reserva. Podes cancelar sem custo até 2 horas antes da hora marcada. Se cancelares com menos de 2 horas ou não apareceres, os 3 € não são devolvidos.

## Limpezas
Podes marcar uma limpeza em casa pela app, com preço fixo conforme o tamanho da casa. Os materiais custam 3 € a mais e as limpezas repetidas têm 10 % de desconto. Se cancelares nos primeiros 5 minutos depois de marcar, não pagas nada.

## Mudar o nome do perfil
O nome do teu perfil não se muda na app. Para mudar o nome, fala com o Suporte e a equipa trata disso. A foto podes mudar tu em Perfil > Editar perfil. O email é o teu acesso à conta e não se altera.

## Mudar o telemóvel
Em Perfil > Editar perfil podes mudar o teu número de telemóvel.

## Fatura com NIF
Antes de pagar podes pedir fatura com o teu NIF. Sem NIF, a fatura sai como consumidor final.

## Falar com a equipa
Em Perfil > Suporte falas com o nosso assistente a qualquer hora. Se for preciso, ele passa a conversa a uma pessoa da equipa.$aj$,
   'claude-code'),
  ('ajuda-publica-estafetas-parceiros',
   'Ajuda pública da Bora — estafetas e parceiros (o que os robôs podem dizer)',
   $aj$# Ajuda Bora — estafetas e parceiros

## Estafeta: ficar online
Para receber pedidos, abre a app de estafeta e liga o botão Online. Tens de ter os documentos aprovados e a localização ligada. Quando acabares, desliga o Online.

## Estafeta: aceitar um pedido
Quando chega um pedido, vês a loja, a distância e quanto ganhas antes de aceitar. Tens alguns segundos para aceitar; se não aceitares, passa a outro estafeta.

## Estafeta: entregar com código
Em alguns pedidos o cliente tem um código de 4 dígitos. Pede-o na entrega e escreve-o na app para fechar o pedido.

## Estafeta: compras em mercados e Favores
Nos mercados e nos Favores compras os produtos, tiras foto ao talão e gravas na app. Nos produtos ao quilo escreves o valor da etiqueta da balança. Se a compra passar do orçamento do cliente, a app pede autorização ao cliente antes de pagares.

## Estafeta: ganhos e pagamentos
Os teus ganhos aparecem na app em cada pedido e no resumo da semana. O acerto de contas é semanal. Se recebeste dinheiro de clientes, o acerto desconta o que é da Bora.

## Estafeta: documentos e conta
Os documentos (identificação, carta, seguro do veículo, IBAN) enviam-se na app e são revistos pela equipa. Para mudar dados da conta, fala com o Suporte.

## Parceiro: receber e preparar pedidos
Os pedidos novos tocam na app do parceiro. Aceita, prepara e marca Pronto: o estafeta é chamado nessa altura. Se não puderes aceitar, recusa logo para o cliente não ficar à espera.

## Parceiro: falta de um produto
Se faltar um produto, marca-o como em falta no pedido. O cliente é avisado e o valor é acertado.

## Parceiro: menu, preços e horário
O menu, as fotos, os preços e o horário mudam-se no painel do parceiro. Mudanças grandes podem ser revistas pela equipa antes de aparecerem na app.

## Parceiro: pagamentos
O acerto com os parceiros é semanal e o extrato fica no painel do parceiro. As condições do teu contrato estão no painel; para dúvidas, fala com a equipa pelo Suporte.

## Parceiro: reservas
Nas reservas o cliente paga 3 € adiantados. Quando o cliente chega, marca a chegada na app e descontas 2 € na conta dele (1 € fica como taxa da reserva da Bora).$aj$,
   'claude-code')
on conflict (pagina) do update
   set titulo = excluded.titulo,
       conteudo = excluded.conteudo,
       atualizado_em = now()
 where public.claude_ai_memoria.origem = 'claude-code'
   and public.claude_ai_memoria.conteudo is distinct from excluded.conteudo;

-- Prova antes de gravar: as duas páginas têm de existir e passar no filtro da função.
do $$
declare
  v_ok int;
begin
  select count(*) into v_ok
    from public.claude_ai_memoria m
   where m.pagina = any (public._robos_livro_lista())
     and not public._robos_texto_interno(m.titulo || E'\n' || m.conteudo);
  if v_ok <> 2 then
    raise exception 'A3b: esperava 2 páginas públicas limpas, há %', v_ok;
  end if;
  raise notice 'A3b: 2 páginas públicas no livro, sem termos internos';
end
$$;

commit;
