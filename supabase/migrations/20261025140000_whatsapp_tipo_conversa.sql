-- Missão livro-comum-2026-10-23 (Bloco 6): WhatsApp — SÓ O ESQUELETO. Nada se liga.
-- O número da loja também é do Danilo e há conversas pessoais lá: antes de qualquer resposta automática
-- é preciso saber de que tipo é cada conversa. Por defeito ninguém é tratado como loja.
alter table public.whatsapp_contacts
  add column if not exists tipo_conversa text not null default 'incerto';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'whatsapp_contacts_tipo_conversa_check') then
    alter table public.whatsapp_contacts
      add constraint whatsapp_contacts_tipo_conversa_check check (tipo_conversa in ('loja', 'pessoal-danilo', 'incerto'));
  end if;
end $$;

comment on column public.whatsapp_contacts.tipo_conversa is
  'loja / pessoal-danilo / incerto (defeito). Só conversas "loja" poderão um dia ter rascunho automático; pessoal nunca. Editável no painel admin (WhatsApp).';

-- Ponto de encaixe do futuro "modo rascunho" (a resposta vai ao Telegram do Danilo e ele diz "manda"): DESLIGADO.
insert into public.whatsapp_settings (key, value, updated_at)
values ('modo_rascunho_ligado', 'false'::jsonb, now())
on conflict (key) do nothing;
