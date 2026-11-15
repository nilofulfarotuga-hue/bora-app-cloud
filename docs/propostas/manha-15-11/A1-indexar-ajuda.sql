-- A1b — indexar a ajuda pública nos robôs (missão manha-15-11, 15/11/2026).
-- PROPOSTA: não foi aplicada. Quem aplica corre este ficheiro inteiro de uma vez (é uma só
-- transação). Gerado a partir de docs/ajuda/ajuda-clientes.md (20 secções) e
-- docs/ajuda/ajuda-estafetas-parceiros.md (11 secções): cada "## " é um trecho.
--
-- Colunas lidas por SELECT a 15/11 (information_schema) em support_knowledge_chunks:
--   id uuid default gen_random_uuid(), source_file text NOT NULL, source_type text NOT NULL,
--   chunk_index int NOT NULL, section_title text, chunk_text text NOT NULL, char_count int,
--   content_hash text NOT NULL, embedding vector, indexed_at timestamptz default now(),
--   embedding_gte vector, indexed_gte_at timestamptz.
-- Restrições lidas a 15/11: UNIQUE(content_hash), UNIQUE(source_file, chunk_index) e
--   CHECK source_type IN ('obsidian','knowledge','business_rules')  <- NÃO aceita 'ajuda'.
--   Por isso o passo 1 alarga o CHECK para também aceitar 'manual', 'faq' e 'ajuda' (os três
--   tipos que a proposta 8e_robos_sem_notas_internas deixa os robôs pesquisar).
--
-- Nota: os trechos antigos usam sha256 no content_hash (64 carateres); estes usam md5 (32),
-- como foi pedido. Não colidem, e a unicidade continua garantida.
--
-- Idempotente: correr duas vezes não duplica nada.
--   * um trecho com o mesmo texto (mesmo md5) é mantido, só se acerta a posição e o título;
--   * se uma secção da ajuda mudar de texto, a versão antiga desse ficheiro (só do tipo 'ajuda'
--     e só destes dois ficheiros) sai e entra a nova, com embedding NULL.
-- Não toca em nenhum trecho de outro tipo.
--
-- DEPOIS DE APLICAR (os vetores ficam vazios de propósito):
--   1) reindex-knowledge com {"mode":"pending"} preenche a coluna embedding (Gemini, 768);
--   2) embeddings-gte (modo manual) preenche embedding_gte (gte-small, 384), que é o motor
--      primário dos robôs. Sem o passo 2 o robô que pesquisa pelo gte não vê estes trechos.
--   3) Para os robôs deixarem de ver as notas internas, aplicar também a proposta
--      docs/propostas/fechar-app-15-11/8e_robos_sem_notas_internas.PROPOSTA.sql (lista fechada).
--
-- PROVA LOCAL (PGlite, Postgres 17, 15/11/2026): numa tabela com as mesmas colunas e restrições,
-- 1.ª corrida = 31 trechos 'ajuda' (+ o trecho antigo intacto); 2.ª corrida = 31 (não duplica);
-- com uma secção alterada e duas trocadas de lugar = 31, posições e títulos certos, o texto novo
-- com embedding NULL; com "Margem" escrita num trecho a transação é recusada (anti-mentira).
--
-- POR CONFIRMAR antes de aplicar: a secção "Reservas em restaurantes" diz que os 3 € são
-- descontados na conta; as regras do negócio (docs/contexto/03-regras-de-negocio.md) e os robôs
-- dizem 2 € de desconto quando o cliente chega. Se a certa for a dos 2 €, corrigir
-- docs/ajuda/ajuda-clientes.md (e "Parceiro: reservas") e gerar este ficheiro outra vez.

begin;

-- 1. O tipo 'ajuda' passa a ser aceite.
alter table public.support_knowledge_chunks
  drop constraint if exists support_knowledge_chunks_source_type_check;
alter table public.support_knowledge_chunks
  add constraint support_knowledge_chunks_source_type_check
  check (source_type = any (array['obsidian','knowledge','business_rules','manual','faq','ajuda']::text[]));

-- 2. Os 31 trechos, tal como estão nos ficheiros (texto = "## título" + parágrafo).
create temp table _ajuda_nova (
  source_file text not null,
  chunk_index int not null,
  section_title text not null,
  chunk_text text not null
) on commit drop;

