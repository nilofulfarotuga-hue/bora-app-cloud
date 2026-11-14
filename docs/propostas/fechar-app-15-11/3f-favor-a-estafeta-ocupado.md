# Bloco 3 (f) — o Favor que foi parar a um estafeta ocupado

> fechar-app-15-11 · escrito a 14/11/2026 (23h UTC) pelo ajudante `dispatch` (só leitura e proposta).
> Nada aqui foi aplicado. Produção só foi lida (SELECT e registos).
> Prova local: `supabase/tests/fechar_app_3f_prova.mjs` (PGlite).

## 1. A causa, em poucas palavras

**Não foi o motor do despacho.** O motor fez o que devia: durante cinco minutos
respondeu sempre "não há ninguém livre para este Favor".

A oferta das 16:32:00 foi **escrita à mão**: um `UPDATE` direto na tabela dos pedidos,
feito pela ligação de agentes à base de dados (o conector MCP da Supabase, com o login
do Danilo). Esse `UPDATE` pôs o estafeta `4f61dd31` como "a quem o pedido está a tocar",
com 120 segundos para responder. O estafeta tinha o Auchan em mãos, viu a oferta no
telemóvel e aceitou 2,6 segundos depois. A função de aceitar não volta a ver se ele
está livre, por isso deixou passar.

## 2. A prova

Tudo lido em produção a 14/11/2026, horas em UTC.

1. **O motor disse 28 vezes "ninguém".** Registos da função `dispatch-engine` entre
   16:27:20 e 16:32:10 para o pedido `09ee41da`: 29 chamadas, 28 com
   `[dispatch] 0 candidatos (de 0, excl 0)` e `NO DRIVERS`, e **zero** linhas
   `Best driver`, `assigning` ou `SUCCESS`. A última resposta "ninguém" é das
   16:32:00.252. A 29.ª chamada (16:32:10) já encontrou o pedido aceite.
2. **A frase exata que criou a oferta** está no registo do Postgres às 16:32:00.969,
   sessão `6af88d00.188c6d`, aplicação `mgmt-api`, utilizador `postgres`:

   ```
   update orders set current_driver_offer_id='4f61dd31-…',
     driver_offer_expires_at=now()+interval '120 seconds', dispatch_last_tick_at=now()
   where id='09ee41da-…' and status='callingDriver'
     and assigned_driver_id is null and current_driver_offer_id is null
   returning id, current_driver_offer_id, driver_offer_expires_at;
   -- source: POST /mcp
   -- user: oauth:9574bd8b-076e-42d6-8773-2a8674b45362
   -- date: 2026-11-14T16:32:00.338Z
   ```

   Ficou registada porque o gatilho `fn_notify_driver_on_offer` escreveu um aviso
   (`orderId=09ee41da… driverId=4f61dd31…`) dentro dessa mesma frase.
3. **Os números batem com a mão, não com o motor.** A linha de `ofertas_prestador_log`
   tem janela de 120 s; o motor usa `dispatch_offer_timeout_seconds` = 60 s. A fase
   ficou `online2`, que é o que o gatilho `_registar_oferta_entrega` escreve quando,
   no instante da oferta, a lista de candidatos está **vazia** (fase "esgotado"). Se o
   estafeta estivesse na lista, a fase seria `online1`. E não houve envio de
   notificação antes do aceite (`push_em` vazio; o `notify-driver` só correu às
   16:32:06 e respondeu `stale offer skipped`).
4. **A mesma ligação andava em cima deste pedido.** Antes do `UPDATE`, a mesma sessão MCP
   procurou o pedido do cliente (16:30:10) e ficou a vigiar o estado dele com
   `pg_sleep(20)` (16:31:28 a 16:31:48).
5. **O aceite foi do próprio estafeta, pela app:** `POST /rest/v1/rpc/driver_accept_offer`
   às 16:32:03.495, utilizador `4f61dd31`, `Dart/3.11`. Um segundo antes a app dele
   pediu `ganho_oferta_adicional` (o cartão de "pedido adicional").
6. **O Auchan estava mesmo ativo:** `b2b746d7` em `driverAccepted` com
   `assigned_driver_id = 4f61dd31` desde 14:52:02 até 16:34:48 (`order_driver_assignment_audit`
   e `order_status_events`).

