-- ADENDO 4 — parte E: foto do prato numa avaliacao (sem premio nenhum).
--
-- A avaliacao continua a ser gravada por submit_rating (nao se mexe nela). Esta
-- funcao so cola a foto DEPOIS, e so se: quem chama e quem avaliou, a avaliacao
-- e a uma loja, a foto esta na pasta do proprio cliente e tem o nome de uma
-- foto de avaliacao, e o interruptor feature_avaliacao_com_foto esta ligado.
-- Fechada a anon.

create or replace function public.rating_anexar_foto(p_rating_id uuid, p_photo_url text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_ligado boolean;
  v_n     integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select coalesce((select (value = 'true'::jsonb) from public.platform_settings
                    where key = 'feature_avaliacao_com_foto'), true)
    into v_ligado;
  if not v_ligado then
    return jsonb_build_object('ok', false, 'error', 'desligado');
  end if;

  if p_photo_url is null
     or position(('/storage/v1/object/public/order-photos/' || v_uid::text || '/avaliacao_') in p_photo_url) = 0 then
    return jsonb_build_object('ok', false, 'error', 'url_invalida');
  end if;

  update public.ratings
     set photo_url = p_photo_url
   where id = p_rating_id
     and rater_user_id = v_uid
     and subject_type = 'partner';
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error', 'avaliacao_nao_encontrada');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.rating_anexar_foto(uuid, text) from public, anon;
grant execute on function public.rating_anexar_foto(uuid, text) to authenticated;
