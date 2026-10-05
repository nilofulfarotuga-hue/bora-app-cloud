-- parte a) da migration 20261004120000_secretario_virtual.sql que ficou por aplicar (Danilo autorizou 05/10)
alter table public.prospects_presenca drop constraint if exists prospects_presenca_cliente_tipo_check;
alter table public.prospects_presenca add constraint prospects_presenca_cliente_tipo_check
  check (cliente_tipo is null or cliente_tipo = any (array['site','parceiro-bora','funcionario-digital','os-dois','secretario-virtual']));
