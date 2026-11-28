-- 28/11/2026 10:10 (adendo do Danilo, missao pedido-exige-telefone-e-morada): o telemovel do perfil
-- aceita numero de QUALQUER pais e grava-se sempre em formato internacional (+indicativo e numero).
-- Antes: so 9 digitos a comecar por 9, gravados sem indicativo. Numero nacional sem indicativo
-- (9 digitos a comecar por 9 ou 2) continua a valer como Portugal (+351). A validacao fina por pais
-- faz-se na app (biblioteca de numeros de telefone). So muda o bloco do telemovel.
create or replace function public._apply_user_profile_change(p_user_id uuid, p_name text, p_phone text, p_changed_by uuid, p_source text, p_pending_action_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_old_name  text;
  v_old_phone text;
  v_name      text;
  v_phone     text;
  v_campos    text[] := '{}';
  v_antes     jsonb := '{}'::jsonb;
  v_depois    jsonb := '{}'::jsonb;
  v_meta      jsonb := '{}'::jsonb;
  v_id        bigint;
begin
  if p_source is null or p_source not in ('cliente', 'admin', 'robo_aprovado') then
    raise exception 'ORIGEM_INVALIDA: %', p_source;
  end if;

  if p_user_id is null then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_CONTA',
      'erro', 'Conta não encontrada.');
  end if;

  select u.name, u.phone into v_old_name, v_old_phone
    from public.users u
   where u.id = p_user_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_CONTA',
      'erro', 'Conta não encontrada.');
  end if;

  v_name := nullif(regexp_replace(btrim(coalesce(p_name, '')), '[[:space:]]+', ' ', 'g'), '');
  if v_name is not null then
    if char_length(v_name) < 2 or char_length(v_name) > 60 then
      return jsonb_build_object('ok', false, 'codigo', 'NOME_INVALIDO',
        'erro', 'O nome tem de ter entre 2 e 60 caracteres.');
    end if;
    if char_length(regexp_replace(v_name, '[^[:alpha:]]', '', 'g')) < 2 then
      return jsonb_build_object('ok', false, 'codigo', 'NOME_INVALIDO',
        'erro', 'Escreve o teu nome com letras.');
    end if;
  end if;

  v_phone := regexp_replace(coalesce(p_phone, ''), '[[:space:]().-]', '', 'g');
  if v_phone = '' then
    v_phone := null;
  end if;
  if v_phone is not null then
    -- 28/11/2026: qualquer pais, sempre +indicativo.
    if v_phone like '00%' then
      v_phone := '+' || substr(v_phone, 3);
    end if;
    if v_phone ~ '^[29][0-9]{8}$' then
      v_phone := '+351' || v_phone;
    elsif v_phone ~ '^351[29][0-9]{8}$' then
      v_phone := '+' || v_phone;
    end if;
    if v_phone !~ '^\+[1-9][0-9]{6,14}$'
       or (v_phone like '+351%' and v_phone !~ '^\+351[0-9]{9}$') then
      return jsonb_build_object('ok', false, 'codigo', 'TELEMOVEL_INVALIDO',
        'erro', 'Telemóvel inválido. Escolhe o indicativo do país e escreve o número.');
    end if;
  end if;

  if v_name is not null and v_name is distinct from v_old_name then
    v_campos := v_campos || 'name'::text;
    v_antes  := v_antes  || jsonb_build_object('name', v_old_name);
    v_depois := v_depois || jsonb_build_object('name', v_name);
    v_meta   := v_meta   || jsonb_build_object('bora_name', v_name);
  else
    v_name := v_old_name;
  end if;

  if v_phone is not null and v_phone is distinct from v_old_phone then
    v_campos := v_campos || 'phone'::text;
    v_antes  := v_antes  || jsonb_build_object('phone', v_old_phone);
    v_depois := v_depois || jsonb_build_object('phone', v_phone);
    v_meta   := v_meta   || jsonb_build_object('bora_phone', v_phone);
  else
    v_phone := v_old_phone;
  end if;

  if cardinality(v_campos) = 0 then
    return jsonb_build_object('ok', true, 'alterado', false,
      'name', v_old_name, 'phone', v_old_phone, 'campos', '[]'::jsonb);
  end if;

  if p_source = 'cliente' and (
       select count(*) from public.user_profile_changes c
        where c.user_id = p_user_id and c.source = 'cliente'
          and c.created_at > now() - interval '1 day') >= 10 then
    return jsonb_build_object('ok', false, 'codigo', 'LIMITE_DIARIO',
      'erro', 'Já mudaste os teus dados muitas vezes hoje. Tenta amanhã ou fala com o Suporte.');
  end if;

  update public.users
     set name  = v_name,
         phone = v_phone
   where id = p_user_id;

  -- Nada de SQL no auth: o metadata do login atualiza-se pela Edge admin-sync-user-name e pela app.
  perform v_meta;

  insert into public.user_profile_changes
    (user_id, changed_by, source, pending_action_id, antes, depois)
  values
    (p_user_id, p_changed_by, p_source, p_pending_action_id, v_antes, v_depois)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'alterado', true,
    'name', v_name, 'phone', v_phone,
    'campos', to_jsonb(v_campos), 'change_id', v_id);
end;
$function$;
