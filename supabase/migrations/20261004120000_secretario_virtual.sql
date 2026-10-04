-- ============================================================================
-- Missão única 2026-10-03 · Bloco 5 — Vender o "Secretário Virtual" em Portugal inteiro
-- Escrita 04/10 no PC; APLICAR pela Claude.ai (conector do PC prende nas escritas).
-- Não toca em dinheiro. "vai" do Danilo 04/10 08h52 para enviar emails com o número de teste.
--
-- Peças:
--   a) alvo novo cliente_tipo='secretario-virtual' + RPC do caçador (ferramentas/secretario-virtual)
--   b) negócio de DEMONSTRAÇÃO escondido (não aprovado, invisível na app) + tenant
--      'secretario-demo' no número da Bora (vps-baileys:351937501673) em modo TESTE;
--      convites com código: o prospect escreve "TESTE 1234" → o número entra na allowlist
--      da demo por 7 dias e sai sozinho depois (relógio horário).
--   c) redator/carteiro: entra na MESMA fila do site (prospect_propostas) e no MESMO tecto
--      de 5 novos/dia útil, 09h30–11h30, conta Bora. Interruptor próprio
--      secretario_envio_ligado (começa FALSE).
--   d) painel admin: resumo + ligar/desligar.
-- ============================================================================

-- ── a) alvo novo ───────────────────────────────────────────────────────────
ALTER TABLE public.prospects_presenca DROP CONSTRAINT IF EXISTS prospects_presenca_cliente_tipo_check;
ALTER TABLE public.prospects_presenca ADD CONSTRAINT prospects_presenca_cliente_tipo_check
  CHECK (cliente_tipo IS NULL OR cliente_tipo IN ('site', 'parceiro-bora', 'funcionario-digital', 'os-dois', 'secretario-virtual'));

INSERT INTO public.platform_settings(key, value, category, description) VALUES
  ('secretario_envio_ligado', 'false'::jsonb, 'robos',
   'Secretário Virtual: o redator escreve e o carteiro envia emails a negócios de Portugal (mesmo tecto de 5/dia útil do caça-clientes).'),
  ('secretario_numero_teste', '"+351 937 501 673"'::jsonb, 'robos',
   'Número de WhatsApp de teste dado aos prospects do Secretário Virtual (número da Bora, tenant secretario-demo).')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.secretario_prospect_registar(p_chave text, p_linha jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'vault' AS $f$
DECLARE v_id bigint; v_email text := lower(nullif(trim(p_linha->>'email'), ''));
BEGIN
  PERFORM public._caca_chave_ok(p_chave);
  IF v_email IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'sem_email'); END IF;
  SELECT id INTO v_id FROM public.prospects_presenca
   WHERE lower(email) = v_email
      OR (nullif(p_linha->>'website', '') IS NOT NULL AND website = p_linha->>'website')
   LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'id', v_id, 'novo', false); END IF;
  INSERT INTO public.prospects_presenca(fonte_id, nome, categoria, morada, concelho, telefone, email, website,
       instagram, facebook, estado, email_verificado, email_fonte, canal_preferido, gancho, cliente_tipo, pontuacao)
  VALUES (p_linha->>'fonte_id', p_linha->>'nome', p_linha->>'categoria', nullif(p_linha->>'morada', ''),
          nullif(p_linha->>'concelho', ''), nullif(p_linha->>'telefone', ''), v_email, nullif(p_linha->>'website', ''),
          nullif(p_linha->>'instagram', ''), nullif(p_linha->>'facebook', ''), 'novo', true,
          coalesce(p_linha->>'email_fonte', 'site'), 'email', p_linha->>'gancho', 'secretario-virtual', 50)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'novo', true);
END $f$;
REVOKE ALL ON FUNCTION public.secretario_prospect_registar(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.secretario_prospect_registar(text, jsonb) TO anon, authenticated, service_role;

-- ── b) negócio de demonstração (ESCONDIDO) + tenant ───────────────────────
-- approval_status 'pending' + is_active_admin=false: não aparece na app. Só serve a agenda da demo.
INSERT INTO public.service_providers(id, name, category, address, phone, approval_status, is_active_admin,
                                     about_text, business_hours)
