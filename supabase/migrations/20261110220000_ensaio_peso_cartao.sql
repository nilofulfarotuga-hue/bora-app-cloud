-- Missão fechar-tudo-2026-11-10, Bloco C — ENSAIO da diferença de peso no cartão (modo de teste).
-- Autorizações do Danilo para a funcionalidade: 26/10 e 02/11 ("Autorizo"), 10/11 ("8 tem que fazer").
--
-- O que cria (nada aqui mexe em pedidos, saldos nem valores cobrados):
--   1) public.ensaio_peso_cartao — onde a Edge cobrar-diferenca-peso grava cada ensaio
--      (caso, pagamento original de teste, cobrança extra de teste, resultado, erro). RLS ligada:
--      só o admin lê; só o servidor escreve.
--   2) public.admin_ensaio_peso_cartao(p_caso) — o botão do painel. Só admin. Faz net.http_post à
--      Edge com a chave de servidor do cofre (a mesma porta que o talão usa para a cobrança real) e
--      o corpo { ensaio: true, caso }. A Edge usa SÓ a chave de teste da empresa, nunca a real.
-- Casos: a_mais | a_menos | recusado | pede_autenticacao. Ver
-- docs/propostas/fechar-tudo-2026-11-10/C_LEIA-ME.md.

create table if not exists public.ensaio_peso_cartao (
  id                   uuid primary key default gen_random_uuid(),
  caso                 text not null,
  estado               text not null check (estado in ('ok', 'falhou', 'erro')),
  esperado             text,
  resultado            text,
  valor_original_cents integer,
  diferenca_cents      integer,
  pi_original          text,
  pi_extra             text,
  conta                text not null default 'empresa',
  erro                 text,
  detalhe              jsonb not null default '{}'::jsonb,
  pedido_por           uuid,
  criado_em            timestamptz not null default now()
);
comment on table public.ensaio_peso_cartao is
  'Ensaios em MODO DE TESTE da diferença de peso no cartão (Edge cobrar-diferenca-peso, { ensaio: true }). '
  'Não são pedidos nem dinheiro real. estado: ok (deu o esperado) | falhou (deu outra coisa) | erro (não correu). '
  'resultado: cartao_cobrado | carteira | bora_assume. Missão fechar-tudo-2026-11-10, Bloco C.';
create index if not exists idx_ensaio_peso_cartao_criado on public.ensaio_peso_cartao (criado_em desc);

alter table public.ensaio_peso_cartao enable row level security;
revoke all on public.ensaio_peso_cartao from public, anon, authenticated;
grant select on public.ensaio_peso_cartao to authenticated;
drop policy if exists ensaio_peso_cartao_admin_le on public.ensaio_peso_cartao;
create policy ensaio_peso_cartao_admin_le on public.ensaio_peso_cartao
  for select to authenticated using (public.is_admin());

create or replace function public.admin_ensaio_peso_cartao(p_caso text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_key    text;
  v_pedido bigint;
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_caso is null or p_caso not in ('a_mais', 'a_menos', 'recusado', 'pede_autenticacao') then
    return jsonb_build_object('ok', false, 'erro', 'caso_invalido');
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  if coalesce(v_url, '') = '' or coalesce(v_key, '') = '' then
    return jsonb_build_object('ok', false, 'erro', 'cofre_sem_url_ou_chave');
  end if;

  select net.http_post(
    url := v_url || '/functions/v1/cobrar-diferenca-peso',
    body := jsonb_build_object('ensaio', true, 'caso', p_caso, 'pedido_por', auth.uid()),
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
    timeout_milliseconds := 60000
  ) into v_pedido;

  return jsonb_build_object('ok', true, 'caso', p_caso, 'pedido_net', v_pedido);
end
$$;
comment on function public.admin_ensaio_peso_cartao(text) is
  'Painel admin → Ajustes de peso → Ensaio do cartão: pede à Edge cobrar-diferenca-peso um ensaio em modo de teste '
  '(a_mais | a_menos | recusado | pede_autenticacao). Só admin. O resultado aparece em ensaio_peso_cartao.';
revoke all on function public.admin_ensaio_peso_cartao(text) from public, anon;
grant execute on function public.admin_ensaio_peso_cartao(text) to authenticated;

-- Prova depois de aplicar (só leitura):
--   select relrowsecurity from pg_class where oid = 'public.ensaio_peso_cartao'::regclass;          -- true
--   select has_function_privilege('anon', 'public.admin_ensaio_peso_cartao(text)', 'execute');      -- false
--   select caso, estado, esperado, resultado, erro from public.ensaio_peso_cartao order by criado_em desc limit 8;