insert into _ajuda_nova (source_file, chunk_index, section_title, chunk_text) values
  ('ajuda-clientes.md', 0, 'Onde entregamos',
   $aj$## Onde entregamos
A Bora entrega na Guarda e arredores, até cerca de 15 km da cidade. Se a tua morada estiver mais longe, a app avisa antes de pagares e não deixa fazer o pedido.$aj$),
  ('ajuda-clientes.md', 1, 'Quanto custa a entrega',
   $aj$## Quanto custa a entrega
A entrega custa 2,50 € até 4 km e mais 0,50 € por cada quilómetro a mais. Os sacos pagam-se à parte: 0,30 € por pedido nos restaurantes e 0,10 € por saco nos mercados. Vês sempre o total antes de confirmar.$aj$),
  ('ajuda-clientes.md', 2, 'Formas de pagamento',
   $aj$## Formas de pagamento
Podes pagar com cartão, com MB WAY ou em dinheiro à porta. Em dinheiro o pedido pode ir até 40 €. Com MB WAY recebes o pedido de pagamento na app MB WAY do teu banco e tens 2 minutos para aceitar; se não aceitares, o pedido não avança e não pagas nada.$aj$),
  ('ajuda-clientes.md', 3, 'O pagamento MB WAY falhou',
   $aj$## O pagamento MB WAY falhou
Se o MB WAY falhar ou o tempo acabar, o pedido não é feito e o teu carrinho continua na app para tentares outra vez ou escolheres outro meio. Se o pedido antigo ainda aparecer na app MB WAY, recusa-o lá. Se o dinheiro tiver saído da tua conta, fala connosco no Suporte e vemos logo.$aj$),
  ('ajuda-clientes.md', 4, 'Tokens Bora',
   $aj$## Tokens Bora
Ganhas tokens em cada compra. Podes usar os tokens para pagar parte de um pedido: no máximo metade do valor dos tokens que tens. Por exemplo, se tens 5 € em tokens, podes usar até 2,50 € num pedido. Os tokens têm prazo de validade, que vês na tua carteira.$aj$),
  ('ajuda-clientes.md', 5, 'Carteira Bora',
   $aj$## Carteira Bora
A carteira guarda o teu saldo Bora (por exemplo, de um reembolso). Podes usar esse saldo em qualquer compra na app. Vês o saldo e o histórico na tua carteira, no Perfil.$aj$),
  ('ajuda-clientes.md', 6, 'Lojas abertas e horários',
   $aj$## Lojas abertas e horários
Cada loja e restaurante tem o seu horário. A app mostra se está aberto agora; quando está fechado, podes agendar o pedido para quando abrir, se a loja o permitir.$aj$),
  ('ajuda-clientes.md', 7, 'Cancelar um pedido',
   $aj$## Cancelar um pedido
Podes cancelar na página do pedido. Logo a seguir a pedir, antes de um estafeta aceitar, o cancelamento é grátis. Depois disso pode haver uma taxa de cancelamento, e a app mostra-ta antes de confirmares. Se o estafeta já recolheu o pedido, já não dá para cancelar.$aj$),
  ('ajuda-clientes.md', 8, 'Reembolsos: carteira ou meio de pagamento',
   $aj$## Reembolsos: carteira ou meio de pagamento
Quando há dinheiro a devolver, és tu que escolhes: (a) Carteira Bora, recebes o valor todo como saldo e podes usá-lo logo; ou (b) reembolso para o teu cartão ou MB WAY, o valor todo, que demora 5 a 10 dias úteis a aparecer na tua conta. Os tokens que usaste nesse pedido voltam para ti como tokens.$aj$),
  ('ajuda-clientes.md', 9, 'Acompanhar o pedido',
   $aj$## Acompanhar o pedido
No separador Pedidos vês o estado do teu pedido em tempo real: a preparar, à procura de estafeta, a caminho e entregue. Quando o estafeta sai, vês no mapa por onde ele vai.$aj$),
  ('ajuda-clientes.md', 10, 'Código de entrega',
   $aj$## Código de entrega
Alguns pedidos têm um código de 4 dígitos. Dá esse código ao estafeta só quando receberes o pedido na mão.$aj$),
  ('ajuda-clientes.md', 11, 'Pedidos agendados',
   $aj$## Pedidos agendados
Podes marcar um pedido para mais tarde, escolhendo a hora no carrinho. O estafeta só é chamado perto da hora marcada.$aj$),
  ('ajuda-clientes.md', 12, 'Favores (Comprar por mim, levar e trazer)',
   $aj$## Favores (Comprar por mim, levar e trazer)
Nos Favores um estafeta faz um recado por ti: comprar alguma coisa numa loja, levar ou trazer um objeto. O serviço Normal custa 6 € e o Expresso 10 €, mais o valor das compras. Se as compras passarem do orçamento que deste, o estafeta pede a tua autorização antes de pagar. Recebes a foto do talão.$aj$),
  ('ajuda-clientes.md', 13, 'Mercados e produtos ao quilo',
   $aj$## Mercados e produtos ao quilo
Nos mercados, os produtos ao quilo (fruta, carne, peixe) têm um preço estimado. O estafeta pesa e escreve o valor certo da etiqueta; pagas o valor real. Se ficar mais barato, a diferença volta para a tua carteira.$aj$),
  ('ajuda-clientes.md', 14, 'Reservas em restaurantes',
   $aj$## Reservas em restaurantes
Para reservar mesa pagas 3 € adiantados. Quando chegas, esse valor é descontado na conta do restaurante. Podes cancelar sem custo até 2 horas antes da hora marcada. Se cancelares com menos de 2 horas ou não apareceres, os 3 € não são devolvidos.$aj$),
  ('ajuda-clientes.md', 15, 'Limpezas',
   $aj$## Limpezas
Podes marcar uma limpeza em casa pela app, com preço fixo conforme o tamanho da casa. Os materiais custam 3 € a mais e as limpezas repetidas têm 10 % de desconto. Se cancelares nos primeiros 5 minutos depois de marcar, não pagas nada.$aj$),
  ('ajuda-clientes.md', 16, 'Mudar o nome do perfil',
   $aj$## Mudar o nome do perfil
O nome do teu perfil não se muda na app. Para mudar o nome, fala com o Suporte e a equipa trata disso. A foto podes mudar tu em Perfil > Editar perfil. O email é o teu acesso à conta e não se altera.$aj$),
  ('ajuda-clientes.md', 17, 'Mudar o telemóvel',
   $aj$## Mudar o telemóvel
Em Perfil > Editar perfil podes mudar o teu número de telemóvel.$aj$),
  ('ajuda-clientes.md', 18, 'Fatura com NIF',
   $aj$## Fatura com NIF
Antes de pagar podes pedir fatura com o teu NIF. Sem NIF, a fatura sai como consumidor final.$aj$),
  ('ajuda-clientes.md', 19, 'Falar com a equipa',
   $aj$## Falar com a equipa
Em Perfil > Suporte falas com o nosso assistente a qualquer hora. Se for preciso, ele passa a conversa a uma pessoa da equipa.$aj$),
  ('ajuda-estafetas-parceiros.md', 0, 'Estafeta: ficar online',
   $aj$## Estafeta: ficar online
Para receber pedidos, abre a app de estafeta e liga o botão Online. Tens de ter os documentos aprovados e a localização ligada. Quando acabares, desliga o Online.$aj$),
  ('ajuda-estafetas-parceiros.md', 1, 'Estafeta: aceitar um pedido',
   $aj$## Estafeta: aceitar um pedido
Quando chega um pedido, vês a loja, a distância e quanto ganhas antes de aceitar. Tens alguns segundos para aceitar; se não aceitares, passa a outro estafeta.$aj$),
  ('ajuda-estafetas-parceiros.md', 2, 'Estafeta: entregar com código',
   $aj$## Estafeta: entregar com código
Em alguns pedidos o cliente tem um código de 4 dígitos. Pede-o na entrega e escreve-o na app para fechar o pedido.$aj$),
  ('ajuda-estafetas-parceiros.md', 3, 'Estafeta: compras em mercados e Favores',
   $aj$## Estafeta: compras em mercados e Favores
Nos mercados e nos Favores compras os produtos, tiras foto ao talão e gravas na app. Nos produtos ao quilo escreves o valor da etiqueta da balança. Se a compra passar do orçamento do cliente, a app pede autorização ao cliente antes de pagares.$aj$),
  ('ajuda-estafetas-parceiros.md', 4, 'Estafeta: ganhos e pagamentos',
   $aj$## Estafeta: ganhos e pagamentos
Os teus ganhos aparecem na app em cada pedido e no resumo da semana. O acerto de contas é semanal. Se recebeste dinheiro de clientes, o acerto desconta o que é da Bora.$aj$),
  ('ajuda-estafetas-parceiros.md', 5, 'Estafeta: documentos e conta',
   $aj$## Estafeta: documentos e conta
Os documentos (identificação, carta, seguro do veículo, IBAN) enviam-se na app e são revistos pela equipa. Para mudar dados da conta, fala com o Suporte.$aj$),
  ('ajuda-estafetas-parceiros.md', 6, 'Parceiro: receber e preparar pedidos',
   $aj$## Parceiro: receber e preparar pedidos
Os pedidos novos tocam na app do parceiro. Aceita, prepara e marca Pronto: o estafeta é chamado nessa altura. Se não puderes aceitar, recusa logo para o cliente não ficar à espera.$aj$),
  ('ajuda-estafetas-parceiros.md', 7, 'Parceiro: falta de um produto',
   $aj$## Parceiro: falta de um produto
Se faltar um produto, marca-o como em falta no pedido. O cliente é avisado e o valor é acertado.$aj$),
  ('ajuda-estafetas-parceiros.md', 8, 'Parceiro: menu, preços e horário',
   $aj$## Parceiro: menu, preços e horário
O menu, as fotos, os preços e o horário mudam-se no painel do parceiro. Mudanças grandes podem ser revistas pela equipa antes de aparecerem na app.$aj$),
  ('ajuda-estafetas-parceiros.md', 9, 'Parceiro: pagamentos',
   $aj$## Parceiro: pagamentos
O acerto com os parceiros é semanal e o extrato fica no painel do parceiro. As condições do teu contrato estão no painel; para dúvidas, fala com a equipa pelo Suporte.$aj$),
  ('ajuda-estafetas-parceiros.md', 10, 'Parceiro: reservas',
   $aj$## Parceiro: reservas
Nas reservas o cliente paga 3 € adiantados. Quando o cliente chega, marca a chegada na app e os 3 € são descontados na conta dele.$aj$);

