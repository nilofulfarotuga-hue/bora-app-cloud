-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115151213); antes não estava em supabase/migrations.
-- Remendo no sítio: lê a definição atual de public.fn_reembolso_cancelado_pelo_sistema, guarda-a em
-- bkp_fn_reembolso_cancelado_pelo_sistema_20261115 e troca a linha da guarda. Abaixo, o texto exato que correu.

do $$
declare
  v_def text;
  v_old text := $q$if new.cancellation_initiator is null or new.cancellation_initiator::text <> 'system' then return new; end if;$q$;
  v_new text := $q$-- 15/11/2026 (autorizo do Danilo 15:15): pedido RECUSADO pela loja tambem e reembolsado sozinho, venha de quem vier
  if new.status::text <> 'rejected'
     and (new.cancellation_initiator is null or new.cancellation_initiator::text <> 'system') then return new; end if;$q$;
begin
  v_def := pg_get_functiondef('public.fn_reembolso_cancelado_pelo_sistema'::regproc);
  create table if not exists public.bkp_fn_reembolso_cancelado_pelo_sistema_20261115 as select now() as guardado_em, v_def as def;
  alter table public.bkp_fn_reembolso_cancelado_pelo_sistema_20261115 enable row level security;
  if position(v_old in v_def) = 0 then raise exception 'linha da guarda nao encontrada'; end if;
  v_def := replace(v_def, v_old, v_new);
  execute v_def;
end $$;
