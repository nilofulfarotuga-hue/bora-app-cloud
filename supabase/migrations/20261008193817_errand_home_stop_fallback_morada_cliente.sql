-- Aplicada em produção a 08/10/2026 pela Claude.ai (MCP), versão 20261008193817.
-- Copiada para o repo a 08/10 à noite (regra: migração no ar = migração no repo).
-- Pedido real 74dd4ecc: a app da cliente gravou errand_home_stop = true com a morada da paragem
-- vazia, e o estafeta não viu o passo "casa da cliente".
-- Favores: quando a cliente pede "passar em casa primeiro" e a app não manda a morada da paragem,
-- usa a morada de entrega da cliente, para o estafeta ir primeiro à casa certa.
create or replace function public.fn_orders_errand_home_stop_fallback()
returns trigger language plpgsql as $$
begin
  if coalesce(new.service_type,'') = 'errand' and coalesce(new.errand_home_stop,false)
     and new.errand_home_stop_lat is null and new.dropoff_lat is not null then
    new.errand_home_stop_address := coalesce(nullif(trim(new.errand_home_stop_address),''), new.dropoff_address);
    new.errand_home_stop_lat := new.dropoff_lat::double precision;
    new.errand_home_stop_lng := new.dropoff_lng::double precision;
  end if;
  return new;
end $$;

create or replace trigger trg_orders_errand_home_stop_fallback
before insert or update of errand_home_stop, errand_home_stop_lat, dropoff_lat on public.orders
for each row execute function public.fn_orders_errand_home_stop_fallback();
