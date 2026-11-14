-- Missão farmacias-loja-2026-11-14 · bloco 2.6 — termos do parceiro nas farmácias.
--
-- O que muda: aceitar os Termos do Parceiro (legal_terms_versions, audience 'parceiro',
-- versão 2026-10-28) passa a preencher também restaurants.dsa_self_certified_at das
-- FARMÁCIAS do dono que aceitou. Os termos trazem a cláusula "10. Autocertificação: a
-- loja declara que só oferece produtos e serviços que cumprem a lei portuguesa e da
-- União Europeia" — aceitar os termos é a autocertificação (DSA, art. 30.º).
--
-- Só farmácias (category = 'pharmacy'): as outras lojas ficam como estavam até ordem do
-- Danilo. Nunca apaga nem muda uma data já posta (só preenche quando está vazia).
-- Sem dinheiro, sem tabelas novas. A app passa a mostrar o portão dos termos às farmácias
-- (lib/widgets/terms_gate.dart, kCategoriasComTermosDoParceiro + 'pharmacy').
--
-- Prova depois de aplicar (só leitura):
--   select id, dsa_self_certified_at from restaurants where category = 'pharmacy' and is_partner;
--   select user_id, audience, version, accepted_at from legal_terms_acceptances
--    where audience = 'parceiro'
--      and user_id in ('9b218f1a-3b54-4168-ba8f-d1b218f6ec94','a34b2f3d-40f4-439a-bf22-3dcc7721c2a4');
-- (antes de alguém tocar em "Aceito": as duas datas vazias e nenhuma linha 'parceiro').

create or replace function public.legal_terms_accept(p_audience text, p_version text, p_platform text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  if not exists (select 1 from public.legal_terms_versions where audience = p_audience and version = p_version) then
    raise exception 'versao_desconhecida';
  end if;
  insert into public.legal_terms_acceptances (user_id, audience, version, platform)
  values (v_uid, p_audience, p_version, p_platform)
  on conflict (user_id, audience, version) do nothing;

  -- 14/11/2026: termos do parceiro aceites = autocertificação da farmácia (cláusula 10).
  if p_audience = 'parceiro' then
    update public.restaurants r
       set dsa_self_certified_at = now()
     where coalesce(r.user_id, r.user_) = v_uid
       and r.category = 'pharmacy'
       and coalesce(r.is_partner, false)
       and r.dsa_self_certified_at is null;
  end if;

  return jsonb_build_object('ok', true, 'version', p_version);
end $$;

revoke all on function public.legal_terms_accept(text, text, text) from public, anon;
grant execute on function public.legal_terms_accept(text, text, text) to authenticated, service_role;
