-- Casa & Manutenção (faz-tudo) — parte 1: papel novo e tabelas.
-- Missão casa-manutencao-2026-10-30 (decisões do Danilo 30/10 21:38).
-- Molde: Limpeza (cleaners / cleaning_bookings). Nomes de colunas legais iguais aos do cleaner
-- (legal_name, nif, address, iban, birth_date, dsa_self_certified_at) para que os gatilhos
-- partilhados de conformidade e de comprovativo de atividade funcionem sem mudança.
-- Toda a escrita é por funções SECURITY DEFINER; as políticas só deixam ler o que é de cada um.
-- As definições (casa_*) vão na parte 1b, à parte.

-- 1) Papel novo nas listas fechadas --------------------------------------------------------
ALTER TABLE public.user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_check
  CHECK (role = ANY (ARRAY['client','driver','delivery','partner','cleaner','washer','handyman','admin']));

ALTER TABLE public.provider_push_tokens DROP CONSTRAINT IF EXISTS provider_push_tokens_role_check;
ALTER TABLE public.provider_push_tokens ADD CONSTRAINT provider_push_tokens_role_check
  CHECK (role = ANY (ARRAY['cleaner','washer','delivery','handyman']));

ALTER TABLE public.preferencias_papel DROP CONSTRAINT IF EXISTS preferencias_papel_papel_check;
ALTER TABLE public.preferencias_papel ADD CONSTRAINT preferencias_papel_papel_check
  CHECK (papel = ANY (ARRAY['driver','delivery','cleaner','washer','handyman']));

CREATE OR REPLACE FUNCTION public.meus_papeis_e_preferencias()
 RETURNS TABLE(papel text, aceita boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ur.role AS papel,
         COALESCE(p.aceita, true) AS aceita
  FROM public.user_roles ur
  LEFT JOIN public.preferencias_papel p
         ON p.user_id = ur.user_id AND p.papel = ur.role
  WHERE ur.user_id = auth.uid()
    AND ur.role IN ('driver', 'delivery', 'cleaner', 'washer', 'handyman')
  -- Ordem em que se lê no ecrã, não alfabética: primeiro o que dá mais
  -- trabalho por semana.
  ORDER BY CASE ur.role
             WHEN 'driver'   THEN 1
             WHEN 'delivery' THEN 2
             WHEN 'cleaner'  THEN 3
             WHEN 'washer'   THEN 4
             WHEN 'handyman' THEN 5
             ELSE 9
           END;
$function$;

-- 2) Ofícios ------------------------------------------------------------------------------
CREATE TABLE public.casa_oficios (
  codigo             text PRIMARY KEY,
  nome               text NOT NULL,
  descricao          text NOT NULL DEFAULT '',
  fase               smallint NOT NULL DEFAULT 1 CHECK (fase IN (1, 2)),
  documento_exigido  text CHECK (documento_exigido IS NULL OR documento_exigido IN ('dgeg_eletricidade','dgeg_gas','impic')),
  ativo              boolean NOT NULL DEFAULT false,
  ordem              integer NOT NULL DEFAULT 0,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by         uuid
);

INSERT INTO public.casa_oficios (codigo, nome, descricao, fase, documento_exigido, ativo, ordem) VALUES
  ('montagem',     'Montagem de móveis',              'Móveis IKEA e outros, em casa do cliente.', 1, NULL, true, 10),
  ('fixacao',      'Pendurar e fixar',                'Televisão, quadros, prateleiras, cortinas e estores.', 1, NULL, true, 20),
  ('reparacoes',   'Pequenas reparações',             'Porta que roça, dobradiça, puxador, silicone.', 1, NULL, true, 30),
  ('canalizacao',  'Torneira, autoclismo e sifão',    'Só peças à vista, sem abrir parede nem mexer em canos embebidos.', 1, NULL, true, 40),
  ('jardinagem',   'Jardinagem e quintal',            'Cortar relva, podar sebes, limpar mato pequeno.', 1, NULL, true, 50),
  ('mudancas',     'Pequenas mudanças com carrinha',  'Transporte de móveis e pequenas mudanças.', 1, NULL, true, 60),
  ('eletricidade', 'Eletricidade',                    'Só com habilitação DGEG aprovada pelo Bora.', 2, 'dgeg_eletricidade', false, 70),
  ('gas',          'Gás',                             'Só entidade instaladora autorizada pela DGEG.', 2, 'dgeg_gas', false, 80),
  ('pladur',       'Pladur e pequena alvenaria',      'Só com certificado IMPIC aprovado pelo Bora.', 2, 'impic', false, 90),
  ('pintura',      'Pintura',                         'Só com certificado IMPIC aprovado pelo Bora.', 2, 'impic', false, 100);

