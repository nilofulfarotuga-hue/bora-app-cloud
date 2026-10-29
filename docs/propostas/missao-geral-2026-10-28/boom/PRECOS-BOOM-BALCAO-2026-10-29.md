# Boom! Burger — pôr os preços de balcão verdadeiros (para o Claude.ai aplicar)

29/10/2026. O dono mandou o preçário de balcão em imagem (lido no WhatsApp da Bora; transcrição completa
fora do repo em `Desktop\Bora\prompts\boom-precario-balcao-2026-10-29.md`). A base tinha o "balcão" de
27/10 cerca de 10 % acima do verdadeiro. Regra em vigor (decisão de 28/10): **preço na app = balcão ÷ 0,9
× 1,05**, arredondado a 0,01 (bate em 56/56 produtos hoje). Pela regra de 28/10, quem troca preços é o
Claude.ai: isto é só a preparação. Não mexe em markup, comissões nem taxas — só no balcão de 27 produtos
que estão na imagem. Bebidas e sobremesas não vieram (ficam como estão). O King Elvis já foi criado hoje
com 13,80 € de balcão (16,10 € na app) pela mesma regra.

Efeito: os 27 produtos descem entre 0,11 € e 1,98 € na app (média −1,05 €); a parte da loja
(`partner_store_share`) passa a dar exatamente o balcão da imagem.

```sql
-- 1. Cópia de antes (nunca apagar)
create table if not exists public.bkp_products_boom_precos_20261029 as
  select now() as guardado_em, * from public.products where restaurant_id = 'boom-burger-guarda';
alter table public.bkp_products_boom_precos_20261029 enable row level security;

-- 2. Balcão verdadeiro (imagem de 29/10) e preço da app pela regra; falha se não bater em 27 produtos
do $$
declare v_n int;
begin
  with novo(nome, balcao) as (values
    ('Bolo do caco com manteiga de alho e ervas', 3.40),
    ('Bolinhas de alheira de Mirandela (4 un)', 3.90),
    ('Asas de frango com molho BBQ (8 un)', 7.80),
    ('Batata gulosa', 5.85),
    ('Cogumelos frescos salteados em flor de sal', 4.90),
    ('Pimentos Padrón salteados com brandy', 4.80),
    ('Tequeños "Palitos de queijo" (4 un)', 4.90),
    ('Bites crocantes de peito de frango', 5.30),
    ('Clássico', 9.90),
    ('Boom! Bombástico', 11.70),
    ('Boom! Cheddar Lovers', 12.80),
    ('Boom! Brie Fan', 12.20),
    ('Boom! Camone', 11.60),
    ('Boom! Chicken Breast', 11.30),
    ('Boom! Crispy Chicken', 12.70),
    ('Boom! Serra da Estrela', 11.80),
    ('Boom! Burguesinha', 13.60),
    ('Boom! Portobello (Limitado)', 13.80),
    ('Boom! Duplo Smash', 14.40),
    ('Boom! Kamikaze', 16.20),
    ('Boom! Veggie Beyond', 12.20),
    ('Nuggets de frango', 8.50),
    ('Dose batata artesanal extra', 2.50),
    ('Dose batata doce extra', 3.50),
    ('Maionese caseira da casa', 1.00),
    ('Maionese caseira de malagueta seca (picante)', 1.20),
    ('Molho cheddar 300 gr', 2.90)
  ),
  alvo as (
    select p.id, n.balcao
    from public.products p
    join novo n on lower(trim(p.name)) = lower(trim(n.nome))
    where p.restaurant_id = 'boom-burger-guarda'
  )
  select count(*) into v_n from alvo;
  if v_n <> 27 then
    raise exception 'Boom: esperava 27 produtos a bater pelo nome, achei %. Conferir os nomes antes de aplicar.', v_n;
  end if;
  update public.products p
     set partner_shelf_price = a.balcao,
         price = round((a.balcao / 0.9 * 1.05)::numeric, 2)
    from (
      select p2.id, n.balcao
      from public.products p2
      join (values
        ('Bolo do caco com manteiga de alho e ervas', 3.40), ('Bolinhas de alheira de Mirandela (4 un)', 3.90),
        ('Asas de frango com molho BBQ (8 un)', 7.80), ('Batata gulosa', 5.85),
        ('Cogumelos frescos salteados em flor de sal', 4.90), ('Pimentos Padrón salteados com brandy', 4.80),
        ('Tequeños "Palitos de queijo" (4 un)', 4.90), ('Bites crocantes de peito de frango', 5.30),
        ('Clássico', 9.90), ('Boom! Bombástico', 11.70), ('Boom! Cheddar Lovers', 12.80), ('Boom! Brie Fan', 12.20),
        ('Boom! Camone', 11.60), ('Boom! Chicken Breast', 11.30), ('Boom! Crispy Chicken', 12.70),
        ('Boom! Serra da Estrela', 11.80), ('Boom! Burguesinha', 13.60), ('Boom! Portobello (Limitado)', 13.80),
        ('Boom! Duplo Smash', 14.40), ('Boom! Kamikaze', 16.20), ('Boom! Veggie Beyond', 12.20),
        ('Nuggets de frango', 8.50), ('Dose batata artesanal extra', 2.50), ('Dose batata doce extra', 3.50),
        ('Maionese caseira da casa', 1.00), ('Maionese caseira de malagueta seca (picante)', 1.20),
        ('Molho cheddar 300 gr', 2.90)
      ) as n(nome, balcao) on lower(trim(p2.name)) = lower(trim(n.nome))
      where p2.restaurant_id = 'boom-burger-guarda'
    ) a
   where p.id = a.id;
end $$;

-- 3. Prova de volta: 27 linhas com price = round(balcao/0.9*1.05, 2) e partner_store_share(price) = balcao
select p.name, p.partner_shelf_price, p.price,
       round((p.partner_shelf_price / 0.9 * 1.05)::numeric, 2) = p.price as regra_ok,
       public.partner_store_share(p.price, 'boom-burger-guarda') as parte_da_loja
  from public.products p
 where p.restaurant_id = 'boom-burger-guarda'
   and p.id in (select id from public.bkp_products_boom_precos_20261029)
   and p.price <> (select b.price from public.bkp_products_boom_precos_20261029 b where b.id = p.id)
 order by p.name;
```

Nomes a conferir antes de aplicar (podem estar escritos de outra forma na base): "Boom! Bombástico"
(na imagem "Boombástico"), "Boom! Veggie Beyond", "Tequeños …". Se o `raise exception` disparar, é por
um nome que não bateu: ajustar o nome na lista, nunca o preço.

## Opções (preço a somar) — só preparar, a confirmar as colunas
Nove opções da imagem também estão ~10 % acima (ex.: Troca pão Brioche balcão 1,90 → regra 2,22; hoje
2,45). As tabelas `product_option_groups`/`product_option_items` (coluna `price_add`) ligam-se aos
produtos da loja; o UPDATE é igual ao de cima com `price_add = round(balcao/0.9*1.05, 2)` por nome da
opção, com backup `bkp_product_option_items_boom_precos_20261029`. Fica para o Claude.ai confirmar as
colunas e aplicar junto.

## Pendente do dono
Bebidas (chegam à tarde), sobremesas do dia (sem preço), hambúrguer de novembro (segunda), opções do
King Elvis, e o email de login do parceiro (segunda, quando ele entrar).
