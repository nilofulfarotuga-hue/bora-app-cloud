-- tvde-conformidade-lei-59-2026 · FASE 1 (dados) — 2026-09-30
-- Lei 45/2018 na versão da Lei 59/2026. Tudo ADITIVO: tabelas novas, colunas
-- novas com default, interruptores DESLIGADOS. Nada muda preço, comissão ou
-- ganho do motorista.
--
-- Regra dos gémeos (o que JÁ existia e continua a ser a fonte):
--   motorista_ficha_legal  -> número/validade do CMTVDE, carta, seguro,
--                             inspeção e dístico declarados pelo motorista.
--   tvde_driver_documents  -> ficheiros de documentos do motorista (bucket
--                             privado driver-documents, URLs assinados).
--   drivers                -> nome, foto, matrícula, marca/modelo, cor.
-- O que é novo vive aqui.

-- ── Interruptores e valores (categoria tvde_conformidade) ───────────────────
insert into public.platform_settings (key, value, description, category) values
  ('tvde_compliance_enforce', 'false'::jsonb, 'INTERRUPTOR MESTRE da conformidade TVDE (Lei 45/2018 rev. Lei 59/2026). Desligado = nenhuma regra nova muda o comportamento da app.', 'tvde_conformidade'),
  ('tvde_compliance_block', 'false'::jsonb, 'Art. 14: bloquear motorista (ficar online e receber ofertas) com CMTVDE, operador, veículo, seguro ou inspeção caducados ou em falta. Só vale com o mestre ligado.', 'tvde_conformidade'),
  ('tvde_work_limit_enforce', 'false'::jsonb, 'Art. 13: limite de horas de serviço numa janela móvel de 24 h. Ao chegar ao limite deixa de receber ofertas (acaba a corrida em curso). Só vale com o mestre ligado.', 'tvde_conformidade'),
  ('tvde_electronic_payment_only', 'false'::jsonb, 'Art. 15.º n.º 7: só pagamento eletrónico no TVDE (esconde o dinheiro e o servidor recusa payment_method=cash). Entregas não mudam. Só vale com o mestre ligado.', 'tvde_conformidade'),
  ('tvde_driver_rates_client_disabled', 'false'::jsonb, 'Art. 19.º n.º 5: o motorista deixa de avaliar o passageiro (ecrã escondido; o servidor ignora a avaliação). Dados antigos ficam. Só vale com o mestre ligado.', 'tvde_conformidade'),
  ('tvde_pref_matching_enforce', 'false'::jsonb, 'Art. 19.º n.º 1 i) e art. 6: respeitar no despacho o pedido de motorista que fala português e de carro adaptado a mobilidade reduzida. Só vale com o mestre ligado.', 'tvde_conformidade'),
  ('tvde_client_options_enabled', 'false'::jsonb, 'Mostrar ao cliente as opções "motorista que fala português" e "mobilidade reduzida" no pedido de viagem.', 'tvde_conformidade'),
  ('tvde_fixed_price_option_enabled', 'false'::jsonb, 'Opção de preço fixo fechado antes de pedir. PROPOSTA — mexe no valor cobrado; só se liga depois do "vai" do Danilo.', 'tvde_conformidade'),
  ('tvde_invoicing_enabled', 'false'::jsonb, 'Art. 15.º n.º 8: emitir fatura por software certificado pela AT no fim da viagem. Desligado = só "Resumo da viagem".', 'tvde_conformidade'),
  ('tvde_invoicing_provider', to_jsonb('stub'::text), 'Fornecedor de faturação certificada: stub | invoicexpress | moloni | vendus.', 'tvde_conformidade'),
  ('tvde_imt_integration_enabled', 'false'::jsonb, 'Art. 17.º-A n.º 2 a): ligação às bases de dados do IMT. Aguarda especificação oficial.', 'tvde_conformidade'),
  ('tvde_amt_report_enabled', 'true'::jsonb, 'Relatório mensal AMT (dia 1): só calcula e guarda, não envia nada.', 'tvde_conformidade'),
  ('tvde_iva_discriminar', 'false'::jsonb, 'Mostrar IVA discriminado ao cliente. Só ligar com a empresa registada (antes disso seria informação falsa).', 'tvde_conformidade'),
  ('tvde_work_limit_hours', '10'::jsonb, 'Art. 13: horas máximas de serviço em 24 h, somando todas as plataformas.', 'tvde_conformidade'),
  ('tvde_intermediacao_teto_pct', '25'::jsonb, 'Art. 15.º n.º 3: teto da taxa de intermediação em % do valor da viagem.', 'tvde_conformidade'),
  ('tvde_amt_contribuicao_pct', '5'::jsonb, 'Contribuição de Regulação e Supervisão da AMT, % da taxa de intermediação.', 'tvde_conformidade'),
  ('tvde_iva_transporte_pct', '6'::jsonb, 'Taxa de IVA do transporte de passageiros (para discriminar na fatura).', 'tvde_conformidade'),
  ('tvde_vehicle_max_age_years', '10'::jsonb, 'Idade máxima do veículo TVDE em anos (desde a 1.ª matrícula).', 'tvde_conformidade'),
  ('tvde_vehicle_max_age_ev_years', '12'::jsonb, 'Idade máxima do veículo TVDE elétrico em anos.', 'tvde_conformidade'),
  ('tvde_vehicle_max_seats', '9'::jsonb, 'Lotação máxima do veículo TVDE (incluindo o condutor).', 'tvde_conformidade'),
  ('tvde_carta_min_anos', '3'::jsonb, 'Anos mínimos de carta B do motorista TVDE.', 'tvde_conformidade'),
  ('tvde_docs_alert_days', '[30, 7]'::jsonb, 'Dias antes da validade em que se avisa motorista e admin.', 'tvde_conformidade'),
  ('tvde_mobilidade_espera_min', '15'::jsonb, 'Art. 6: minutos até informar o cliente de alternativas quando não há carro adaptado.', 'tvde_conformidade'),
  ('tvde_retencao_anos', '2'::jsonb, 'Retenção mínima (anos) de tempos de trabalho, queixas e registos de conformidade.', 'tvde_conformidade'),
  ('plataforma_denominacao', to_jsonb(''::text), 'Denominação social do operador de plataforma (vazio = "em constituição").', 'legal'),
  ('plataforma_sede', to_jsonb(''::text), 'Sede do operador de plataforma (vazio = "em constituição").', 'legal'),
  ('plataforma_marca', to_jsonb('Bora'::text), 'Marca comercial da plataforma TVDE.', 'legal'),
  ('plataforma_email_contacto', to_jsonb('boraappbora@gmail.com'::text), 'Email de contacto e de reclamações da plataforma.', 'legal'),
  ('livro_reclamacoes_url', to_jsonb('https://www.livroreclamacoes.pt/Inicio/'::text), 'Livro de Reclamações Eletrónico (link oficial).', 'legal')
