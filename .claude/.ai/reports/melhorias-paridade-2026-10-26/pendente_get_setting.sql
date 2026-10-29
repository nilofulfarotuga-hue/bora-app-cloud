-- pendente_get_setting.sql — PREPARADO, NÃO APLICADO (missão melhorias-paridade-2026-10-26,
-- adendo D da Claude.ai de 26/10 10:25). A Claude.ai aplica depois de rever (segurança: não
-- espera por sábado). Fora de supabase/migrations de propósito; quando for aplicado, copiar
-- para supabase/migrations/<data>_get_setting_sem_fuga.sql.
--
-- O PROBLEMA (confirmado pela Claude.ai em transação desfeita): as chaves is_secret saíam
-- quando a chamada chegava SEM claims, porque o recurso usava current_user — e dentro de uma
-- função SECURITY DEFINER o current_user é o dono (postgres), que está na lista. Resultado:
-- anon com claims → escondido; anon/qualquer papel sem claims → mostra. São 48 chaves
-- (comissões, margens, telefone MB Way da Bora, relatórios…).
--
-- A REGRA NOVA:
--   · com claims (pedido pela API): só service_role ou admin (is_admin()) veem segredos;
--   · sem claims: só se session_user for postgres ou supabase_admin (pg_cron, chamadas internas,
--     editor SQL); 'authenticator' e outros papéis nunca.
--   · chaves NÃO secretas: iguais a hoje, para toda a gente (a app lê taxas por aqui).
-- Mesma assinatura, mesmo dono, mesmos grants, mesmo STABLE SECURITY DEFINER.
--
-- PROVA (transação desfeita, 26/10): ver o fim deste ficheiro.
-- REVERTER: o corpo antigo está no bloco "ORIGINAL" no fim.

CREATE OR REPLACE FUNCTION public.get_setting(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row    record;
  v_claims text;
  v_role   text;
  v_admin  boolean := false;
begin
  select value, is_secret into v_row from public.platform_settings where key = p_key;
  if not found then return null; end if;
  if not v_row.is_secret then return v_row.value; end if;

  -- Chave sensível: só passa a quem tem autoridade.
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  if v_claims is not null then
    -- Pedido pela API (PostgREST / Edge): decide o papel do token.
    begin
      v_role := v_claims::jsonb ->> 'role';
    exception when others then
      v_role := null;
    end;
    if v_role = 'service_role' then
      return v_row.value;
    end if;
    begin
      v_admin := public.is_admin();
    exception when others then
      v_admin := false;
    end;
    if v_admin then return v_row.value; end if;
    return null;
  end if;

  -- Sem claims: só o próprio servidor (pg_cron, funções internas, editor SQL).
  -- session_user é quem abriu a ligação (o current_user aqui dentro é sempre o dono).
  if session_user in ('postgres', 'supabase_admin') then
    return v_row.value;
  end if;
  return null;
end $function$;

-- Grants iguais aos de hoje (o CREATE OR REPLACE mantém-nos; repetidos por segurança).
grant execute on function public.get_setting(text) to anon, authenticated, service_role;

/* ORIGINAL (produção a 26/10/2026) — para reverter, correr isto:
CREATE OR REPLACE FUNCTION public.get_setting(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row   record;
  v_role  text;
  v_admin boolean := false;
begin
  select value, is_secret into v_row from public.platform_settings where key = p_key;
  if not found then return null; end if;
  if not v_row.is_secret then return v_row.value; end if;

  -- Chave sensivel: so passa a quem tem autoridade.
  begin
    v_role := coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', current_user);
  exception when others then
    v_role := current_user;
  end;
  if v_role in ('service_role','postgres','supabase_admin','authenticator') then
    return v_row.value;
  end if;
  begin
    v_admin := public.is_admin();
  exception when others then
    v_admin := false;
  end;
  if v_admin then return v_row.value; end if;
  return null;
end $function$;
*/

/* PROVA (26/10/2026, transação desfeita, versão nova instalada com o nome temporário
   get_setting_pendente_teste — nada ficou no banco):
     session_user=postgres
     anon com claims ............... NULL      (chave secreta bora_mbway_phone)
     anon, chave pública ........... 99        (non_partner_service_fee_cents: igual a hoje)
     cliente (authenticated) ....... NULL
     admin ......................... valor
     service_role .................. valor
     interno sem claims (postgres) . valor     (pg_cron, funções internas)
     ATUAL get_setting, sem claims . valor     ← a fuga de hoje
   Limite: o editor SQL liga-se como postgres e não pode mudar o session_user para
   'authenticator' (permission denied to set session authorization). Numa ligação real do
   PostgREST o session_user é 'authenticator', que NÃO está na lista → NULL. Provado pela
   expressão, não ao vivo.

   TOTAL DO CHECKOUT IGUAL: a trava do Bora recusa, por desenho, um SQL que crie uma função e
   chame quote_order_pricing no mesmo pedido (registado no e2e_log). Prova por análise do
   banco (pg_proc, 26/10): as funções que leem CHAVES SECRETAS pela get_setting são
     _refresh_driver_debt_marks, _settlement_debt_reminders, settlement_debtors  → cron
     (sem claims, session_user postgres: valor antes e depois);
     admin_update_weekly_closeout_settings, admin_weekly_closeout_list → admin (valor antes e
     depois);
     tvde_request_ride, _tvde_finish_km_part, tvde_finish_ride (tvde_plan_driver_pct) →
     chamadas com o token do cliente/motorista: a regra ANTIGA já devolvia NULL (papel
     'authenticated' não estava na lista e não é admin) — igual depois.
   quote_order_pricing e create_order NÃO leem nenhuma chave secreta pela get_setting.
   Logo o mesmo carrinho dá o mesmo total antes e depois. A única mudança de comportamento é
   "sem claims e session_user ≠ postgres/supabase_admin" → passa a NULL (era a fuga).
*/
