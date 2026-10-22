-- Receita do Dia (Bora Todo Dia, novidade n.º 2) — 15/10/2026.
-- Missão sistema-sem-travas-2026-10-15, bloco 4.3. Ordem do Danilo: uma receita
-- por dia em PT-PT com 5 a 8 ingredientes comuns, aviso às 10:00 de Lisboa só a
-- quem pedir, botão "Pôr no carrinho" no supermercado não-parceiro mais barato
-- (reusa assistant_basket_quote do Bora Assistente), painel admin para criar,
-- editar, agendar, ligar/desligar e mudar a hora. Não dá nem gasta nada ao
-- cliente: é só conteúdo e um atalho para o carrinho normal.

-- ---------------------------------------------------------------------------
-- 1. Tabelas
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.receitas_do_dia (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo         text NOT NULL CHECK (length(btrim(titulo)) BETWEEN 3 AND 80),
  resumo         text,
  ingredientes   jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(ingredientes) = 'array'),
  passos         jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(passos) = 'array'),
  tempo_min      integer CHECK (tempo_min BETWEEN 1 AND 600),
  doses          integer CHECK (doses BETWEEN 1 AND 20),
  foto_url       text,
  data_agendada  date UNIQUE,
  ordem          integer NOT NULL DEFAULT 0,
  ativa          boolean NOT NULL DEFAULT true,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.receitas_do_dia IS
  'Receita do Dia (15/10/2026). ingredientes = [{nome, quantidade, pesquisa}]; pesquisa = termo para achar o produto no supermercado. data_agendada fixa a receita num dia; sem data entra na rotação por ordem.';

ALTER TABLE public.receitas_do_dia ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS receitas_do_dia_admin ON public.receitas_do_dia;
CREATE POLICY receitas_do_dia_admin ON public.receitas_do_dia
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
-- O cliente lê só a receita de hoje, pela função client_receita_de_hoje().
REVOKE ALL ON public.receitas_do_dia FROM anon;
REVOKE TRUNCATE ON public.receitas_do_dia FROM authenticated;

CREATE OR REPLACE FUNCTION public._receitas_do_dia_tocar()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_receitas_do_dia_tocar ON public.receitas_do_dia;
CREATE TRIGGER trg_receitas_do_dia_tocar BEFORE UPDATE ON public.receitas_do_dia
  FOR EACH ROW EXECUTE FUNCTION public._receitas_do_dia_tocar();

-- Quem pediu o aviso diário (opt-in explícito no ecrã da receita).
CREATE TABLE IF NOT EXISTS public.receita_avisos (
  user_id        uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  ligado         boolean NOT NULL,
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.receita_avisos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS receita_avisos_ler_o_meu ON public.receita_avisos;
CREATE POLICY receita_avisos_ler_o_meu ON public.receita_avisos
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.receita_avisos FROM anon, authenticated;

-- Um aviso por pessoa por dia (regista-se antes de enviar).
CREATE TABLE IF NOT EXISTS public.receita_avisos_envios (
  id           bigserial PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dia          date NOT NULL,
  receita_id   uuid,
  pedido_http  bigint,
  enviado_em   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT receita_avisos_um_por_dia UNIQUE (user_id, dia)
);
ALTER TABLE public.receita_avisos_envios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS receita_avisos_envios_admin_le ON public.receita_avisos_envios;
CREATE POLICY receita_avisos_envios_admin_le ON public.receita_avisos_envios
  FOR SELECT TO authenticated USING (public.is_admin());
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.receita_avisos_envios FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Definições (o painel muda-as com admin_update_setting)
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('receita_do_dia_enabled', 'true'::jsonb,
   'Receita do Dia: mostra o cartão na home do cliente.', 'marketing'),
  ('receita_do_dia_push_enabled', 'true'::jsonb,
   'Receita do Dia: envia o aviso diário a quem o pediu no ecrã da receita.', 'marketing'),
  ('receita_do_dia_push_hour', '10'::jsonb,
   'Receita do Dia: hora do aviso diário (0-23, hora de Lisboa).', 'marketing')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. A receita de hoje (agendada para hoje; senão a da rotação)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._receita_de_hoje(p_dia date)
RETURNS public.receitas_do_dia
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r   public.receitas_do_dia;
  n   integer;
BEGIN
  SELECT * INTO r FROM public.receitas_do_dia
   WHERE ativa AND data_agendada = p_dia LIMIT 1;
  IF FOUND THEN RETURN r; END IF;

  SELECT count(*) INTO n FROM public.receitas_do_dia
   WHERE ativa AND data_agendada IS NULL;
  IF n = 0 THEN RETURN NULL; END IF;

  SELECT * INTO r FROM public.receitas_do_dia
   WHERE ativa AND data_agendada IS NULL
   ORDER BY ordem, criado_em, id
  OFFSET ((p_dia - date '2026-01-01') % n) LIMIT 1;
  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.client_receita_de_hoje()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_hoje   date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_on     boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_enabled'), false);
  v_push   boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_push_enabled'), false);
  v_hora   integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings WHERE key = 'receita_do_dia_push_hour'), 10);
  r        public.receitas_do_dia;
