-- 01/11/2026 (missão seguranca-05, bloco 5) — fechar a inserção DIRETA de pedidos pelo cliente.
--
-- PORQUÊ: a política orders_insert_client (INSERT, {authenticated}, with_check auth.uid() = user_id)
-- deixava qualquer conta inserir um pedido CRU em /rest/v1/orders com os campos que quisesse:
-- status='delivered', payment_status='paid', price=0,01, driver_earnings=50, restaurant_id de qualquer
-- loja... saltando o create_order (preço do servidor, carteira, tokens, limites de distância/dinheiro).
--
-- COMO A APP CRIA PEDIDOS (lido 01/11): SÓ pela RPC create_order(jsonb) — lib/stores/order_store.dart:994
-- (`supabase.rpc('create_order', ...)`) e, do lado do servidor, finalize-order-from-intent/index.ts:91
-- (`admin.rpc('create_order', ...)`). Não há nenhum `.from('orders').insert(` em lib/, nas Edge Functions,
-- em web/ nem em ferramentas/. As únicas funções SQL que fazem INSERT INTO orders são create_order e
-- partner_chamar_estafeta, ambas SECURITY DEFINER com dono postgres (rolbypassrls = true), logo
-- nenhuma depende desta política. Prova nos dados: os 79 pedidos dos últimos 60 dias têm todos
-- payment_buffer_total e platform_commission preenchidos (assinatura do create_order).
--
-- SOLUÇÃO MENOS INVASIVA: a política passa a with_check (false) — igual à orders_insert_partner
-- que já existe assim. Nada muda no checkout, na app ou nas Edge Functions. Não se apaga a política
-- (fica o nome e a história; voltar atrás = alter policy ... with check (auth.uid() = user_id)).
-- Alternativa rejeitada: gatilho a recalcular o total — mais código numa zona 🔴 e sem ganho, porque
-- o cliente não tem nenhum caminho legítimo de INSERT direto.
--
-- Mudança na app Flutter: NENHUMA.
-- Idempotente: ALTER POLICY com o mesmo with_check não falha; guardado com DO para o caso de a política
-- ter sido removida entretanto.

do $mig$
begin
  if exists (select 1 from pg_policies where schemaname='public' and tablename='orders' and policyname='orders_insert_client') then
    alter policy orders_insert_client on public.orders with check (false);
  else
    create policy orders_insert_client on public.orders for insert to authenticated with check (false);
  end if;
end
$mig$;

comment on policy orders_insert_client on public.orders is
  '01/11/2026 seguranca-05: fechada (false). Pedidos nascem só pela RPC create_order (definer) ou pelo servidor.';

-- PROVA (correr depois de aplicar):
--   select policyname, cmd, roles::text, with_check from pg_policies
--     where schemaname='public' and tablename='orders' and cmd='INSERT';
--   -- esperado: orders_insert_client → with_check = 'false' ; orders_insert_partner → 'false'
--   -- Testes com set local role: supabase/tests/seguranca_05_2026_11_01_prova.sql (bloco B).