VALUES ('5ec0de00-0000-4000-8000-000000000001', 'Barbearia Bora Demo', 'barbershop',
        'Rua de Demonstração 1, Guarda (fictícia)', '+351937501673', 'pending', false,
        'Negócio fictício para demonstrar o Secretário Virtual. Não existe.',
        '{"mon":{"open":"09:00","close":"19:00","closed":false},"tue":{"open":"09:00","close":"19:00","closed":false},
          "wed":{"open":"09:00","close":"19:00","closed":false},"thu":{"open":"09:00","close":"19:00","closed":false},
          "fri":{"open":"09:00","close":"20:00","closed":false},"sat":{"open":"09:00","close":"13:00","closed":false},
          "sun":{"open":"09:00","close":"13:00","closed":true}}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.provider_services(provider_id, name, description, price_cents, duration_minutes, is_active, sort_order) VALUES
  ('5ec0de00-0000-4000-8000-000000000001', 'Corte de cabelo', 'Corte à tesoura ou máquina, com lavagem.', 1200, 30, true, 1),
  ('5ec0de00-0000-4000-8000-000000000001', 'Corte + barba', 'Corte e barba com toalha quente.', 1800, 45, true, 2),
  ('5ec0de00-0000-4000-8000-000000000001', 'Barba', 'Barba aparada e desenhada à navalha.', 900, 20, true, 3),
  ('5ec0de00-0000-4000-8000-000000000001', 'Corte criança (até 12 anos)', 'Corte simples para crianças.', 900, 25, true, 4)
ON CONFLICT DO NOTHING;

INSERT INTO public.assistant_tenants(slug, nome, provider_id, sessao, mode, allowlist, blocklist,
       owner_number, dono_destino, knowledge, motor, motores_reserva, orcamento_mensal_eur, tom)
VALUES ('secretario-demo', 'Bora Secretário Virtual — demo', '5ec0de00-0000-4000-8000-000000000001',
        'vps-baileys:351937501673', 'teste', '{}', '{}', NULL, '351931992662',
        jsonb_build_object('ficha', jsonb_build_object(
          'nome', 'Barbearia Bora Demo',
          'dono', 'Rui (fictício)',
          'morada', 'Rua de Demonstração 1, Guarda — negócio fictício para teste',
          'telefone', '+351 937 501 673',
          'pagamento', 'Dinheiro, MB WAY e cartão no balcão.',
          'notas', 'ISTO É UMA DEMONSTRAÇÃO do Secretário Virtual da Bora App. A barbearia não existe: as marcações são de faz-de-conta. Se perguntarem como ter isto no negócio deles, diz que a equipa da Bora responde ao email que receberam (ou boraguarda.com/secretario). Nunca fales de preços do Secretário Virtual.',
          'apos_marcacao', 'Isto foi uma demonstração: no seu negócio, o cliente recebia agora a confirmação e um lembrete na véspera.'),
          'perguntas_aprendidas', '[]'::jsonb),
        'gemini:gemini-3-flash-preview',
        ARRAY['gemini2:gemini-3-flash-preview', 'gemini:gemini-3.1-flash-lite', 'gemini2:gemini-3.1-flash-lite',
              'groq:openai/gpt-oss-120b', 'groq:qwen/qwen3.8-27b'],
        0,
        'Português de Portugal, curto e simpático, como um bom recepcionista. Sem emojis em excesso.')
ON CONFLICT (slug) DO NOTHING;

