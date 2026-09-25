-- O robô marcava negócios como «descartado» e a base nunca sabia.
-- Missão agente-avenca-qualidade-2026-09-24.
--
-- A RPC `prospect_registar` gravava o nome, a pontuação e as notas, mas **não o estado**. Por
-- isso os 48 negócios que o portão de identidade tinha descartado (sede de partido em vez de
-- café, negócio fechado, aldeia em vez de restaurante) continuavam na base marcados como
-- «novo», à espera de serem trabalhados. O motivo estava escrito no campo das notas e mais
-- nada olhava para ele.
--
-- Passa a aceitar o estado, com duas travas:
--   · só valores da lista (novo, amostra_pronta, proposta_rascunho, descartado, recusado);
--   · o robô NUNCA pode escrever «enviado» nem «cliente» — esses são do Danilo, e se já lá
--     estiverem não são pisados por uma corrida nova do robô.
create or replace function public.prospect_registar(p_chave text, p_linha jsonb)
returns bigint
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text; v_id bigint; v_estado text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'prospects_presenca_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  v_estado := nullif(p_linha->>'estado','');
  if v_estado is not null and v_estado not in ('novo','amostra_pronta','proposta_rascunho','descartado','recusado') then
    v_estado := null;
  end if;
  insert into public.prospects_presenca (fonte_id, nome, categoria, morada, concelho, lat, lon, km_da_guarda,
         telefone, email, website, instagram, facebook, sem_site, sem_telefone, sem_horario, ficha_google,
         instagram_parado_dias, pontuacao, notas, estado)
  values (p_linha->>'fonte_id', coalesce(p_linha->>'nome','(sem nome)'), p_linha->>'categoria', p_linha->>'morada',
          p_linha->>'concelho', nullif(p_linha->>'lat','')::double precision, nullif(p_linha->>'lon','')::double precision,
          nullif(p_linha->>'km_da_guarda','')::numeric, p_linha->>'telefone', p_linha->>'email', p_linha->>'website',
          p_linha->>'instagram', p_linha->>'facebook', coalesce((p_linha->>'sem_site')::boolean,false),
          coalesce((p_linha->>'sem_telefone')::boolean,false), coalesce((p_linha->>'sem_horario')::boolean,false),
          coalesce(p_linha->>'ficha_google','por_ver'), nullif(p_linha->>'instagram_parado_dias','')::integer,
          nullif(p_linha->>'pontuacao','')::smallint, p_linha->>'notas', coalesce(v_estado,'novo'))
  on conflict (fonte_id) do update
     set nome = excluded.nome, categoria = coalesce(excluded.categoria, prospects_presenca.categoria),
         morada = coalesce(excluded.morada, prospects_presenca.morada),
         telefone = coalesce(excluded.telefone, prospects_presenca.telefone),
         email = coalesce(excluded.email, prospects_presenca.email),
         website = coalesce(excluded.website, prospects_presenca.website),
         instagram = coalesce(excluded.instagram, prospects_presenca.instagram),
         facebook = coalesce(excluded.facebook, prospects_presenca.facebook),
         sem_site = excluded.sem_site, sem_telefone = excluded.sem_telefone, sem_horario = excluded.sem_horario,
         ficha_google = coalesce(excluded.ficha_google, prospects_presenca.ficha_google),
         pontuacao = coalesce(excluded.pontuacao, prospects_presenca.pontuacao),
         notas = coalesce(excluded.notas, prospects_presenca.notas),
         estado = case
                    when prospects_presenca.estado in ('enviado','cliente') then prospects_presenca.estado
                    when v_estado is not null then v_estado
                    else prospects_presenca.estado
                  end,
         atualizado_em = now()
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.prospect_registar(text, jsonb) from public;
grant execute on function public.prospect_registar(text, jsonb) to anon, authenticated, service_role;
