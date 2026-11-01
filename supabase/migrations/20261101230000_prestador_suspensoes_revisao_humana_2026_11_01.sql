-- ============================================================================
-- BORA — Suspensões de prestadores com revisão humana (Diretiva (UE) 2024/2831, art. 10.º e 11.º)
-- Missão diretiva-plataformas-2026-11-01 (Claude Code, 01/11/2026).
-- ESTADO: PREPARADA, NÃO APLICADA. O Danilo aplica (ordem de 01/11/2026: "deixa escrito no
-- sistema ... e garantir que uma pessoa revê as suspensões").
--
-- O QUE FAZ (em português de gente):
--  1. Tabela prestador_suspensoes: toda a suspensão/encerramento/restrição de um prestador
--     (estafeta, motorista, limpeza, lavagem, casa, parceiro, serviço) fica registada com
--     motivo escrito, data, QUEM decidiu (pessoa admin, nunca "sistema"), até quando, e o
--     pedido de revisão + resposta humana com prazo de 7 dias.
--  2. Trava no servidor (trigger em drivers, cleaners, washers, casa_profissionais,
--     restaurants, service_providers): ninguém põe is_banned=true / approval_status='suspended'
--     / is_active_admin=false sem um registo humano em prestador_suspensoes. Um cron, um robô
--     ou uma função sem pessoa por trás é RECUSADO (SUSPENSAO_SEM_HUMANO). Um admin que
--     esqueça o motivo é recusado (SUSPENSAO_SEM_MOTIVO).
--  3. RPCs: admin_suspender_prestador, admin_reativar_prestador, admin_responder_revisao,
--     admin_registar_pedido_revisao (pedido chegado por WhatsApp/email),
--     prestador_minha_suspensao (ecrã da app), prestador_pedir_revisao (botão da app).
--  4. Vista admin_fila_revisoes: fila de revisões pendentes com prazo e atraso.
--  5. Corrige cancel_cleaning_booking: a app DEIXA de suspender sozinha a profissional de
--     limpeza ao 3.º cancelamento tardio em 30 dias. Passa a criar uma "proposta automática"
--     na fila para uma pessoa decidir (art. 11.º/5: restrição/suspensão/encerramento só por humano).
--  6. Cron prestador_suspensoes_manutencao(): expira suspensões temporárias e avisa a equipa
--     quando faltam 2 dias para o prazo da revisão.
--
-- O QUE NÃO FAZ: não mexe em dinheiro, preços, dispatch, pricing_service, bora_tokens, Stripe.
-- Não apaga nada. admin_ban_driver / admin_review_cleaner / admin_update_washer continuam a
-- funcionar: o trigger reconhece que é um admin com motivo escrito e cria o registo sozinho.
-- O botão "desligar loja" do painel (is_active_admin=false direto) passa a exigir motivo:
-- o painel tem de chamar admin_suspender_prestador (ver relatório).
-- ============================================================================

BEGIN;

-- ─── 1. Tabela ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.prestador_suspensoes (
  id                    bigserial PRIMARY KEY,
  user_id               uuid,                       -- conta auth do prestador (pode ser NULL em loja sem conta)
  tipo_conta            text NOT NULL CHECK (tipo_conta IN
                          ('estafeta','motorista','limpeza','lavagem','casa','parceiro','servico')),
  entidade_tabela       text NOT NULL CHECK (entidade_tabela IN
                          ('drivers','cleaners','washers','casa_profissionais','restaurants','service_providers')),
  entidade_id           text NOT NULL,              -- id da linha (uuid ou text legado)
  tipo                  text NOT NULL CHECK (tipo IN
                          ('suspensao_temporaria','suspensao','encerramento','restricao','proposta_automatica')),
  estado                text NOT NULL DEFAULT 'ativa' CHECK (estado IN
                          ('ativa','em_revisao','mantida','reduzida','revertida','expirada',
                           'pendente_decisao','arquivada')),
  motivo                text NOT NULL CHECK (length(trim(motivo)) >= 10),
  motivo_codigo         text,                       -- ex.: fraud, misconduct, documents_invalid, cancelamentos_tardios
  factos                jsonb NOT NULL DEFAULT '{}'::jsonb, -- pedidos, datas, contagens que sustentam o motivo
  origem                text NOT NULL DEFAULT 'admin' CHECK (origem IN ('admin','sistema')),
  decidido_por          uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decidido_por_email    text,
  decidido_em           timestamptz NOT NULL DEFAULT now(),
  ate                   timestamptz,                -- NULL = sem data de fim
  comunicado_em         timestamptz,                -- quando o prestador recebeu o motivo (art. 11.º/2)
  revisao_pedida_em     timestamptz,
  revisao_via           text CHECK (revisao_via IS NULL OR revisao_via IN ('app','whatsapp','email','telefone')),
  revisao_texto         text,
  revisao_prazo         timestamptz,                -- revisao_pedida_em + 7 dias (a lei dá 14)
  revisao_aviso_em      timestamptz,                -- último aviso à equipa sobre o prazo
  revisao_resposta      text,
  revisto_por           uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  revisto_em            timestamptz,
  reativado_em          timestamptz,
  reativado_por         uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reativacao_nota       text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  -- Regra de ouro: decisão humana tem pessoa; o sistema só pode PROPOR.
  CONSTRAINT prestador_suspensoes_humano_chk CHECK (
    (origem = 'sistema' AND tipo = 'proposta_automatica' AND decidido_por IS NULL)
    OR (origem = 'admin' AND tipo <> 'proposta_automatica' AND decidido_por IS NOT NULL)
  ),
  CONSTRAINT prestador_suspensoes_temp_tem_fim CHECK (tipo <> 'suspensao_temporaria' OR ate IS NOT NULL)
);

COMMENT ON TABLE public.prestador_suspensoes IS
  'Registo de toda a suspensão/encerramento/restrição de prestador, com motivo, quem decidiu (pessoa) e revisão humana em 7 dias. Diretiva (UE) 2024/2831 art. 11.º. Nunca apagar linhas.';
COMMENT ON COLUMN public.prestador_suspensoes.origem IS
  'admin = decisão de uma pessoa (obrigatório para suspender). sistema = só proposta automática para a fila, nunca suspende.';

CREATE INDEX IF NOT EXISTS idx_prestador_suspensoes_entidade
  ON public.prestador_suspensoes (entidade_tabela, entidade_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prestador_suspensoes_user
  ON public.prestador_suspensoes (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prestador_suspensoes_fila
  ON public.prestador_suspensoes (estado, revisao_prazo) WHERE estado IN ('em_revisao','pendente_decisao');

ALTER TABLE public.prestador_suspensoes ENABLE ROW LEVEL SECURITY;

CREATE POLICY prestador_suspensoes_admin_tudo ON public.prestador_suspensoes
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY prestador_suspensoes_proprio_le ON public.prestador_suspensoes
  FOR SELECT TO authenticated USING (user_id = auth.uid());

REVOKE ALL ON public.prestador_suspensoes FROM anon;
GRANT SELECT ON public.prestador_suspensoes TO authenticated;
GRANT INSERT, UPDATE ON public.prestador_suspensoes TO authenticated; -- RLS limita a admin

-- Ninguém apaga o registo (nem admin): histórico legal.
CREATE OR REPLACE FUNCTION public._prestador_suspensoes_sem_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'prestador_suspensoes: registo legal, não se apaga (arquivar com estado=arquivada)';
END $$;
CREATE OR REPLACE TRIGGER trg_prestador_suspensoes_sem_delete BEFORE DELETE ON public.prestador_suspensoes
  FOR EACH ROW EXECUTE FUNCTION public._prestador_suspensoes_sem_delete();

-- ─── 2. Ajudante: tipo_conta a partir da tabela e da linha ──────────────────
CREATE OR REPLACE FUNCTION public._prestador_tipo_conta(p_tabela text, p_row jsonb)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_tabela
    WHEN 'drivers' THEN CASE WHEN p_row->>'vehicle_type' = 'carro_passageiros' THEN 'motorista' ELSE 'estafeta' END
    WHEN 'cleaners' THEN 'limpeza'
    WHEN 'washers' THEN 'lavagem'
    WHEN 'casa_profissionais' THEN 'casa'
    WHEN 'restaurants' THEN 'parceiro'
    WHEN 'service_providers' THEN 'servico'
  END;
$$;

-- ─── 3. A TRAVA: suspensão só com registo humano ────────────────────────────
-- BEFORE UPDATE nas 6 tabelas. Deteta a transição para "suspenso/encerrado/desligado".
-- Procura um registo humano ativo criado nos últimos 10 minutos para esta entidade.
-- Se não há: admin com motivo escrito na própria linha → cria o registo sozinho;
-- admin sem motivo → SUSPENSAO_SEM_MOTIVO; sem pessoa (cron/robô/RPC de outro utilizador)
-- → SUSPENSAO_SEM_HUMANO.
CREATE OR REPLACE FUNCTION public.fn_suspensao_so_com_humano()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_old jsonb := to_jsonb(OLD);
  v_new jsonb := to_jsonb(NEW);
  v_transicao boolean := false;
  v_tipo text;
  v_motivo text;
  v_codigo text;
  v_ate timestamptz;
  v_uid uuid := auth.uid();
  v_email text;
  v_user_id uuid;
  v_id text := v_new->>'id';
BEGIN
  -- Deteção por tabela
  IF TG_TABLE_NAME = 'drivers' THEN
    IF COALESCE((v_new->>'is_banned')::boolean,false) AND NOT COALESCE((v_old->>'is_banned')::boolean,false) THEN
      v_transicao := true;
      v_ate := (v_new->>'banned_until')::timestamptz;
      v_tipo := CASE WHEN v_ate IS NULL THEN 'suspensao' ELSE 'suspensao_temporaria' END;
      v_motivo := v_new->>'ban_reason';
      v_codigo := v_new->>'ban_reason_code';
    ELSIF (v_new->>'deleted_at') IS NOT NULL AND (v_old->>'deleted_at') IS NULL THEN
      v_transicao := true;
      v_tipo := 'encerramento';
      v_motivo := v_new->>'deletion_reason';
    END IF;
  ELSIF TG_TABLE_NAME IN ('cleaners','casa_profissionais','washers') THEN
    IF COALESCE((v_new->>'is_banned')::boolean,false) AND NOT COALESCE((v_old->>'is_banned')::boolean,false) THEN
      v_transicao := true; v_tipo := 'suspensao'; v_motivo := v_new->>'ban_reason';
    ELSIF (v_new->>'approval_status') IN ('suspended','banned') AND (v_old->>'approval_status') IS DISTINCT FROM (v_new->>'approval_status') THEN
      v_transicao := true;
      v_tipo := CASE WHEN v_new->>'approval_status' = 'banned' THEN 'encerramento' ELSE 'suspensao' END;
      v_motivo := v_new->>'rejection_reason';
    ELSIF (v_new->>'approval_status') = 'rejected' AND (v_old->>'approval_status') = 'approved' THEN
      -- recusar quem já estava aprovado = encerrar a conta
      v_transicao := true; v_tipo := 'encerramento'; v_motivo := v_new->>'rejection_reason';
    END IF;
  ELSIF TG_TABLE_NAME IN ('restaurants','service_providers') THEN
    IF COALESCE((v_old->>'is_active_admin')::boolean,true) AND NOT COALESCE((v_new->>'is_active_admin')::boolean,true) THEN
      v_transicao := true; v_tipo := 'suspensao';
      v_motivo := NULLIF(current_setting('bora.motivo_suspensao', true), '');
      v_codigo := NULLIF(current_setting('bora.motivo_codigo', true), '');
    ELSIF (v_new->>'approval_status') = 'rejected' AND (v_old->>'approval_status') = 'approved' THEN
      v_transicao := true; v_tipo := 'encerramento'; v_motivo := v_new->>'rejection_reason';
    END IF;
  END IF;

  IF NOT v_transicao THEN RETURN NEW; END IF;

  -- Encerramento a pedido do próprio titular (Edge delete-account, 01/11/2026): não é suspensão,
  -- é o direito de apagar a conta. Padrão da anonimização: nome 'Conta eliminada' ou motivo
  -- 'Encerramento a pedido do titular' ou dono desligado da loja (user_id passa a NULL).
  IF (v_new->>'deletion_reason') ILIKE '%pedido do titular%'
     OR (v_new->>'name') = 'Conta eliminada'
     OR (TG_TABLE_NAME = 'restaurants' AND (v_old->>'user_id') IS NOT NULL AND (v_new->>'user_id') IS NULL) THEN
    RETURN NEW;
  END IF;

  -- Motivo pode também vir pela variável de sessão (RPC admin_suspender_prestador)
  v_motivo := COALESCE(NULLIF(trim(COALESCE(v_motivo,'')),''), NULLIF(current_setting('bora.motivo_suspensao', true), ''));
  v_codigo := COALESCE(v_codigo, NULLIF(current_setting('bora.motivo_codigo', true), ''));

  -- Já existe registo humano ativo recente para esta entidade? (criado pelo RPC) → ok
  IF EXISTS (
    SELECT 1 FROM public.prestador_suspensoes s
     WHERE s.entidade_tabela = TG_TABLE_NAME AND s.entidade_id = v_id
       AND s.origem = 'admin' AND s.estado = 'ativa'
       AND s.created_at > now() - interval '10 minutes'
  ) THEN
    RETURN NEW;
  END IF;

  -- Sem pessoa por trás (cron, robô, função chamada por não-admin) → recusa
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    BEGIN
      INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
      VALUES ('suspensao-so-com-humano', 'recusado', 'ok',
              TG_TABLE_NAME || ' id=' || COALESCE(left(v_id, 12), '?') || ' tipo=' || v_tipo || ' uid=' || COALESCE(v_uid::text, 'null'),
              'servidor');
    EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE EXCEPTION 'SUSPENSAO_SEM_HUMANO: % só pode ser decidido por uma pessoa da equipa Bora (Diretiva 2024/2831 art. 11.º/5). Usa admin_suspender_prestador.', v_tipo
      USING ERRCODE = 'P0001';
  END IF;

  -- Admin sem motivo escrito → recusa
  IF v_motivo IS NULL OR length(trim(v_motivo)) < 10 THEN
    RAISE EXCEPTION 'SUSPENSAO_SEM_MOTIVO: escreve o motivo (mínimo 10 letras) — o prestador tem direito a recebê-lo por escrito. Usa admin_suspender_prestador(...).'
      USING ERRCODE = 'P0001';
  END IF;

  -- Admin com motivo (ex.: admin_ban_driver, admin_review_cleaner) → cria o registo sozinho
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  v_user_id := CASE WHEN TG_TABLE_NAME = 'restaurants'
                    THEN COALESCE((v_new->>'user_id')::uuid, (v_new->>'user_')::uuid)
                    ELSE (v_new->>'user_id')::uuid END;

  INSERT INTO public.prestador_suspensoes
    (user_id, tipo_conta, entidade_tabela, entidade_id, tipo, estado, motivo, motivo_codigo,
     origem, decidido_por, decidido_por_email, ate, comunicado_em, factos)
  VALUES
    (v_user_id, public._prestador_tipo_conta(TG_TABLE_NAME, v_new), TG_TABLE_NAME, v_id, v_tipo, 'ativa',
     trim(v_motivo), v_codigo, 'admin', v_uid, v_email, v_ate, now(),
     jsonb_build_object('via', 'trigger', 'rpc_origem', 'coluna da tabela'));

  -- Comunicar ao prestador no mesmo dia (art. 11.º/2) — melhor esforço
  IF v_user_id IS NOT NULL THEN
    BEGIN
      PERFORM public._push_in_app_notification(v_user_id, 'conta_suspensa',
        CASE v_tipo WHEN 'encerramento' THEN 'A tua conta foi encerrada' ELSE 'A tua conta foi suspensa' END,
        'Motivo: ' || trim(v_motivo) || CASE WHEN v_ate IS NOT NULL THEN ' Até ' || to_char(v_ate AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '.' ELSE '' END
          || ' Podes pedir revisão na app (A minha conta) ou pelo WhatsApp da Bora. Uma pessoa responde em 7 dias.',
        NULL);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['drivers','cleaners','washers','casa_profissionais','restaurants','service_providers'] LOOP
    -- Corre antes dos outros triggers (nome começa por "a_" não é preciso: ordem alfabética
    -- só importa entre BEFORE do mesmo evento; este não depende de nenhum).
    EXECUTE format('CREATE OR REPLACE TRIGGER trg_suspensao_so_com_humano BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_suspensao_so_com_humano()', t);
  END LOOP;
END $$;

-- ─── 4. RPCs de admin ────────────────────────────────────────────────────────
-- 4a. Suspender / encerrar / restringir com registo completo. Aplica o estado na tabela certa.
CREATE OR REPLACE FUNCTION public.admin_suspender_prestador(
  p_entidade_tabela text,
  p_entidade_id     text,
  p_tipo            text,                 -- suspensao_temporaria | suspensao | encerramento | restricao
  p_motivo          text,
  p_ate             timestamptz DEFAULT NULL,
  p_motivo_codigo   text DEFAULT NULL,
  p_factos          jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin RECORD;
  v_row jsonb;
  v_user_id uuid;
  v_id bigint;
  v_tipo_conta text;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_tipo NOT IN ('suspensao_temporaria','suspensao','encerramento','restricao') THEN
    RAISE EXCEPTION 'tipo_invalido: %', p_tipo;
  END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 10 THEN
    RAISE EXCEPTION 'SUSPENSAO_SEM_MOTIVO: escreve o motivo (mínimo 10 letras)';
  END IF;
  IF p_tipo = 'suspensao_temporaria' AND (p_ate IS NULL OR p_ate <= now()) THEN
    RAISE EXCEPTION 'suspensao_temporaria_precisa_de_data_futura';
  END IF;
  IF p_entidade_tabela NOT IN ('drivers','cleaners','washers','casa_profissionais','restaurants','service_providers') THEN
    RAISE EXCEPTION 'tabela_invalida: %', p_entidade_tabela;
  END IF;

  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.id::text = $1', p_entidade_tabela)
    INTO v_row USING p_entidade_id;
  IF v_row IS NULL THEN RAISE EXCEPTION 'prestador_nao_encontrado: % %', p_entidade_tabela, p_entidade_id; END IF;

  v_user_id := CASE WHEN p_entidade_tabela = 'restaurants'
                    THEN COALESCE((v_row->>'user_id')::uuid, (v_row->>'user_')::uuid)
                    ELSE (v_row->>'user_id')::uuid END;
  v_tipo_conta := public._prestador_tipo_conta(p_entidade_tabela, v_row);

  -- Bloqueio por trabalho em curso (mesma regra da skill ban-or-reactivate-entity)
  IF p_entidade_tabela = 'drivers' AND EXISTS (
       SELECT 1 FROM public.orders o WHERE o.assigned_driver_id = p_entidade_id
          AND o.status IN ('preparing','callingDriver','driverAccepted','pickedUp','onTheWay')) THEN
    RAISE EXCEPTION 'prestador_com_pedido_em_curso: espera que termine ou passa o pedido com ops_reassign_order';
  END IF;

  -- 1) Registo humano primeiro (o trigger vai encontrá-lo)
  INSERT INTO public.prestador_suspensoes
    (user_id, tipo_conta, entidade_tabela, entidade_id, tipo, estado, motivo, motivo_codigo,
     factos, origem, decidido_por, decidido_por_email, ate, comunicado_em)
  VALUES
    (v_user_id, v_tipo_conta, p_entidade_tabela, p_entidade_id, p_tipo, 'ativa', trim(p_motivo), p_motivo_codigo,
     COALESCE(p_factos,'{}'::jsonb), 'admin', v_admin.admin_id, v_admin.admin_email, p_ate, now())
  RETURNING id INTO v_id;

  -- 2) Aplicar o estado na tabela (restricao não mexe no estado da conta: só regista)
  PERFORM set_config('bora.motivo_suspensao', trim(p_motivo), true);
  PERFORM set_config('bora.motivo_codigo', COALESCE(p_motivo_codigo,''), true);
  IF p_tipo <> 'restricao' THEN
    CASE p_entidade_tabela
      WHEN 'drivers' THEN
        IF p_tipo = 'encerramento' THEN
          UPDATE public.drivers SET deleted_at = now(), deleted_by = v_admin.admin_id,
                 deletion_reason = trim(p_motivo), is_online = false WHERE id::text = p_entidade_id;
        ELSE
          UPDATE public.drivers SET is_banned = true, banned_at = now(), banned_by = v_admin.admin_id,
                 banned_until = p_ate,
                 ban_reason_code = CASE WHEN p_motivo_codigo IN ('fraud','misconduct','documents_invalid','inactivity','safety')
                                        THEN p_motivo_codigo::public.ban_reason_code ELSE 'other'::public.ban_reason_code END,
                 ban_reason = trim(p_motivo), is_online = false WHERE id::text = p_entidade_id;
        END IF;
      WHEN 'cleaners' THEN
        UPDATE public.cleaners SET approval_status = 'suspended', rejection_reason = trim(p_motivo),
               is_active = false WHERE id::text = p_entidade_id;
      WHEN 'casa_profissionais' THEN
        UPDATE public.casa_profissionais SET approval_status = CASE WHEN p_tipo='encerramento' THEN 'banned' ELSE 'suspended' END,
               rejection_reason = trim(p_motivo), is_active = false WHERE id::text = p_entidade_id;
      WHEN 'washers' THEN
        UPDATE public.washers SET is_banned = true, ban_reason = trim(p_motivo), banned_at = now(),
               is_active = false WHERE id::text = p_entidade_id;
      WHEN 'restaurants' THEN
        UPDATE public.restaurants SET is_active_admin = false WHERE id::text = p_entidade_id;
      WHEN 'service_providers' THEN
        UPDATE public.service_providers SET is_active_admin = false, is_online = false WHERE id::text = p_entidade_id;
    END CASE;
  END IF;

  -- 3) Auditoria + aviso ao prestador
  BEGIN
    PERFORM public.log_admin_action('prestador_' || p_tipo, p_entidade_tabela, p_entidade_id,
      jsonb_build_object('suspensao_id', v_id, 'motivo', trim(p_motivo), 'codigo', p_motivo_codigo, 'ate', p_ate));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'admin_suspender_prestador: audit falhou: %', SQLERRM; END;

  IF v_user_id IS NOT NULL THEN
    BEGIN
      PERFORM public._push_in_app_notification(v_user_id, 'conta_suspensa',
        CASE p_tipo WHEN 'encerramento' THEN 'A tua conta foi encerrada'
                    WHEN 'restricao' THEN 'Restrição na tua conta'
                    ELSE 'A tua conta foi suspensa' END,
        'Motivo: ' || trim(p_motivo)
          || CASE WHEN p_ate IS NOT NULL THEN ' Até ' || to_char(p_ate AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '.' ELSE '' END
          || ' Podes pedir revisão na app (A minha conta) ou pelo WhatsApp da Bora. Uma pessoa responde em 7 dias.',
        NULL);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'suspensao_id', v_id, 'tipo', p_tipo, 'ate', p_ate, 'tipo_conta', v_tipo_conta);
END $$;

-- 4b. Reativar (decisão humana, com nota)
CREATE OR REPLACE FUNCTION public.admin_reativar_prestador(p_suspensao_id bigint, p_nota text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin RECORD; v_s public.prestador_suspensoes;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_nota IS NULL OR length(trim(p_nota)) < 3 THEN RAISE EXCEPTION 'nota_obrigatoria'; END IF;
  SELECT * INTO v_s FROM public.prestador_suspensoes WHERE id = p_suspensao_id FOR UPDATE;
  IF v_s.id IS NULL THEN RAISE EXCEPTION 'suspensao_nao_encontrada'; END IF;
  IF v_s.estado IN ('revertida','expirada','arquivada') THEN RAISE EXCEPTION 'ja_terminada: %', v_s.estado; END IF;

  CASE v_s.entidade_tabela
    WHEN 'drivers' THEN
      UPDATE public.drivers SET is_banned=false, banned_at=NULL, banned_by=NULL, banned_until=NULL,
             ban_reason_code=NULL, ban_reason=NULL, deleted_at=NULL, deleted_by=NULL, deletion_reason=NULL
       WHERE id::text = v_s.entidade_id;
    WHEN 'cleaners' THEN
      UPDATE public.cleaners SET approval_status='approved', rejection_reason=NULL, is_active=true, flagged_low_rating=false
       WHERE id::text = v_s.entidade_id;
    WHEN 'casa_profissionais' THEN
      UPDATE public.casa_profissionais SET approval_status='approved', rejection_reason=NULL, is_active=true
       WHERE id::text = v_s.entidade_id;
    WHEN 'washers' THEN
      UPDATE public.washers SET is_banned=false, ban_reason=NULL, banned_at=NULL, is_active=true
       WHERE id::text = v_s.entidade_id;
    WHEN 'restaurants' THEN
      UPDATE public.restaurants SET is_active_admin=true WHERE id::text = v_s.entidade_id;
    WHEN 'service_providers' THEN
      UPDATE public.service_providers SET is_active_admin=true WHERE id::text = v_s.entidade_id;
  END CASE;

  UPDATE public.prestador_suspensoes
     SET estado = 'revertida', reativado_em = now(), reativado_por = v_admin.admin_id, reativacao_nota = trim(p_nota)
   WHERE id = p_suspensao_id;

  BEGIN
    PERFORM public.log_admin_action('prestador_reativar', v_s.entidade_tabela, v_s.entidade_id,
      jsonb_build_object('suspensao_id', p_suspensao_id, 'nota', trim(p_nota)));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  IF v_s.user_id IS NOT NULL THEN
    BEGIN
      PERFORM public._push_in_app_notification(v_s.user_id, 'conta_reativada', 'A tua conta está ativa outra vez',
        'Uma pessoa da equipa Bora reviu o caso: ' || trim(p_nota) || ' Já podes voltar a ficar online.', NULL);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RETURN jsonb_build_object('ok', true, 'suspensao_id', p_suspensao_id);
END $$;

-- 4c. Registar pedido de revisão chegado por fora (WhatsApp/email/telefone)
CREATE OR REPLACE FUNCTION public.admin_registar_pedido_revisao(p_suspensao_id bigint, p_via text, p_texto text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin RECORD; v_s public.prestador_suspensoes;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_via NOT IN ('whatsapp','email','telefone') THEN RAISE EXCEPTION 'via_invalida'; END IF;
  SELECT * INTO v_s FROM public.prestador_suspensoes WHERE id = p_suspensao_id FOR UPDATE;
  IF v_s.id IS NULL THEN RAISE EXCEPTION 'suspensao_nao_encontrada'; END IF;
  IF v_s.estado NOT IN ('ativa','mantida','reduzida') THEN RAISE EXCEPTION 'estado_nao_permite_revisao: %', v_s.estado; END IF;
  UPDATE public.prestador_suspensoes
     SET estado='em_revisao', revisao_pedida_em=now(), revisao_via=p_via,
         revisao_texto=NULLIF(trim(COALESCE(p_texto,'')),''), revisao_prazo = now() + interval '7 days',
         revisao_resposta=NULL, revisto_por=NULL, revisto_em=NULL
   WHERE id = p_suspensao_id;
  RETURN jsonb_build_object('ok', true, 'prazo', now() + interval '7 days');
END $$;

-- 4d. Responder à revisão (pessoa). decisao: mantida | reduzida | revertida
CREATE OR REPLACE FUNCTION public.admin_responder_revisao(
  p_suspensao_id bigint, p_decisao text, p_resposta text, p_nova_ate timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin RECORD; v_s public.prestador_suspensoes;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_decisao NOT IN ('mantida','reduzida','revertida') THEN RAISE EXCEPTION 'decisao_invalida'; END IF;
  IF p_resposta IS NULL OR length(trim(p_resposta)) < 10 THEN
    RAISE EXCEPTION 'resposta_obrigatoria: a resposta tem de ser por escrito e fundamentada (mínimo 10 letras)';
  END IF;
  SELECT * INTO v_s FROM public.prestador_suspensoes WHERE id = p_suspensao_id FOR UPDATE;
  IF v_s.id IS NULL THEN RAISE EXCEPTION 'suspensao_nao_encontrada'; END IF;
  IF v_s.estado NOT IN ('em_revisao','pendente_decisao') THEN RAISE EXCEPTION 'nao_esta_em_revisao: %', v_s.estado; END IF;

  IF p_decisao = 'revertida' THEN
    PERFORM public.admin_reativar_prestador(p_suspensao_id, 'Revisão: ' || trim(p_resposta));
    UPDATE public.prestador_suspensoes
       SET revisao_resposta = trim(p_resposta), revisto_por = v_admin.admin_id, revisto_em = now()
     WHERE id = p_suspensao_id;
  ELSE
    IF p_decisao = 'reduzida' THEN
      IF p_nova_ate IS NULL OR p_nova_ate <= now() THEN RAISE EXCEPTION 'reduzida_precisa_de_nova_data_futura'; END IF;
      IF v_s.entidade_tabela = 'drivers' THEN
        UPDATE public.drivers SET banned_until = p_nova_ate WHERE id::text = v_s.entidade_id;
      END IF;
    END IF;
    UPDATE public.prestador_suspensoes
       SET estado = p_decisao, revisao_resposta = trim(p_resposta), revisto_por = v_admin.admin_id, revisto_em = now(),
           ate = CASE WHEN p_decisao = 'reduzida' THEN p_nova_ate ELSE ate END,
           tipo = CASE WHEN p_decisao = 'reduzida' AND tipo = 'suspensao' THEN 'suspensao_temporaria' ELSE tipo END
     WHERE id = p_suspensao_id;
  END IF;

  BEGIN
    PERFORM public.log_admin_action('prestador_revisao_' || p_decisao, v_s.entidade_tabela, v_s.entidade_id,
      jsonb_build_object('suspensao_id', p_suspensao_id, 'resposta', trim(p_resposta), 'nova_ate', p_nova_ate));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  IF v_s.user_id IS NOT NULL THEN
    BEGIN
      PERFORM public._push_in_app_notification(v_s.user_id, 'revisao_respondida', 'Resposta à tua revisão',
        CASE p_decisao WHEN 'mantida' THEN 'A suspensão mantém-se. '
                       WHEN 'reduzida' THEN 'A suspensão foi reduzida até ' || to_char(p_nova_ate AT TIME ZONE 'Europe/Lisbon','DD/MM HH24:MI') || '. '
                       ELSE 'A tua conta foi reativada. ' END || trim(p_resposta), NULL);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RETURN jsonb_build_object('ok', true, 'decisao', p_decisao);
END $$;

-- 4e. Transformar uma proposta automática em decisão (ou arquivar)
CREATE OR REPLACE FUNCTION public.admin_decidir_proposta(p_suspensao_id bigint, p_decisao text, p_motivo text, p_ate timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin RECORD; v_s public.prestador_suspensoes; v_r jsonb;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT * INTO v_s FROM public.prestador_suspensoes WHERE id = p_suspensao_id FOR UPDATE;
  IF v_s.id IS NULL OR v_s.tipo <> 'proposta_automatica' OR v_s.estado <> 'pendente_decisao' THEN
    RAISE EXCEPTION 'nao_e_proposta_pendente';
  END IF;
  IF p_decisao = 'arquivar' THEN
    UPDATE public.prestador_suspensoes SET estado='arquivada', revisto_por=v_admin.admin_id, revisto_em=now(),
           revisao_resposta = NULLIF(trim(COALESCE(p_motivo,'')),'') WHERE id = p_suspensao_id;
    RETURN jsonb_build_object('ok', true, 'decisao', 'arquivada');
  ELSIF p_decisao IN ('suspensao_temporaria','suspensao','encerramento','restricao') THEN
    v_r := public.admin_suspender_prestador(v_s.entidade_tabela, v_s.entidade_id, p_decisao, p_motivo, p_ate,
             v_s.motivo_codigo, v_s.factos || jsonb_build_object('proposta_id', p_suspensao_id));
    UPDATE public.prestador_suspensoes SET estado='arquivada', revisto_por=v_admin.admin_id, revisto_em=now(),
           revisao_resposta = 'Decidido: ' || p_decisao || ' (registo ' || (v_r->>'suspensao_id') || ')' WHERE id = p_suspensao_id;
    RETURN v_r;
  END IF;
  RAISE EXCEPTION 'decisao_invalida: %', p_decisao;
END $$;

-- ─── 5. RPCs do prestador (app) ──────────────────────────────────────────────
-- 5a. O que a app mostra no ecrã "A minha conta foi suspensa"
CREATE OR REPLACE FUNCTION public.prestador_minha_suspensao()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE((
    SELECT jsonb_build_object(
      'id', s.id, 'tipo', s.tipo, 'tipo_conta', s.tipo_conta, 'estado', s.estado,
      'motivo', s.motivo, 'decidido_em', s.decidido_em, 'ate', s.ate,
      'decidido_por', 'Equipa Bora (responsável)',   -- pessoa, sem expor o nome (privacidade do operador)
      'revisao_pedida_em', s.revisao_pedida_em, 'revisao_prazo', s.revisao_prazo,
      'revisao_resposta', s.revisao_resposta, 'revisto_em', s.revisto_em,
      'pode_pedir_revisao', s.estado IN ('ativa','mantida','reduzida'),
      'contacto_whatsapp', '+351937501673', 'contacto_email', 'boraappbora@gmail.com')
    FROM public.prestador_suspensoes s
    WHERE s.user_id = auth.uid() AND s.origem = 'admin'
      AND s.estado NOT IN ('revertida','expirada','arquivada')
    ORDER BY s.created_at DESC LIMIT 1
  ), jsonb_build_object('suspensa', false));
$$;

-- 5b. Botão "Pedir revisão" (art. 11.º/3). Prazo de resposta: 7 dias.
CREATE OR REPLACE FUNCTION public.prestador_pedir_revisao(p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_s public.prestador_suspensoes; v_prazo timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
    RAISE EXCEPTION 'escreve_o_teu_lado: conta o que aconteceu (mínimo 5 letras)';
  END IF;
  SELECT * INTO v_s FROM public.prestador_suspensoes
   WHERE user_id = v_uid AND origem = 'admin' AND estado IN ('ativa','mantida','reduzida')
   ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF v_s.id IS NULL THEN RAISE EXCEPTION 'sem_suspensao_ativa'; END IF;
  v_prazo := now() + interval '7 days';
  UPDATE public.prestador_suspensoes
     SET estado='em_revisao', revisao_pedida_em=now(), revisao_via='app', revisao_texto=trim(p_motivo),
         revisao_prazo=v_prazo, revisao_resposta=NULL, revisto_por=NULL, revisto_em=NULL
   WHERE id = v_s.id;
  BEGIN
    PERFORM public._cleaning_notify_admin('Pedido de revisão de suspensão',
      v_s.tipo_conta || ' (' || left(v_s.entidade_id, 8) || ') pediu revisão. Responder por escrito até '
      || to_char(v_prazo AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '. Painel > Revisões.');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
    VALUES ('revisao-humana', 'pedido', 'ok', v_s.entidade_tabela || ' id=' || left(v_s.entidade_id, 12) || ' suspensao=' || v_s.id, 'app');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN jsonb_build_object('ok', true, 'suspensao_id', v_s.id, 'prazo', v_prazo,
    'mensagem', 'Pedido registado. Uma pessoa da equipa Bora responde por escrito até ' || to_char(v_prazo AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '.');
END $$;

-- ─── 6. Vista do painel: fila de revisões e propostas, com prazo ────────────
CREATE OR REPLACE VIEW public.admin_fila_revisoes
WITH (security_invoker = true) AS
SELECT s.id, s.tipo_conta, s.entidade_tabela, s.entidade_id, s.user_id, s.tipo, s.estado,
       s.motivo, s.motivo_codigo, s.factos, s.decidido_por_email, s.decidido_em, s.ate,
       s.revisao_pedida_em, s.revisao_via, s.revisao_texto, s.revisao_prazo,
       CASE WHEN s.revisao_prazo IS NULL THEN NULL
            ELSE GREATEST(0, EXTRACT(epoch FROM (s.revisao_prazo - now())) / 86400.0)::numeric(6,1) END AS dias_restantes,
       (s.revisao_prazo IS NOT NULL AND s.revisao_prazo < now()) AS atrasada,
       s.created_at
  FROM public.prestador_suspensoes s
 WHERE s.estado IN ('em_revisao','pendente_decisao')
 ORDER BY (s.estado = 'em_revisao') DESC, s.revisao_prazo NULLS LAST, s.created_at;

GRANT SELECT ON public.admin_fila_revisoes TO authenticated; -- RLS da tabela: só admin vê tudo

-- ─── 7. Manutenção (cron de hora a hora) ────────────────────────────────────
-- Expira suspensões temporárias (reativa limpeza/lavagem/casa cuja data passou — os drivers
-- já expiram sozinhos por driver_effective_status) e avisa a equipa 2 dias antes do prazo.
CREATE OR REPLACE FUNCTION public.prestador_suspensoes_manutencao()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_exp int := 0; v_av int := 0; r RECORD;
BEGIN
  FOR r IN SELECT * FROM public.prestador_suspensoes
            WHERE estado IN ('ativa','mantida','reduzida') AND tipo = 'suspensao_temporaria'
              AND ate IS NOT NULL AND ate <= now() LOOP
    CASE r.entidade_tabela
      WHEN 'cleaners' THEN UPDATE public.cleaners SET approval_status='approved', rejection_reason=NULL, is_active=true WHERE id::text = r.entidade_id AND approval_status='suspended';
      WHEN 'casa_profissionais' THEN UPDATE public.casa_profissionais SET approval_status='approved', rejection_reason=NULL, is_active=true WHERE id::text = r.entidade_id AND approval_status='suspended';
      WHEN 'washers' THEN UPDATE public.washers SET is_banned=false, ban_reason=NULL, banned_at=NULL, is_active=true WHERE id::text = r.entidade_id;
      WHEN 'restaurants' THEN UPDATE public.restaurants SET is_active_admin=true WHERE id::text = r.entidade_id;
      WHEN 'service_providers' THEN UPDATE public.service_providers SET is_active_admin=true WHERE id::text = r.entidade_id;
      ELSE NULL; -- drivers: driver_effective_status já trata; limpamos só o registo
    END CASE;
    UPDATE public.prestador_suspensoes SET estado='expirada', reativado_em=now(), reativacao_nota='Suspensão temporária terminou na data marcada' WHERE id = r.id;
    v_exp := v_exp + 1;
    IF r.user_id IS NOT NULL THEN
      BEGIN
        PERFORM public._push_in_app_notification(r.user_id, 'conta_reativada', 'A tua suspensão terminou', 'Já podes voltar a ficar online.', NULL);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;

  FOR r IN SELECT * FROM public.prestador_suspensoes
            WHERE estado = 'em_revisao' AND revisao_prazo IS NOT NULL
              AND revisao_prazo - now() < interval '2 days'
              AND (revisao_aviso_em IS NULL OR revisao_aviso_em < now() - interval '1 day') LOOP
    BEGIN
      PERFORM public._cleaning_notify_admin(
        CASE WHEN r.revisao_prazo < now() THEN 'REVISÃO ATRASADA (lei: resposta por escrito)' ELSE 'Revisão a vencer em menos de 2 dias' END,
        r.tipo_conta || ' (' || left(r.entidade_id, 8) || ') — prazo ' || to_char(r.revisao_prazo AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '. Painel > Revisões.');
    EXCEPTION WHEN OTHERS THEN NULL; END;
    UPDATE public.prestador_suspensoes SET revisao_aviso_em = now() WHERE id = r.id;
    v_av := v_av + 1;
  END LOOP;
  RETURN jsonb_build_object('expiradas', v_exp, 'avisos', v_av);
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prestador-suspensoes-manutencao') THEN
      PERFORM cron.schedule('prestador-suspensoes-manutencao', '23 * * * *', 'SELECT public.prestador_suspensoes_manutencao();');
    END IF;
  END IF;
END $$;

-- ─── 8. cancel_cleaning_booking: a app deixa de suspender sozinha ───────────
-- Única mudança: o bloco "IF v_late_count >= v_limit" já não faz
-- UPDATE cleaners SET approval_status='suspended'. Cria uma proposta automática na fila
-- (prestador_suspensoes, origem=sistema, estado=pendente_decisao) e avisa a equipa e a
-- profissional de que uma PESSOA vai rever. O resto da função é igual ao que está em produção.
CREATE OR REPLACE FUNCTION public.cancel_cleaning_booking(p_booking_id uuid, p_reason text DEFAULT ''::text, p_no_show boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_b cleaning_bookings;
  v_me cleaners;
  v_is_client boolean;
  v_hours numeric;
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_half int := public._cleaning_setting_int('cleaning_cancel_half_hours', 2);
  v_fee int := 0;
  v_late boolean := false;
  v_late_count int;
  v_limit int := public._cleaning_setting_int('cleaning_late_cancel_limit', 3);
  v_bora_pct int := public._cleaning_setting_int('cleaning_bora_pct', 15);
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted','on_the_way') THEN
    RAISE EXCEPTION 'cannot_cancel_from_%', v_b.status;
  END IF;

  v_is_client := (v_b.client_user_id = v_uid);
  IF NOT v_is_client THEN
    v_me := public._cleaning_current_cleaner();
    IF v_b.cleaner_id IS DISTINCT FROM v_me.id
       AND v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
      RAISE EXCEPTION 'booking_not_yours';
    END IF;
  END IF;

  v_hours := EXTRACT(epoch FROM (v_b.scheduled_at - now())) / 3600.0;

  IF v_is_client THEN
    IF v_hours >= v_free OR now() - v_b.created_at <= make_interval(mins => public._cleaning_setting_int('cleaning_cancel_grace_minutes', 5)) THEN v_fee := 0;
    ELSIF v_hours >= v_half THEN v_fee := round(v_b.total_cents * 0.5)::int;
    ELSE v_fee := v_b.total_cents;
    END IF;

    UPDATE cleaning_bookings
    SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'client',
        cancel_reason = COALESCE(p_reason,''), cancel_fee_cents = v_fee,
        payment_status = CASE
          WHEN payment_method = 'cash' AND v_fee > 0 THEN 'cash_pending'
          WHEN payment_status = 'held' THEN 'estornado'
          ELSE payment_status
        END,
        offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;

    IF v_b.cleaner_id IS NOT NULL THEN
      PERFORM public._cleaning_notify_user(
        (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
        'cleaning_cancelled', 'Limpeza cancelada',
        'O cliente cancelou a limpeza de ' ||
        to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
        CASE WHEN v_fee > 0
             THEN '. Recebes ' || (round(v_fee * (100 - v_bora_pct) / 100.0) / 100.0)::numeric(10,2) || ' EUR de compensação.'
             ELSE '.' END,
        p_booking_id::text);
    END IF;

  ELSE
    IF p_no_show THEN
      IF now() < v_b.scheduled_at THEN
        RAISE EXCEPTION 'no_show_only_after_scheduled_time';
      END IF;
      v_fee := v_b.total_cents;
      UPDATE cleaning_bookings
      SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'cleaner',
          cancel_reason = COALESCE(NULLIF(p_reason,''), 'no_show_cliente'),
          cancel_fee_cents = v_fee, no_show_client = true,
          payment_status = CASE
            WHEN payment_method = 'cash' THEN 'cash_pending'
            WHEN payment_status = 'held' THEN 'released'
            ELSE payment_status END
      WHERE id = p_booking_id;
      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_no_show',
        'Limpeza marcada como não comparência',
        'A profissional não conseguiu aceder à morada à hora marcada. Foi aplicada a taxa prevista.',
        p_booking_id::text);
    ELSE
      v_late := (v_hours < v_free);
      UPDATE cleaning_bookings
      SET status = 'scheduled', cleaner_id = NULL, accepted_at = NULL,
          cancelled_late = v_late OR cancelled_late,
          offer_cleaner_id = NULL, offer_expires_at = NULL,
          offered_cleaner_ids = CASE WHEN v_me.id = ANY (offered_cleaner_ids)
                                     THEN offered_cleaner_ids
                                     ELSE offered_cleaner_ids || v_me.id END
      WHERE id = p_booking_id;

      IF v_late THEN
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, true);
        SELECT count(*) INTO v_late_count FROM cleaner_cancel_events
        WHERE cleaner_id = v_me.id AND was_late AND created_at > now() - interval '30 days';
        IF v_late_count >= v_limit THEN
          -- Diretiva 2024/2831 art. 11.º/5: suspender é decisão de PESSOA. A app só propõe.
          IF NOT EXISTS (SELECT 1 FROM public.prestador_suspensoes
                          WHERE entidade_tabela='cleaners' AND entidade_id = v_me.id::text
                            AND tipo='proposta_automatica' AND estado='pendente_decisao') THEN
            INSERT INTO public.prestador_suspensoes
              (user_id, tipo_conta, entidade_tabela, entidade_id, tipo, estado, motivo, motivo_codigo, origem, factos)
            VALUES (v_me.user_id, 'limpeza', 'cleaners', v_me.id::text, 'proposta_automatica', 'pendente_decisao',
                    'Proposta automática: ' || v_late_count || ' cancelamentos tardios em 30 dias (limite ' || v_limit || '). Uma pessoa decide.',
                    'cancelamentos_tardios', 'sistema',
                    jsonb_build_object('cancelamentos_tardios_30d', v_late_count, 'limite', v_limit, 'ultimo_booking', p_booking_id));
          END IF;
          PERFORM public._cleaning_notify_admin('Profissional precisa de decisão humana',
            v_me.name || ' atingiu ' || v_late_count || ' cancelamentos tardios em 30 dias. A app NÃO suspendeu: decide no painel > Revisões.');
          PERFORM public._cleaning_notify_user(v_me.user_id, 'cleaner_revisao',
            'A tua conta vai ser revista',
            'Atingiste o limite de cancelamentos tardios. Uma pessoa da equipa Bora vai rever a tua conta e falar contigo antes de qualquer decisão.',
            NULL);
        END IF;
      ELSE
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, false);
      END IF;

      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_reassigning',
        'A tua limpeza vai ser reatribuída',
        'A profissional cancelou. Estamos a procurar outra profissional para o mesmo horário.',
        p_booking_id::text);
      PERFORM public._cleaning_next_offer(p_booking_id);
    END IF;
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $function$;

-- ─── 9. Grants ───────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.admin_suspender_prestador(text,text,text,text,timestamptz,text,jsonb) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_reativar_prestador(bigint,text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_registar_pedido_revisao(bigint,text,text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_responder_revisao(bigint,text,text,timestamptz) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_decidir_proposta(bigint,text,text,timestamptz) FROM public, anon;
REVOKE ALL ON FUNCTION public.prestador_minha_suspensao() FROM public, anon;
REVOKE ALL ON FUNCTION public.prestador_pedir_revisao(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.prestador_suspensoes_manutencao() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_suspensao_so_com_humano() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public._prestador_tipo_conta(text,jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_suspender_prestador(text,text,text,text,timestamptz,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reativar_prestador(bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_registar_pedido_revisao(bigint,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_responder_revisao(bigint,text,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_decidir_proposta(bigint,text,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prestador_minha_suspensao() TO authenticated;
GRANT EXECUTE ON FUNCTION public.prestador_pedir_revisao(text) TO authenticated;

-- ─── 10. Texto legal nas versões de termos (para o TermsGate mostrar) ──────
-- Versão 2026-11-02 para estafetas: não substitui a de 01/11 (recibo à Bora); acrescenta
-- a informação sobre sistemas automáticos e revisão humana (art. 9.º e 11.º). O texto
-- completo está em docs/legal/gestao-algoritmica-prestadores.md. Só inserir depois de o
-- Danilo confirmar que quer que o portão de termos volte a perguntar (2.ª aceitação em 2 dias).
-- INSERT INTO public.legal_terms_versions (version, audience, effective_date, title, body) VALUES (...);

COMMIT;
