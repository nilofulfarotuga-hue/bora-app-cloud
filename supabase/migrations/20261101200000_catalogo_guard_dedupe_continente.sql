-- catalogo-2026-11-01 (ordem do Danilo 01/11/2026 19:56: "uns 300 produtos repetidos no
-- Continente... arrumar tudo"). Aplicada em prod via MCP apply_migration
-- ("catalogo_guard_dedupe_continente_20261101").
--
-- Diagnóstico: o Continente tinha dois catálogos sobrepostos — 'cont-<sku>' (importação
-- estática de 07/06, nome com tamanho "(emb. 200 gr)", foto Glovo) e 'cnt-<sku>' (cron
-- semanal update-products, nome oficial sem tamanho, foto oficial, preço vivo). 2760 SKUs
-- estavam nos dois. A migração de 11/06 apagou os cnt- com par, mas o cron voltou a
-- inseri-los (12/10: 1273 novos). Esta guarda torna a limpeza permanente:
-- 1) Produto novo 'cnt-<sku>' esconde o gémeo 'cont-<sku>' (mesmo SKU).
-- 2) O cron (service_role) não volta a ligar um produto escondido como duplicado nesta
--    missão (removal_reason 'duplicado ... (catalogo-2026-11-01...)'); o admin
--    (authenticated) continua a poder ligar à mão.
-- 3) Continente cnt-: quando há 'unit' (tamanho copiado do gémeo cont-), o nome mostra o
--    tamanho no fim "(200 gr)" mesmo depois de o cron reescrever o nome. Não se aplica a
--    peças ao quilo (peso_medio_kg > 0, §59) nem a unit '1 un'.
-- Ordem dos BEFORE triggers (alfabética): este corre antes de set_search_normalized.
create or replace function public.fn_products_catalogo_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_role text;
  v_unit text;
begin
  -- 3) nome com tamanho (só Continente cnt-, só quando não é peça ao quilo)
  if new.restaurant_id = 'continente-guarda' and new.id like 'cnt-%'
     and coalesce(new.unit,'') <> '' and new.unit <> '1 un'
     and coalesce(new.peso_medio_kg, 0) <= 0 then
    v_unit := new.unit;
    if new.name not like '%(' || v_unit || ')' then
      new.name := regexp_replace(rtrim(coalesce(new.name,'')), '\s*\([^()]*\)\s*$', '') || ' (' || v_unit || ')';
    end if;
  end if;

  if tg_op = 'INSERT' then
    -- 1) gémeo cont- do mesmo SKU fica escondido
    if new.id like 'cnt-%' and new.restaurant_id = 'continente-guarda' then
      update public.products
         set is_available = false,
             removal_reason = 'duplicado cnt/cont mesmo SKU (catalogo-2026-11-01, trigger)'
       where id = 'cont-' || substring(new.id from 5)
         and restaurant_id = 'continente-guarda'
         and is_available = true;
    end if;
    return new;
  end if;

  -- 2) o cron não ressuscita duplicados escondidos nesta missão
  if old.is_available = false and new.is_available = true
     and coalesce(old.removal_reason,'') like 'duplicado%(catalogo-2026-11-01%'
     and new.removal_reason is not distinct from old.removal_reason then
    v_role := coalesce(
      nullif(current_setting('request.jwt.claim.role', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'));
    if v_role = 'service_role' then
      new.is_available := false;
    end if;
  end if;
  return new;
end;
$$;

create or replace trigger trg_products_catalogo_guard
before insert or update of name, unit, is_available on public.products
for each row execute function public.fn_products_catalogo_guard();

-- Dados (feitos por MCP na mesma missão, registo em public.catalogo_dedupe_log_20261101;
-- backup integral em public.bkp_products_20261101):
--   * 2760 'cont-<sku>' com gémeo 'cnt-<sku>' → is_available=false,
--     removal_reason='duplicado cnt/cont mesmo SKU (catalogo-2026-11-01)'.
--   * products.unit dos cnt- preenchido com o tamanho "(emb. ...)" do gémeo cont-;
--     2180 nomes passaram a acabar em "(<unit>)".