BEGIN
  IF v_uid IS NULL OR NOT v_on THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;
  r := public._receita_de_hoje(v_hoje);
  IF r.id IS NULL THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;
  RETURN jsonb_build_object(
    'enabled', true,
    'dia', v_hoje,
    'aviso_disponivel', v_push,
    'aviso_hora', v_hora,
    'aviso_ligado', COALESCE((SELECT a.ligado FROM public.receita_avisos a WHERE a.user_id = v_uid), false),
    'receita', jsonb_build_object(
      'id', r.id, 'titulo', r.titulo, 'resumo', r.resumo,
      'ingredientes', r.ingredientes, 'passos', r.passos,
      'tempo_min', r.tempo_min, 'doses', r.doses, 'foto_url', r.foto_url));
END;
$$;

CREATE OR REPLACE FUNCTION public.client_receita_aviso(p_ligado boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  INSERT INTO public.receita_avisos (user_id, ligado, atualizado_em)
  VALUES (v_uid, COALESCE(p_ligado, false), now())
  ON CONFLICT (user_id) DO UPDATE SET ligado = EXCLUDED.ligado, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'aviso_ligado', COALESCE(p_ligado, false));
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Aviso diário (pg_cron de hora a hora; a hora certa vem das definições, em Lisboa)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.receita_avisos_processar()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hoje    date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_hora    integer := extract(hour FROM (now() AT TIME ZONE 'Europe/Lisbon'))::integer;
  v_on      boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_enabled'), false);
  v_push    boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_push_enabled'), false);
  v_h       integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings WHERE key = 'receita_do_dia_push_hour'), 10);
  r         public.receitas_do_dia;
  v_url     text;
  v_key     text;
  v_req     bigint;
  v_pessoas integer := 0;
  v_lotes   integer := 0;
  g         record;
