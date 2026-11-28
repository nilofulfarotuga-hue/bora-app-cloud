-- Robô do Jai (missão jai-robo-23-11): duas portas estreitas para o robô da VPS, que só tem a chave anon.
-- 1) jai_robo_aviso_urgente: chama notify_admin_urgent_push (sininho + push + Telegram) no máximo 1 vez
--    por 20 h (emergência: até 3 em 24 h). Texto curto, só com a chave do robô.
-- 2) jai_robo_gravar_pagina: escreve SÓ as páginas jai-robo-estado e jai-relatorio-AAAA-MM do livro
--    (claude_ai_memoria, espelhada no Córtex de hora a hora).
-- A chave do robô nunca fica aqui: guarda-se só o sha256 dela (passo manual no fim, fora do repo).

create table if not exists public.jai_robo_chave (
  id int primary key default 1 check (id = 1),
  hash text not null,
  criado_em timestamptz not null default now()
);
alter table public.jai_robo_chave enable row level security;
revoke all on public.jai_robo_chave from public, anon, authenticated;

create table if not exists public.jai_robo_avisos (
  id bigserial primary key,
  criado_em timestamptz not null default now(),
  texto text not null,
  teste boolean not null default false,
  emergencia boolean not null default false,
  admin_event uuid
);
alter table public.jai_robo_avisos enable row level security;
revoke all on public.jai_robo_avisos from public, anon, authenticated;

create or replace function public._jai_robo_chave_ok(p_chave text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.jai_robo_chave
    where id = 1 and hash = encode(extensions.digest(coalesce(p_chave, ''), 'sha256'), 'hex')
  );
$$;
revoke all on function public._jai_robo_chave_ok(text) from public, anon, authenticated;

create or replace function public.jai_robo_aviso_urgente(p_chave text, p_texto text, p_emergencia boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_teste boolean := coalesce(p_texto, '') like 'TESTE robô do Jai%';
begin
  if not public._jai_robo_chave_ok(p_chave) then
    raise exception 'jai_robo: chave invalida' using errcode = '28000';
  end if;
  if p_texto is null or length(btrim(p_texto)) = 0 or length(p_texto) > 400 then
    raise exception 'jai_robo: texto vazio ou maior que 400';
  end if;
  -- 1 aviso por dia (20 h de folga para a hora da corrida variar), salvo emergência
  if not coalesce(p_emergencia, false) and exists (
       select 1 from public.jai_robo_avisos where criado_em > now() - interval '20 hours') then
    return null;
  end if;
  if coalesce(p_emergencia, false) and (
       select count(*) from public.jai_robo_avisos where criado_em > now() - interval '24 hours') >= 3 then
    return null;
  end if;
  v_id := public.notify_admin_urgent_push(
    'jai_robo',
    'Robô do Jai' || E'\n' || btrim(p_texto),
    'jai_robo',
    'jai-robo',
    jsonb_build_object('origem', 'robo-jai', 'push_ref', 'jai-robo'),
    '/admin'
  );
  insert into public.jai_robo_avisos (texto, teste, emergencia, admin_event)
  values (btrim(p_texto), v_teste, coalesce(p_emergencia, false), v_id);
  return v_id;
end;
$$;
revoke all on function public.jai_robo_aviso_urgente(text, text, boolean) from public;
grant execute on function public.jai_robo_aviso_urgente(text, text, boolean) to anon, authenticated;

create or replace function public.jai_robo_gravar_pagina(p_chave text, p_pagina text, p_conteudo text)
returns timestamptz
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_quando timestamptz := now();
begin
  if not public._jai_robo_chave_ok(p_chave) then
    raise exception 'jai_robo: chave invalida' using errcode = '28000';
  end if;
  if p_pagina is null or not (p_pagina = 'jai-robo-estado' or p_pagina ~ '^jai-relatorio-[0-9]{4}-[0-9]{2}$') then
    raise exception 'jai_robo: pagina nao permitida: %', p_pagina;
  end if;
  if p_conteudo is null or length(p_conteudo) = 0 or length(p_conteudo) > 60000 then
    raise exception 'jai_robo: conteudo vazio ou grande demais';
  end if;
  insert into public.claude_ai_memoria (pagina, titulo, conteudo, origem, atualizado_em)
  values (p_pagina, p_pagina, p_conteudo, 'robo-jai', v_quando)
  on conflict (pagina) do update
    set conteudo = excluded.conteudo, origem = excluded.origem, atualizado_em = excluded.atualizado_em
    where public.claude_ai_memoria.origem = 'robo-jai';
  return v_quando;
end;
$$;
revoke all on function public.jai_robo_gravar_pagina(text, text, text) from public;
grant execute on function public.jai_robo_gravar_pagina(text, text, text) to anon, authenticated;

-- PASSO MANUAL (fora do repo, por quem aplica): gerar a chave na VPS e gravar só o hash:
--   insert into public.jai_robo_chave (id, hash) values (1, '<sha256 hex da chave>')
--   on conflict (id) do update set hash = excluded.hash, criado_em = now();
-- e pôr a chave em /root/radar-jai/.env como JAI_ROBO_CHAVE=...
