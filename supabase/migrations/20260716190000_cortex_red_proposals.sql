-- Superfície de revisão para propostas zona-vermelha do Córtex (cortex-mcp).
-- Espelho read-only isolado de proposals.jsonl (VPS) — NÃO liga a robot_suggestions/aprovador-vermelho.
-- Aprovar aqui nunca executa nada sozinho: status só marca "vista"/"decidida_fora", decisão humana.

create table if not exists public.cortex_red_proposals (
  pid text primary key,
  ordem_id text,
  tipo text,
  zona text not null default 'vermelha',
  tarefa text not null,
  who text,
  criada_em timestamptz not null,
  sincronizada_em timestamptz not null default now(),
  status text not null default 'nova' check (status in ('nova','vista','decidida_fora')),
  revisada_por uuid,
  revisada_por_email text,
  revisada_em timestamptz,
  nota_revisao text
);

alter table public.cortex_red_proposals enable row level security;
-- Sem policies de propósito: acesso só via as 3 RPCs abaixo (mesmo padrão de robot_suggestions).

-- RPC 1: sync (VPS cron, chave anon) — só INSERT de proposta nova, nunca sobrescreve status/nota
-- já decididos por um admin (ON CONFLICT DO NOTHING). Validação apertada porque é anon-callable.
create or replace function public.cortex_proposal_sync_upsert(
  p_pid text,
  p_ordem_id text,
  p_tipo text,
  p_zona text,
  p_tarefa text,
  p_who text,
  p_criada_em timestamptz
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if p_pid is null or p_pid !~ '^prop-[0-9a-f]{6,16}$' then
    raise exception 'pid_invalido';
  end if;
  if p_tarefa is null or length(trim(p_tarefa)) = 0 then
    raise exception 'tarefa_vazia';
  end if;

  insert into public.cortex_red_proposals (pid, ordem_id, tipo, zona, tarefa, who, criada_em)
  values (
    p_pid,
    left(p_ordem_id, 200),
    left(p_tipo, 50),
    coalesce(left(p_zona, 20), 'vermelha'),
    left(p_tarefa, 8000),
    left(p_who, 100),
    coalesce(p_criada_em, now())
  )
  on conflict (pid) do nothing;
end;
$$;

grant execute on function public.cortex_proposal_sync_upsert(text,text,text,text,text,text,timestamptz) to anon;

-- RPC 2: listar (admin, chamada pelo ecrã Central)
create or replace function public.cortex_list_red_proposals(
  p_status text default 'nova',
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  perform public._admin_op_guard();
  return coalesce((
    select jsonb_agg(to_jsonb(s) order by s.criada_em desc)
      from (
        select pid, ordem_id, tipo, zona, tarefa, who, criada_em, sincronizada_em,
               status, revisada_por_email, revisada_em, nota_revisao
          from public.cortex_red_proposals
         where (p_status is null or status = p_status)
         order by criada_em desc
         limit least(greatest(coalesce(p_limit, 100), 1), 500)
        offset greatest(coalesce(p_offset, 0), 0)
      ) s
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.cortex_list_red_proposals(text,int,int) to authenticated;

-- RPC 3: marcar estado (admin) — nunca dispara execução, só regista decisão humana
create or replace function public.cortex_proposal_mark_status(
  p_pid text,
  p_status text,
  p_nota text default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  perform public._admin_op_guard();

  if p_status not in ('vista', 'decidida_fora') then
    raise exception 'status_invalido: % (permitido: vista, decidida_fora)', p_status;
  end if;

  update public.cortex_red_proposals
     set status = p_status,
         revisada_por = auth.uid(),
         revisada_por_email = coalesce(auth.jwt() ->> 'email', auth.jwt() -> 'user_metadata' ->> 'email'),
         revisada_em = now(),
         nota_revisao = left(trim(coalesce(p_nota, '')), 500)
   where pid = p_pid;

  if not found then
    raise exception 'proposta_nao_encontrada';
  end if;

  -- entity_id é null::uuid explícito para desambiguar entre as 2 sobrecargas de log_admin_action
  -- (pid não é uuid, por isso não passa como entity_id — vai no jsonb de details).
  perform public.log_admin_action(
    'cortex_proposal_mark_status',
    'cortex_red_proposal',
    null::uuid,
    jsonb_build_object('pid', p_pid, 'status', p_status, 'nota', left(trim(coalesce(p_nota, '')), 500))
  );
end;
$$;

grant execute on function public.cortex_proposal_mark_status(text,text,text) to authenticated;
