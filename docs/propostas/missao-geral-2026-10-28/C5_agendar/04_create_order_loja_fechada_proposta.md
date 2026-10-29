# C5 · Proposta 04 — Sem isto, a loja FECHADA recusa o pedido agendado (`STORE_CLOSED`)

Item 5 do adendo 5 (29/10/2026). **NÃO APLICADA.** É a 4.ª proposta do item 5 (as 3 pedidas são a 01, 02 e 03);
nasce porque, ao procurar como o carrinho passa a hora ao `create_order`, descobri que **não passa e que o
servidor trava o pedido antes**. Mexe em `create_order` (função de dinheiro), num gatilho de `orders` e em
`lib/stores/order_store.dart` — tudo coisas em que esta missão não toca. **"⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO.
Está tudo pronto — confirma que eu aplico."** Revisor independente obrigatório.

## 1. O que descobri (lido nos ficheiros)

1. `create_order` **não aceita hora marcada**. O único remendo que existe para isso está em
   `supabase/migrations/20260825091000_festas_money_patch.sql` e diz no topo "NAO APLICADA".
   (Confirmar na base: `select position('scheduled_for' in pg_get_functiondef('create_order(jsonb)'::regprocedure));`
   — 0 = não grava.)
2. Por isso as Festas gravam a data **depois** de criar o pedido, por uma RPC à parte (`festas_set_schedule`,
   chamada em `cart_store.dart` `finishOrder` e em `payment_method_screen.dart`). A C5 fez o mesmo
   (`client_set_order_schedule`, na migração 20261029200700) — **não toca `create_order`**.
3. **Mas a loja fechada trava o INSERT.** O gatilho `trg_store_closed_guard_orders` (BEFORE INSERT em `orders`,
   função `_store_closed_guard_orders`, definição viva em `20261027180000_estado_aplicado_sem_migracao_boom_2026_10_27.sql`
   linhas ~125-146) chama `is_partner_open(NEW.restaurant_id)` — **a hora de agora** — e lança
   `STORE_CLOSED` se a loja estiver fechada. Não olha a `scheduled_for`.
   ⇒ Com a loja fechada, o pedido nem chega a existir, e a RPC pós-criação nunca tem um pedido para marcar.
4. O cartão ainda é pior: o pedido nasce no servidor (`finalize-order-from-intent`) **depois** de a Stripe
   cobrar, a partir do rascunho (`payment_drafts.payload`, que é o `cart_input` da app inteiro, passado
   tal e qual ao `create_order`). Se o `create_order` recusar com `STORE_CLOSED` aí, **o cliente já pagou**.

## 2. O que a C5 já faz sem isto (e o que fica por fazer)

| Situação | Funciona só com a migração 20261029200700? |
|---|---|
| Loja ABERTA agora, cliente escolhe "Agendar" (dinheiro, MB Way, saldo, cartão com `orderId`) | Sim: cria o pedido e grava a hora a seguir (3 tentativas; a hora também vai na nota do pedido). Há uma janela de ~1 s em que o pedido existe sem hora. |
| Loja FECHADA agora | **Não** — `STORE_CLOSED`. É o caso do item 5. Precisa desta proposta. |
| Cartão pelo rascunho (webhook) | **Não** — a hora nem chega ao rascunho. Precisa desta proposta. |

**Por isso o interruptor tem a tranca `scheduled_orders_revisor_ok`**: o painel não deixa ligar enquanto o
revisor não disser SIM, e o SIM só se dá com esta proposta aplicada e provada nos três métodos de pagamento.

## 3. As quatro peças (por esta ordem)

### A. Gatilho: a loja só tem de estar aberta NA HORA MARCADA