O que os registos **não** dizem: qual das sessões de agente foi (o identificador
`oauth:9574bd8b…` é o login da Supabase, o mesmo que eu próprio usei às 23:17 para
ler; serve para qualquer agente ligado por esse conector) nem se foi por ordem do
Danilo. Não há linha no `e2e_log` nem no `admin_audit_log` sobre isto.

## 3. As hipóteses que vinham no pedido, uma a uma

- **(1) A função no ar é diferente da do repositório — afastada.** A que está no ar
  (versão 71 da plataforma) escreve `v64` nos registos; li-a com `get_edge_function` e
  as partes que escolhem e oferecem (`dispatchOrder`, `carregarCandidatos`,
  `findNextDriver`, `assignDriver`) são iguais às do repositório, linha a linha. Só usa
  `dispatch_candidatos_entrega`. Não comparei o ficheiro inteiro byte a byte.
- **(2) As funções de candidatos mudaram depois das 16:32 — afastada.** Nenhuma
  migração de despacho a 14/11 (as duas aplicadas depois das 16:32 são
  `quadro_sim_nao_painel_admin` e `log_admin_action_guarda_chamada_direta`). E o motor
  já respondia "0 candidatos" das 16:27 às 16:32.
- **(3) O estafeta estava "livre" para a função — afastada.** O Auchan contava:
  `driverAccepted`, `assigned_driver_id` igual à chave do estafeta. A própria fase
  `online2` mostra que a função o deixou de fora no instante da oferta.
- **(4) Registos da função por volta das 16:32 — feito.** 28 vezes zero candidatos,
  nenhuma oferta.
- **(5) Outro caminho — é este.** `UPDATE` direto por MCP (ponto 2 da prova).

## 4. Porque é que o sistema deixou passar

1. **A regra "Favor só a quem está livre" vive num sítio só:** na lista de candidatos
   (`_dispatch_candidatos_online` e `_dispatch_forcados_entrega`, condição
   `NOT v_favor OR ativos = 0`). Quem escreve a oferta por fora dessa lista salta a regra.
2. **`driver_accept_offer` só confirma que a oferta é dele** (`current_driver_offer_id = auth.uid()`).
   Não vê quantos pedidos ele tem em mãos.
3. **A guarda das colunas do estafeta só trava a app.** O gatilho
   `a00_pedido_loja_estafeta_guarda_upd` deixa passar tudo o que não seja
   `authenticated`/`anon`; um `UPDATE` como `postgres` (MCP) passa sem perguntas.
4. **O caminho oficial dos agentes também não conhece a regra.** `ops_reassign_order`
   só vê se o estafeta está ligado e tem notificações. Se o agente tivesse usado o
   caminho certo, o Favor ia na mesma para o estafeta ocupado (atribuído sem ele aceitar).

## 5. A proposta

Duas partes pequenas e independentes. Pode aplicar-se só a primeira.

- **Parte 1 — `driver_accept_offer`.** Se o pedido é um Favor e o estafeta já tem outro
  pedido por entregar, não aceita: larga a oferta (para o pedido não ficar preso nele
  até ao fim da janela), acorda o motor e responde `offer_expired_or_taken` com
  `motivo: favor_so_com_estafeta_livre`. Usei o código de erro que a app já conhece
  para a app de hoje mostrar "esta oferta já não está disponível" sem precisar de versão
  nova. Não mete o estafeta em `tried_driver_ids`: quando ele ficar livre o motor
  volta a oferecer-lhe o Favor. O trinco (`pg_advisory_xact_lock`) serve para dois
  aceites do mesmo estafeta no mesmo instante não se cruzarem.
- **Parte 2 — `ops_reassign_order`.** Se o pedido é um Favor já pronto e o estafeta
  escolhido tem pedidos por entregar, responde `ok=false`, `favor_so_com_estafeta_livre`,
  com a explicação em palavras simples. Só passa com `p_forcar => true`, que já é
  "só por ordem do Danilo".

O que **não** muda: quem recebe ofertas (as funções de candidatos e o motor ficam
iguais), entregas normais em cima de outras (até 3), preços, ganhos, e o
`admin_reassign_order` do painel (o Danilo no painel continua a poder dar um Favor a
quem quiser).

As duas funções partem da definição de produção de 14/11/2026. As linhas novas estão
entre `-- >>> 3f` e `-- <<< 3f`; tirando-as, o corpo volta a ser o de produção (a prova
confirma pelo md5).

