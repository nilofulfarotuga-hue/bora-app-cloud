-- Liga o carteiro depois de o email de teste passar (ordem do Danilo, 03/10): interruptor + bots vendedor.
-- So quem tem a chave dos prospects; a prova do teste fica escrita no e2e_log.
create or replace function public.carteiro_ligar(p_chave text, p_prova text)
returns jsonb
language plpgsql security definer set search_path = public, vault as $$
begin
  perform public._caca_chave_ok(p_chave);
  if coalesce(length(p_prova), 0) < 10 then raise exception 'sem_prova'; end if;
  update public.platform_settings set value = 'true'::jsonb, updated_at = now() where key = 'caca_clientes_enabled';
  update public.agentes_estado set ligado = true, horario_ligado = true, cadencia_min = 1440,
         nota = coalesce(nota || ' | ', '') || 'carteiro ligado 03/10', updated_at = now()
   where agente in ('vendedor', 'vendedor-servicos');
  insert into public.e2e_log (fluxo, passo, estado, detalhe, device, run_id)
  values ('caca-clientes', 'c5-ligar', 'provado', left('Email de teste passou; interruptor e bots vendedor ligados. Prova: ' || p_prova, 2000), 'pc-danilo', 'caca-clientes-2026-10-03');
  return jsonb_build_object('ligado', true);
end $$;
revoke all on function public.carteiro_ligar(text, text) from public;
grant execute on function public.carteiro_ligar(text, text) to anon, authenticated, service_role;
