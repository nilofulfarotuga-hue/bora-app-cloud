-- PROPOSTA (missão app-15-11, 15/11/2026; varredura 9166 n.º 6). Nome sugerido:
-- 20261115125000_reconciler_achados_sem_repetidos. Aplica a Claude.ai.
--
-- MEDIDO (SELECT 15/11 ~12:40, Postgres 17.6): a tabela de achados do vigia de pagamentos
-- (payment_reconciliation_findings) tem a regra UNIQUE (kind, pi_id, entity_id). Quando o achado não
-- tem pagamento Stripe (pi_id vazio), o Postgres trata dois vazios como DIFERENTES e a regra não
-- impede repetir: 44 linhas sem pi_id, 4 casos repetidos, 40 linhas a mais. E cada repetido conta como
-- "achado novo" e manda alerta.
--
-- O QUE FAZ: (1) guarda as linhas repetidas em bkp_payment_reconciliation_findings_20261115;
-- (2) tira as repetidas, ficando a mais antiga de cada caso; (3) troca a regra por
-- UNIQUE NULLS NOT DISTINCT (kind, pi_id, entity_id): dois vazios passam a contar como iguais.
-- Não toca em pagamentos, pedidos nem dinheiro: só na tabela de achados do vigia.
-- A outra metade do n.º 6 (o filtro das limpezas) está no código da Edge payments-reconciler,
-- commit desta missão: publicar a Edge depois disto.

create table if not exists public.bkp_payment_reconciliation_findings_20261115 as
  select f.* from public.payment_reconciliation_findings f
   where f.pi_id is null
     and exists (select 1 from public.payment_reconciliation_findings g
                  where g.pi_id is null and g.kind = f.kind and g.entity_id = f.entity_id and g.id <> f.id);
alter table public.bkp_payment_reconciliation_findings_20261115 enable row level security;
revoke all on public.bkp_payment_reconciliation_findings_20261115 from public, anon, authenticated;

delete from public.payment_reconciliation_findings f
 where f.pi_id is null
   and exists (select 1 from public.payment_reconciliation_findings g
                where g.pi_id is null and g.kind = f.kind and g.entity_id = f.entity_id
                  and (g.run_at, g.id) < (f.run_at, f.id));

alter table public.payment_reconciliation_findings
  drop constraint if exists payment_reconciliation_findings_kind_pi_id_entity_id_key;
alter table public.payment_reconciliation_findings
  add constraint payment_reconciliation_findings_kind_pi_id_entity_id_key
  unique nulls not distinct (kind, pi_id, entity_id);

-- Prova dentro da migração.
do $$
declare v int;
begin
  select count(*) into v from (
    select kind, entity_id from public.payment_reconciliation_findings
     where pi_id is null group by 1, 2 having count(*) > 1) x;
  if v > 0 then raise exception 'ainda ha % casos repetidos', v; end if;
end $$;
-- Depois: select count(*) from public.bkp_payment_reconciliation_findings_20261115;  -- 44 (as 4 de origem + 40)
--         e o upsert da Edge (onConflict kind,pi_id,entity_id) continua a funcionar: a regra tem o mesmo nome e colunas.