on conflict (key) do nothing;

-- Um interruptor de conformidade só vale com o mestre ligado.
create or replace function public.tvde_conf_ativa(p_key text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((public.get_setting('tvde_compliance_enforce') #>> '{}')::boolean, false)
     and coalesce((public.get_setting(p_key) #>> '{}')::boolean, false)
$$;
revoke all on function public.tvde_conf_ativa(text) from public, anon;
grant execute on function public.tvde_conf_ativa(text) to authenticated;

-- ── Operadores TVDE (os motoristas entram POR um operador) ──────────────────
create table if not exists public.tvde_operators (
  id uuid primary key default gen_random_uuid(),
  denominacao text not null,
  nipc text not null check (nipc ~ '^[0-9]{9}$'),
  licenca_imt_numero text,
  licenca_imt_validade date,
  email text,
  telefone text,
  sede text,
  estado text not null default 'pendente'
    check (estado in ('pendente','aprovado','suspenso','rejeitado')),
  estado_motivo text,
  contrato_path text,
  contrato_assinado_em date,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  decidido_por uuid,
  decidido_em timestamptz,
  unique (nipc)
);
alter table public.tvde_operators enable row level security;
create policy tvde_operators_admin_all on public.tvde_operators
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- O motorista vê a lista dos aprovados só pela RPC tvde_operadores_aprovados()
-- (sem contrato nem notas).

-- ── Colunas novas em drivers (motorista TVDE) ───────────────────────────────
alter table public.drivers
  add column if not exists tvde_operator_id uuid references public.tvde_operators(id) on delete set null,
  add column if not exists carta_b_emitida_em date,
  add column if not exists tvde_cert_foto_path text,
  add column if not exists tvde_contrato_operador_path text,
  add column if not exists fala_portugues boolean,
  add column if not exists tvde_curso_atualizacao_em date,
  add column if not exists tvde_horas_outras_plataformas numeric(4,1),
  add column if not exists tvde_horas_outras_declaradas_em timestamptz;
comment on column public.drivers.tvde_operator_id is 'Operador TVDE pelo qual o motorista trabalha (Lei 45/2018 art. 10).';
comment on column public.drivers.carta_b_emitida_em is 'Data de emissão da carta B (o motorista TVDE precisa de mais de 3 anos).';
comment on column public.drivers.tvde_horas_outras_plataformas is 'Horas declaradas pelo motorista noutras plataformas nas últimas 24 h (art. 13).';

-- ── Veículos TVDE ───────────────────────────────────────────────────────────
create table if not exists public.tvde_vehicles (
  id uuid primary key default gen_random_uuid(),
  operator_id uuid references public.tvde_operators(id) on delete set null,
  matricula text not null,
  marca text,
  modelo text,
  cor text,
  ano_fabrico integer check (ano_fabrico is null or ano_fabrico between 1980 and 2100),
  primeira_matricula_em date,
  lugares integer check (lugares is null or lugares between 1 and 9),
  eletrico boolean not null default false,
  foto_path text,
  registo_imt_numero text,
  registo_imt_validade date,
  seguro_seguradora text,
  seguro_apolice text,
  seguro_validade date,
  seguro_acidentes_pessoais boolean,
  seguro_path text,
  inspecao_proxima date,
  distico_id text,
  adaptado_mobilidade_reduzida boolean not null default false,
  estado text not null default 'pendente'
    check (estado in ('pendente','aprovado','suspenso','rejeitado')),
  estado_motivo text,
  submetido_por uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  decidido_por uuid,
  decidido_em timestamptz
);
create unique index if not exists tvde_vehicles_matricula_uq on public.tvde_vehicles (upper(replace(matricula, '-', '')));
alter table public.tvde_vehicles enable row level security;
create policy tvde_vehicles_admin_all on public.tvde_vehicles
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Associação nominal motorista <-> carro (art. 12)
create table if not exists public.tvde_driver_vehicle (
  driver_user_id uuid not null,
  vehicle_id uuid not null references public.tvde_vehicles(id) on delete cascade,
  ativo boolean not null default true,
  desde timestamptz not null default now(),
  ate timestamptz,
  criado_por uuid,
  primary key (driver_user_id, vehicle_id)
);
alter table public.tvde_driver_vehicle enable row level security;
create policy tvde_dv_admin_all on public.tvde_driver_vehicle
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy tvde_dv_proprio on public.tvde_driver_vehicle
  for select to authenticated using (driver_user_id = auth.uid());
create policy tvde_vehicles_proprio on public.tvde_vehicles
  for select to authenticated using (
    submetido_por = auth.uid()
    or exists (select 1 from public.tvde_driver_vehicle dv
                where dv.vehicle_id = tvde_vehicles.id and dv.driver_user_id = auth.uid()));

-- ── Tempos de serviço (art. 13) — retenção mínima 2 anos, nunca se apaga ────
create table if not exists public.tvde_driver_work_log (
  id bigserial primary key,
  driver_user_id uuid not null,
  inicio timestamptz not null,
  fim timestamptz,
  fecho text check (fecho in ('offline','sem_sinal','admin')),
  created_at timestamptz not null default now(),
  check (fim is null or fim >= inicio)
);
create index if not exists tvde_work_log_driver_idx on public.tvde_driver_work_log (driver_user_id, inicio desc);
create unique index if not exists tvde_work_log_um_aberto on public.tvde_driver_work_log (driver_user_id) where fim is null;
alter table public.tvde_driver_work_log enable row level security;
create policy tvde_work_log_leitura on public.tvde_driver_work_log
  for select to authenticated using (driver_user_id = auth.uid() or public.is_admin());

-- ── Queixas (art. 19.º n.º 3) — retenção mínima 2 anos ─────────────────────
create sequence if not exists public.tvde_complaints_numero_seq;
create table if not exists public.tvde_complaints (
  id uuid primary key default gen_random_uuid(),
  numero bigint not null default nextval('public.tvde_complaints_numero_seq') unique,
  ride_id uuid references public.tvde_rides(id) on delete set null,
  autor_user_id uuid,
  autor_papel text not null default 'cliente' check (autor_papel in ('cliente','motorista','outro')),
  driver_user_id uuid,
  canal text not null default 'app' check (canal in ('app','livro_reclamacoes','email','telefone','outro')),
  categoria text not null default 'outro'
    check (categoria in ('preco','comportamento','seguranca','veiculo','percurso','pagamento','acessibilidade','dados_pessoais','outro')),
  descricao text not null check (length(trim(descricao)) >= 5),
  contacto text,
  estado text not null default 'recebida'
    check (estado in ('recebida','em_analise','respondida','resolvida','arquivada')),
  diligencias jsonb not null default '[]'::jsonb,
  resposta text,
  resolucao text,
  respondida_em timestamptz,
  resolvida_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tvde_complaints_estado_idx on public.tvde_complaints (estado, created_at desc);
alter table public.tvde_complaints enable row level security;
create policy tvde_complaints_autor_ou_admin on public.tvde_complaints
  for select to authenticated using (autor_user_id = auth.uid() or public.is_admin());

-- ── Auditoria de conformidade (bloqueios, verificações, fiscalização) ───────
create table if not exists public.tvde_compliance_events (
  id bigserial primary key,
  tipo text not null,
  driver_user_id uuid,
  vehicle_id uuid,
  operator_id uuid,
  ride_id uuid,
  ator_user_id uuid,
  ator text not null default 'sistema',
  motivo text,
  meta jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index if not exists tvde_ce_driver_idx on public.tvde_compliance_events (driver_user_id, at desc);
create index if not exists tvde_ce_tipo_idx on public.tvde_compliance_events (tipo, at desc);
alter table public.tvde_compliance_events enable row level security;
create policy tvde_ce_admin on public.tvde_compliance_events
  for select to authenticated using (public.is_admin());

-- Estado de conformidade por motorista (calculado pelo cron; o bloqueio manual
-- do admin também vive aqui — não se escreve em drivers).
create table if not exists public.tvde_driver_compliance (
  driver_user_id uuid primary key,
  bloqueado boolean not null default false,
  motivos jsonb not null default '[]'::jsonb,
  avisos jsonb not null default '[]'::jsonb,
  bloqueio_manual boolean not null default false,
  bloqueio_manual_motivo text,
  bloqueio_manual_por uuid,
  bloqueio_manual_em timestamptz,
  verificado_em timestamptz not null default now()
);
alter table public.tvde_driver_compliance enable row level security;
create policy tvde_dc_leitura on public.tvde_driver_compliance
  for select to authenticated using (driver_user_id = auth.uid() or public.is_admin());

-- ── Preferências do cliente (art. 19.º n.º 1 i) e art. 6) ──────────────────
create table if not exists public.tvde_client_prefs (
  client_id uuid primary key,
  fala_portugues boolean not null default false,
  mobilidade_reduzida boolean not null default false,
  cao_guia boolean not null default false,
  cadeira_rodas boolean not null default false,
  carrinho_bebe boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.tvde_client_prefs enable row level security;
create policy tvde_prefs_proprio on public.tvde_client_prefs
  for select to authenticated using (client_id = auth.uid() or public.is_admin());

alter table public.tvde_rides
  add column if not exists pref_fala_portugues boolean not null default false,
  add column if not exists pede_mobilidade_reduzida boolean not null default false,
  add column if not exists necessidades jsonb not null default '{}'::jsonb;

-- ── SOS (arts. 17.º-A n.º 2 e) e 19.º n.º 1 j)) ─────────────────────────────
create table if not exists public.tvde_sos_events (
  id bigserial primary key,
  ride_id uuid references public.tvde_rides(id) on delete set null,
  user_id uuid not null,
  papel text not null check (papel in ('cliente','motorista')),
  lat double precision,
  lng double precision,
  ligou_112 boolean not null default false,
  partilhou boolean not null default false,
  at timestamptz not null default now()
);
alter table public.tvde_sos_events enable row level security;
create policy tvde_sos_leitura on public.tvde_sos_events
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- ── Acesso das entidades fiscalizadoras (art. 20.º-A) ───────────────────────
create table if not exists public.tvde_fiscal_access (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  entidade text not null,
  agente text,
  finalidade text not null,
  escopo jsonb not null default '{}'::jsonb,
  criado_por uuid not null,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  revogado_em timestamptz,
  consultas integer not null default 0,
  ultima_consulta timestamptz
);
alter table public.tvde_fiscal_access enable row level security;
create policy tvde_fa_admin on public.tvde_fiscal_access
  for select to authenticated using (public.is_admin());

-- ── Teto da taxa de intermediação (art. 15.º n.º 3) — só verifica ───────────
create table if not exists public.tvde_intermediacao_verificacao (
  ride_id uuid primary key references public.tvde_rides(id) on delete cascade,
  valor_viagem_cents integer not null,
  intermediacao_cents integer not null,
  pct numeric(6,2),
  teto_pct numeric(5,2) not null,
  cumpre boolean not null,
  base text not null,
  verificado_em timestamptz not null default now()
);
alter table public.tvde_intermediacao_verificacao enable row level security;
create policy tvde_iv_admin on public.tvde_intermediacao_verificacao
  for select to authenticated using (public.is_admin());

-- ── Relatório mensal AMT ────────────────────────────────────────────────────
create table if not exists public.tvde_amt_reports (
  mes date primary key,
  viagens integer not null,
  faturado_cents bigint not null,
  intermediacao_cents bigint not null,
  contribuicao_pct numeric(5,2) not null,
  contribuicao_cents bigint not null,
  viagens_acima_teto integer not null default 0,
  detalhe jsonb not null default '{}'::jsonb,
  gerado_em timestamptz not null default now()
);
alter table public.tvde_amt_reports enable row level security;
create policy tvde_amt_admin on public.tvde_amt_reports
  for select to authenticated using (public.is_admin());

-- ── Faturação certificada (adaptador; stub até existir empresa) ─────────────
create table if not exists public.tvde_invoices (
  ride_id uuid primary key references public.tvde_rides(id) on delete cascade,
  fornecedor text not null,
  modo text not null check (modo in ('stub','teste','producao')),
  estado text not null check (estado in ('pendente','emitida','falhou')),
  numero text,
  atcud text,
  documento_url text,
  erro text,
  pedido jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.tvde_invoices enable row level security;
create policy tvde_inv_leitura on public.tvde_invoices
  for select to authenticated using (
    public.is_admin() or exists (select 1 from public.tvde_rides r
      where r.id = tvde_invoices.ride_id and (r.client_id = auth.uid() or r.driver_id = auth.uid())));

-- ── Checklist "Pronto para licenciamento" (semeada da matriz da Fase 0) ─────
create table if not exists public.tvde_legal_requirements (
  codigo text primary key,
  ordem integer not null,
  area text not null,
  requisito text not null,
  base_legal text not null,
  estado text not null check (estado in ('verde','amarelo','vermelho')),
  o_que_falta text,
  interruptor text,
  atualizado_em timestamptz not null default now()
);
alter table public.tvde_legal_requirements enable row level security;
create policy tvde_lr_admin on public.tvde_legal_requirements
  for select to authenticated using (public.is_admin());

-- ── Documentos: tipos novos e validade (tabela que já existia) ─────────────
alter table public.tvde_driver_documents add column if not exists validade date;
alter table public.tvde_driver_documents drop constraint if exists tvde_driver_documents_doc_type_check;
alter table public.tvde_driver_documents add constraint tvde_driver_documents_doc_type_check
  check (doc_type = any (array['carta_conducao','certificado_tvde_imt','dut','seguro','inspecao',
    'registo_criminal','contrato_operador','curso_atualizacao']));
