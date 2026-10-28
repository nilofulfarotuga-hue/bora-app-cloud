create or replace function public.admin_partners_closed_now() returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_rows jsonb;
begin
  perform public._admin_op_guard();
  with base as (
    select r.id, r.name, r.category,
           (select to_jsonb(pso) from public.partner_status_override pso
              where pso.restaurant_id = r.id and pso.starts_at <= now()
                and (pso.ends_at is null or pso.ends_at > now())
              order by pso.starts_at desc limit 1) as ov
    from public.restaurants r where coalesce(r.is_partner,false) = true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'restaurant_id', id, 'name', name, 'category', category,
    'reason', case
      when ov is not null and (ov->>'is_open')::boolean is false then 'admin_override'
      when ov is not null and (ov->>'is_open')::boolean is true then null
      else 'business_hours' end,
    'override_ends_at', case when ov is not null then ov->>'ends_at' end,
    'override_note', case when ov is not null then ov->>'note' end
  ) order by name), '[]'::jsonb) into v_rows
  from base
  where (ov is not null and (ov->>'is_open')::boolean is false)
     or (ov is null and not coalesce((select (public.is_partner_open(id) ->> 'is_open')::boolean), false));
  return jsonb_build_object('count', jsonb_array_length(v_rows), 'partners', v_rows, 'generated_at', now());
end $$;
notify pgrst, 'reload schema';
