-- Missão livro-comum-2026-10-23 (Bloco 5g): três linhas do caça-clientes no relatório da manhã do Hermes.
-- Só leitura. Protegida pela chave do caça-clientes (vault prospects_presenca_key), como as outras RPC do carteiro.
create or replace function public.caca_resumo_manha(p_chave text)
returns jsonb
language plpgsql
security definer
set search_path = public, vault
as $$
declare v_ontem date := ((now() at time zone 'Europe/Lisbon') - interval '1 day')::date;
begin
  perform public._caca_chave_ok(p_chave);
  return jsonb_build_object(
    'contactados_ontem', (select count(*) from public.prospect_propostas
                           where enviado_em is not null and (enviado_em at time zone 'Europe/Lisbon')::date = v_ontem
                             and destinatario not ilike 'boraappbora@%'),
    'contactados_7_dias', (select count(*) from public.prospect_propostas
                            where enviado_em >= now() - interval '7 days' and destinatario not ilike 'boraappbora@%'),
    'responderam_ontem', coalesce((select jsonb_agg(jsonb_build_object('nome', p.nome, 'estado', r.estado))
                            from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
                           where r.estado in ('respondeu', 'recusou')
                             and (r.atualizado_em at time zone 'Europe/Lisbon')::date = v_ontem), '[]'::jsonb),
    'cacados_ontem', (select count(*) from public.prospects_presenca
                       where (criado_em at time zone 'Europe/Lisbon')::date = v_ontem and email_verificado),
    'prontas', (select count(*) from public.prospect_propostas where estado = 'pronta'));
end $$;

revoke all on function public.caca_resumo_manha(text) from public;
grant execute on function public.caca_resumo_manha(text) to anon, authenticated, service_role;
comment on function public.caca_resumo_manha(text) is
  'Resumo do caça-clientes para o relatório da manhã do Hermes (só leitura, exige a chave do caça-clientes). Missão livro-comum-2026-10-23.';
