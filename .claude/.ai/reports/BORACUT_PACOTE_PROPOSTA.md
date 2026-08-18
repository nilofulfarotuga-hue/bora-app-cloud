# 🔴 bora_cut NEGATIVO nas corridas de PACOTE — causa raiz + fix + recálculo (PROPOSE-ONLY)

> Missão 17-18/08 (Danilo): "corte da plataforma NEGATIVO; 6 com final_fare_cents=0".
> **Dinheiro real → NADA aqui foi aplicado.** Preparado + provado por rollback-tx;
> o apply final é da Claude.ai por MCP (como no cêntimo).

## 1. Verdade de produção (verificada via MCP 2026-08-18)

12 corridas `finalizada`. As linhas com `bora_cut_cents < 0` armazenado são **5 — e TODAS
são de pacote ida-e-volta** (`roundtrip_credit_id` preenchido, vales todos CASH):

| corrida | dia | perna | vale (paid) | earn | final_fare | bora_cut gravado |
|---|---|---|---|---|---|---|
| f51f7c17 | 31/07 | ida  | 9b2ce73d (800, usado)    | 400  | 0 | **−400** |
| d7e0e535 | 31/07 | volta| 9b2ce73d (mesmo vale)    | 350  | 0 | **−350** |
| 21df2885 | 01/08 | ida  | 02293ef6 (800, expirado) | 1440 | 0 | **−1440** |
| ee6767ac | 02/08 | ida  | 5455d2a7 (2880, expirado)| 1440 | 0 | **−1440** |
| f1a3d2ba | 14/08 | ida  | 850717d7 (800, expirado) | 400  | 0 | **−400** |

(Nota ao briefing "10 de 12 negativas": no armazenado são 5; a contagem 10/7 vem do cálculo
que o APP faz na linha — `(final ?? est) − earn` — que também apanha 2 corridas de PLANO com
`bora_cut` gravado POSITIVO e correto (e3478429 cut=160, 5680dd97 cut=60). O plano não tem bug.)

As corridas normais estão certas (est=500, final=500, cut=+100).

## 2. Causa raiz (uma linha)

No ramo `v_prepaid` do `tvde_finish_ride`, **a receita do pacote (`tvde_roundtrip_credits.paid_cents`)
nunca entra**: `v_fare := v_stops_fee (0)` → `v_bora_cut := 0 − earn` → negativo, e `final_fare_cents=0`.
O cliente PAGOU o pacote (no vale), mas nenhuma perna reconhece esse dinheiro. O settle do motorista
(`tvde_driver_balances`) usa `v_rt_price` à parte e **está certo** — o bug é só de registo
(bora_cut/final_fare), não de dinheiro movido.

Quem grava `final_fare_cents` é o próprio `tvde_finish_ride` (única via); para pacote gravava
0-de-stops por desenho.

## 3. Fix da raiz (função — modelo de contabilidade)

**Modelo proposto**: a IDA reconhece a receita do vale e reserva o custo previsto da volta; a VOLTA
fecha a 0 (margem só dos stops). Assim cada perna é ≥0 no caso normal e a soma bate com a margem real.

- **IDA**: `final_fare = paid_cents + stops_fee`; `bora_cut = final_fare − earn_ida − reserva_volta`,
  com `reserva_volta = tvde_roundtrip_return_driver_cents + extra_km × per_km`.
  Ex.: vale 800, earn 400, reserva 350 → **cut +50** ✓.
- **VOLTA**: `final_fare = stops_fee`; `bora_cut = stops_fee − stops_drv` (≥0; tipicamente 0).
- **Tokens**: bloco de desconto ganha `AND NOT v_prepaid` (pacote já foi pago; sem isto, `v_fare=800`
  na ida passaria a aceitar desconto de tokens no fecho — mudança de comportamento indesejada).
- **GUARDA (pedido do Danilo)**: corrida `cash` nunca GRAVA `bora_cut` negativo — clamp a 0 na linha,
  valor cru no evento (`bora_cut_raw_cents`). ⚠️ **O settle continua a usar o valor CRU** — clamp no
  settle mexeria dinheiro (ex.: membro-cash com fare 250 < earn 400: a Bora DEVE 1,50 ao motorista;
  o clamp roubaria isso). Guard = registo, settle = verdade.

