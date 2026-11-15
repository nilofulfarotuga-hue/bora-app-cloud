-- PROPOSTA E — LOJA ONLINE DENTRO DA APP (missão fechar-tudo-15-11, 15/11/2026, Claude Code, ajudante E).
-- Ordem do Danilo (caixa_guardados 57, ponto E, e caixa 10): os mesmos produtos que a Bora vende na
-- loja Shopify (dropshipping: o fornecedor envia pelo correio, de qualquer origem, no prazo que der)
-- aparecem aos clientes dentro da app. Começa por PETS; preparada para mais nichos, um em destaque
-- por semana. NADA DISTO FOI APLICADO: aplica a Claude.ai com execute_sql, pela ordem, uma parte de
-- cada vez. Nenhuma linha mexe em orders, carteiras, ledger, tokens, preços de outras categorias nem
-- no Stripe. Nesta primeira versão NÃO há pagamento (o botão "Encomendar" da app está desligado).
--
-- O QUE FAZ
--   E.1  tabela public.loja_online_nichos      (pets, casa, …; destaque_desde marca o nicho da semana)
--   E.2  tabela public.loja_online_produtos    (espelho dos produtos da Shopify, com preço final da Bora)
--   E.3  RLS: quem não é admin (anon e authenticated) lê SÓ linhas ativas; admin lê e escreve tudo
--        (is_admin()). Anon lê porque o catálogo de produtos da app já é público (products_public_read
--        é `true` para public, lido em pg_policies a 15/11).
--   E.4  interruptor platform_settings 'loja_online_ativa' = false (a app só mostra o ladrilho com true)
--   E.5  RPCs do painel: admin_loja_online_produto_estado e admin_loja_online_nicho_da_semana
--        (SECURITY DEFINER, guarda public.is_admin(), motivo obrigatório, auditoria por
--        public.log_admin_action)
--   E.6  semente: só o nicho 'pets'
--
-- PORQUÊ ASSIM
--   * O preço ao cliente (preco_bora_cents) é 2 × custo_fornecedor_cents — AUTORIZO do Danilo de
--     14/11/2026 12:19 (caixa 10, adendo 1). A regra NÃO é calculada aqui nem na app: é aplicada pela
--     importação da Shopify (Edge Function de sincronização, passo seguinte, precisa do token da Shopify
--     que fica só nos segredos do servidor — outra sessão). Os produtos nascem com ativo=false; o painel
--     é que os liga.
--   * Tudo fechado por omissão: interruptor false, produtos inativos. Nada muda para o cliente até a
--     Claude.ai ligar no painel.
--   * admin_update_setting (a RPC que o painel já usa para interruptores) recusa chaves que não existem
--     (`unknown_setting`, lido em pg_get_functiondef a 15/11): por isso a E.4 insere a chave.
--
-- LIDO EM PRODUÇÃO SÓ COM SELECT (15/11/2026 14:2x):
--   to_regclass('public.loja_online_nichos') e ('public.loja_online_produtos') = NULL (não existem);
--   platform_settings sem a chave 'loja_online_ativa'; nenhuma função admin_loja_online%;
--   public.is_admin() existe (SECURITY DEFINER, boolean);
--   public.log_admin_action tem DUAS versões — (p_action text, p_entity_type text, p_entity_id uuid,
--   p_details jsonb) e (p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb) —
--   por isso as chamadas abaixo levam ::text explícito no 3.º argumento;
--   platform_settings: key, value jsonb, description, category, updated_at, updated_by, is_secret.
--
-- A APP (ramo ai/2026-11-15-app) JÁ ESPERA ISTO:
--   lib/services/loja_online_service.dart lê as duas tabelas (.eq('ativo', true)) e a chave;
--   lib/screens/admin/admin_loja_online_screen.dart chama as duas RPCs com estes nomes e parâmetros.
--   Enquanto a proposta não for aplicada, a app mostra "Em breve" e o painel "Esta parte ainda não foi
--   instalada no servidor." — sem erro.