<!-- SQL-3F:INICIO -->
```sql
-- ════════════════════════════════════════════════════════════════════════════
-- PROPOSTA fechar-app-15-11 (3f) — Favor só a quem está livre, também ao ACEITAR
-- e também quando é um agente a passar o pedido. NÃO APLICADA.
-- Cicatriz: 14/11/2026 16:32, Favor 09ee41da oferecido por UPDATE direto (MCP) a
-- um estafeta com o pedido b2b746d7 em mãos; driver_accept_offer aceitou.
-- Base: pg_get_functiondef de produção a 14/11/2026.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Parte 1: aceitar ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.driver_accept_offer(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_rows integer;
  v_fiscal_bloqueado boolean := false;
  -- >>> 3f
  v_favor boolean;
  v_ativos integer := 0;
  -- <<< 3f
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
  END IF;
  -- FECHO MENSAL (staged_fecho_mensal_20260929, aplicado a 09/10/2026): a partir do prazo
  -- platform_settings.estafeta_fiscal_prazo (15/10/2026) o estafeta sem NIF válido + atividade
  -- aberta não aceita entregas. A app já bloqueia (DriverFiscalGate); isto fecha o caminho no
  -- servidor. Contas demo ficam de fora (_estafeta_fiscal_bloqueado).
  v_fiscal_bloqueado := public._estafeta_fiscal_bloqueado(v_uid);
  -- >>> 3f — Favor só a quem está livre (fechar-app-15-11). A lista de candidatos já o
  -- garante (NOT v_favor OR ativos = 0); isto fecha o ACEITAR, para a regra valer também
  -- quando a oferta foi escrita por fora do motor. Larga a oferta sem marcar o estafeta
  -- como tentado: quando ele ficar livre, o motor volta a oferecer-lhe o Favor.
  PERFORM pg_advisory_xact_lock(hashtext('driver_accept_offer:' || v_uid::text));
  SELECT o.service_type = 'errand' INTO v_favor
    FROM public.orders o
   WHERE o.id = p_order_id
     AND o.status = 'callingDriver'
     AND o.assigned_driver_id IS NULL
     AND o.current_driver_offer_id = v_uid::text;
  IF COALESCE(v_favor, false) THEN
    SELECT count(*) INTO v_ativos
      FROM public.orders a
     WHERE a.id <> p_order_id
       AND a.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
       AND (a.assigned_driver_id = v_uid::text
            OR a.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d
                                         WHERE d.user_id = v_uid));
    IF v_ativos > 0 THEN
      UPDATE public.orders
         SET current_driver_offer_id = NULL,
             driver_offer_expires_at = NULL
       WHERE id = p_order_id
         AND status = 'callingDriver'
         AND assigned_driver_id IS NULL
         AND current_driver_offer_id = v_uid::text;
      PERFORM public.invoke_dispatch_engine(p_order_id);
      RETURN jsonb_build_object('ok', false, 'error', 'offer_expired_or_taken',
                                'motivo', 'favor_so_com_estafeta_livre',
                                'ativos', v_ativos);
    END IF;
  END IF;
  -- <<< 3f
  PERFORM set_config('app.order_transition_source', 'driver_accept_offer', true);
  UPDATE public.orders
     SET assigned_driver_id = v_uid::text,
         driver_id = v_uid,
         status = 'driverAccepted',
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL,
         driver_phone = COALESCE(
           driver_phone,
           (SELECT d.phone FROM public.drivers d
             WHERE d.user_id = v_uid LIMIT 1)
         )
   WHERE id = p_order_id
     AND status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id = v_uid::text
     AND NOT v_fiscal_bloqueado;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE id = p_order_id
        AND assigned_driver_id = v_uid::text
        AND status IN ('driverAccepted', 'pickedUp', 'onTheWay', 'delivered')
    ) THEN
      RETURN jsonb_build_object('ok', true, 'order_id', p_order_id,
                                'status', 'driverAccepted',
                                'idempotent', true);
    END IF;
    IF v_fiscal_bloqueado THEN
      RETURN jsonb_build_object('ok', false, 'error', 'estafeta_sem_nif_atividade',
                                'hint', 'Confirme o NIF e a atividade aberta nas Finanças na app');
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'offer_expired_or_taken');
  END IF;
  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id,
                            'status', 'driverAccepted');
END;
$function$;

-- ── Parte 2: o caminho oficial dos agentes ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.ops_reassign_order(p_order_id text, p_new_driver text, p_motivo text, p_agente text, p_forcar boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_o record;
  v_d record;
  v_pronto boolean;
  v_claims_antes text;
  v_res jsonb;
  c_admin_uid constant text := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  -- >>> 3f
  v_ativos integer := 0;
  -- <<< 3f
BEGIN
  IF coalesce(btrim(p_agente), '') = '' OR coalesce(btrim(p_motivo), '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'agente_e_motivo_obrigatorios');
  END IF;
  PERFORM set_config('bora.caminho_oficial', 'ops_reassign_order', true);

  SELECT id, status, assigned_driver_id, service_type INTO v_o FROM orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  IF v_o.status IN ('delivered', 'cancelled', 'rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_ja_terminal', 'status', v_o.status);
  END IF;
  IF COALESCE(v_o.service_type, '') = 'takeaway' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'takeaway_sem_estafeta');
  END IF;

  SELECT * INTO v_d FROM public._driver_reachability(p_new_driver);
  IF v_d.driver_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_encontrado');
  END IF;
  IF v_d.is_banned THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_banido', 'estafeta', v_d.name);
  END IF;

  v_pronto := v_o.status IN ('callingDriver', 'driverAccepted', 'pickedUp', 'onTheWay');

  IF NOT p_forcar AND (NOT v_d.online_agora OR NOT v_d.tem_notificacoes) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'estafeta_nao_vai_receber',
      'estafeta', v_d.name,
      'online_agora', v_d.online_agora,
      'tem_notificacoes', v_d.tem_notificacoes,
      'ultimo_sinal', v_d.last_heartbeat_at,
      'plataforma', v_d.last_platform,
      'status_pedido', v_o.status,
      'o_que_fazer', 'Não atribuas por outro caminho. Diz ao Danilo o motivo em palavras simples. Só repetir com p_forcar => true se o Danilo mandar expressamente depois de saber o motivo.');
  END IF;

  -- >>> 3f — Favor só a quem está livre, também quando é um agente a passar o pedido
  -- (fechar-app-15-11). Só para Favor já pronto: reservar para mais tarde não conta.
  IF NOT p_forcar AND v_pronto AND v_o.service_type = 'errand' THEN
    SELECT count(*) INTO v_ativos
      FROM orders a
     WHERE a.id <> p_order_id
       AND a.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
       AND a.assigned_driver_id IN (v_d.driver_id::text, COALESCE(v_d.user_id, v_d.driver_id)::text);
    IF v_ativos > 0 THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'favor_so_com_estafeta_livre',
        'estafeta', v_d.name,
        'pedidos_em_maos', v_ativos,
        'status_pedido', v_o.status,
        'o_que_fazer', 'Este estafeta ainda tem pedidos por entregar e um Favor só se dá a quem está livre. Escolhe outro estafeta ou espera que ele entregue. Não atribuas por outro caminho. Só repetir com p_forcar => true se o Danilo mandar expressamente depois de saber o motivo.');
    END IF;
  END IF;
  -- <<< 3f
  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c_admin_uid, 'role', 'authenticated',
                      'email', 'nilofulfarotuga@gmail.com',
                      'app_metadata', json_build_object('role', 'admin'))::text, true);
  BEGIN
    v_res := public.admin_reassign_order(p_order_id, p_new_driver,
                                         left('[agente ' || p_agente || '] ' || p_motivo, 500));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);

  INSERT INTO admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
  VALUES ('order_reassigned_by_agent', 'order', p_order_id, 'agente:' || p_agente,
          jsonb_build_object('agente', p_agente, 'motivo', p_motivo,
                             'de', v_o.assigned_driver_id,
                             'para', coalesce(v_d.user_id, v_d.driver_id), 'estafeta', v_d.name,
                             'forcado', p_forcar, 'online_agora', v_d.online_agora,
                             'tem_notificacoes', v_d.tem_notificacoes, 'status_pedido', v_o.status,
                             'pre_atribuicao', NOT v_pronto,
                             'resultado', v_res));

  RETURN coalesce(v_res, '{}'::jsonb)
         || jsonb_build_object('agente', p_agente, 'forcado', p_forcar,
                               'online_agora', v_d.online_agora, 'tem_notificacoes', v_d.tem_notificacoes,
                               'pre_atribuicao', NOT v_pronto);
END $function$;
```
<!-- SQL-3F:FIM -->