BEGIN
  IF NOT (v_on AND v_push) THEN
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'desligado');
  END IF;
  IF v_hora <> v_h THEN
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'fora_de_hora', 'hora_lisboa', v_hora);
  END IF;
  r := public._receita_de_hoje(v_hoje);
  IF r.id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'sem_receita');
  END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'segredos_em_falta');
  END IF;

  FOR g IN
    WITH alvo AS (
      SELECT a.user_id
        FROM public.receita_avisos a
       WHERE a.ligado
         AND EXISTS (SELECT 1 FROM public.client_push_tokens t WHERE t.user_id = a.user_id AND t.active)
         AND NOT EXISTS (SELECT 1 FROM public.receita_avisos_envios e
                          WHERE e.user_id = a.user_id AND e.dia = v_hoje)
    ), lotes AS (
      -- lotes de 150: o push-clientes-alvo lê os aparelhos com a lista no endereço
      SELECT user_id, (row_number() OVER (ORDER BY user_id) - 1) / 150 AS lote FROM alvo
    )
    SELECT array_agg(user_id) AS ids FROM lotes GROUP BY lote
  LOOP
    -- regista primeiro: se o envio falhar, ninguém recebe o mesmo aviso duas vezes
    INSERT INTO public.receita_avisos_envios (user_id, dia, receita_id)
    SELECT x, v_hoje, r.id FROM unnest(g.ids) AS x
    ON CONFLICT ON CONSTRAINT receita_avisos_um_por_dia DO NOTHING;

    SELECT net.http_post(
      url := v_url || '/functions/v1/push-clientes-alvo',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object('user_ids', to_jsonb(g.ids), 'title', 'Receita do dia',
                                 'body', 'Hoje: ' || r.titulo || '. Os ingredientes vão para o carrinho num toque.',
                                 'type', 'receita_do_dia'),
      timeout_milliseconds := 60000
    ) INTO v_req;

    UPDATE public.receita_avisos_envios SET pedido_http = v_req
     WHERE dia = v_hoje AND user_id = ANY (g.ids);

    v_pessoas := v_pessoas + array_length(g.ids, 1);
    v_lotes := v_lotes + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'dia', v_hoje, 'receita', r.titulo,
                            'pessoas', v_pessoas, 'pedidos_http', v_lotes);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Painel admin: números do aviso
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_receita_resumo()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  r      public.receitas_do_dia;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  r := public._receita_de_hoje(v_hoje);
  RETURN jsonb_build_object(
    'hoje', v_hoje,
    'receita_hoje', r.titulo,
    'receita_hoje_id', r.id,
    'avisos_ligados', (SELECT count(*) FROM public.receita_avisos WHERE ligado),
    'enviados_hoje', (SELECT count(*) FROM public.receita_avisos_envios WHERE dia = v_hoje),
    'enviados_7_dias', (SELECT count(*) FROM public.receita_avisos_envios WHERE dia > v_hoje - 7),
    'receitas_ativas', (SELECT count(*) FROM public.receitas_do_dia WHERE ativa));
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Permissões (funções novas nascem fechadas a anon desde 05/10)
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public._receitas_do_dia_tocar() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._receita_de_hoje(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.receita_avisos_processar() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.client_receita_de_hoje() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_receita_aviso(boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_receita_resumo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_receita_de_hoje() TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_receita_aviso(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_receita_resumo() TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. As primeiras 14 receitas (duas semanas de rotação; o painel acrescenta mais)
-- ---------------------------------------------------------------------------
INSERT INTO public.receitas_do_dia (titulo, resumo, ingredientes, passos, tempo_min, doses, ordem)
SELECT v.* FROM (VALUES
  ('Bacalhau à Brás', 'O clássico de sempre, pronto em meia hora.', '[{"nome": "Bacalhau desfiado", "quantidade": "400 g", "pesquisa": "bacalhau desfiado"}, {"nome": "Batata palha", "quantidade": "1 pacote (200 g)", "pesquisa": "batata palha"}, {"nome": "Ovos", "quantidade": "6", "pesquisa": "ovos"}, {"nome": "Cebola", "quantidade": "2", "pesquisa": "cebola"}, {"nome": "Alho", "quantidade": "2 dentes", "pesquisa": "alho"}, {"nome": "Azeite", "quantidade": "4 colheres", "pesquisa": "azeite"}, {"nome": "Salsa", "quantidade": "1 molho", "pesquisa": "salsa"}, {"nome": "Azeitonas pretas", "quantidade": "q.b.", "pesquisa": "azeitonas pretas"}]'::jsonb, '["Demolha o bacalhau se não vier pronto e escorre bem.", "Aloura a cebola às rodelas finas e o alho no azeite.", "Junta o bacalhau e deixa cozinhar 5 minutos, sempre a mexer.", "Junta a batata palha e, fora do lume, os ovos batidos. Mexe até ficar cremoso.", "Serve com salsa picada e azeitonas."]'::jsonb, 30, 4, 10),
  ('Frango assado com batatas', 'Tudo no mesmo tabuleiro, sem complicações.', '[{"nome": "Frango inteiro", "quantidade": "1 (1,5 kg)", "pesquisa": "frango inteiro"}, {"nome": "Batatas", "quantidade": "1 kg", "pesquisa": "batata"}, {"nome": "Alho", "quantidade": "4 dentes", "pesquisa": "alho"}, {"nome": "Limão", "quantidade": "1", "pesquisa": "limão"}, {"nome": "Azeite", "quantidade": "4 colheres", "pesquisa": "azeite"}, {"nome": "Colorau", "quantidade": "1 colher", "pesquisa": "colorau"}, {"nome": "Louro", "quantidade": "2 folhas", "pesquisa": "louro"}]'::jsonb, '["Tempera o frango com alho esmagado, limão, colorau, sal e azeite.", "Corta as batatas em gomos e espalha-as à volta do frango com o louro.", "Leva ao forno a 200 °C cerca de 1 hora, regando com o molho a meio.", "Deixa repousar 5 minutos antes de cortar."]'::jsonb, 70, 4, 20),
  ('Caldo verde', 'A sopa que aquece a Guarda no inverno.', '[{"nome": "Couve galega cortada", "quantidade": "300 g", "pesquisa": "couve galega"}, {"nome": "Batatas", "quantidade": "600 g", "pesquisa": "batata"}, {"nome": "Cebola", "quantidade": "1", "pesquisa": "cebola"}, {"nome": "Alho", "quantidade": "2 dentes", "pesquisa": "alho"}, {"nome": "Chouriço", "quantidade": "1", "pesquisa": "chouriço"}, {"nome": "Azeite", "quantidade": "3 colheres", "pesquisa": "azeite"}]'::jsonb, '["Coze as batatas com a cebola e o alho em 1,5 L de água com sal.", "Tritura tudo até ficar um creme.", "Junta a couve e deixa ferver 5 minutos, sem tampa.", "Serve com rodelas de chouriço e um fio de azeite."]'::jsonb, 40, 4, 30),
  ('Esparguete à bolonhesa', 'O jantar que agrada a miúdos e graúdos.', '[{"nome": "Esparguete", "quantidade": "500 g", "pesquisa": "esparguete"}, {"nome": "Carne picada", "quantidade": "500 g", "pesquisa": "carne picada"}, {"nome": "Polpa de tomate", "quantidade": "1 lata", "pesquisa": "polpa de tomate"}, {"nome": "Cebola", "quantidade": "1", "pesquisa": "cebola"}, {"nome": "Alho", "quantidade": "2 dentes", "pesquisa": "alho"}, {"nome": "Azeite", "quantidade": "2 colheres", "pesquisa": "azeite"}, {"nome": "Queijo ralado", "quantidade": "q.b.", "pesquisa": "queijo ralado"}]'::jsonb, '["Aloura a cebola e o alho picados no azeite.", "Junta a carne picada e deixa alourar, a desfazer com a colher.", "Junta a polpa de tomate, sal e pimenta e deixa apurar 15 minutos.", "Coze o esparguete, escorre e serve com o molho e queijo ralado."]'::jsonb, 35, 4, 40),
  ('Arroz de atum', 'Rápido, barato e com o que há na despensa.', '[{"nome": "Arroz", "quantidade": "300 g", "pesquisa": "arroz"}, {"nome": "Atum em lata", "quantidade": "3 latas", "pesquisa": "atum"}, {"nome": "Cebola", "quantidade": "1", "pesquisa": "cebola"}, {"nome": "Alho", "quantidade": "2 dentes", "pesquisa": "alho"}, {"nome": "Tomate", "quantidade": "2", "pesquisa": "tomate"}, {"nome": "Azeite", "quantidade": "3 colheres", "pesquisa": "azeite"}, {"nome": "Salsa", "quantidade": "q.b.", "pesquisa": "salsa"}]'::jsonb, '["Aloura a cebola, o alho e o tomate picados no azeite.", "Junta o arroz, envolve e acrescenta 700 ml de água a ferver com sal.", "Deixa cozinhar 12 minutos em lume brando.", "Junta o atum escorrido, mexe e serve com salsa."]'::jsonb, 25, 4, 50),
  ('Omelete de queijo e fiambre', 'Jantar em 10 minutos, com salada ao lado.', '[{"nome": "Ovos", "quantidade": "4", "pesquisa": "ovos"}, {"nome": "Queijo fatiado", "quantidade": "4 fatias", "pesquisa": "queijo fatiado"}, {"nome": "Fiambre", "quantidade": "4 fatias", "pesquisa": "fiambre"}, {"nome": "Alface", "quantidade": "1", "pesquisa": "alface"}, {"nome": "Tomate", "quantidade": "2", "pesquisa": "tomate"}, {"nome": "Azeite", "quantidade": "1 colher", "pesquisa": "azeite"}]'::jsonb, '["Bate os ovos com uma pitada de sal.", "Deita numa frigideira com azeite quente em lume médio.", "Quando estiver quase firme, põe o queijo e o fiambre e dobra ao meio.", "Serve com alface e tomate temperados."]'::jsonb, 10, 2, 60),
  ('Sopa de legumes', 'A sopa da avó, cheia de cor.', '[{"nome": "Batatas", "quantidade": "3", "pesquisa": "batata"}, {"nome": "Cenouras", "quantidade": "3", "pesquisa": "cenoura"}, {"nome": "Cebola", "quantidade": "1", "pesquisa": "cebola"}, {"nome": "Abóbora", "quantidade": "300 g", "pesquisa": "abóbora"}, {"nome": "Courgette", "quantidade": "1", "pesquisa": "courgette"}, {"nome": "Azeite", "quantidade": "3 colheres", "pesquisa": "azeite"}]'::jsonb, '["Descasca e corta os legumes em pedaços.", "Coze tudo em 2 L de água com sal durante 25 minutos.", "Tritura até ficar cremosa.", "Junta o azeite no fim, fora do lume."]'::jsonb, 40, 6, 70),
  ('Bifanas no pão', 'Sabor de tasca, feitas em casa.', '[{"nome": "Febras de porco", "quantidade": "600 g", "pesquisa": "febras de porco"}, {"nome": "Pão", "quantidade": "4 papo-secos", "pesquisa": "papo-seco"}, {"nome": "Alho", "quantidade": "4 dentes", "pesquisa": "alho"}, {"nome": "Vinho branco", "quantidade": "1 copo", "pesquisa": "vinho branco"}, {"nome": "Louro", "quantidade": "2 folhas", "pesquisa": "louro"}, {"nome": "Colorau", "quantidade": "1 colher", "pesquisa": "colorau"}]'::jsonb, '["Tempera as febras com alho, colorau, louro, sal e o vinho branco. Deixa 15 minutos.", "Frita as febras num fio de azeite, 2 minutos de cada lado.", "Junta a marinada à frigideira e deixa reduzir.", "Mete no pão e rega com o molho."]'::jsonb, 25, 4, 80),
  ('Salada fria de massa com atum', 'Para o almoço do dia seguinte ou um dia quente.', '[{"nome": "Massa espiral", "quantidade": "300 g", "pesquisa": "massa espirais"}, {"nome": "Atum em lata", "quantidade": "2 latas", "pesquisa": "atum"}, {"nome": "Milho", "quantidade": "1 lata", "pesquisa": "milho"}, {"nome": "Ervilhas", "quantidade": "150 g", "pesquisa": "ervilhas"}, {"nome": "Maionese", "quantidade": "3 colheres", "pesquisa": "maionese"}, {"nome": "Ovos", "quantidade": "3", "pesquisa": "ovos"}]'::jsonb, '["Coze a massa e as ervilhas, escorre e deixa arrefecer.", "Coze os ovos 10 minutos e corta-os aos pedaços.", "Junta o atum, o milho e a maionese.", "Envolve tudo e guarda no frigorífico até servir."]'::jsonb, 20, 4, 90),
  ('Pescada no forno com batatas', 'Peixe leve, sem cheiro pela casa.', '[{"nome": "Pescada em postas", "quantidade": "800 g", "pesquisa": "pescada"}, {"nome": "Batatas", "quantidade": "800 g", "pesquisa": "batata"}, {"nome": "Cebola", "quantidade": "2", "pesquisa": "cebola"}, {"nome": "Tomate", "quantidade": "2", "pesquisa": "tomate"}, {"nome": "Alho", "quantidade": "3 dentes", "pesquisa": "alho"}, {"nome": "Azeite", "quantidade": "5 colheres", "pesquisa": "azeite"}, {"nome": "Louro", "quantidade": "2 folhas", "pesquisa": "louro"}]'::jsonb, '["Corta as batatas às rodelas e coze-as 10 minutos.", "Faz uma cama com batata, cebola e tomate às rodelas num tabuleiro.", "Põe a pescada por cima, com alho, louro, sal e azeite.", "Leva ao forno a 190 °C cerca de 25 minutos."]'::jsonb, 45, 4, 100),
  ('Arroz de frango', 'Malandrinho, como deve ser.', '[{"nome": "Peito de frango", "quantidade": "500 g", "pesquisa": "peito de frango"}, {"nome": "Arroz", "quantidade": "300 g", "pesquisa": "arroz"}, {"nome": "Cebola", "quantidade": "1", "pesquisa": "cebola"}, {"nome": "Alho", "quantidade": "2 dentes", "pesquisa": "alho"}, {"nome": "Cenoura", "quantidade": "1", "pesquisa": "cenoura"}, {"nome": "Ervilhas", "quantidade": "100 g", "pesquisa": "ervilhas"}, {"nome": "Azeite", "quantidade": "3 colheres", "pesquisa": "azeite"}]'::jsonb, '["Corta o frango em cubos e aloura-o no azeite com a cebola e o alho.", "Junta a cenoura às rodelas e as ervilhas.", "Acrescenta o arroz e 900 ml de água a ferver com sal.", "Deixa cozinhar 15 minutos e serve logo, ainda malandrinho."]'::jsonb, 40, 4, 110),
  ('Feijoada rápida', 'Conforto num tacho, com feijão de lata.', '[{"nome": "Feijão encarnado cozido", "quantidade": "2 latas", "pesquisa": "feijão encarnado"}, {"nome": "Chouriço", "quantidade": "1", "pesquisa": "chouriço"}, {"nome": "Bacon", "quantidade": "150 g", "pesquisa": "bacon"}, {"nome": "Cebola", "quantidade": "1", "pesquisa": "cebola"}, {"nome": "Alho", "quantidade": "2 dentes", "pesquisa": "alho"}, {"nome": "Cenoura", "quantidade": "2", "pesquisa": "cenoura"}, {"nome": "Arroz", "quantidade": "250 g", "pesquisa": "arroz"}]'::jsonb, '["Aloura a cebola, o alho, o bacon e o chouriço às rodelas.", "Junta a cenoura e um copo de água e deixa cozinhar 10 minutos.", "Junta o feijão com o caldo e deixa apurar 10 minutos.", "Serve com arroz branco."]'::jsonb, 35, 4, 120),
  ('Panquecas para o lanche', 'Com mel, fruta ou doce — como preferires.', '[{"nome": "Farinha", "quantidade": "200 g", "pesquisa": "farinha"}, {"nome": "Leite", "quantidade": "300 ml", "pesquisa": "leite"}, {"nome": "Ovos", "quantidade": "2", "pesquisa": "ovos"}, {"nome": "Açúcar", "quantidade": "2 colheres", "pesquisa": "açúcar"}, {"nome": "Manteiga", "quantidade": "30 g", "pesquisa": "manteiga"}, {"nome": "Fermento em pó", "quantidade": "1 colher de chá", "pesquisa": "fermento"}]'::jsonb, '["Mistura a farinha, o açúcar e o fermento.", "Junta os ovos, o leite e a manteiga derretida e bate até ficar liso.", "Numa frigideira untada, deita uma concha de massa e vira quando fizer bolhas.", "Serve quentes."]'::jsonb, 20, 4, 130),
  ('Salada de grão com atum', 'Fresca, nutritiva e sem fogão.', '[{"nome": "Grão-de-bico cozido", "quantidade": "2 frascos", "pesquisa": "grão-de-bico"}, {"nome": "Atum em lata", "quantidade": "2 latas", "pesquisa": "atum"}, {"nome": "Cebola roxa", "quantidade": "1", "pesquisa": "cebola roxa"}, {"nome": "Ovos", "quantidade": "3", "pesquisa": "ovos"}, {"nome": "Salsa", "quantidade": "q.b.", "pesquisa": "salsa"}, {"nome": "Azeite", "quantidade": "4 colheres", "pesquisa": "azeite"}, {"nome": "Vinagre", "quantidade": "2 colheres", "pesquisa": "vinagre"}]'::jsonb, '["Passa o grão por água e escorre.", "Coze os ovos 10 minutos e corta-os aos quartos.", "Junta a cebola picada, o atum e a salsa.", "Tempera com azeite, vinagre e sal e envolve tudo."]'::jsonb, 15, 4, 140)
) AS v(titulo, resumo, ingredientes, passos, tempo_min, doses, ordem)
WHERE NOT EXISTS (SELECT 1 FROM public.receitas_do_dia);

-- ---------------------------------------------------------------------------
-- 8. Tarefa agendada: de hora a hora, ao minuto 4; a função decide se é a hora certa.
-- ---------------------------------------------------------------------------
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'receita-do-dia-avisos';
SELECT cron.schedule('receita-do-dia-avisos', '4 * * * *', 'SELECT public.receita_avisos_processar();');