-- 3) Catálogo de serviços (preços = PROPOSTA até ao "autorizo" do Danilo) -----------------
CREATE TABLE public.casa_servicos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  oficio           text NOT NULL REFERENCES public.casa_oficios(codigo),
  nome             text NOT NULL,
  descricao        text NOT NULL DEFAULT '',
  modo             text NOT NULL CHECK (modo IN ('fixo','hora','orcamento')),
  preco_cents      integer CHECK (preco_cents IS NULL OR preco_cents > 0),
  unidade          text NOT NULL DEFAULT 'tarefa' CHECK (unidade IN ('tarefa','movel','hora')),
  min_quantidade   numeric NOT NULL DEFAULT 1 CHECK (min_quantidade > 0),
  max_quantidade   numeric NOT NULL DEFAULT 10 CHECK (max_quantidade >= min_quantidade),
  duracao_min      integer NOT NULL DEFAULT 60 CHECK (duracao_min > 0),
  perguntas        jsonb NOT NULL DEFAULT '[]'::jsonb,
  ativo            boolean NOT NULL DEFAULT true,
  ordem            integer NOT NULL DEFAULT 0,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       uuid,
  CONSTRAINT casa_servicos_preco_por_modo CHECK (
    (modo = 'orcamento' AND preco_cents IS NULL) OR (modo <> 'orcamento' AND preco_cents IS NOT NULL))
);
CREATE INDEX idx_casa_servicos_oficio ON public.casa_servicos (oficio, ordem);

