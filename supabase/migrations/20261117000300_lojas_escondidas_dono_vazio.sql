-- Missão noite-farmacia-17-11 (achado do Bloco 4, A3 Guarda): uma loja escondida
-- (so_lista_permissao = true) SEM dono (user_id e user_ nulos) aparecia a qualquer cliente
-- com sessão. Em SQL, "r.user_id = auth.uid()" com user_id nulo dá NULL; o "or" ficava NULL,
-- o "not (...)" também, e o where deixava a loja FORA da lista das escondidas.
-- Provado a 16/11 com a loja a3-guarda (sem dono ainda): um cliente fora da lista via a loja.
-- Hoje só a a3-guarda está assim (pendente, por isso escondida); as farmácias têm dono.
-- Única mudança: cada comparação com coalesce(..., false).

create or replace function public.lojas_escondidas_para_mim()
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $function$
  select coalesce(array_agg(r.id), '{}'::text[])
    from public.restaurants r
   where r.so_lista_permissao
     and not (
       auth.uid() is not null and (
         coalesce(public.is_admin(), false)
         or coalesce(r.user_id = auth.uid(), false)
         or coalesce(r.user_ = auth.uid(), false)
         or exists (select 1 from public.loja_lista_permissao l
                     where l.restaurant_id = r.id and l.user_id = auth.uid())
       )
     );
$function$;