**Segurança verificada**: `tvde_ride_charge_cents` (= COALESCE(final_fare, est_fare, 0)) só é chamado
pela EF `tvde-payment` na **criação** da corrida (final_fare ainda NULL) — gravar final_fare no fecho
não dispara cobrança nenhuma. Consumidores restantes de final_fare (driver_earnings_summary,
admin_tvde_rides_list, admin_list_payments, mark_noshow/revert) são exibição/relatório.

### Função completa (substitui a de produção md5 2e29dbe4…, base = migration 20260813)

```sql
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(
  p_ride_id uuid, p_final_distance_km numeric,
  p_distance_source text DEFAULT NULL::text, p_tokens_to_apply integer DEFAULT 0)
RETURNS public.tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
  v_stops_fee INT; v_stops_drv INT; v_prepaid BOOLEAN; v_settle INT;
  v_tokens_discount_cents INT; v_max_discount_cents INT; v_token_value_x100 INT;
  v_pm TEXT; v_rt_cash BOOLEAN := false; v_rt_price INT;
  v_stops_cash INT;
  v_rt_paid INT; v_return_reserve INT := 0; v_bora_raw INT;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);
  v_prepaid   := v_ride.roundtrip_credit_id IS NOT NULL;
  v_pm        := COALESCE(v_ride.payment_method, 'cash');

  SELECT COALESCE(SUM(fee_cents),0) INTO v_stops_cash
    FROM public.tvde_ride_stops
   WHERE ride_id = p_ride_id AND payment_intent_id IS NULL;

  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  END IF;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;

  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  IF v_prepaid THEN
    -- ⭐ FIX 2026-08-18: reconhecer a receita do PACOTE. Antes: v_fare := v_stops_fee
    -- e v_bora_cut := v_fare − earn → corte NEGATIVO e final_fare=0 (bug bora_cut).
    SELECT paid_cents INTO v_rt_paid
      FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
    v_driver_earn := v_driver_earn + v_stops_drv;
    IF COALESCE(v_ride.is_return_leg, false) THEN
      -- VOLTA: receita já reconhecida na ida; margem só dos stops.
      v_fare     := v_stops_fee;
      v_bora_cut := v_stops_fee - v_stops_drv;
    ELSE
      -- IDA: receita do vale entra aqui; reserva o custo previsto da volta.
      v_return_reserve := COALESCE((public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int, 350)
                          + v_extra_km * v_d_perkm;
      v_fare     := COALESCE(v_rt_paid, 0) + v_stops_fee;
      v_bora_cut := v_fare - v_driver_earn - v_return_reserve;
    END IF;
  ELSIF v_covered THEN
    v_bora_cut    := (v_driver_earn - ROUND(v_driver_earn * 0.85)::int) + (v_stops_fee - v_stops_drv);
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int + v_stops_drv;
    v_fare        := v_stops_fee;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
      WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
      INTO v_is_member;
    IF v_is_member THEN
      v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    END IF;
    v_fare        := v_fare + v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;
  END IF;

  -- Tokens: NUNCA em pacote (já pago no vale; sem isto a ida com v_fare=paid aceitaria desconto).
  IF p_tokens_to_apply > 0 AND v_fare > 0 AND NOT v_prepaid THEN
    v_token_value_x100 := COALESCE((public.get_setting('token_value_cents_x100') #>> '{}')::int, 50);
    v_max_discount_cents := GREATEST(0, (v_fare
      * COALESCE((public.get_setting('token_payment_max_pct') #>> '{}')::int, 50)) / 100);
    v_tokens_discount_cents := LEAST((p_tokens_to_apply * v_token_value_x100) / 100, v_max_discount_cents);
    v_fare := v_fare - v_tokens_discount_cents;
    v_bora_cut := v_bora_cut - v_tokens_discount_cents;
  ELSE
    v_tokens_discount_cents := 0;
  END IF;

  -- ⭐ GUARDA (Danilo 17/08): corrida CASH nunca GRAVA corte negativo; o cru vai no
  -- evento e o settle usa o cru (guard é de registo, não mexe no dinheiro).
  v_bora_raw := v_bora_cut;
  IF v_pm = 'cash' AND v_bora_cut < 0 THEN v_bora_cut := 0; END IF;

  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    final_distance_source = COALESCE(p_distance_source, final_distance_source),
    tokens_applied_count = CASE WHEN p_tokens_to_apply > 0 THEN p_tokens_to_apply ELSE tokens_applied_count END,
    tokens_applied_value_cents = CASE WHEN p_tokens_to_apply > 0 THEN v_tokens_discount_cents ELSE tokens_applied_value_cents END,
    updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  IF v_prepaid AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    SELECT (payment_intent_id IS NULL), paid_cents INTO v_rt_cash, v_rt_price
      FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
  END IF;

  -- === LIQUIDACAO DO SALDO DO MOTORISTA (tvde_driver_balances) ===
  -- +v_settle = motorista DEVE a Bora ; -v_settle = Bora DEVE ao motorista.
  IF v_pm = 'cash' AND NOT v_prepaid AND NOT v_covered THEN
    v_settle := v_bora_raw;  -- ⭐ o CRU, não o clampado (ver GUARDA acima)
  ELSIF v_prepaid AND COALESCE(v_rt_cash, false) AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    v_settle := (COALESCE(v_rt_price, (public.get_setting('tvde_roundtrip_price_cents') #>> '{}')::int) + v_stops_cash) - v_driver_earn;
  ELSE
    v_settle := v_stops_cash - v_driver_earn;
  END IF;
  IF v_settle <> 0 THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_settle / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE
        SET balance = public.tvde_driver_balances.balance + ROUND(v_settle / 100.0, 2), updated_at = now();
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver', jsonb_build_object('final_distance_km', p_final_distance_km,
      'final_fare_cents', v_fare, 'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut,
      'bora_cut_raw_cents', v_bora_raw, 'return_reserve_cents', v_return_reserve, 'rt_paid_cents', v_rt_paid,
      'extra_stops_fee_cents', v_stops_fee, 'extra_stops_driver_cents', v_stops_drv,
      'stops_cash_cents', v_stops_cash,
      'is_return_leg', v_ride.is_return_leg, 'prepaid', v_prepaid, 'rt_cash', v_rt_cash, 'payment_method', v_pm,
      'roundtrip_price_cents', v_rt_price,
      'settle_cents', v_settle,
      'distance_source', p_distance_source, 'subscription', v_sub,
      'tokens_applied_count', p_tokens_to_apply, 'tokens_discount_cents', v_tokens_discount_cents));

  UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3 WHERE r3.driver_id = v_uid AND r3.is_queued = true
               AND r3.status = 'motorista_atribuido' ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;

  RETURN v_ride;
END; $function$;
```

