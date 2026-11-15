-- PROPOSTA P3 (missão painel-admin-15-11, 15/11/2026, Claude Code). Aplica a Claude.ai com execute_sql.
-- Segurança: decide QUEM passa nas funções de admin. Pede a ordem da Claude.ai; não mexe em dinheiro.
--
-- O problema (relatórios S1 e S2, conferido por pg_get_functiondef a 15/11):
--   O painel tem dois porteiros diferentes.
--   * is_admin() (usado em 266 regras de acesso) aceita app_metadata.role = 'admin' OU os dois emails
--     do dono.
--   * _admin_op_guard() (usado pelo mapa ao vivo, Pedidos parados, Cancelamentos, carteiras, códigos
--     promocionais, tokens, repasses e os interruptores de Stripe e Farmácias) só aceita
--     app_metadata.role = 'admin' no token.
--   A segunda conta de email do dono não tem esse papel: se ele entrar com ela, metade dos botões dá
--   "admin_required" (o painel abre, porque o resto usa is_admin()).
-- O que muda: _admin_op_guard passa a aceitar também is_admin(). Não abre nada a mais do que já está
-- aberto pelas 266 regras: são as mesmas pessoas.
-- Alternativa sem mudar código: dar app_metadata.role = 'admin' à segunda conta (Papéis da pessoa).

create or replace function public._admin_op_guard()
 returns table(admin_id uuid, admin_email text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_uid uuid; v_email text; v_app_role text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'admin_required: not authenticated' using errcode = '42501';
  end if;
  v_email := coalesce(
    auth.jwt() ->> 'email',
    auth.jwt() -> 'user_metadata' ->> 'email'
  );
  v_app_role := auth.jwt() -> 'app_metadata' ->> 'role';
  -- 15/11/2026: o mesmo porteiro das regras de acesso (is_admin) também passa aqui.
  if v_app_role is distinct from 'admin' and not public.is_admin() then
    raise exception 'admin_required: app_metadata.role=% (need admin)',
      coalesce(v_app_role, 'NULL') using errcode = '42501';
  end if;
  return query select v_uid, v_email;
end;
$function$;

-- PROVA: select position('is_admin()' in prosrc) > 0 from pg_proc where proname = '_admin_op_guard';  -- true
-- E no painel, com a segunda conta do dono: o mapa ao vivo abre sem "admin_required".
--
-- NOTA (falso alarme do relatório S6, conferido): "log_admin_action não confirma que quem chama é admin"
-- NÃO é verdade. As duas versões começam por _audit_chamada_direta_nao_admin(): uma chamada direta de
-- quem não é admin é ignorada sem gravar. Nada a mudar aí.