begin;

-- =====================================================================================================
-- E.1  NICHOS
-- =====================================================================================================
create table if not exists public.loja_online_nichos (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  nome            text not null,
  ordem           integer not null default 100,
  ativo           boolean not null default true,
  destaque_desde  timestamptz,                       -- o nicho da semana é o ativo com a data mais recente
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
comment on table public.loja_online_nichos is
  'Loja Online (15/11/2026): nichos da loja Shopify da Bora mostrados na app. O nicho da semana é o ativo com destaque_desde mais recente.';

-- =====================================================================================================
-- E.2  PRODUTOS
-- =====================================================================================================
create table if not exists public.loja_online_produtos (
  id                      uuid primary key default gen_random_uuid(),
  shopify_product_id      text not null unique,      -- chave da sincronização (upsert por aqui)
  shopify_variant_id      text,
  nicho_id                uuid not null references public.loja_online_nichos(id) on delete restrict,
  titulo                  text not null,
  descricao               text,
  imagens                 text[] not null default '{}',
  custo_fornecedor_cents  integer not null default 0 check (custo_fornecedor_cents >= 0),
  preco_bora_cents        integer not null default 0 check (preco_bora_cents >= 0),  -- = 2 × custo, pela importação
  prazo_min_dias          integer not null default 0 check (prazo_min_dias >= 0),
  prazo_max_dias          integer not null default 0 check (prazo_max_dias >= prazo_min_dias),
  ativo                   boolean not null default false,   -- nasce escondido; o painel liga
  destaque                boolean not null default false,   -- entra na "Novidade da semana" do nicho
  criado_em               timestamptz not null default now(),
  atualizado_em           timestamptz not null default now()
);
comment on table public.loja_online_produtos is
  'Loja Online (15/11/2026): espelho dos produtos da Shopify. preco_bora_cents é o preço final ao cliente (IVA e envio incluídos) = 2 × custo_fornecedor_cents, regra aplicada pela importação (AUTORIZO 14/11/2026 12:19).';
create index if not exists loja_online_produtos_nicho_ativo_idx
  on public.loja_online_produtos (nicho_id, ativo, destaque);

-- =====================================================================================================
-- E.3  RLS E PERMISSÕES
-- =====================================================================================================
alter table public.loja_online_nichos   enable row level security;
alter table public.loja_online_produtos enable row level security;

revoke all on public.loja_online_nichos   from anon, authenticated;
revoke all on public.loja_online_produtos from anon, authenticated;
grant select on public.loja_online_nichos   to anon, authenticated;
grant select on public.loja_online_produtos to anon, authenticated;
-- A escrita fica só para admins (regra abaixo); a sincronização usa service_role, que não passa pela RLS.
grant insert, update, delete on public.loja_online_nichos   to authenticated;
grant insert, update, delete on public.loja_online_produtos to authenticated;

drop policy if exists loja_online_nichos_leitura_ativos on public.loja_online_nichos;
create policy loja_online_nichos_leitura_ativos on public.loja_online_nichos
  for select to anon, authenticated
  using (ativo or public.is_admin());

drop policy if exists loja_online_nichos_admin on public.loja_online_nichos;
create policy loja_online_nichos_admin on public.loja_online_nichos
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists loja_online_produtos_leitura_ativos on public.loja_online_produtos;
create policy loja_online_produtos_leitura_ativos on public.loja_online_produtos
  for select to anon, authenticated
  using (ativo or public.is_admin());

drop policy if exists loja_online_produtos_admin on public.loja_online_produtos;
create policy loja_online_produtos_admin on public.loja_online_produtos
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- =====================================================================================================
-- E.4  INTERRUPTOR (nasce DESLIGADO; o painel liga por admin_update_setting, auditado)
-- =====================================================================================================
insert into public.platform_settings (key, value, description, category, is_secret)
values (
  'loja_online_ativa', 'false'::jsonb,
  'Loja Online dentro da app do cliente (produtos da loja Shopify da Bora, enviados pelo correio). false = o ladrilho não aparece. Ligar só com produtos ativos.',
  'loja_online', false
)
on conflict (key) do nothing;

-- =====================================================================================================
-- E.5  RPCs DO PAINEL
-- =====================================================================================================
-- E.5.1  Liga/desliga ou destaca um produto. NULL num parâmetro = não mexe nesse campo.
create or replace function public.admin_loja_online_produto_estado(p_id uuid, p_ativo boolean, p_destaque boolean, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  public.loja_online_produtos%rowtype;
  v_depois public.loja_online_produtos%rowtype;
begin
  -- Guarda: is_admin() (JWT), nunca current_user (dentro de SECURITY DEFINER é sempre o dono).
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'reason_required' using errcode = '22023';
  end if;
  if p_ativo is null and p_destaque is null then
    raise exception 'nada_a_mudar' using errcode = '22023';
  end if;

  select * into v_antes from public.loja_online_produtos where id = p_id for update;
  if not found then
    raise exception 'produto_nao_encontrado' using errcode = 'P0002';
  end if;

  update public.loja_online_produtos
     set ativo         = coalesce(p_ativo, ativo),
         destaque      = coalesce(p_destaque, destaque),
         atualizado_em = now()
   where id = p_id
   returning * into v_depois;

  perform public.log_admin_action(
    'loja_online_produto_estado'::text,
    'loja_online_produto'::text,
    p_id::text,
    jsonb_build_object(
      'motivo', trim(p_motivo),
      'titulo', v_depois.titulo,
      'antes',  jsonb_build_object('ativo', v_antes.ativo,  'destaque', v_antes.destaque),
      'depois', jsonb_build_object('ativo', v_depois.ativo, 'destaque', v_depois.destaque)
    )
  );

  return jsonb_build_object('ok', true, 'id', v_depois.id, 'ativo', v_depois.ativo, 'destaque', v_depois.destaque);
end;
$$;
revoke all on function public.admin_loja_online_produto_estado(uuid, boolean, boolean, text) from public, anon;
grant execute on function public.admin_loja_online_produto_estado(uuid, boolean, boolean, text) to authenticated;

-- E.5.2  Nicho da semana: carimba destaque_desde = now() (e garante ativo). A app escolhe o mais recente.
create or replace function public.admin_loja_online_nicho_da_semana(p_nicho_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nicho public.loja_online_nichos%rowtype;
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'reason_required' using errcode = '22023';
  end if;

  select * into v_nicho from public.loja_online_nichos where id = p_nicho_id for update;
  if not found then
    raise exception 'nicho_nao_encontrado' using errcode = 'P0002';
  end if;

  update public.loja_online_nichos
     set destaque_desde = now(),
         ativo          = true,
         atualizado_em  = now()
   where id = p_nicho_id
   returning * into v_nicho;

  perform public.log_admin_action(
    'loja_online_nicho_da_semana'::text,
    'loja_online_nicho'::text,
    p_nicho_id::text,
    jsonb_build_object('motivo', trim(p_motivo), 'slug', v_nicho.slug, 'nome', v_nicho.nome,
                       'destaque_desde', v_nicho.destaque_desde)
  );

  return jsonb_build_object('ok', true, 'id', v_nicho.id, 'slug', v_nicho.slug, 'destaque_desde', v_nicho.destaque_desde);
end;
$$;
revoke all on function public.admin_loja_online_nicho_da_semana(uuid, text) from public, anon;
grant execute on function public.admin_loja_online_nicho_da_semana(uuid, text) to authenticated;

-- =====================================================================================================
-- E.6  SEMENTE: só pets (os produtos vêm da sincronização com a Shopify, nunca à mão)
-- =====================================================================================================
insert into public.loja_online_nichos (slug, nome, ordem, ativo, destaque_desde)
values ('pets', 'Pets', 10, true, now())
on conflict (slug) do nothing;

commit;

-- =====================================================================================================
-- PROVAS (correr depois de aplicar; cada uma tem o resultado esperado)
-- =====================================================================================================
-- 1) As tabelas existem:
--    select to_regclass('public.loja_online_nichos') t1, to_regclass('public.loja_online_produtos') t2;
--    -> ambos não nulos
-- 2) O interruptor existe e está DESLIGADO:
--    select key, value, category from public.platform_settings where key = 'loja_online_ativa';
--    -> value = false
-- 3) Regras de acesso (4 linhas):
--    select tablename, policyname, roles::text, cmd from pg_policies where tablename like 'loja_online_%' order by 1,2;
-- 4) As funções existem, SECURITY DEFINER, fechadas a anon:
--    select p.proname, pg_get_function_identity_arguments(p.oid) args, p.prosecdef,
--           has_function_privilege('anon', p.oid, 'execute') anon_pode,
--           has_function_privilege('authenticated', p.oid, 'execute') auth_pode
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname like 'admin_loja_online%';
--    -> prosecdef = true, anon_pode = false, auth_pode = true
-- 5) Semente:
--    select slug, nome, ordem, ativo, destaque_desde is not null em_destaque from public.loja_online_nichos;
--    -> 1 linha: pets
-- 6) Teste anti-mentira da RLS (visitante vê só o ativo; nenhum produto porque nascem inativos):
--    set role anon; select count(*) nichos from public.loja_online_nichos; select count(*) produtos from public.loja_online_produtos; reset role;
--    -> nichos = 1, produtos = 0
-- 7) A guarda das RPCs recusa quem não é admin (com um JWT de cliente, pela API):
--    select public.admin_loja_online_nicho_da_semana((select id from public.loja_online_nichos where slug='pets'), 'teste');
--    -> ERRO admin_required (42501) para não-admin; para admin devolve ok=true e cria uma linha em
--       admin_audit_log com action 'loja_online_nicho_da_semana'.
-- 8) Na app: com 'loja_online_ativa' = false o ladrilho não aparece; com true e sem produtos ativos o
--    ecrã diz "Ainda não há produtos nesta loja."; o painel deixa de dizer "Esta parte ainda não foi
--    instalada no servidor.".

