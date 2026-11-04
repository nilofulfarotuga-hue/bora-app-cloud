-- embeddings-supabase-2026-11-03 — parte 2.
-- (a) Orçamento de processador do gte por pedido (medido: ~115 ms de CPU por texto; a Edge Function
--     morre com "CPU Time exceeded" acima de ~2 s). (b) Tabelas SÓ da prova de qualidade e das fatias
--     do preenchimento (RLS ligada, sem políticas: só o servidor). Nada disto mexe em catálogo ou dinheiro.

insert into public.platform_settings (key, value, description, category) values
  ('embeddings_gte_max_por_pedido', '6'::jsonb, 'Quantos vetores gte (motor grátis, gasta processador da função) se calculam no máximo por pedido ao assistente/suporte; acima disso passa à reserva. Máx. 12.', 'assistente')
on conflict (key) do nothing;

-- fatias do preenchimento (id do produto entre "depois" e "antes", exclusivos)
create table if not exists public.tmp_emb_fatias_20261103 (
  n       integer primary key,
  depois  text not null,
  antes   text,
  pedido  bigint,
  criado_em timestamptz not null default now()
);
alter table public.tmp_emb_fatias_20261103 enable row level security;

-- prova de qualidade
create table if not exists public.eval_emb_perguntas_20261103 (
  id        text primary key,
  conjunto  text not null check (conjunto in ('prova', 'calibracao', 'ajuda')),
  pergunta  text not null,
  criterio  text not null,   -- expressão (sem acentos, minúsculas) que um resultado CERTO tem de cumprir
  nota      text
);
create table if not exists public.eval_emb_vetores_20261103 (
  pergunta_id text not null references public.eval_emb_perguntas_20261103(id),
  motor       text not null check (motor in ('gte', 'gemini')),
  embedding   extensions.vector not null,
  ms          integer,
  primary key (pergunta_id, motor)
);
create table if not exists public.eval_emb_pool_20261103 (
  product_id text primary key,
  origem     text not null
);
create table if not exists public.eval_emb_pool_gemini_20261103 (
  product_id text primary key,
  embedding  extensions.vector(768) not null
);
create table if not exists public.eval_emb_resultados_20261103 (
  pergunta_id text not null,
  corrida     text not null,
  rank        integer not null,
  item_id     text,
  sim         numeric,
  nota        text,
  criado_em   timestamptz not null default now(),
  primary key (pergunta_id, corrida, rank)
);
alter table public.eval_emb_perguntas_20261103 enable row level security;
alter table public.eval_emb_vetores_20261103 enable row level security;
alter table public.eval_emb_pool_20261103 enable row level security;
alter table public.eval_emb_pool_gemini_20261103 enable row level security;
alter table public.eval_emb_resultados_20261103 enable row level security;

create or replace function public.eval_emb_pool_sem_gemini_20261103(p_limit integer default 100)
returns table(id text, texto text)
language sql stable security definer
set search_path to 'public'
as $function$
  select p.id,
         left(coalesce(p.name,'') || case when coalesce(p.category,'') <> '' then ' · ' || p.category else '' end
              || case when coalesce(p.unit,'') <> '' then ' · ' || p.unit else '' end, 300)
    from public.eval_emb_pool_20261103 x
    join public.products p on p.id = x.product_id
   where not exists (select 1 from public.eval_emb_pool_gemini_20261103 g where g.product_id = x.product_id)
   order by p.id
   limit greatest(1, least(p_limit, 500));
$function$;

-- motor contra motor: só os produtos do conjunto que têm vetor NOS DOIS motores
create or replace function public.eval_emb_vizinhos_20261103(p_vetor extensions.vector, p_limite integer default 5)
returns table(product_id text, sim double precision)
language sql stable security definer
set search_path to 'public', 'extensions'
as $function$
  (select x.product_id, 1 - (g.embedding <=> p_vetor)
     from public.eval_emb_pool_20261103 x
     join public.product_embeddings_gte g on g.product_id = x.product_id
    where vector_dims(p_vetor) = 384
      and exists (select 1 from public.eval_emb_pool_gemini_20261103 m where m.product_id = x.product_id)
    order by g.embedding <=> p_vetor
    limit p_limite)
  union all
  (select x.product_id, 1 - (m.embedding <=> p_vetor)
     from public.eval_emb_pool_20261103 x
     join public.eval_emb_pool_gemini_20261103 m on m.product_id = x.product_id
    where vector_dims(p_vetor) = 768
      and exists (select 1 from public.product_embeddings_gte g where g.product_id = x.product_id)
    order by m.embedding <=> p_vetor
    limit p_limite);
$function$;

