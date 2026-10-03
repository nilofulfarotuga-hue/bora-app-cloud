-- Passo 2: aprovação real, autenticada, de uma proposta zona-vermelha do Córtex.
-- Diferença-chave vs. as 22 tentativas recusadas: a autoridade não é texto — é o JWT real de
-- app_metadata.role='admin' (a mesma identidade protegida por trg_protect_admin_app_role em
-- auth.users), verificado no servidor por _admin_op_guard(). Nenhum agente/executor tem esse JWT.
--
-- A RPC só MARCA (status, quem, quando, audit id). NUNCA executa nada. A criação da ordem real
-- na fila é um passo SEPARADO (hermes-cortex-proposals-sync.sh, passo 2), e mesmo essa ordem
-- passa pela zona_vermelha() própria do carteiro.sh, que reavalia o TEXTO da tarefa a cada
-- pickup — independente do que a ordem diga em `zona:`. Conteúdo de dinheiro volta a exigir
-- humano (Telegram "vai <id>") mesmo depois de aprovado aqui.

alter table public.cortex_red_proposals
  drop constraint if exists cortex_red_proposals_status_check;

alter table public.cortex_red_proposals
  add constraint cortex_red_proposals_status_check
  check (status in ('nova', 'vista', 'decidida_fora', 'aprovada_danilo'));

alter table public.cortex_red_proposals
  add column if not exists ordem_criada_em timestamptz,
  add column if not exists ordem_ficheiro text;

-- RPC 1: aprovar (admin, UM pid por chamada). Só marca — nunca executa.
create or replace function public.cortex_proposal_approve(p_pid text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_admin_id uuid;
  v_admin_email text;
  v_log_id uuid;
  v_ts text;
begin
  perform public._admin_op_guard();
  v_admin_id := auth.uid();
  v_admin_email := coalesce(auth.jwt() ->> 'email', auth.jwt() -> 'user_metadata' ->> 'email');
  v_ts := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

  update public.cortex_red_proposals
     set status = 'aprovada_danilo',
         revisada_por = v_admin_id,
         revisada_por_email = v_admin_email,
         revisada_em = now()
   where pid = p_pid and status in ('nova', 'vista');

  if not found then
    raise exception 'proposta_nao_encontrada_ou_ja_decidida';
  end if;

  v_log_id := public.log_admin_action(
    'cortex_proposal_approve',
    'cortex_red_proposal',
    null::uuid,
    jsonb_build_object('pid', p_pid)
  );

  update public.cortex_red_proposals
     set nota_revisao = 'aprovada pelo Danilo via Central em ' || v_ts || ', audit id ' || v_log_id::text
   where pid = p_pid;

  return jsonb_build_object('pid', p_pid, 'audit_id', v_log_id, 'aprovada_em', v_ts);
end;
$$;

grant execute on function public.cortex_proposal_approve(text) to authenticated;

-- RPC 2: cortex_proposal_mark_status estendida — agora também aceita reverter para 'nova'
-- (reversível, auditado). Bloqueia o revert se a ordem já foi despachada para a fila (reverter
-- aqui não cancela trabalho já em curso — isso precisaria de ação manual na fila).
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
declare v_ordem_criada timestamptz;
begin
  perform public._admin_op_guard();

  if p_status not in ('vista', 'decidida_fora', 'nova') then
    raise exception 'status_invalido: % (permitido: vista, decidida_fora, nova)', p_status;
  end if;

  select ordem_criada_em into v_ordem_criada
    from public.cortex_red_proposals where pid = p_pid;

  if p_status = 'nova' and v_ordem_criada is not null then
    raise exception 'ordem_ja_despachada_em_%: reverter aqui nao cancela a ordem ja criada na fila',
      to_char(v_ordem_criada, 'YYYY-MM-DD HH24:MI');
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

  perform public.log_admin_action(
    'cortex_proposal_mark_status',
    'cortex_red_proposal',
    null::uuid,
    jsonb_build_object('pid', p_pid, 'status', p_status, 'nota', left(trim(coalesce(p_nota, '')), 500))
  );
end;
$$;

-- RPC 3: leitura anon MÍNIMA para o cron da VPS — só pids aprovados e ainda não despachados.
-- Deliberadamente NUNCA devolve o texto da tarefa (mesmo princípio de red_queue_watermark:
-- "só agregado/id, sem conteúdo"). O script busca o texto no proposals.jsonl LOCAL (mesmo host),
-- nunca pela rede — a chave anon não consegue ler conteúdo de proposta nenhuma.
create or replace function public.cortex_list_approved_pids()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object('pid', pid)), '[]'::jsonb)
    from public.cortex_red_proposals
   where status = 'aprovada_danilo' and ordem_criada_em is null;
$$;

grant execute on function public.cortex_list_approved_pids() to anon;

-- RPC 4: confirmação anon de que a ordem foi criada — só marca ordem_criada_em/ordem_ficheiro,
-- idempotente (WHERE ordem_criada_em IS NULL), não aceita nenhum outro campo.
create or replace function public.cortex_mark_ordem_criada(p_pid text, p_ordem_ficheiro text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if p_pid is null or p_pid !~ '^prop-[0-9a-f]{6,16}$' then
    raise exception 'pid_invalido';
  end if;

  update public.cortex_red_proposals
     set ordem_criada_em = now(),
         ordem_ficheiro = left(p_ordem_ficheiro, 300)
   where pid = p_pid and status = 'aprovada_danilo' and ordem_criada_em is null;
end;
$$;

grant execute on function public.cortex_mark_ordem_criada(text, text) to anon;