`CREATE OR REPLACE` não mexe nas permissões: `driver_accept_offer` continua aberta só
a `authenticated` e `service_role`; `ops_reassign_order` fica como está.

**Como desfazer:** voltar a aplicar o corpo de produção de 14/11 (md5 do corpo:
`driver_accept_offer` `1bd68d8d36fcde2ed7c08af8082aade3`, 2162 caracteres;
`ops_reassign_order` `2edbd2d9778d032506ed7481ac36d3d6`, 3652 caracteres), que é este
mesmo texto sem as linhas entre `-- >>> 3f` e `-- <<< 3f`. Antes de aplicar, guardar
os dois corpos numa tabela `bkp_fn_favor_livre_20261115` (como as outras `bkp_fn_*`).

## 6. O que muda para cada um

**Para o estafeta.** Hoje, com um pedido em mãos, ele nunca devia ver um Favor a tocar
(o motor não lho oferece). Se alguma vez lhe aparecer um por engano e ele carregar em
aceitar, a app responde que a oferta já não está disponível e o cartão desaparece; ele
continua o pedido que tem. Quando entregar, o Favor volta a tocar-lhe se ainda ninguém
o tiver. Entregas normais em cima de outras continuam a aceitar-se como hoje.

**Para o cliente do Favor.** O Favor fica à espera de um estafeta livre, como a regra
manda, em vez de ficar atrás de uma compra de supermercado que ainda vai a meio. No caso
de 14/11 o estafeta aceitou o Favor às 16:32 mas só entregou o Auchan às 16:42: nesses
dez minutos o Favor esteve "aceite" sem ninguém a tratar dele.