-- Pontos de partida da pesquisa de 29/10 (montagem a partir de 25 €, pendurar TV 30 €,
-- torneira 35 €, hora 20 a 25 €). Só os números que a pesquisa deu; o resto é orçamento.
INSERT INTO public.casa_servicos (oficio, nome, descricao, modo, preco_cents, unidade, min_quantidade, max_quantidade, duracao_min, perguntas, ordem) VALUES
  ('montagem', 'Montar um móvel', 'Preço por móvel. O cliente já tem o móvel em casa.', 'fixo', 2500, 'movel', 1, 10, 60,
   '[{"id":"tipo_movel","texto":"Que móvel é? (ex.: roupeiro, cómoda, cama)","tipo":"texto"},{"id":"marca","texto":"É do IKEA ou de outra marca?","tipo":"escolha","opcoes":["IKEA","Outra marca","Não sei"]}]', 10),
  ('montagem', 'Montagem grande ou cozinha', 'Vários móveis, roupeiros grandes ou cozinha: pede orçamento.', 'orcamento', NULL, 'tarefa', 1, 1, 180,
   '[{"id":"o_que","texto":"O que é preciso montar?","tipo":"texto"}]', 20),
  ('fixacao', 'Pendurar televisão', 'Fixar a televisão na parede com suporte do cliente.', 'fixo', 3000, 'tarefa', 1, 4, 60,
   '[{"id":"polegadas","texto":"Quantas polegadas tem a televisão?","tipo":"texto"},{"id":"parede","texto":"Que parede é?","tipo":"escolha","opcoes":["Tijolo ou betão","Pladur","Não sei"]},{"id":"suporte","texto":"Já tem o suporte?","tipo":"escolha","opcoes":["Sim","Não"]}]', 10),
  ('fixacao', 'Quadros, prateleiras ou cortinas', 'À hora, mínimo de 1 hora.', 'hora', 2000, 'hora', 1, 8, 60,
   '[{"id":"o_que","texto":"O que é preciso pendurar ou fixar, e quantos?","tipo":"texto"},{"id":"parede","texto":"Que parede é?","tipo":"escolha","opcoes":["Tijolo ou betão","Pladur","Não sei"]}]', 20),
  ('reparacoes', 'Pequena reparação', 'Porta que roça, dobradiça, puxador, silicone. À hora, mínimo de 1 hora.', 'hora', 2000, 'hora', 1, 8, 60,
   '[{"id":"o_que","texto":"O que está estragado?","tipo":"texto"}]', 10),
  ('reparacoes', 'Outra reparação', 'Não sabe quanto tempo leva? Pede orçamento com fotos.', 'orcamento', NULL, 'tarefa', 1, 1, 120,
   '[{"id":"o_que","texto":"Descreve o problema","tipo":"texto"}]', 20),
  ('canalizacao', 'Trocar torneira', 'O cliente já tem a torneira nova. Só peças à vista.', 'fixo', 3500, 'tarefa', 1, 4, 60,
   '[{"id":"onde","texto":"Onde é a torneira?","tipo":"escolha","opcoes":["Cozinha","Casa de banho","Exterior"]},{"id":"tem_peca","texto":"Já tem a torneira nova?","tipo":"escolha","opcoes":["Sim","Não"]}]', 10),
  ('canalizacao', 'Autoclismo ou sifão', 'Afinar ou trocar peças à vista. À hora, mínimo de 1 hora.', 'hora', 2000, 'hora', 1, 4, 60,
   '[{"id":"o_que","texto":"O que acontece? (ex.: autoclismo sempre a correr, sifão a pingar)","tipo":"texto"}]', 20),
  ('jardinagem', 'Cortar relva e podar', 'À hora, mínimo de 2 horas.', 'hora', 2000, 'hora', 2, 8, 120,
   '[{"id":"tamanho","texto":"Mais ou menos que tamanho tem o jardim?","tipo":"escolha","opcoes":["Pequeno","Médio","Grande"]},{"id":"ferramentas","texto":"Tem corta-relva em casa?","tipo":"escolha","opcoes":["Sim","Não"]}]', 10),
  ('jardinagem', 'Limpar terreno ou mato grande', 'Pede orçamento com fotos.', 'orcamento', NULL, 'tarefa', 1, 1, 240,
   '[{"id":"tamanho","texto":"Mais ou menos que área tem?","tipo":"texto"}]', 20),
  ('mudancas', 'Pequena mudança ou transporte', 'Transporte de móveis com carrinha. Pede orçamento.', 'orcamento', NULL, 'tarefa', 1, 1, 120,
   '[{"id":"o_que","texto":"O que é preciso levar?","tipo":"texto"},{"id":"destino","texto":"Para onde? (morada ou localidade)","tipo":"texto"},{"id":"andar","texto":"Há escadas ou elevador?","tipo":"escolha","opcoes":["Rés-do-chão","Escadas","Elevador"]}]', 10),
  ('eletricidade', 'Trabalho de eletricidade', 'Só profissionais com habilitação DGEG. Pede orçamento.', 'orcamento', NULL, 'tarefa', 1, 1, 120,
   '[{"id":"o_que","texto":"Descreve o trabalho","tipo":"texto"}]', 10),
  ('gas', 'Trabalho de gás', 'Só entidades instaladoras autorizadas pela DGEG. Pede orçamento.', 'orcamento', NULL, 'tarefa', 1, 1, 120,
   '[{"id":"o_que","texto":"Descreve o trabalho","tipo":"texto"}]', 10),
  ('pladur', 'Pladur ou pequena alvenaria', 'Só com certificado IMPIC. Pede orçamento.', 'orcamento', NULL, 'tarefa', 1, 1, 240,
   '[{"id":"o_que","texto":"Descreve o trabalho","tipo":"texto"}]', 10),
  ('pintura', 'Pintura', 'Só com certificado IMPIC. Pede orçamento.', 'orcamento', NULL, 'tarefa', 1, 1, 240,
   '[{"id":"o_que","texto":"Que divisões e mais ou menos que área?","tipo":"texto"}]', 10);

