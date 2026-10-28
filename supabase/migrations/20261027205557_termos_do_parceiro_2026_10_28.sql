-- Nota (missao-geral-2026-10-28): o NIPC da empresa foi retirado desta copia porque o repositorio e publico.
-- O texto aplicado em producao esta em supabase_migrations.schema_migrations (versao 20261027205557).
-- Termos e Condições do PARCEIRO (Regulamento UE 2019/1150, plataformas -> utilizadores profissionais).
-- Missão boom-burger-2026-10-27, adendo 3, passo F4 (Claude Code, 27/10/2026).
-- Até hoje legal_terms_versions só aceitava 'cliente' e 'estafeta' e nenhum parceiro tinha aceite termos.
--  1. o público 'parceiro' passa a ser válido;
--  2. versão 2026-10-28, texto curto em PT-PT, igual para todos os parceiros (base: o contrato enviado à Boom! Burger);
--  3. a aceitação guarda quem a registou e uma nota, para o admin registar um "Aceito" recebido por WhatsApp/email;
--  4. admin_parceiros_termos(): lista de parceiros com a versão aceite e a data (painel admin);
--  5. admin_registar_aceitacao_termos_parceiro(): o admin regista a aceitação recebida fora da app, com nota.
-- legal_terms_pending('parceiro') e legal_terms_accept('parceiro', ...) já servem sem mudança (não filtram o público).
-- 27/10 21:40 (Claude.ai): a identidade passou a não ter nome nem morada (ninguém pode saber quem é o dono);
-- a versão 2026-10-28 foi atualizada na base com 0 aceitações e este ficheiro acompanha o texto em vigor.

alter table public.legal_terms_versions drop constraint if exists legal_terms_versions_audience_check;
alter table public.legal_terms_versions add constraint legal_terms_versions_audience_check
  check (audience = any (array['cliente'::text, 'estafeta'::text, 'parceiro'::text]));

alter table public.legal_terms_acceptances
  add column if not exists registado_por uuid references auth.users(id) on delete set null,
  add column if not exists nota text;

insert into public.legal_terms_versions (version, audience, effective_date, title, body)
values ('2026-10-28', 'parceiro', date '2026-10-28', 'Termos e Condições do Parceiro — versão de 28/10/2026',
$termos$Estes são os termos entre a Bora e as lojas parceiras. São iguais para todos os parceiros. A Bora é gerida por uma sociedade unipessoal com o NIPC [NIPC retirado do repositorio publico; o texto exato esta na base], com sede na Guarda.

1. A Bora é uma plataforma de intermediação. Liga a sua loja aos clientes e aos estafetas. Não compra nem revende os seus produtos.

2. As condições comerciais (comissão ou mensalidade) são as que combinámos por escrito consigo e aparecem no seu painel.

3. Os pagamentos são semanais, com extrato pedido a pedido no painel.

4. Cada um fatura o que é seu: a loja fatura os produtos ao cliente; a Bora fatura o serviço dela.

5. Os pedidos, os produtos, a higiene e a informação de alergénios são da responsabilidade da loja.

6. As entregas são feitas por estafetas independentes.

7. Nas reservas é a loja que decide se pede sinal ao cliente. Sem sinal, a reserva fica feita na mesma.

8. Enquanto durar a parceria, a Bora pode usar o nome, o logótipo e as fotos da loja na app, no site e na divulgação.

9. A Bora comunica às Finanças os dados que a lei exige às plataformas (Lei n.º 36/2023) e trata os dados pessoais segundo o RGPD.

10. Autocertificação: a loja declara que só oferece produtos e serviços que cumprem a lei portuguesa e da União Europeia.

11. Não há fidelização: a loja pode sair quando quiser. A Bora só termina a parceria com 30 dias de aviso e as razões por escrito, salvo falta grave.

12. Qualquer mudança a estes termos é avisada com pelo menos 15 dias de antecedência.

13. Aplica-se a lei portuguesa. O foro é o da comarca da Guarda.

Ao tocar em "Aceito" confirma que leu e aceita estes termos.$termos$)
on conflict (version, audience) do nothing;

create or replace function public.admin_parceiros_termos()
 returns table (restaurant_id text, loja text, user_id uuid, email text, versao_atual text,
                versao_aceite text, aceite_em timestamptz, via text, nota text)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return query
  with v as (
    select t.version from public.legal_terms_versions t
     where t.audience = 'parceiro' order by t.effective_date desc, t.created_at desc limit 1)
  select r.id::text, r.name, coalesce(r.user_id, r.user_), u.email::text, (select v.version from v),
         a.version, a.accepted_at, a.platform, a.nota
    from public.restaurants r
    left join auth.users u on u.id = coalesce(r.user_id, r.user_)
    left join lateral (
      select x.version, x.accepted_at, x.platform, x.nota from public.legal_terms_acceptances x
       where x.user_id = coalesce(r.user_id, r.user_) and x.audience = 'parceiro'
       order by x.accepted_at desc limit 1) a on true
   where coalesce(r.is_partner, false) and r.approval_status = 'approved'
   order by r.name;
end
$function$;

create or replace function public.admin_registar_aceitacao_termos_parceiro(p_restaurant_id text, p_via text, p_nota text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid uuid;
  v_ver text;
  v_n   int;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_via is null or p_via not in ('whatsapp', 'email') then raise exception 'via_invalida'; end if;
  select coalesce(r.user_id, r.user_) into v_uid from public.restaurants r where r.id::text = p_restaurant_id;
  if v_uid is null then raise exception 'loja_sem_conta'; end if;
  select t.version into v_ver from public.legal_terms_versions t
   where t.audience = 'parceiro' order by t.effective_date desc, t.created_at desc limit 1;
  if v_ver is null then raise exception 'sem_versao_parceiro'; end if;
  insert into public.legal_terms_acceptances (user_id, audience, version, platform, registado_por, nota)
  values (v_uid, 'parceiro', v_ver, p_via, auth.uid(), nullif(trim(coalesce(p_nota, '')), ''))
  on conflict (user_id, audience, version) do nothing;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'version', v_ver, 'ja_aceite', v_n = 0);
end
$function$;

revoke all on function public.admin_parceiros_termos() from public, anon;
revoke all on function public.admin_registar_aceitacao_termos_parceiro(text, text, text) from public, anon;
grant execute on function public.admin_parceiros_termos() to authenticated;
grant execute on function public.admin_registar_aceitacao_termos_parceiro(text, text, text) to authenticated;
