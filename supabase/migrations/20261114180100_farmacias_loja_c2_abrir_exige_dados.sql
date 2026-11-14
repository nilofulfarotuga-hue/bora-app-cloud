-- =============================================================================
-- farmacias-loja-2026-11-14 · c2 · Uma farmácia parceira só sai da lista de permissão com tudo em dia
--
-- PORQUÊ (achado a 14/11 ao preparar o Bloco 5): as duas farmácias já têm coming_soon = false desde
-- 11/11. O portão de conformidade que existe (trg_conformidade_abrir_loja_parceira) só olha para a
-- passagem de coming_soon true -> false. Por isso admin_farmacia_abrir (e admin_farmacia_definir com
-- p_so_lista = false) abriam a farmácia ao público SEM nome legal, NIF, IBAN nem termos aceites, e
-- com a conta de login ainda no e-mail de demonstração. Nada no servidor travava.
--
-- O QUE FAZ: gatilho BEFORE UPDATE OF so_lista_permissao em restaurants. Quando uma farmácia
-- PARCEIRA (category = 'pharmacy' e is_partner) passa de escondida (so_lista_permissao = true) para
-- visível a todos (false), exige:
--   1) a conta de login do dono e o e-mail da loja já não são de demonstração (demo.*);
--   2) _conformidade_em_falta vazio (nome legal, NIF, morada, IBAN, data de nascimento só para pessoa
--      singular, autocertificação = termos aceites) — os mesmos códigos e a mesma frase do portão
--      antigo ("conformidade_incompleta: faltam nif, iban"), que o painel já sabe ler.
-- Respeita as mesmas duas válvulas do portão antigo: platform_settings
-- conformidade_ativacao_obrigatoria = false, ou set_config('bora.forcar_ativacao','1', true) na
-- transação (só para correções do Danilo).
--
-- Não toca no corpo de admin_farmacia_abrir nem em comissões: só impede a passagem quando falta algo.
-- =============================================================================

create or replace function public.fn_farmacia_abrir_exige_dados()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_obrig  boolean := coalesce((public.get_setting('conformidade_ativacao_obrigatoria') #>> '{}')::boolean, true);
  v_login  text;
  v_falta  text[];
begin
  if new.category is distinct from 'pharmacy'
     or not coalesce(new.is_partner, false)
     or not coalesce(old.so_lista_permissao, false)
     or coalesce(new.so_lista_permissao, false) then
    return new;
  end if;
  if not v_obrig or coalesce(current_setting('bora.forcar_ativacao', true), '') = '1' then
    return new;
  end if;

  select email into v_login from auth.users where id = coalesce(new.user_id, new.user_);
  if coalesce(v_login, '') ~* '^demo[._+-]' or coalesce(new.email, '') ~* '^demo[._+-]' then
    raise exception 'email_demonstracao: a conta da farmácia ainda usa o e-mail de demonstração (%). Troque pelo e-mail verdadeiro antes de abrir.',
      coalesce(v_login, new.email)
      using errcode = 'P0001';
  end if;

  v_falta := public._conformidade_em_falta(to_jsonb(new));
  if array_length(v_falta, 1) > 0 then
    raise exception 'conformidade_incompleta: faltam %', array_to_string(v_falta, ', ')
      using errcode = 'P0001',
            hint = 'Antes de abrir a farmácia ao público: nome legal, NIF, morada, IBAN e termos aceites pela farmácia.';
  end if;
  return new;
end $function$;

revoke all on function public.fn_farmacia_abrir_exige_dados() from public, anon, authenticated;

drop trigger if exists trg_farmacia_abrir_exige_dados on public.restaurants;
create trigger trg_farmacia_abrir_exige_dados
  before update of so_lista_permissao on public.restaurants
  for each row execute function public.fn_farmacia_abrir_exige_dados();
