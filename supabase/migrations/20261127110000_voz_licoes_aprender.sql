-- 27/11/2026 — Atendente de voz aprende com os erros (pedido do Danilo depois da chamada de teste das 10:43:
-- "tem que aprender com os erros ... cada vez se aprimorar mais").
-- Depois de cada chamada, a central chama voz-cerebro {op:"aprender"}: o Opus revê a conversa contra as
-- regras e escreve lições curtas em voz_licoes. As lições ATIVAS entram no prompt de todas as chamadas
-- seguintes. Lições que tocam em dinheiro e informação em falta nascem PENDENTES (a equipa vê no painel).
-- O painel (Chamadas → Lições) lê, liga/desliga, aprova, edita e cria lições; cada chamada mostra a revisão.

-- ─── 1. Lições ────────────────────────────────────────────────────────────────
create table if not exists public.voz_licoes (
  id bigserial primary key,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  chamada_id uuid references public.chamadas_voz(id) on delete set null,
  tipo text not null default 'comportamento' check (tipo in ('comportamento','conhecimento')),
  regra text not null check (char_length(regra) between 10 and 400),
  motivo text,
  estado text not null default 'ativa' check (estado in ('ativa','pendente','desligada')),
  vezes integer not null default 1,
  origem text not null default 'ia' check (origem in ('ia','admin')),
  mudado_por uuid
);
create index if not exists voz_licoes_estado_idx on public.voz_licoes (estado, vezes desc, atualizado_em desc);

alter table public.voz_licoes enable row level security;
revoke all on public.voz_licoes from anon;
create policy voz_licoes_admin_ler on public.voz_licoes
  for select to authenticated using (public.is_admin());

-- ─── 2. Revisão de cada chamada ───────────────────────────────────────────────
alter table public.chamadas_voz add column if not exists revisao_ia jsonb;
alter table public.chamadas_voz add column if not exists revisto_ia_em timestamptz;

-- ─── 3. Reforço (o treinador viu a mesma falha outra vez) — só o servidor ─────
create or replace function public.voz_licao_reforcar(p_id bigint)
returns void language sql security definer set search_path = public as $$
  update public.voz_licoes set vezes = vezes + 1, atualizado_em = now() where id = p_id;
$$;
revoke all on function public.voz_licao_reforcar(bigint) from public, anon, authenticated;
grant execute on function public.voz_licao_reforcar(bigint) to service_role;

-- ─── 4. Painel (só admin) ─────────────────────────────────────────────────────
create or replace function public.admin_voz_licoes(p_estado text default null)
returns setof public.voz_licoes
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'so admin' using errcode = '42501'; end if;
  return query
  select * from public.voz_licoes l
   where p_estado is null or p_estado = '' or l.estado = p_estado
   order by case l.estado when 'pendente' then 0 when 'ativa' then 1 else 2 end, l.vezes desc, l.atualizado_em desc
   limit 500;
end $$;

create or replace function public.admin_voz_licao_mudar(p_id bigint, p_estado text default null, p_regra text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_antes jsonb;
begin
  if not public.is_admin() then raise exception 'so admin' using errcode = '42501'; end if;
  if p_estado is not null and p_estado not in ('ativa','pendente','desligada') then raise exception 'estado invalido'; end if;
  if p_regra is not null and char_length(trim(p_regra)) not between 10 and 400 then raise exception 'a licao tem de ter entre 10 e 400 letras'; end if;
  select to_jsonb(l) into v_antes from public.voz_licoes l where l.id = p_id;
  if v_antes is null then raise exception 'licao nao existe'; end if;
  update public.voz_licoes set estado = coalesce(p_estado, estado), regra = coalesce(nullif(trim(p_regra), ''), regra),
         atualizado_em = now(), mudado_por = auth.uid()
   where id = p_id;
  perform public.log_admin_action('voz_licao_mudar'::text, 'voz_licoes'::text, p_id::text,
    jsonb_build_object('antes', v_antes, 'estado', p_estado, 'regra', p_regra));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_voz_licao_nova(p_regra text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not public.is_admin() then raise exception 'so admin' using errcode = '42501'; end if;
  if char_length(trim(coalesce(p_regra, ''))) not between 10 and 400 then raise exception 'a licao tem de ter entre 10 e 400 letras'; end if;
  insert into public.voz_licoes (regra, estado, origem, mudado_por, motivo)
  values (trim(p_regra), 'ativa', 'admin', auth.uid(), 'escrita pela equipa no painel')
  returning id into v_id;
  perform public.log_admin_action('voz_licao_nova'::text, 'voz_licoes'::text, v_id::text, jsonb_build_object('regra', p_regra));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

revoke all on function public.admin_voz_licoes(text) from public, anon;
revoke all on function public.admin_voz_licao_mudar(bigint, text, text) from public, anon;
revoke all on function public.admin_voz_licao_nova(text) from public, anon;
grant execute on function public.admin_voz_licoes(text), public.admin_voz_licao_mudar(bigint, text, text),
  public.admin_voz_licao_nova(text) to authenticated;

-- ─── 5. A atendente fala no feminino (voz de mulher da Google) ────────────────
update public.voz_definicoes
   set value = to_jsonb('Olá, está a falar com a assistente virtual da Bora. A chamada é gravada para qualidade. Em que posso ajudar?'::text),
       updated_at = now()
 where key = 'voz_saudacao' and value #>> '{}' ilike '%o assistente virtual%';