-- =====================================================================================================
-- ROLLBACK (comentado; só por ordem explícita — apaga as duas tabelas e o que estiver dentro)
-- =====================================================================================================
-- begin;
-- drop function if exists public.admin_loja_online_nicho_da_semana(uuid, text);
-- drop function if exists public.admin_loja_online_produto_estado(uuid, boolean, boolean, text);
-- drop table if exists public.loja_online_produtos;
-- drop table if exists public.loja_online_nichos;
-- delete from public.platform_settings where key = 'loja_online_ativa';
-- commit;

-- =====================================================================================================
-- PASSO SEGUINTE (fora desta proposta, outra sessão)
-- =====================================================================================================
-- * Edge Function `loja-online-sync` (service_role): lê os produtos da loja Shopify pela Admin API
--   (token SÓ nos segredos da Edge Function, nunca no repositório), faz upsert em loja_online_produtos
--   por shopify_product_id com preco_bora_cents = 2 * custo_fornecedor_cents (AUTORIZO 14/11/2026 12:19),
--   imagens, prazo do fornecedor; os produtos novos ficam ativo=false. Agendar por cron (pg_cron) e
--   permitir "sincronizar agora" no painel.
-- * Pagamento (só depois do autorizo com data, caixa 10 bloco 2.3): carrinho e pagamento pelo caminho do
--   Stripe já provado no delivery (sem dinheiro à entrega, porque chega pelo correio), encomenda criada
--   na Shopify pela Admin API para o AutoDS enviar, número de seguimento em "Os meus pedidos".
