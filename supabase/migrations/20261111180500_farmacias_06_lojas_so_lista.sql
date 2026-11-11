-- =============================================================================
-- farmacias-2026-11-11 · 06 · Ligar as duas farmácias SÓ para as contas do Danilo (dados)
-- Ordem do Danilo 11/11 15:18: "deixar liberado só na minha conta. Mais para ninguém."
-- Corre DEPOIS de 01 a 05. Lojas criadas pelo PC a 11/11 com approval_status='rejected' (escondidas).
--
-- Conformidade (nome legal, NIF, IBAN, autocertificação): as lojas ficam escondidas (so_lista_permissao),
-- por isso usa-se o escape previsto bora.forcar_ativacao SÓ nesta transação. ANTES de abrir ao público
-- (admin_farmacia_abrir) a conformidade tem de estar completa — o gatilho volta a exigi-la nessa altura.
-- =============================================================================

select set_config('bora.forcar_ativacao', '1', true);

-- 1) Lista de permissão primeiro (assim, no instante em que ficam aprovadas, já estão escondidas).
update public.restaurants
   set so_lista_permissao = true
 where id in ('farmacia-se-guarda', 'farmacia-teixeira-guarda');

insert into public.loja_lista_permissao (restaurant_id, user_id, motivo)
select r.id, u.id, 'Contas do Danilo — demonstração na farmácia (11/11/2026)'
  from (values ('farmacia-se-guarda'), ('farmacia-teixeira-guarda')) as r(id)
  cross join (values ('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7'::uuid),
                     ('c9fccf85-03ee-4efc-83bf-613f211a78ff'::uuid)) as u(id)
 where exists (select 1 from auth.users a where a.id = u.id)
on conflict do nothing;

-- 2) Ligar: aprovadas, ativas, a aceitar pedidos (de demonstração), receita só para a lista.
update public.restaurants
   set approval_status = 'approved',
       approved_at = coalesce(approved_at, now()),
       rejection_reason = null,
       is_active_admin = true,
       coming_soon = false,
       pharmacy_prescription_mode = 'so_lista',
       partner_extra_commission_pct = 0.10,
       partner_extra_commission_starts_at = null
 where id in ('farmacia-se-guarda', 'farmacia-teixeira-guarda')
   and so_lista_permissao;

-- Verificação (tem de dar 2 linhas com so_lista_permissao=true e 4 linhas na lista):
-- select id, approval_status, is_active_admin, coming_soon, so_lista_permissao, pharmacy_prescription_mode,
--        partner_extra_commission_pct, partner_extra_commission_starts_at from restaurants where id like 'farmacia-%-guarda';
-- select restaurant_id, user_id from loja_lista_permissao order by 1, 2;