-- ── convites ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.secretario_convites (
  id           bigserial PRIMARY KEY,
  prospect_id  bigint NOT NULL REFERENCES public.prospects_presenca(id),
  codigo       text NOT NULL,
  criado_em    timestamptz NOT NULL DEFAULT now(),
  valido_ate   timestamptz NOT NULL DEFAULT now() + interval '30 days',
  numero       text,
  ativado_em   timestamptz,
  expira_em    timestamptz,
  removido_em  timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS secretario_convites_codigo_vivo ON public.secretario_convites(codigo)
  WHERE removido_em IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS secretario_convites_um_por_prospect ON public.secretario_convites(prospect_id)
  WHERE removido_em IS NULL;
ALTER TABLE public.secretario_convites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS secretario_convites_admin ON public.secretario_convites;
CREATE POLICY secretario_convites_admin ON public.secretario_convites FOR SELECT TO authenticated USING (public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.secretario_convites FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._secretario_convite(p_prospect_id bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE v text; i int := 0;
BEGIN
  SELECT codigo INTO v FROM public.secretario_convites WHERE prospect_id = p_prospect_id AND removido_em IS NULL;
  IF v IS NOT NULL THEN RETURN v; END IF;
  LOOP
    v := lpad((floor(random() * 9000) + 1000)::int::text, 4, '0');
    BEGIN
      INSERT INTO public.secretario_convites(prospect_id, codigo) VALUES (p_prospect_id, v);
      RETURN v;
    EXCEPTION WHEN unique_violation THEN
      i := i + 1; IF i > 20 THEN RAISE; END IF;
    END;
  END LOOP;
END $f$;
REVOKE ALL ON FUNCTION public._secretario_convite(bigint) FROM PUBLIC, anon, authenticated;

-- Chamada pelo assistente (service_role) quando um número desconhecido escreve "TESTE 1234".
CREATE OR REPLACE FUNCTION public.secretario_ativar(p_numero text, p_codigo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE c public.secretario_convites%ROWTYPE; v_num text := regexp_replace(coalesce(p_numero, ''), '\D', '', 'g');
        v_tid uuid;
BEGIN
  IF length(v_num) < 9 THEN RETURN jsonb_build_object('ok', false, 'motivo', 'numero_invalido'); END IF;
  -- Nunca mexer em números de outros clientes do assistente (Mister Navalha/Ernando, dono, Danilo).
  IF EXISTS (SELECT 1 FROM public.assistant_tenants t
              WHERE t.slug <> 'secretario-demo'
                AND (v_num = ANY (t.allowlist) OR v_num = regexp_replace(coalesce(t.owner_number, ''), '\D', '', 'g')
                     OR v_num = regexp_replace(coalesce(t.dono_destino, ''), '\D', '', 'g'))) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'numero_de_outro_cliente');
  END IF;
  SELECT * INTO c FROM public.secretario_convites
   WHERE codigo = p_codigo AND removido_em IS NULL AND valido_ate > now()
   FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'motivo', 'codigo_invalido'); END IF;
  IF c.numero IS NOT NULL AND c.numero <> v_num THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'codigo_ja_usado');
  END IF;
  UPDATE public.secretario_convites
     SET numero = v_num, ativado_em = COALESCE(ativado_em, now()),
         expira_em = COALESCE(expira_em, now() + interval '7 days')
   WHERE id = c.id;
  UPDATE public.assistant_tenants
     SET allowlist = array_append(allowlist, v_num), updated_at = now()
   WHERE slug = 'secretario-demo' AND NOT (v_num = ANY (allowlist))
  RETURNING id INTO v_tid;
  UPDATE public.prospects_presenca SET resposta = coalesce(resposta || ' | ', '') || 'testou a demo ' || to_char(now(), 'DD/MM HH24:MI'),
         atualizado_em = now()
   WHERE id = c.prospect_id;
  RETURN jsonb_build_object('ok', true, 'expira_em', (SELECT expira_em FROM public.secretario_convites WHERE id = c.id));
END $f$;
REVOKE ALL ON FUNCTION public.secretario_ativar(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.secretario_ativar(text, text) TO service_role;

-- Relógio: tira da allowlist da demo quem passou os 7 dias.
CREATE OR REPLACE FUNCTION public.secretario_expirar()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE x record; n int := 0;
BEGIN
  FOR x IN SELECT id, numero FROM public.secretario_convites
            WHERE numero IS NOT NULL AND removido_em IS NULL AND expira_em <= now() LOOP
    UPDATE public.assistant_tenants SET allowlist = array_remove(allowlist, x.numero), updated_at = now()
     WHERE slug = 'secretario-demo';
    UPDATE public.secretario_convites SET removido_em = now() WHERE id = x.id;
    n := n + 1;
  END LOOP;
  RETURN n;
END $f$;
REVOKE ALL ON FUNCTION public.secretario_expirar() FROM PUBLIC, anon, authenticated;
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'secretario-expirar';
SELECT cron.schedule('secretario-expirar', '17 * * * *', $$SELECT public.secretario_expirar();$$);

-- ── c) redator: a mesma fila, com os prospects do secretário (sem amostra) ──
CREATE OR REPLACE FUNCTION public.redator_fila(p_chave text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'vault' AS $function$
DECLARE v_sec boolean;
BEGIN
  PERFORM public._caca_chave_ok(p_chave);
  SELECT coalesce((value #>> '{}')::boolean, false) INTO v_sec FROM public.platform_settings WHERE key = 'secretario_envio_ligado';
  RETURN coalesce((SELECT jsonb_agg(x) FROM (
    -- (igual ao de 03/10) site / parceiro-bora: precisam da amostra
    SELECT jsonb_build_object('id', p.id, 'nome', p.nome, 'categoria', p.categoria, 'concelho', p.concelho, 'gancho', p.gancho,
                              'cliente_tipo', p.cliente_tipo, 'link', a.link_unico) x
      FROM public.prospects_presenca p
      JOIN LATERAL (SELECT link_unico FROM public.prospect_amostras a WHERE a.prospect_id = p.id ORDER BY criado_em DESC LIMIT 1) a ON true
     WHERE p.email_verificado AND coalesce(p.email, '') <> '' AND p.estado IN ('novo', 'amostra_pronta', 'proposta_rascunho')
       AND coalesce(p.cliente_tipo, '') <> 'secretario-virtual'
       AND NOT EXISTS (SELECT 1 FROM public.prospect_propostas r WHERE r.prospect_id = p.id AND r.canal = 'email'
                        AND r.estado IN ('pronta', 'enviada', 'respondeu', 'recusou', 'sem_resposta', 'pausada'))
    UNION ALL
    -- secretário virtual: link fixo da página + código de teste (só com o interruptor ligado)
    SELECT jsonb_build_object('id', p.id, 'nome', p.nome, 'categoria', p.categoria, 'concelho', p.concelho, 'gancho', p.gancho,
                              'cliente_tipo', p.cliente_tipo, 'link', 'https://boraguarda.com/secretario',
                              'codigo', public._secretario_convite(p.id),
                              'numero_teste', (SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'secretario_numero_teste'))
      FROM public.prospects_presenca p
     WHERE v_sec AND p.cliente_tipo = 'secretario-virtual'
       AND p.email_verificado AND coalesce(p.email, '') <> '' AND p.estado IN ('novo', 'proposta_rascunho')
       AND NOT EXISTS (SELECT 1 FROM public.prospect_propostas r WHERE r.prospect_id = p.id AND r.canal = 'email'
                        AND r.estado IN ('pronta', 'enviada', 'respondeu', 'recusou', 'sem_resposta', 'pausada'))
     LIMIT 40) q), '[]'::jsonb);
END $function$;

-- ── d) painel admin ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_secretario_resumo()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  RETURN jsonb_build_object(
    'envio_ligado', (SELECT coalesce((value #>> '{}')::boolean, false) FROM public.platform_settings WHERE key = 'secretario_envio_ligado'),
    'numero_teste', (SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'secretario_numero_teste'),
    'prospects', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', p.id, 'nome', p.nome, 'categoria', p.categoria, 'concelho', p.concelho, 'email', p.email,
        'estado', p.estado, 'gancho', p.gancho, 'resposta', p.resposta,
        'codigo', c.codigo, 'testou_em', c.ativado_em, 'numero', c.numero, 'expira_em', c.expira_em,
        'email_estado', (SELECT r.estado FROM public.prospect_propostas r WHERE r.prospect_id = p.id AND r.canal = 'email' ORDER BY r.id DESC LIMIT 1),
        'enviado_em', (SELECT r.enviado_em FROM public.prospect_propostas r WHERE r.prospect_id = p.id AND r.canal = 'email' ORDER BY r.id DESC LIMIT 1))
        ORDER BY c.ativado_em DESC NULLS LAST, p.id DESC)
      FROM public.prospects_presenca p
      LEFT JOIN public.secretario_convites c ON c.prospect_id = p.id AND c.removido_em IS NULL
     WHERE p.cliente_tipo = 'secretario-virtual'), '[]'::jsonb),
    'conversas_demo', coalesce((SELECT jsonb_agg(m ORDER BY m->>'em' DESC) FROM (
        SELECT jsonb_build_object('numero', am.numero, 'direcao', am.direcao, 'texto', left(am.texto, 300), 'em', am.created_at) m
          FROM public.assistant_messages am JOIN public.assistant_tenants t ON t.id = am.tenant_id
         WHERE t.slug = 'secretario-demo' ORDER BY am.created_at DESC LIMIT 200) z), '[]'::jsonb));
END $f$;
REVOKE ALL ON FUNCTION public.admin_secretario_resumo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_secretario_resumo() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_secretario_envio(p_ligado boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE n int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  UPDATE public.platform_settings SET value = to_jsonb(p_ligado) WHERE key = 'secretario_envio_ligado';
  IF NOT p_ligado THEN
    -- desligar trava também o que já estava pronto para sair
    UPDATE public.prospect_propostas r SET estado = 'pausada', atualizado_em = now()
      FROM public.prospects_presenca p
     WHERE p.id = r.prospect_id AND p.cliente_tipo = 'secretario-virtual' AND r.estado = 'pronta';
    GET DIAGNOSTICS n = ROW_COUNT;
  ELSE
    UPDATE public.prospect_propostas r SET estado = 'pronta', atualizado_em = now()
      FROM public.prospects_presenca p
     WHERE p.id = r.prospect_id AND p.cliente_tipo = 'secretario-virtual' AND r.estado = 'pausada' AND r.enviado_em IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
  END IF;
  RETURN jsonb_build_object('ok', true, 'ligado', p_ligado, 'propostas_mexidas', n);
END $f$;
REVOKE ALL ON FUNCTION public.admin_secretario_envio(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_secretario_envio(boolean) TO authenticated;