-- As perguntas e o critério de acerto, escritos ANTES de correr (ver ESPEC.md da missão).
insert into public.eval_emb_perguntas_20261103 (id, conjunto, pergunta, criterio, nota) values
  ('p01','prova','arroz carolino','arroz.*carolin|carolin.*arroz',null),
  ('p02','prova','leite meio gordo','leite.*meio.?gordo',null),
  ('p03','prova','antigripal','gripe|gripal|grippine|constipa|griponal|antigrip',null),
  ('p04','prova','remédio pra dor de cabeça','paracetamol|ibuprofen|ben.?u.?ron|aspirina|brufen|cefaleia|dor de cabeca|analgesic','PT-BR'),
  ('p05','prova','hambúrguer','hamb[uú]rg|burger',null),
  ('p06','prova','fraldas para bebé','fralda',null),
  ('p07','prova','ração de cão','^(?=.*(racao|alimento|comida|croquete|pienso|snack|petisco))(?=.*(\mcao\M|\mcaes\M|canin|\mdog|perro|cachorr|puppy))',null),
  ('p08','prova','o de sempre','^$','precisa do histórico do cliente; nenhuma pesquisa por produto acerta'),
  ('p09','prova','arros carolino','arroz.*carolin|carolin.*arroz','erro de escrita'),
  ('p10','prova','lete meio gordo','leite.*meio.?gordo','erro de escrita'),
  ('p11','prova','iogurte grego','iogurte.*grego|grego.*iogurte',null),
  ('p12','prova','papel higienico','papel higi','sem acento'),
  ('p13','prova','azeite virgem extra','azeite',null),
  ('p14','prova','uma duzia de ovos','\movos?\M',null),
  ('p15','prova','pão de forma','pao.*forma|forma.*pao',null),
  ('p16','prova','detergente para a loiça','detergente.*(loica|louca)|(loica|louca).*detergente|maquina.*loica',null),
  ('p17','prova','coca cola','coca.?cola',null),
  ('p18','prova','cervejas','cerveja|\mbeer\M',null),
  ('p19','prova','champô anticaspa','^(?=.*(champo|shampoo|champu))(?=.*(caspa|dandruff))|anti.?caspa',null),
  ('p20','prova','pasta de dentes','pasta (de )?dent|dentifric|colgate',null),
  ('p21','prova','peito de frango','frango|pollo|chicken',null),
  ('p22','prova','bife de vaca','^(?=.*(bife|bitoque|vazia|lombo|alcatra|picanha))(?=.*(vaca|novilho|bovin|vitela))',null),
  ('p23','prova','bacalhau','bacalhau',null),
  ('p24','prova','batatas','batata',null),
  ('p25','prova','tomate','tomate',null),
  ('p26','prova','bananas','banana',null),
  ('p27','prova','maçãs','\mmacas?\M',null),
  ('p28','prova','café em cápsulas','capsul|nespresso|dolce gusto|delta q',null),
  ('p29','prova','açucar','acucar','acento a menos'),
  ('p30','prova','farinha para bolos','farinha',null),
  ('p31','prova','esparguete','esparguete|spaghetti|espaguete',null),
  ('p32','prova','atum em lata','\matum\M',null),
  ('p33','prova','sumo de laranja','^(?=.*(sumo|suco|nectar))(?=.*laranja)',null),
  ('p34','prova','água com gás','agua.*(gas|gaseificada)|pedras salgadas|gaseificada|\mcastello\M',null),
  ('p35','prova','pizza margarita','pizza.*(margherita|margarita|margarida)|margherita','escrita aproximada'),
  ('p36','prova','sushi','sushi|sashimi|uramaki|hosomaki|nigiri|\mmaki|temaki|gunkan',null),
  ('p37','prova','ração pra gato','^(?=.*(racao|alimento|comida|croquete|pienso|snack|petisco|saqueta|humido|seco))(?=.*(gato|felin|\mcat\M|kitten|gatinho))','PT-BR'),
  ('p38','prova','absorvente','\mpensos?\M|absorvente|tampao|tampoes','PT-BR (pensos higiénicos)'),
  ('p39','prova','sabão em pó','^(?=.*(detergente|sabao))(?=.*(roupa|\mpo\M|lavar))','PT-BR (detergente da roupa)'),
  ('p40','prova','refrigerante','refrigerante|coca.?cola|pepsi|fanta|sprite|7.?up|sumol|ice tea|guarana','PT-BR'),
  ('c01','calibracao','cebola','cebola',null),
  ('c02','calibracao','alho','\malho\M',null),
  ('c03','calibracao','limões','limao|limoes',null),
  ('c04','calibracao','vinho tinto','vinho tinto|tinto.*douro|\mtinto\M',null),
  ('c05','calibracao','biscoito recheado','bolacha|biscoit|cookie|oreo','PT-BR'),
  ('c06','calibracao','manteiga sem sal','manteiga',null),
  ('c07','calibracao','queijo fatiado','^(?=.*queijo)(?=.*(fatia|flamengo))',null),
  ('c08','calibracao','presunto','presunto|fiambre',null),
  ('c09','calibracao','carregador de telemóvel','carregador|charger',null),
  ('c10','calibracao','lâmpada led','^(?=.*lampada)(?=.*led)',null),
  ('c11','calibracao','protetor solar','prote(c)?tor solar|\mspf\s?[0-9]|solar.*fps|\mfps\s?[0-9]',null),
  ('c12','calibracao','açaí','acai',null),
  ('a01','ajuda','como pago com mb way?','mb ?way',null),
  ('a02','ajuda','posso pagar em dinheiro?','dinheiro',null),
  ('a03','ajuda','como cancelo um pedido?','cancel',null),
  ('a04','ajuda','quanto custa a entrega?','taxa de entrega|entrega.{0,60}(€|eur|custo|preco|taxa)',null),
  ('a05','ajuda','o que são os tokens?','token',null),
  ('a06','ajuda','como faço uma reserva num restaurante?','reserva',null),
  ('a07','ajuda','o estafeta não aparece','estafeta.{0,80}(atras|demora|nao aparece|aparece|chega)|atraso|demora',null),
  ('a08','ajuda','como mudo a morada de entrega?','morada',null),
  ('a09','ajuda','esqueci-me da palavra-passe','palavra.?passe|password|senha|recuperar',null),
  ('a10','ajuda','o que é um favor?','favor',null),
  ('a11','ajuda','como apago a minha conta?','(apagar|eliminar|encerrar|excluir).{0,20}conta|conta.{0,20}(apagar|eliminar|encerrar)',null),
  ('a12','ajuda','o pedido veio errado, quero o dinheiro de volta','reembols|devolu|estorno',null)
on conflict (id) do nothing;
