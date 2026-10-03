-- Redator: quem tem email verificado e peca pronta mas ainda nao tem email escrito. Maquete antes do contacto: sem link nao entra.
create or replace function public.redator_fila(p_chave text)
returns jsonb
language plpgsql security definer set search_path = public, vault as $$
begin
  perform public._caca_chave_ok(p_chave);
  return coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('id', p.id, 'nome', p.nome, 'categoria', p.categoria, 'concelho', p.concelho, 'gancho', p.gancho,
                              'cliente_tipo', p.cliente_tipo, 'link', a.link_unico) x
      from public.prospects_presenca p
      join lateral (select link_unico from public.prospect_amostras a where a.prospect_id = p.id order by criado_em desc limit 1) a on true
     where p.email_verificado and coalesce(p.email,'') <> '' and p.estado in ('novo','amostra_pronta','proposta_rascunho')
       and not exists (select 1 from public.prospect_propostas r where r.prospect_id = p.id and r.canal = 'email'
                        and r.estado in ('pronta','enviada','respondeu','recusou','sem_resposta','pausada'))
     order by p.pontuacao desc nulls last, p.id limit 20) q), '[]'::jsonb);
end $$;
revoke all on function public.redator_fila(text) from public;
grant execute on function public.redator_fila(text) to anon, authenticated, service_role;

create or replace function public.carteiro_registo(p_chave text, p_passo text, p_estado text, p_detalhe text)
returns void
language plpgsql security definer set search_path = public, vault as $$
begin
  perform public._caca_chave_ok(p_chave);
  insert into public.e2e_log (fluxo, passo, estado, detalhe, device, run_id)
  values ('caca-clientes', left(p_passo, 80), left(p_estado, 20), left(p_detalhe, 2000), 'vps', 'caca-clientes-' || to_char(now() at time zone 'Europe/Lisbon', 'YYYY-MM-DD'));
end $$;
revoke all on function public.carteiro_registo(text, text, text, text) from public;
grant execute on function public.carteiro_registo(text, text, text, text) to anon, authenticated, service_role;
