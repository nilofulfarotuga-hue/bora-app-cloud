-- catalogo-2026-11-01: a secção que o cliente vê na loja é products.category_root (1.º segmento
-- de category; ver lib/screens/store_products_screen.dart _categoryOf). No Continente o cron
-- (update-products, ids cnt-) traz caminhos como "Supermercado/Mercearia/..." ou
-- "Marcas/Marcas Continente/...", por isso a app mostrava secções "Supermercado" (1085 produtos),
-- "Oportunidades", "Marcas", "Negócios", "Cão", "Gato" e secções em duplicado (Animais / Animais
-- de Estimação, Bebé / Bebé e Criança, Congelados / Gelados e Congelados, Papelaria / Livraria e
-- Papelaria...). Como o cron reescreve category todas as semanas, o mapa vive no gatilho que
-- deriva category_root, para ser permanente. Só mexe em continente-guarda; as outras lojas
-- continuam com raiz = 1.º segmento.
-- Aplicada em prod via MCP (continente_category_root_mapa_20261101, _b e auchan_category_root_mapa_20261101).
-- Backfill feito na missão: UPDATE products SET category = category WHERE restaurant_id =
-- 'continente-guarda'. Atenção: nos cont- (importação estática) a raiz tinha sido corrigida à
-- mão sem alinhar category; esse backfill sobrepôs essas raízes e foram repostas do backup
-- bkp_products_20261101 alinhando category = category_root (803 linhas).
create or replace function public.fn_products_set_category_root()
returns trigger
language plpgsql
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  s1 text; s2 text; s3 text; sub text; r text;
begin
  s1 := nullif(trim(split_part(coalesce(new.category, ''), '/', 1)), '');
  s2 := nullif(trim(split_part(coalesce(new.category, ''), '/', 2)), '');
  s3 := nullif(trim(split_part(coalesce(new.category, ''), '/', 3)), '');
  r := s1;
  if new.restaurant_id = 'continente-guarda' and s1 is not null then
    r := case s1
      when 'Supermercado' then case s2
        when 'Higiene e Cuidado Pessoal' then 'Beleza e Higiene'
        when 'Consumíveis' then 'Casa e Jardim'
        when 'Suplementos e Nutrição' then 'Saúde e Bem-Estar'
        when 'Refeições Práticas' then 'Refeições Frescas'
        when 'Talho' then 'Talho e Peixaria'
        when 'Peixaria' then 'Talho e Peixaria'
        when 'Frutas e Legumes' then 'Frutas e Vegetais'
        when 'Congelados' then 'Gelados e Congelados'
        else coalesce(s2, 'Mercearia') end
      when 'Marcas' then case s2
        when 'Marcas Continente' then 'Refeições Frescas'
        when 'Dolce Gusto' then 'Mercearia'
        when 'Berg' then 'Desporto e Viagem'
        else 'Casa e Jardim' end
      when 'Oportunidades' then case s2
        when 'Vinhos, Enchidos e Queijos' then 'Vinhos e Espumantes'
        when 'Verão' then 'Bebidas Espirituosas'
        when 'Páscoa' then 'Vinhos e Espumantes'
        when 'Fim de Ano' then 'Vinhos e Espumantes'
        when 'Frescura de Portugal' then 'Bebidas Espirituosas'
        when 'Cozinhas do Mundo' then 'Mercearia'
        when 'Cabazes de Natal' then 'Mercearia'
        when 'Feira da Poupança' then 'Mercearia'
        else 'Casa e Jardim' end
      when 'Negócios' then case s2 when 'Presentes Corporativos' then 'Mercearia' else 'Casa e Jardim' end
      when 'Cão' then 'Animais de Estimação'
      when 'Gato' then 'Animais de Estimação'
      when 'Animais' then 'Animais de Estimação'
      when 'Bebé' then 'Bebé e Criança'
      when 'Congelados' then 'Gelados e Congelados'
      when 'Papelaria' then 'Livraria e Papelaria'
      when 'Casa, Bricolage e Jardim' then 'Casa e Jardim'
      when 'Beleza' then 'Beleza e Higiene'
      when 'Garrafeira' then 'Vinhos e Espumantes'
      else s1 end;
    sub := case when s1 = 'Supermercado' then s3 else s2 end;
    if r = 'Bebidas e Garrafeira' then
      r := case
        when sub in ('Bebidas Espirituosas','Gin e Vodka','Cachaça e Aguardente') then 'Bebidas Espirituosas'
        when sub = 'Cervejas e Sidras' then 'Cervejas e Sidras'
        when sub in ('Sumos e Refrigerantes','Água','Energéticas e Isotónicas','Bebidas Energéticas e Isotónicas') then 'Águas e Sumos'
        when sub is null then 'Bebidas e Garrafeira'
        else 'Vinhos e Espumantes' end;
    end if;
    if r = 'Mercearia' and s1 in ('Mercearia','Supermercado') then
      r := case
        when sub in ('Bolachas, Biscoitos e Tostas','Chocolate, Gomas e Rebuçados','Açúcar e Sobremesas','Cereais e Barras','Compotas, Cremes e Mel','Bolachas e Biscoitos') then 'Mercearia Doce'
        when sub = 'Alimentação Infantil' then 'Bebé e Criança'
        when sub like 'Suplementos e Vitaminas%' then 'Saúde e Bem-Estar'
        else 'Mercearia' end;
    end if;
  elsif new.restaurant_id = 'auchan-guarda' and s1 is not null then
    -- Auchan (cron): "Alimentação", "Gastronomia" e raízes promocionais → secções reais
    r := case s1
      when 'Alimentação' then case s2 when 'Queijaria' then 'Queijaria' when 'Ovos' then 'Laticínios e Ovos' else 'Mercearia' end
      when 'Gastronomia' then case when s2 in ('Massas Frescas','Massas Culinárias') then 'Mercearia' else 'Refeições Frescas' end
      when 'Promoções Clube Auchan' then 'Fruta'
      when 'Frutas E Legumes Produtos Locais' then 'Legumes'
      else s1 end;
  end if;
  new.category_root := r;
  return new;
end;
$$;
