-- /baixar: contagem de visitas por origem feita no servidor (Cloudflare Pages Function
-- functions/baixar.js do bora-site), 30/09/2026.
-- Porque: de 23/09 a 30/09 a pagina /baixar ficou fora da copia filtrada do deploy e o
-- link passou a ser um redireccionamento da Cloudflare sem contagem nenhuma; o ?de=...
-- de QR, reels e anuncios deixou de ser contado (ultima linha em link_clicks 23/09 17:41).
-- A funcao corre como definidor (link_clicks e site_visits tem RLS sem politicas) e so
-- aceita origens no formato da casa; robos de pre-visualizacao nao contam.
create or replace function public.registar_visita_baixar(
  p_de text,
  p_page text default '/baixar',
  p_plataforma text default 'outro',
  p_ua text default null,
  p_ref text default null,
  p_ip text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_de text := lower(coalesce(p_de, ''));
begin
  if v_de !~ '^[a-z0-9-]{1,48}$' then
    v_de := 'directo';
  end if;
  -- renderizadores de pre-visualizacao e robos (chegam em rajadas, nao sao gente)
  if coalesce(p_ua, '') ~* '(bot|crawler|spider|facebookexternalhit|facebot|whatsapp|telegrambot|twitterbot|linkedinbot|slackbot|discordbot|preview|headless|curl/|python-requests|wget/)' then
    return false;
  end if;
  insert into public.link_clicks (origin, page, platform, user_agent, referrer, ip_trunc)
  values (v_de, coalesce(p_page, '/baixar'), coalesce(p_plataforma, 'outro'), left(p_ua, 400), left(p_ref, 400), left(p_ip, 64));
  insert into public.site_visits (origem, dia)
  values (v_de, (now() at time zone 'Europe/Lisbon')::date);
  return true;
end;
$$;

revoke all on function public.registar_visita_baixar(text, text, text, text, text, text) from public;
grant execute on function public.registar_visita_baixar(text, text, text, text, text, text) to anon, authenticated, service_role;
