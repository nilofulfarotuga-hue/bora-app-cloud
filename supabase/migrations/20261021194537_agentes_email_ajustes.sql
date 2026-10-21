-- Caixa dos agentes, ajustes da missão agentes-email-2026-10-21 (Claude Code), por cima das três
-- migrações de 21/10 11:29-11:33 UTC.
-- 1) O mesmo e-mail enviado a dois agentes (ex.: suporte@ e radar@ no mesmo envio) fica uma vez em
--    cada caixa; só se recusa a repetição para o MESMO agente.
drop index if exists public.agentes_email_msgid_uq;
create unique index if not exists agentes_email_msgid_uq
  on public.agentes_email (direcao, agente, message_id) where message_id is not null;

-- 2) O painel só lê e muda o estado; ninguém apaga nem insere pela API (quem escreve é o servidor).
revoke all on public.agentes_email from authenticated;
grant select, update on public.agentes_email to authenticated;

-- 3) Anexos: o admin lê os ficheiros do bucket privado (link assinado no painel).
drop policy if exists agentes_email_anexos_admin_le on storage.objects;
create policy agentes_email_anexos_admin_le on storage.objects
  for select to authenticated using (bucket_id = 'agentes-email' and public.is_admin());

-- 4) Resumo por agente para o painel (respeita a RLS: quem não é admin recebe zero linhas).
create or replace function public.agentes_email_resumo()
returns table (agente text, nao_lidos bigint, total bigint, ultimo timestamptz)
language sql
stable
security invoker
set search_path = public
as $$
  select e.agente,
         count(*) filter (where e.direcao = 'entrada' and e.estado = 'novo') as nao_lidos,
         count(*) as total,
         max(e.criado_em) as ultimo
  from public.agentes_email e
  group by e.agente
  order by e.agente;
$$;
revoke all on function public.agentes_email_resumo() from public, anon;
grant execute on function public.agentes_email_resumo() to authenticated, service_role;
