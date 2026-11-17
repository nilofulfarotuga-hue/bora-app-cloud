-- Missão noite-farmacia-17-11 (1.4): a Farmácia Teixeira fica visível a todos como "Em breve"
-- (coming_soon = true) sem aceitar pedidos, enquanto a farmácia não manda o IBAN.
-- A trava fn_farmacia_abrir_exige_dados recusava tirar a farmácia da lista de permissão mesmo
-- em "Em breve" (faltam IBAN e autocertificação). Em "Em breve" não há pedidos nem dinheiro:
-- _coming_soon_guard_orders e _guard_payment_draft_coming_soon já bloqueiam no servidor, e a
-- outra trava (fn_conformidade_abrir_loja_parceira) já deixa passar coming_soon. Única mudança:
-- "or coalesce(new.coming_soon, false)" no primeiro if. Abrir de verdade (coming_soon=false)
-- continua a exigir todos os dados: de "Em breve" para aberta quem trava é
-- fn_conformidade_abrir_loja_parceira (coming_soon true → false), que pede IBAN e o resto.

create or replace function public.fn_farmacia_abrir_exige_dados()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare
  v_obrig boolean := coalesce((public.get_setting('conformidade_ativacao_obrigatoria') #>> '{}')::boolean, true);
  v_login text;
  v_falta text[];
begin
  if new.category is distinct from 'pharmacy'
     or not coalesce(new.is_partner, false)
     or not coalesce(old.so_lista_permissao, false)
     or coalesce(new.so_lista_permissao, false)
     or coalesce(new.coming_soon, false) then
    return new;
  end if;
  if not v_obrig or coalesce(current_setting('bora.forcar_ativacao', true), '') = '1' then
    return new;
  end if;
  select email into v_login from auth.users where id = coalesce(new.user_id, new.user_);
  if coalesce(v_login, '') ~* '^demo[._+-]' or coalesce(new.email, '') ~* '^demo[._+-]' then
    raise exception 'email_demonstracao: a conta da farmácia ainda usa o e-mail de demonstração (%). Troque pelo e-mail verdadeiro antes de abrir.', coalesce(v_login, new.email)
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
