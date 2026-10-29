-- ADENDO 4 — parte B: quem pode VER duas fotos do balde privado order-photos.
--
--  1) Foto de prova da entrega: o cliente dono do pedido passa a vê-la
--     (hoje só o admin, o estafeta e a loja viam). A foto fica em
--     <uid do estafeta>/entrega_<pedido>_<hora>.jpg e o endereço dela está
--     em orders.foto_entrega_url.
--  2) Foto do prato numa avaliação: quem avaliou, o dono da loja avaliada e
--     qualquer cliente com sessão (só se a avaliação for pública e não estiver
--     assinalada como imprópria). O endereço está em ratings.photo_url.
--
-- So leitura. Nenhuma politica de escrita nova (o envio e feito pela funcao
-- upload-order-photo, que ja existe).

drop policy if exists order_photos_select_entrega_cliente on storage.objects;
create policy order_photos_select_entrega_cliente
  on storage.objects for select to authenticated
  using (
    bucket_id = 'order-photos'
    and name like '%entrega\_%'
    and exists (
      select 1 from public.orders o
       where o.user_id = auth.uid()
         and o.foto_entrega_url is not null
         and o.foto_entrega_url = any (array[
               'order-photos/' || objects.name,
               objects.name,
               'https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/order-photos/' || objects.name
             ])
    )
  );

drop policy if exists order_photos_select_avaliacao on storage.objects;
create policy order_photos_select_avaliacao
  on storage.objects for select to authenticated
  using (
    bucket_id = 'order-photos'
    and name like '%avaliacao\_%'
    and exists (
      select 1 from public.ratings r
       where r.photo_url is not null
         and r.photo_url = any (array[
               'order-photos/' || objects.name,
               objects.name,
               'https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/order-photos/' || objects.name
             ])
         and (
               r.rater_user_id = auth.uid()
            or (r.is_private is not true and r.flagged_inappropriate is not true)
            or exists (select 1 from public.restaurants rest
                        where rest.id = r.subject_id
                          and r.subject_type = 'partner'
                          and rest.user_ = auth.uid())
         )
    )
  );
