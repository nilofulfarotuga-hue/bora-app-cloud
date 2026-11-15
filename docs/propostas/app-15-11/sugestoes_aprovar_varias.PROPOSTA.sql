-- PROPOSTA (missão app-15-11, 15/11/2026; varredura 9166 n.º 14). Nome sugerido:
-- 20261115125100_admin_bulk_approve_skill_suggestions_v2. Aplica a Claude.ai.
--
-- O botão "Aprovar N" do painel (lib/screens/admin/admin_skill_suggestions_screen.dart:240) chama
-- public.admin_bulk_approve_skill_suggestions, que NÃO existe no servidor: a migração
-- 20260518210000 nunca foi aplicada. E essa versão antiga tinha um defeito de segurança:
--   IF (auth.jwt() -> 'app_metadata' ->> 'role') != 'admin' THEN RAISE ...
-- com o papel vazio a comparação dá NULL, o IF não dispara e QUALQUER utilizador com sessão passava.
-- Esta versão usa public.is_admin() (a verificação da casa) e fecha o acesso a visitantes.
-- Mesma resposta que o ecrã espera: {approved, skipped_critical, errors}. Só aprova sugestões
-- 'safe' e 'pending', uma a uma, pela função que já existe (admin_approve_skill_suggestion).

create or replace function public.admin_bulk_approve_skill_suggestions(p_ids uuid[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_id uuid;
  v_approved int := 0;
  v_skipped int := 0;
  v_errors int := 0;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if exists (select 1 from public.skill_suggestions
                where id = v_id and zone_type = 'safe' and status = 'pending') then
      begin
        perform public.admin_approve_skill_suggestion(v_id);
        v_approved := v_approved + 1;
      exception when others then
        v_errors := v_errors + 1;
      end;
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;
  return jsonb_build_object('approved', v_approved, 'skipped_critical', v_skipped, 'errors', v_errors);
end $function$;

revoke all on function public.admin_bulk_approve_skill_suggestions(uuid[]) from public, anon;
grant execute on function public.admin_bulk_approve_skill_suggestions(uuid[]) to authenticated;

-- PROVA (depois):
--   select public.admin_bulk_approve_skill_suggestions(array[]::uuid[]);  -- como postgres (sem sessão) → 42501
--   no painel, com a conta de admin: "Aprovar N" devolve {approved, skipped_critical, errors}.