-- 3. Versões antigas da ajuda destes dois ficheiros que já não existem no texto saem.
delete from public.support_knowledge_chunks k
 where k.source_type = 'ajuda'
   and k.source_file in ('ajuda-clientes.md', 'ajuda-estafetas-parceiros.md')
   and k.content_hash not in (select md5(n.chunk_text) from _ajuda_nova n);

-- 4. As que ficam saem do caminho das posições (UNIQUE(source_file, chunk_index)) para a
--    ordem nova poder entrar sem chocar; o passo 5 volta a pôr a posição certa.
update public.support_knowledge_chunks k
   set chunk_index = -1 - k.chunk_index
 where k.source_type = 'ajuda'
   and k.source_file in ('ajuda-clientes.md', 'ajuda-estafetas-parceiros.md')
   and k.chunk_index >= 0;

-- 5. Entrar (ou acertar posição e título, se o texto já lá estava).
insert into public.support_knowledge_chunks
  (source_file, source_type, chunk_index, section_title, chunk_text, char_count, content_hash,
   embedding, embedding_gte)
select n.source_file, 'ajuda', n.chunk_index, n.section_title, n.chunk_text,
       char_length(n.chunk_text), md5(n.chunk_text), null, null
  from _ajuda_nova n
on conflict (content_hash) do update
   set chunk_index   = excluded.chunk_index,
       section_title = excluded.section_title,
       source_file   = excluded.source_file
 where public.support_knowledge_chunks.source_type = 'ajuda';