## 4. Recálculo das linhas históricas (**5** UPDATEs, mesma contabilidade)

> Correção 18/08: são **5**, não 6 (erro de contagem meu na 1.ª versão) — são exatamente as 5 linhas
> com `bora_cut_cents < 0`, todas de pacote.

Só `final_fare_cents`/`bora_cut_cents` — **não toca** `driver_earn_cents`, `tvde_driver_balances`
nem settlements (os ganhos dos motoristas sempre estiveram certos). Para o par completo usa-se o
earn REAL da volta como reserva; para vales com volta expirada não há custo de volta a subtrair.

```sql
-- Par completo 31/07 (vale 9b2ce73d, 800): margem real = 800−400−350 = +50
UPDATE tvde_rides SET final_fare_cents=800, bora_cut_cents=50
 WHERE id='f51f7c17-77d3-4d3f-94e8-95cca9ab5948' AND bora_cut_cents=-400;
UPDATE tvde_rides SET bora_cut_cents=0
 WHERE id='d7e0e535-0c94-4dbd-8ff5-fc4530c396f3' AND bora_cut_cents=-350;

-- Ida 01/08 (vale 02293ef6, 800; earn 1440; volta expirou): VERDADE = 800−1440 = −640
-- ✅ DECIDIDO pelo Danilo 18/08: grava a PERDA REAL (−640), não 0 — "a contabilidade
-- diz a verdade". Perda histórica do preço fixo €8 numa corrida de 18 km (pré-dinâmico).
UPDATE tvde_rides SET final_fare_cents=800, bora_cut_cents=-640
 WHERE id='21df2885-101e-489a-bad7-3b29d6de80e0' AND bora_cut_cents=-1440;

-- Ida 02/08 (vale 5455d2a7, 2880 dinâmico; earn 1440; volta expirou): 2880−1440 = +1440
UPDATE tvde_rides SET final_fare_cents=2880, bora_cut_cents=1440
 WHERE id='ee6767ac-cecd-44f4-a5fa-de65c95b79c5' AND bora_cut_cents=-1440;

-- Ida 14/08 (vale 850717d7, 800; earn 400; volta expirou): 800−400 = +400
UPDATE tvde_rides SET final_fare_cents=800, bora_cut_cents=400
 WHERE id='f1a3d2ba-9eaf-4cdf-925d-b5556b01ac69' AND bora_cut_cents=-400;
```