**Para o cliente do outro pedido.** Deixa de ter o seu estafeta a pegar num Favor a
meio da compra dele. Segundo o cabeçalho da migração da compra guardada, foi a entrada
deste Favor que fez a app trocar de pedido e perder o que estava marcado no Auchan
(isso não fui eu que provei; está lá escrito).

**Para os agentes.** `ops_reassign_order` passa a dizer "este estafeta tem pedidos por
entregar, um Favor só se dá a quem está livre", com o número de pedidos. Só passa com
`p_forcar => true` por ordem do Danilo.

## 7. A segunda metade da regra: "Favor urgente logo a seguir ao pedido em curso"

**Como está hoje em produção.** Não existe. As duas funções de candidatos tratam o
Favor urgente (`errand_speed = 'express'`) igual ao normal: só o oferecem a quem tem
zero pedidos (`NOT v_favor OR ativos = 0`). Um Favor urgente com todos os estafetas
ocupados fica à espera, como o normal. Em `platform_settings` só há o preço e o prazo
do expresso (`errand_fee_express_cents`, `errand_driver_express_cents`,
`errand_sla_express_minutes`); nada sobre a quem se oferece. Em produção ainda não
houve nenhum Favor urgente: os 18 Favores criados até hoje são todos `normal`.

**O que a migração por aplicar `20261114190000_compra_guardada_e_fila_estafeta.sql`
resolve.** Resolve a **ordem** dentro da fila de um estafeta que já tem vários pedidos:
quando ele entrega o que tem em curso, o seguinte é o que já foi recolhido, depois o
que tem compra começada, depois o da mesma loja, depois **Favor urgente → entregas →
Favor normal** (`_fila_pedidos_ativos`, classe 1/2/3). E guarda qual é o pedido em
curso, para um pedido aceite depois não passar à frente.

**O que essa migração não resolve.** Não muda quem recebe ofertas (está escrito no
cabeçalho dela). Ou seja: a fila sabe pôr o Favor urgente "logo a seguir", mas o motor
nunca chega a oferecer um Favor urgente a um estafeta ocupado, por isso essa posição
da fila só se usa quando alguém atribui à mão.

**O que falta para a regra ficar inteira (desenho, sem SQL final e sem prova).**
Precisa de três decisões do Danilo antes de se escrever:

1. Com quantos pedidos em mãos o estafeta ainda pode receber um Favor urgente
   (sugestão: no máximo 1, e nunca se esse já for um Favor).
2. Se um estafeta livre passa sempre à frente de um ocupado, mesmo estando mais longe
   (sugestão: sim).
3. Se depende de a migração da fila já estar aplicada (sugestão: sim, senão a app não
   sabe pôr o urgente a seguir).

Com essas respostas a mudança é de três linhas iguais em três sítios, e têm de ir
juntas na mesma migração:

- `_dispatch_candidatos_online` e `_dispatch_forcados_entrega`: trocar
  `AND (NOT v_favor OR x.ativos = 0)` por
  `AND (NOT v_favor OR x.ativos = 0 OR (v_urgente AND x.ativos <= 1))`, com
  `v_urgente := v_favor AND o.errand_speed = 'express'` (ler `errand_speed` no SELECT
  do pedido), e pôr os livres primeiro na ordenação (`(x.ativos = 0) DESC`).
- `driver_accept_offer` (Parte 1 acima): a mesma exceção no `IF v_ativos > 0`, senão
  o motor oferece e o aceitar recusa.

Isto muda quem recebe ofertas: é zona protegida e só com ordem expressa.

## 8. Para aplicar

- É despacho (zona protegida). Não mexe em preços, ganhos nem pagamentos.
- Ordem do Danilo precisa: uma frase com data a mandar aplicar a trava do Favor no
  aceitar e no caminho dos agentes (ex.: "aplica a trava do Favor a quem está livre,
  15/11").
- Quem aplica: a Claude.ai, por migração (`supabase/migrations/…_favor_so_a_quem_esta_livre.sql`
  com o bloco SQL acima, cópia exata), depois de guardar os corpos atuais.
- Antes de aplicar, confirmar que os dois md5 de produção ainda são os de cima (se
  alguém mexeu entretanto, refazer a partir do corpo novo).
- Depois de aplicar, provar em produção só por leitura: `md5(prosrc)` das duas
  funções diferente do de antes, e o corpo sem as linhas `3f` igual ao md5 antigo.

## 9. O que ficou por provar

- Qual foi a sessão de agente que escreveu o `UPDATE` e se foi por ordem do Danilo.
  Os registos da base só dão o login da Supabase. Para saber, é ler a conversa da
  Claude.ai (ou do agente que estava ligado) das 16:27 às 16:35 de 14/11.
- A função `dispatch-engine` no ar não foi comparada byte a byte com o repositório;
  só as partes que escolhem e oferecem.
- A prova da proposta é local (PGlite), com réplicas pequenas das tabelas. Não corri
  nada em produção.
- O texto que a app mostra ao estafeta quando recebe `offer_expired_or_taken` não foi
  visto num telemóvel (modo leve, sem Flutter).

## 10. Outros erros vistos (só reportar)

1. **Escritas diretas em pedidos pela ligação MCP, a 14/11.** Além da oferta das 16:32:
   às 14:51:11 houve uma tentativa de `UPDATE` direto a pôr um pedido em `driverAccepted`
   com o estafeta `4f61dd31`, antecedida de
   `set_config('bora.caminho_oficial','admin_reassign_order',true)` (a marca de "caminho
   oficial" posta à mão). Falhou por outra razão (`cancellation_reason`). 51 segundos
   depois o pedido `b2b746d7` nasceu por `INSERT` direto, já atribuído. As regras da casa
   proíbem as três coisas; a auditoria marcou o `INSERT` como `origem_direta = true`.
2. **O talão do Auchan `b2b746d7` não tem foto.** Em `order_receipts_v2.photo_url` está
   `talao-auchan-2026-11-14-16h32-foto-so-no-chat`, que não existe no balde `receipts`
   (0 ficheiros; a leitura automática do talão recebeu 400 às 16:34:48). Nos registos
   da API não há nenhuma chamada `rpc/finalizar_talao_nao_parceiro` entre as 16:34:40 e
   as 16:34:52, embora o fecho esteja registado às 16:34:48 em nome do estafeta. Tudo
   indica que o fecho foi feito por SQL e não pela app dele; não está provado por quem.
3. **O registo da oferta fica com um rótulo enganador.** Uma oferta escrita por fora do
   motor fica como `online2` em `ofertas_prestador_log`, igual a uma oferta normal da
   terceira fase. Não há maneira de ver no painel que foi à mão.
4. **`_preassign_to_offer` também oferece sem ver se o estafeta está ocupado.** É o
   caminho de "pedido reservado": quando o pedido fica pronto, toca primeiro ao
   reservado. Com a Parte 1, um Favor reservado a um estafeta ocupado é recusado no
   aceitar e volta ao motor.
5. **Quando a oferta é largada pela Parte 1, o registo fica "recusou"** (é o gatilho
   `_registar_oferta_entrega` que decide o desfecho). Fica dito para ninguém pensar
   que o estafeta recusou de propósito.