```sql
-- backup
create table if not exists public.bkp_fn_store_closed_guard_orders_20261029 as
  select now() as guardado_em, pg_get_functiondef('public._store_closed_guard_orders()'::regprocedure) as def;
alter table public.bkp_fn_store_closed_guard_orders_20261029 enable row level security;

CREATE OR REPLACE FUNCTION public._store_closed_guard_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_estado JSONB; v_abre TEXT;
BEGIN
  IF NEW.restaurant_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.service_type NOT IN ('restaurant','storeShopping','takeaway') THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('app.parceiro_chama_estafeta', true), '') = 'on' THEN RETURN NEW; END IF;
  -- 27/10/2026 modo demonstracao: so o pedido de teste do cliente demo, na loja e janela definidas.
  IF COALESCE(NEW.is_test_order, false) AND public._modo_demo_loja(NEW.restaurant_id, NEW.user_id) THEN RETURN NEW; END IF;

  -- C5 (29/10/2026): pedido AGENDADO (interruptor ligado, restaurante parceiro com entrega, não festas):
  -- a loja só tem de estar aberta na hora marcada. A hora já foi validada contra as janelas no create_order (peça B).
  IF NEW.scheduled_for IS NOT NULL
     AND NEW.service_type = 'restaurant'
     AND COALESCE(NEW.is_partner_store, false)
     AND (public._sched_cfg()->>'enabled')::boolean
     AND NOT EXISTS (SELECT 1 FROM public.restaurants fr WHERE fr.id = NEW.restaurant_id AND fr.category = 'festas')
  THEN
    v_estado := public.is_partner_open(NEW.restaurant_id, NEW.scheduled_for);
  ELSE
    v_estado := public.is_partner_open(NEW.restaurant_id);
  END IF;

  IF COALESCE((v_estado->>'is_open')::boolean, true) IS FALSE THEN
    v_abre := v_estado->>'opens_at';
    RAISE EXCEPTION 'STORE_CLOSED: A loja esta fechada neste momento.%',
      CASE WHEN v_abre IS NOT NULL THEN ' Abre as ' || v_abre || '.' ELSE '' END
      USING ERRCODE = 'P0001', HINT = 'STORE_CLOSED';
  END IF;
  RETURN NEW;
END;
$function$;
```

Com o interruptor desligado, ou sem `scheduled_for`, o caminho é **exatamente** o de hoje (`is_partner_open(NEW.restaurant_id)`).

### B. `create_order`: grava `scheduled_for` do `p_input` e valida a hora

Mesma técnica do remendo das Festas: `REPLACE` textual sobre a definição **viva**, com âncoras verificadas (se uma
não bater, aborta sem mexer em nada). **Antes**, confirmar que as Festas não aplicaram já a parte 1 (peça 1 do
item 1 acima: `position(...) = 0`); se já grava, só a validação (B2) é precisa.

```sql
-- backup
insert into public._fn_backups (fn_name, def)
values ('create_order(jsonb) · C5 29/10', pg_get_functiondef('create_order(jsonb)'::regprocedure));

DO $do$
DECLARE
  v_def text := pg_get_functiondef('create_order(jsonb)'::regprocedure);
  v_a1 text := $a$    takeaway_is_curbside, takeaway_curbside_info, takeaway_pickup_code
  ) VALUES ($a$;
  v_a2 text := $a$    v_takeaway_curbside,
    p_input->>'takeaway_curbside_info',
    v_takeaway_pickup_code
  );$a$;
  v_a3 text := $a$    v_bag_fee             := v_pricing.bag_fee;
  END IF;$a$;
BEGIN
  IF POSITION('scheduled_for' IN v_def) > 0 THEN
    RAISE EXCEPTION 'C5: create_order ja menciona scheduled_for — rever à mao (festas aplicou o remendo?)';
  END IF;
  IF POSITION(v_a1 IN v_def) = 0 OR POSITION(v_a2 IN v_def) = 0 OR POSITION(v_a3 IN v_def) = 0 THEN
    RAISE EXCEPTION 'C5: ancora nao encontrada em create_order — abortado sem alterar nada';
  END IF;
  -- B1) a coluna e o valor no INSERT
  v_def := replace(v_def, v_a1, $r$    takeaway_is_curbside, takeaway_curbside_info, takeaway_pickup_code,
    scheduled_for
  ) VALUES ($r$);
  v_def := replace(v_def, v_a2, $r$    v_takeaway_curbside,
    p_input->>'takeaway_curbside_info',
    v_takeaway_pickup_code,
    NULLIF(p_input->>'scheduled_for','')::timestamptz
  );$r$);
  -- B2) a validação, depois do preço e antes do INSERT
  v_def := replace(v_def, v_a3, $r$    v_bag_fee             := v_pricing.bag_fee;
  END IF;

  -- C5 (29/10/2026): pedido agendado — a hora tem de ser o início de uma janela livre (a mesma regra da app).
  -- 15 min de folga na antecedência: no cartão o pedido nasce uns minutos depois de o cliente escolher.
  IF NULLIF(p_input->>'scheduled_for','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.restaurants fr
                      WHERE fr.id = p_input->>'restaurant_id' AND fr.category = 'festas') THEN
    IF NOT (public._sched_cfg()->>'enabled')::boolean THEN
      RAISE EXCEPTION 'SCHEDULED_ORDERS_DISABLED: Os pedidos agendados estao desligados.'
        USING ERRCODE = 'P0001', HINT = 'SCHEDULED_ORDERS_DISABLED';
    END IF;
    IF NOT EXISTS (
      SELECT 1
        FROM jsonb_array_elements(public._sched_windows_core(
               p_input->>'restaurant_id',
               ((NULLIF(p_input->>'scheduled_for',''))::timestamptz AT TIME ZONE 'Europe/Lisbon')::date,
               15)) w
       WHERE (w->>'inicio')::timestamptz = (NULLIF(p_input->>'scheduled_for',''))::timestamptz
    ) THEN
      RAISE EXCEPTION 'SCHEDULE_WINDOW_INVALID: A hora escolhida ja nao esta disponivel.'
        USING ERRCODE = 'P0001', HINT = 'SCHEDULE_WINDOW_INVALID';
    END IF;
  END IF;$r$);
  EXECUTE v_def;
END $do$;
```