-- 4) Profissionais ------------------------------------------------------------------------
CREATE TABLE public.casa_profissionais (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                uuid NOT NULL UNIQUE REFERENCES auth.users(id),
  name                   text NOT NULL,
  phone                  text NOT NULL DEFAULT '',
  email                  text NOT NULL DEFAULT '',
  photo_url              text NOT NULL DEFAULT '',
  bio                    text NOT NULL DEFAULT '',
  nif                    text NOT NULL DEFAULT '',
  legal_name             text,
  iban                   text,
  address                text,
  birth_date             date,
  dsa_self_certified_at  timestamptz,
  dsa_self_cert_version  text,
  base_lat               double precision,
  base_lng               double precision,
  base_address           text NOT NULL DEFAULT '',
  service_radius_km      numeric NOT NULL DEFAULT 15 CHECK (service_radius_km > 0 AND service_radius_km <= 100),
  has_van                boolean NOT NULL DEFAULT false,
  has_tools              boolean NOT NULL DEFAULT true,
  approval_status        text NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending','approved','rejected','suspended','banned')),
  approved_at            timestamptz,
  approved_by            uuid,
  rejection_reason       text,
  is_active              boolean NOT NULL DEFAULT true,
  rating_avg             numeric NOT NULL DEFAULT 0,
  ratings_count          integer NOT NULL DEFAULT 0,
  jobs_done              integer NOT NULL DEFAULT 0,
  sem_comissao_ate       date,
  docs                   jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_casa_profissionais_status ON public.casa_profissionais (approval_status);

CREATE TRIGGER trg_casa_profissionais_touch BEFORE UPDATE ON public.casa_profissionais
  FOR EACH ROW EXECUTE FUNCTION public._cleaning_touch_updated_at();
CREATE TRIGGER trg_grant_role_casa AFTER INSERT ON public.casa_profissionais
  FOR EACH ROW EXECUTE FUNCTION public._grant_role_from_profile('handyman');
CREATE TRIGGER trg_atividade_antes_de_ativar BEFORE UPDATE OF approval_status ON public.casa_profissionais
  FOR EACH ROW WHEN (NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION public.fn_atividade_antes_de_ativar();
CREATE TRIGGER trg_conformidade_antes_de_ativar BEFORE UPDATE OF approval_status ON public.casa_profissionais
  FOR EACH ROW EXECUTE FUNCTION public.fn_conformidade_antes_de_ativar();

-- Ofícios de cada profissional: aprovação ofício a ofício, interruptor por ofício.
CREATE TABLE public.casa_profissional_oficios (
  profissional_id  uuid NOT NULL REFERENCES public.casa_profissionais(id) ON DELETE CASCADE,
  oficio           text NOT NULL REFERENCES public.casa_oficios(codigo),
  estado           text NOT NULL DEFAULT 'pending' CHECK (estado IN ('pending','approved','rejected','suspended')),
  ligado           boolean NOT NULL DEFAULT true,
  decidido_por     uuid,
  decidido_em      timestamptz,
  motivo           text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (profissional_id, oficio)
);

-- Documentos (gerais quando oficio é NULL; por ofício quando não é).
CREATE TABLE public.casa_documentos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id  uuid NOT NULL REFERENCES public.casa_profissionais(id) ON DELETE CASCADE,
  oficio           text REFERENCES public.casa_oficios(codigo),
  tipo             text NOT NULL CHECK (tipo IN ('cartao_cidadao','seguro_acidentes','seguro_rc','dgeg_eletricidade','dgeg_gas','impic','outro')),
  storage_path     text NOT NULL,
  numero           text,
  validade         date,
  estado           text NOT NULL DEFAULT 'pending' CHECK (estado IN ('pending','approved','rejected','expired')),
  decidido_por     uuid,
  decidido_em      timestamptz,
  motivo           text,
  aviso_caducar_em timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_casa_documentos_prof ON public.casa_documentos (profissional_id, tipo);
CREATE TRIGGER trg_casa_documentos_touch BEFORE UPDATE ON public.casa_documentos
  FOR EACH ROW EXECUTE FUNCTION public._cleaning_touch_updated_at();

CREATE TABLE public.casa_disponibilidade (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id  uuid NOT NULL REFERENCES public.casa_profissionais(id) ON DELETE CASCADE,
  weekday          smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time       time NOT NULL,
  end_time         time NOT NULL,
  CHECK (end_time > start_time)
);
CREATE INDEX idx_casa_disponibilidade ON public.casa_disponibilidade (profissional_id, weekday);

-- 5) Pedidos ------------------------------------------------------------------------------
-- estado: aguarda_pagamento (cartão/MB Way antes de retido) · procura (preço fixo, oferta a um
-- profissional de cada vez) · orcamentos (à espera de orçamentos) · aceite · a_caminho · chegou ·
-- em_curso · concluido (o profissional terminou; espera o cliente ou 24 h) · confirmado ·
-- disputa (cliente pediu para refazer) · cancelado · expirado.
CREATE TABLE public.casa_pedidos (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_user_id           uuid NOT NULL REFERENCES auth.users(id),
  servico_id               uuid REFERENCES public.casa_servicos(id),
  oficio                   text NOT NULL REFERENCES public.casa_oficios(codigo),
  modo                     text NOT NULL CHECK (modo IN ('fixo','hora','orcamento')),
  quantidade               numeric NOT NULL DEFAULT 1 CHECK (quantidade > 0),
  descricao                text NOT NULL DEFAULT '',
  respostas                jsonb NOT NULL DEFAULT '{}'::jsonb,
  address_street           text NOT NULL DEFAULT '',
  address_city             text NOT NULL DEFAULT '',
  address_postal           text NOT NULL DEFAULT '',
  lat                      double precision,
  lng                      double precision,
  scheduled_at             timestamptz NOT NULL,
  duracao_min              integer NOT NULL DEFAULT 60,
  estado                   text NOT NULL DEFAULT 'procura' CHECK (estado IN ('aguarda_pagamento','procura','orcamentos','aceite','a_caminho','chegou','em_curso','concluido','confirmado','disputa','cancelado','expirado')),
  payment_method           text NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('card','mbway','cash')),
  payment_status           text NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid','held','released','estornado','cash_pending','cash_settled')),
  pagamento_ref            text,
  preco_cents              integer NOT NULL DEFAULT 0 CHECK (preco_cents >= 0),
  extras_cents             integer NOT NULL DEFAULT 0 CHECK (extras_cents >= 0),
  total_cents              integer NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  comissao_pct             numeric,
  comissao_cents           integer NOT NULL DEFAULT 0,
  ganho_cents              integer NOT NULL DEFAULT 0,
  profissional_id          uuid REFERENCES public.casa_profissionais(id),
  orcamento_aceite_id      uuid,
  offer_profissional_id    uuid REFERENCES public.casa_profissionais(id),
  offer_expires_at         timestamptz,
  offered_profissional_ids uuid[] NOT NULL DEFAULT '{}',
  offer_round              smallint NOT NULL DEFAULT 1,
  convites_enviados_em     timestamptz,
  accepted_at              timestamptz,
  on_the_way_at            timestamptz,
  arrived_at               timestamptz,
  started_at               timestamptz,
  done_at                  timestamptz,
  confirmed_at             timestamptz,
  cancelled_at             timestamptz,
  cancelled_by             text CHECK (cancelled_by IS NULL OR cancelled_by IN ('client','handyman','admin','sistema')),
  cancel_reason            text,
  cancel_fee_cents         integer NOT NULL DEFAULT 0,
  reembolso_pendente       boolean NOT NULL DEFAULT false,
  rating_cliente           smallint CHECK (rating_cliente IS NULL OR rating_cliente BETWEEN 1 AND 5),
  comentario_cliente       text,
  rating_profissional      smallint CHECK (rating_profissional IS NULL OR rating_profissional BETWEEN 1 AND 5),
  refazer_pedido_em        timestamptz,
  refazer_motivo           text,
  reminder_24h_sent_at     timestamptz,
  reminder_2h_sent_at      timestamptz,
  stuck_alerted_at         timestamptz,
  client_confirm_reminded_at timestamptz,
  is_test_order            boolean NOT NULL DEFAULT false,
  idempotency_key          text,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_casa_pedidos_client ON public.casa_pedidos (client_user_id, created_at DESC);
CREATE INDEX idx_casa_pedidos_prof ON public.casa_pedidos (profissional_id, scheduled_at DESC);
CREATE INDEX idx_casa_pedidos_estado ON public.casa_pedidos (estado, scheduled_at);
CREATE INDEX idx_casa_pedidos_offer ON public.casa_pedidos (offer_profissional_id) WHERE offer_profissional_id IS NOT NULL;
CREATE UNIQUE INDEX ux_casa_pedidos_idem ON public.casa_pedidos (client_user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE TRIGGER trg_casa_pedidos_touch BEFORE UPDATE ON public.casa_pedidos
  FOR EACH ROW EXECUTE FUNCTION public._cleaning_touch_updated_at();
CREATE TRIGGER trg_convidado_so_ve BEFORE INSERT OR UPDATE ON public.casa_pedidos
  FOR EACH ROW EXECUTE FUNCTION public.trg_convidado_so_ve();

CREATE TABLE public.casa_pedido_fotos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id     uuid NOT NULL REFERENCES public.casa_pedidos(id) ON DELETE CASCADE,
  tipo          text NOT NULL CHECK (tipo IN ('problema','antes','depois','extra')),
  storage_path  text NOT NULL,
  enviado_por   uuid NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_casa_pedido_fotos ON public.casa_pedido_fotos (pedido_id, tipo);

CREATE TABLE public.casa_orcamentos (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id           uuid NOT NULL REFERENCES public.casa_pedidos(id) ON DELETE CASCADE,
  profissional_id     uuid NOT NULL REFERENCES public.casa_profissionais(id),
  preco_cents         integer NOT NULL CHECK (preco_cents > 0),
  inclui              text NOT NULL DEFAULT '',
  materiais           text NOT NULL DEFAULT '',
  materiais_incluidos boolean NOT NULL DEFAULT false,
  prazo               text NOT NULL DEFAULT '',
  duracao_min         integer CHECK (duracao_min IS NULL OR duracao_min > 0),
  estado              text NOT NULL DEFAULT 'enviado' CHECK (estado IN ('enviado','aceite','recusado','expirado','retirado')),
  expira_em           timestamptz NOT NULL,
  decidido_em         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pedido_id, profissional_id)
);
CREATE INDEX idx_casa_orcamentos_pedido ON public.casa_orcamentos (pedido_id, estado);
ALTER TABLE public.casa_pedidos ADD CONSTRAINT casa_pedidos_orcamento_aceite_fkey
  FOREIGN KEY (orcamento_aceite_id) REFERENCES public.casa_orcamentos(id);

CREATE TABLE public.casa_extras (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id     uuid NOT NULL REFERENCES public.casa_pedidos(id) ON DELETE CASCADE,
  valor_cents   integer NOT NULL CHECK (valor_cents > 0),
  motivo        text NOT NULL CHECK (length(motivo) BETWEEN 3 AND 500),
  estado        text NOT NULL DEFAULT 'pedido' CHECK (estado IN ('pedido','aceite','recusado')),
  pedido_por    uuid NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  respondido_em timestamptz
);
CREATE INDEX idx_casa_extras_pedido ON public.casa_extras (pedido_id);

CREATE TABLE public.casa_mensagens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id    uuid NOT NULL REFERENCES public.casa_pedidos(id) ON DELETE CASCADE,
  sender_role  text NOT NULL CHECK (sender_role IN ('client','handyman','admin')),
  message      text NOT NULL CHECK (length(message) BETWEEN 1 AND 2000),
  read         boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_casa_mensagens ON public.casa_mensagens (pedido_id, created_at);

-- Registo de ofertas e convites (quem recebeu, se tinha aparelho, quanto tempo teve).
CREATE TABLE public.casa_ofertas (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id        uuid NOT NULL REFERENCES public.casa_pedidos(id) ON DELETE CASCADE,
  profissional_id  uuid NOT NULL REFERENCES public.casa_profissionais(id),
  user_id          uuid NOT NULL,
  tipo             text NOT NULL CHECK (tipo IN ('oferta','convite_orcamento','repeticao')),
  enviada_em       timestamptz NOT NULL DEFAULT now(),
  expira_em        timestamptz,
  tinha_aparelho   boolean NOT NULL DEFAULT false,
  resposta         text CHECK (resposta IS NULL OR resposta IN ('aceite','recusada','expirada','sem_aparelho','orcamento_enviado')),
  respondida_em    timestamptz,
  ronda            smallint NOT NULL DEFAULT 1
);
CREATE INDEX idx_casa_ofertas_pedido ON public.casa_ofertas (pedido_id, enviada_em);
CREATE INDEX idx_casa_ofertas_prof ON public.casa_ofertas (profissional_id, enviada_em DESC);

-- Histórico de estados (para o painel e para as provas).
CREATE TABLE public.casa_pedido_eventos (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id   uuid NOT NULL REFERENCES public.casa_pedidos(id) ON DELETE CASCADE,
  estado_de   text,
  estado_para text,
  por_user_id uuid,
  por_papel   text,
  detalhe     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_casa_pedido_eventos ON public.casa_pedido_eventos (pedido_id, created_at);

-- 6) Acerto semanal (cêntimos inteiros, juntado por pessoa) -------------------------------
CREATE TABLE public.casa_acertos_semanais (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id        uuid NOT NULL REFERENCES public.casa_profissionais(id),
  user_id                uuid NOT NULL,
  week_start_at          timestamptz NOT NULL,
  week_end_at            timestamptz NOT NULL,
  total_jobs             integer NOT NULL DEFAULT 0,
  total_bruto_cents      integer NOT NULL DEFAULT 0,
  total_comissao_cents   integer NOT NULL DEFAULT 0,
  recebido_em_mao_cents  integer NOT NULL DEFAULT 0,
  net_payout_cents       integer NOT NULL DEFAULT 0,
  direction              text NOT NULL DEFAULT 'bora_to_handyman' CHECK (direction IN ('bora_to_handyman','handyman_to_bora','zero')),
  status                 text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','received','disputed')),
  payment_method         text,
  payment_reference      text,
  paid_at                timestamptz,
  paid_by                uuid,
  notes                  text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (profissional_id, week_start_at)
);
CREATE INDEX idx_casa_acertos_user ON public.casa_acertos_semanais (user_id, week_start_at DESC);
CREATE TRIGGER trg_acerto_pago_congelado BEFORE UPDATE ON public.casa_acertos_semanais
  FOR EACH ROW EXECUTE FUNCTION public._acerto_pago_congelado();

-- 7) RLS: ler só o que é de cada um; escrever só por funções -----------------------------
ALTER TABLE public.casa_oficios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_servicos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_profissionais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_profissional_oficios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_disponibilidade ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_pedido_fotos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_orcamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_extras ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_mensagens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_ofertas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_pedido_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casa_acertos_semanais ENABLE ROW LEVEL SECURITY;

