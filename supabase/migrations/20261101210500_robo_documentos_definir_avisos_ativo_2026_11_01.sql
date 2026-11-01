-- O painel (admin_robo_documentos_definir) passa a aceitar o interruptor robo_documentos_avisos_ativo
-- (emails automaticos de "faltam documentos" ao candidato). Complemento da migracao 20261101200500.

create or replace function public.admin_robo_documentos_definir(p_chave text, p_valor jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_corte jsonb;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_chave in ('robo_documentos_ativo', 'robo_documentos_avisos_ativo') then
    if jsonb_typeof(p_valor) <> 'boolean' then raise exception 'valor_invalido'; end if;
  elsif p_chave = 'robo_documentos_modo' then
    if p_valor not in ('"sombra"'::jsonb, '"ativo"'::jsonb) then raise exception 'valor_invalido'; end if;
  elsif p_chave = 'robo_documentos_confianca_min' then
    if jsonb_typeof(p_valor) <> 'number' or (p_valor #>> '{}')::numeric < 0.5 or (p_valor #>> '{}')::numeric > 1 then
      raise exception 'valor_invalido';
    end if;
  elsif p_chave = 'robo_documentos_limite_dia' then
    if jsonb_typeof(p_valor) <> 'number' or (p_valor #>> '{}')::numeric < 0 or (p_valor #>> '{}')::numeric > 2000 then
      raise exception 'valor_invalido';
    end if;
  else
    raise exception 'chave_invalida';
  end if;
  update public.platform_settings set value = p_valor, updated_at = now(), updated_by = auth.uid() where key = p_chave;
  if p_chave = 'robo_documentos_ativo' and p_valor = 'true'::jsonb then
    select value into v_corte from public.platform_settings where key = 'robo_documentos_corte';
    if v_corte is null or v_corte = 'null'::jsonb then
      update public.platform_settings
         set value = to_jsonb(to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')), updated_at = now(), updated_by = auth.uid()
       where key = 'robo_documentos_corte';
    end if;
  end if;
  perform public.log_admin_action('robo_documentos_definir'::text, 'platform_settings'::text, p_chave::text,
    jsonb_build_object('valor', p_valor));
  return public.admin_robo_documentos_config();
end
$f$;

-- O config do painel passa a trazer tambem o interruptor dos avisos e quantos avisos saem por dia.
create or replace function public.admin_robo_documentos_config()
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return public._robo_documentos_cfg() || jsonb_build_object(
    'a_agir', public._robo_documentos_age(),
    'avisos_ativo', coalesce((select (value #>> '{}')::boolean from public.platform_settings
                              where key = 'robo_documentos_avisos_ativo'), true),
    'avisos_24h', (select count(*) from public.documentos_lembretes_enviados
                    where quem = 'robo' and enviado_em > now() - interval '24 hours'),
    'analises_24h', (select count(*) from public.documentos_verificacoes
                      where created_at > now() - interval '24 hours' and modelo is not null),
    'total', (select count(*) from public.documentos_verificacoes));
end
$f$;
