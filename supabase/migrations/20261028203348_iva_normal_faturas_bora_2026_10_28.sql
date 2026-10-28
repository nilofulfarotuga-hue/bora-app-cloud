create table if not exists public.bkp_fn_admin_monthly_closeout_20261028 as
  select now() as guardado_em, 'admin_monthly_closeout(integer,integer)'::text as assinatura,
         pg_get_functiondef('public.admin_monthly_closeout(integer,integer)'::regprocedure) as definicao;
alter table public.bkp_fn_admin_monthly_closeout_20261028 enable row level security;
create or replace function public._bora_invoice_iva_texto() returns trigger language plpgsql set search_path = public as $$
begin
  if new.data is not null and new.data >= date '2026-11-01'
     and (new.iva is null or new.iva = 'IVA — regime de isenção (art. 53.º CIVA), M10') then
    new.iva := 'IVA 23% incluído — regime normal';
  end if;
  return new;
end $$;
revoke all on function public._bora_invoice_iva_texto() from public, anon, authenticated;
drop trigger if exists trg_bora_invoice_iva_texto on public.bora_invoices_pending;
create trigger trg_bora_invoice_iva_texto before insert or update of data, iva on public.bora_invoices_pending
  for each row execute function public._bora_invoice_iva_texto();
do $$
declare
  v_def text := pg_get_functiondef('public.admin_monthly_closeout(integer,integer)'::regprocedure);
  v_old text := '''Regime simplificado, IVA isento ao abrigo do art. 53.º do CIVA (M10).''';
  v_new text := '''IVA: até outubro de 2026, isenção do art. 53.º do CIVA (M10); a partir de novembro de 2026, regime normal (trimestral), com IVA 23% incluído nas faturas da Bora.''';
  v_n int;
begin
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'admin_monthly_closeout: esperava 1 ocorrencia, achei %', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $$;