CREATE POLICY casa_oficios_ler ON public.casa_oficios FOR SELECT TO authenticated USING (true);
CREATE POLICY casa_servicos_ler ON public.casa_servicos FOR SELECT TO authenticated USING (true);

CREATE POLICY casa_profissionais_proprio ON public.casa_profissionais FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());
CREATE POLICY casa_prof_oficios_proprio ON public.casa_profissional_oficios FOR SELECT TO authenticated
  USING (profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid())) OR public.is_admin());
CREATE POLICY casa_documentos_proprio ON public.casa_documentos FOR SELECT TO authenticated
  USING (profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid())) OR public.is_admin());
CREATE POLICY casa_disponibilidade_proprio ON public.casa_disponibilidade FOR SELECT TO authenticated
  USING (profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid())) OR public.is_admin());

-- O pedido inteiro (com a morada) só o vê o cliente e o profissional ATRIBUÍDO. Quem só recebeu
-- a oferta ou o convite vê um resumo pela função casa_minhas_ofertas (zona, não a porta).
CREATE POLICY casa_pedidos_participantes ON public.casa_pedidos FOR SELECT TO authenticated
  USING (client_user_id = (SELECT auth.uid())
         OR profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid()))
         OR public.is_admin());
CREATE POLICY convidado_so_ve ON public.casa_pedidos AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT (SELECT public.is_conta_convidado())) WITH CHECK (NOT (SELECT public.is_conta_convidado()));