-- 6. Prova antes de gravar: se falhar, nada fica.
do $$
declare
  v_total int;
  v_sensiveis int;
begin
  select count(*),
         count(*) filter (where chunk_text ~* '(markup|ocult|lucro|margem|comiss|danilo|sk_live|service_role|claude_ai_memoria|support_knowledge|_rpc|agent_get)')
    into v_total, v_sensiveis
    from public.support_knowledge_chunks
   where source_type = 'ajuda'
     and source_file in ('ajuda-clientes.md', 'ajuda-estafetas-parceiros.md')
     and chunk_index >= 0;
  if v_total <> 31 then
    raise exception 'A1-indexar-ajuda: esperava 31 trechos de ajuda, ficaram %', v_total;
  end if;
  if v_sensiveis > 0 then
    raise exception 'A1-indexar-ajuda: % trechos com texto interno — não aplicado', v_sensiveis;
  end if;
  raise notice 'A1-indexar-ajuda: 31 trechos de ajuda prontos (vetores por preencher)';
end
$$;

commit;

-- Ver depois de aplicar:
-- select source_file, chunk_index, section_title, char_count, embedding is null as sem_vetor,
--        embedding_gte is null as sem_gte
--   from public.support_knowledge_chunks where source_type = 'ajuda' order by 1, 2;