**Impacto no reporting** (números conferidos na BD a 18/08 — a 1.ª versão trocou o total pela soma
das negativas): as **5 linhas de pacote** somam **−4030 antes → +1250 depois**; o **TOTAL** de todas
as 12 `finalizada` passa de **−3310 → +1970** (as outras 7 linhas, já corretas, somam +720).
No app do motorista, as linhas passam a "Cobrado €8.00 · Bora €0.50" em vez de "Cobrado €0.00 ·
Bora €-4.00" (com o fix de UI 5f0e70c, um negativo residual sai em palavras: "Bora deve €X").

Verificação pós-apply:
```sql
SELECT id, final_fare_cents, bora_cut_cents FROM tvde_rides
 WHERE status='finalizada' AND bora_cut_cents < 0;   -- esperado: SÓ 21df2885 (−640)
SELECT SUM(bora_cut_cents) FROM tvde_rides WHERE status='finalizada';  -- esperado: +1970
```

## 4-bis. ⚠️ A guarda entrou em tensão com a decisão de 18/08 (decidir no apply)

A guarda "cash nunca grava corte negativo" foi pedida a 17/08 **quando os negativos eram artefacto
do bug**. Com a raiz corrigida, o que restar negativo é **perda REAL** — e a guarda passaria a
escondê-la, exatamente o contrário de "a contabilidade diz a verdade". O staged fica com a guarda
ligada (foi o pedido original), mas **recomendo desligá-la**: apagar só a linha
`IF v_pm = 'cash' AND v_bora_cut < 0 THEN v_bora_cut := 0; END IF;`. A UI já mostra negativos em
palavras desde o vc533, e o `settle` usa o valor CRU nos dois casos — **zero impacto em dinheiro
pago ou recebido**, é só o que fica escrito na linha.

## 5. Prova (rollback-tx, corrida ao vivo contra a função NOVA — correr antes do apply)

Num só batch: `CREATE OR REPLACE` da função nova + vale cash 800 + par ida/volta fabricado +
`tvde_finish_ride` real nas duas pernas + corrida cash normal (regressão) → `RAISE EXCEPTION`
com os números → TUDO revertido (função de produção intacta).

**CORRIDA 2026-08-18 00:57 UTC — output REAL do Postgres (artefacto):**
```
ERROR: P0001: PROVA_BORACUT_ROLLBACK
|| IDA pacote800: fare=800 cut=50 earn=400 settle=400 reserve=350
|| VOLTA: fare=0 cut=0 earn=350 settle=-350
|| NORMAL cash: fare=500 cut=100 earn=400 settle=100
```
Bate 1:1 com a regra de negócio (CLAUDE.md §5): pacote €8 → ida €4, volta €3,50, **Bora €0,50**.
Regressão da corrida cash normal intacta (500/100/400/+100 = produção).
Pós-rollback verificado por MCP: `md5(tvde_finish_ride) = 2e29dbe4…` (produção INTACTA),
resíduo de rides=0, vales=0.

## 6. Aplicar (Claude.ai, por MCP, após "vai")
1. `apply_migration` da função (§3).
2. Os 6 UPDATEs (§4) — com a decisão do 21df2885 tomada.
3. Correr a verificação (§4) e colar o output no relatório.
