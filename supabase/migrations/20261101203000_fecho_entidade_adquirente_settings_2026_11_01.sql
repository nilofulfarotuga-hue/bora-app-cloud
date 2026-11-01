-- 01/11/2026 (missão contabilista-2026-11-01) — DADOS DO ADQUIRENTE NO FECHO MENSAL.
-- Porquê: o email de fecho de 01/11 (Edge Function monthly-partner-statement, RPC
-- driver_monthly_invoice_summary) disse aos estafetas "Cliente: Consumidor final". Está errado: o
-- recibo verde do estafeta é passado a quem lhe paga — em outubro/2026 o Danilo em nome individual;
-- a partir de dezembro/2026 (cobranças de novembro) a sociedade. Em vez de escrever o nome no código,
-- a função lê estas chaves de platform_settings e o painel admin pode trocá-las quando a empresa entrar.
-- Não mexe em preços nem em dinheiro: só textos que entram no email e no resumo do recibo.

insert into public.platform_settings (key, value, description, category, is_secret) values
  ('fecho_entidade_tipo',   to_jsonb('individual'::text),
   'Fecho mensal: quem é o adquirente dos recibos verdes dos prestadores — individual (Danilo em nome próprio) ou sociedade (Danilo Fulfaro da Silva - Unipessoal Lda). Trocar para sociedade quando a empresa começar a cobrar.', 'fecho', false),
  ('fecho_entidade_nome',   to_jsonb('Danilo Fulfaro da Silva'::text),
   'Fecho mensal: nome do adquirente que vai no recibo verde dos prestadores.', 'fecho', false),
  ('fecho_entidade_nif',    to_jsonb('322151171'::text),
   'Fecho mensal: NIF do adquirente que vai no recibo verde dos prestadores (individual 322151171; sociedade 519686233).', 'fecho', false),
  ('fecho_entidade_morada', to_jsonb('Rua do Torreão 14, 6300-610 Guarda'::text),
   'Fecho mensal: morada do adquirente que vai no recibo verde dos prestadores.', 'fecho', false),
  ('fecho_contabilista_email', to_jsonb(''::text),
   'Fecho mensal automático (dia 1, 08:00): email do contabilista (Hugo Carvalho, DC Consultores) que recebe o relatório do mês. Vazio = não envia ao contabilista, só ao Danilo.', 'fecho', false),
  ('fecho_contabilista_nome', to_jsonb('Hugo Carvalho'::text),
   'Fecho mensal automático: nome do contabilista no email.', 'fecho', false),
  ('fecho_contabilista_ativo', to_jsonb(false),
   'Liga o envio automático do relatório mensal ao contabilista no dia 1 às 08:00 (Edge Function fecho-mensal-contabilista). Desligado até o Danilo dizer "liga".', 'fecho', false)
on conflict (key) do update
  set description = excluded.description, category = excluded.category, updated_at = now()
  -- os valores existentes não são tocados: se já houver dados, mandam os do painel
;