CREATE POLICY casa_fotos_participantes ON public.casa_pedido_fotos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.casa_pedidos b WHERE b.id = casa_pedido_fotos.pedido_id
                 AND (b.client_user_id = (SELECT auth.uid())
                      OR b.profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid()))))
         OR public.is_admin());

CREATE POLICY casa_orcamentos_participantes ON public.casa_orcamentos FOR SELECT TO authenticated
  USING (profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid()))
         OR EXISTS (SELECT 1 FROM public.casa_pedidos b WHERE b.id = casa_orcamentos.pedido_id AND b.client_user_id = (SELECT auth.uid()))
         OR public.is_admin());

CREATE POLICY casa_extras_participantes ON public.casa_extras FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.casa_pedidos b WHERE b.id = casa_extras.pedido_id
                 AND (b.client_user_id = (SELECT auth.uid())
                      OR b.profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid()))))
         OR public.is_admin());

CREATE POLICY casa_mensagens_participantes ON public.casa_mensagens FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.casa_pedidos b WHERE b.id = casa_mensagens.pedido_id
                 AND (b.client_user_id = (SELECT auth.uid())
                      OR b.profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid()))))
         OR public.is_admin());

CREATE POLICY casa_eventos_participantes ON public.casa_pedido_eventos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.casa_pedidos b WHERE b.id = casa_pedido_eventos.pedido_id
                 AND (b.client_user_id = (SELECT auth.uid())
                      OR b.profissional_id IN (SELECT p.id FROM public.casa_profissionais p WHERE p.user_id = (SELECT auth.uid()))))
         OR public.is_admin());