`_sched_windows_core` é a função interna da migração 20261029200700 (sem verificação de sessão, porque o
`create_order` corre com a chave de serviço no caminho do cartão).

### C. App (`lib/stores/order_store.dart` — zona proibida nesta missão)

Mesmo caminho do `deixarAPorta` (`order_store.dart` linhas ~509/587 em `startCardPaymentDraft` e ~771/905 em
`createOrder`; `cart_store.dart` ~1409 e ~1514 chamam com `deixarAPorta: deixarAPortaNoPedido(...)`):

```dart
// parâmetro novo nos DOIS métodos (startCardPaymentDraft e createOrder):
DateTime? scheduledFor,
// no mapa do payload (junto de 'deixar_a_porta'):
if (scheduledFor != null) 'scheduled_for': scheduledFor.toUtc().toIso8601String(),
// em cart_store.dart, nas DUAS chamadas:
scheduledFor: AgendarPedidoEstado.instance.escolhaPara(_vendorRestaurantId) && AgendarPedidoEstado.instance.ligado
    ? AgendarPedidoEstado.instance.escolha!.instante
    : null,
```

Com isto, `client_set_order_schedule` passa a ser só uma rede de segurança (devolve `ja_estava: true`).

### D. Edge Functions: **nada a mudar**

`create-payment-intent` grava o `cart_input` inteiro em `payment_drafts.payload` e
`finalize-order-from-intent` passa esse `payload` tal e qual ao `create_order`
(`supabase/functions/finalize-order-from-intent/index.ts` ~linha 90). A chave nova viaja sozinha.

## 4. O que o revisor deve tentar derrubar

1. **Cartão: pagou e o pedido não nasceu.** Se `create_order` lançar `SCHEDULE_WINDOW_INVALID` depois da cobrança,
   o cliente pagou sem pedido. Mitigações: folga de 15 min; e confirmar que o caminho de hoje para
   "`create_order` falhou depois de cobrar" devolve o dinheiro (`payments-reconciler` / `auto-refund-order`).
   Provar com um pagamento de teste em dinheiro real mínimo, com a janela a expirar entre o rascunho e o webhook.
2. **Janela de ~1 s sem hora** (se só a peça C faltar): o pedido existe `created` sem `scheduled_for`; a loja é
   avisada ("Novo pedido"). Com a peça C aplicada isto desaparece.
3. **Aviso "Novo pedido!" de um pedido para daqui a dias.** O parceiro recebe o alarme de pedido novo logo que
   o pedido é criado (comportamento já existente), mesmo que seja para sábado. É bom (aceita logo), mas o som
   repete até aceitar. Decidir se se quer silenciar o alarme em ciclo para agendados a mais de 2 h.
4. **Vigias de pedidos parados / sem resposta da loja.** Se existir auto-cancelamento de `created` sem aceite
   (não encontrei no repo, mas pode estar só na base), um agendado para daqui a 6 dias seria cancelado.
   `select jobname, command from cron.job;` e ler os que falam de `created`/`orphan`.
5. **Fusos e mudança de hora (último domingo de outubro / março).** `_sched_windows_core` usa `AT TIME ZONE
   'Europe/Lisbon'`; provar os dois dias de mudança de hora (a 25/10/2026 já passou; a próxima é 28/03/2027).
6. **`is_partner_open(NEW.restaurant_id, NEW.scheduled_for)` com `partner_status_override`** (loja forçada
   fechada pelo admin): respeita o override que cobre a hora marcada, não o de agora — é o desejado.
7. **Regressão:** pedido normal (sem `scheduled_for`) com a loja aberta e fechada: comportamento idêntico ao de hoje
   (a peça A só muda o ramo com `scheduled_for`).

## 5. Reversão

```sql
-- gatilho: restaurar a definição guardada
DO $rev$ BEGIN EXECUTE (select def from public.bkp_fn_store_closed_guard_orders_20261029 order by guardado_em limit 1); END $rev$;
-- create_order: restaurar de public._fn_backups (a linha 'create_order(jsonb) · C5 29/10')
-- ou, sem tocar em nada: desligar o interruptor no painel (Pedidos agendados).
```