CREATE POLICY casa_acertos_proprio ON public.casa_acertos_semanais FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());

-- casa_ofertas: sem políticas (só funções e admin pela função própria).
REVOKE ALL ON public.casa_ofertas FROM anon, authenticated;

-- Nada de escrita direta por anon nem por authenticated: só as funções SECURITY DEFINER.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON
  public.casa_oficios, public.casa_servicos, public.casa_profissionais, public.casa_profissional_oficios,
  public.casa_documentos, public.casa_disponibilidade, public.casa_pedidos, public.casa_pedido_fotos,
  public.casa_orcamentos, public.casa_extras, public.casa_mensagens, public.casa_pedido_eventos,
  public.casa_acertos_semanais
FROM anon, authenticated;
REVOKE ALL ON
  public.casa_oficios, public.casa_servicos, public.casa_profissionais, public.casa_profissional_oficios,
  public.casa_documentos, public.casa_disponibilidade, public.casa_pedidos, public.casa_pedido_fotos,
  public.casa_orcamentos, public.casa_extras, public.casa_mensagens, public.casa_pedido_eventos,
  public.casa_acertos_semanais
FROM anon;

-- 8) Tempo real: sem isto o ecrã para de atualizar sem erro (defeito da Lavagem, não copiar).
ALTER PUBLICATION supabase_realtime ADD TABLE public.casa_pedidos;
ALTER PUBLICATION supabase_realtime ADD TABLE public.casa_mensagens;
ALTER PUBLICATION supabase_realtime ADD TABLE public.casa_orcamentos;
ALTER PUBLICATION supabase_realtime ADD TABLE public.casa_extras;