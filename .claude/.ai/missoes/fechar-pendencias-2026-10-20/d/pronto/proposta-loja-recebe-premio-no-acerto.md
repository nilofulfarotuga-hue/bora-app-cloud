# Proposta — a loja recebe o prémio no acerto semanal sozinha (Bloco D)

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

Data: 21/10/2026. Missão fechar-pendencias-2026-10-20, Bloco D (prémios dos marcos do check-in).

## O que faz, em palavras simples

Hoje (aplicado) o prémio entra no pedido como um artigo a 0,00 €. O cliente paga a entrega e as
taxas; a Keli e o Goola preparam o artigo; o estafeta acerta certo com a Bora. Mas como o artigo
vale 0 no pedido, o **acerto semanal automático da loja não inclui o prémio**. Enquanto esta
proposta não for aplicada, o que a Bora deve às lojas pelos prémios aparece no painel admin
(Clientes → Check-in diário → Prémios → "A pagar às lojas"), com o botão "Marcar como pago".

Esta proposta põe o prémio dentro do acerto semanal da loja, como venda normal: quando o pedido com
o prémio fica entregue e pago, entra uma linha de ganho da loja (`ledger_entries`, tipo `earning`,
referência `checkin_premio`) com o valor do custo do vale (a venda normal da loja:
2 Salgados Grandes = 5,40 €; Goola Bowl = 7,90 €). O acerto da loja
(`compute_partner_weekly_settlement`) já soma todas as linhas `earning` de cada pedido, por isso
não precisa de mudar. O vale fica marcado "pago à loja pelo acerto" e sai da lista manual.

## Porque não está aplicada

Escreve em `ledger_entries` (zona protegida). A bora-tranca recusa qualquer migração com
`INSERT INTO public.ledger_entries`, e isso não se contorna. Também não foi possível prová-la
dentro da base em transação desfeita, pela mesma regra.

## Prova que existe (transação desfeita, 21/10/2026, cliente demo, pedido em dinheiro)

- Pedido do prémio na Sabores do Brasil entregue pelo estafeta demo: o acerto da loja na semana
  mudou em **+1 pedido, +0,00 € de parte da loja** (sem esta proposta o prémio não entra).
- A venda normal da loja para 6,30 € (2 × 3,15 € na app) é `partner_store_share(6.30, 'sabores-brasil-guarda')` = **5,40 €**,
  igual ao `custo_cents` do vale (540). Com esta proposta, essa mesma semana passaria a
  **+5,40 € de parte da loja** (a função de acerto soma `SUM(le.amount)` das linhas `earning` do pedido).
- Lista "a pagar às lojas" no painel, no mesmo teste: Sabores do Brasil, 1 vale, 540 cêntimos.

## Efeito lateral a saber

No fecho semanal da loja, a coluna "comissão" (`commission_total = gross_sales - partner_share`)
fica mais baixa nas semanas com prémios, porque o artigo vale 0 em `subtotal` (gross) e 5,40 € na
parte da loja. O valor a pagar à loja (`net_balance`) fica certo. Se quiseres a comissão certinha
também, é mais uma mudança na função de acerto (protegida).

## SQL (aplicar só depois do "vai", pela Claude.ai)

```sql
-- Bloco D — a loja recebe o prémio do check-in no acerto semanal (venda normal).
CREATE OR REPLACE FUNCTION public._checkin_premio_loja_no_acerto()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT * FROM public.checkin_premios_vales
     WHERE pedido_id = NEW.id AND estado = 'usado' AND tipo = 'produto' AND pago_loja_em IS NULL
     FOR UPDATE
  LOOP
    IF v.custo_cents > 0 AND v.loja_id IS NOT NULL THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES (v.loja_id, 'restaurant', NEW.id::uuid, ROUND(v.custo_cents / 100.0, 2), 'earning', 'checkin_premio')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
    UPDATE public.checkin_premios_vales
       SET pago_loja_em = now(), pago_loja_nota = 'acerto semanal da loja (ledger checkin_premio)', atualizado_em = now()
     WHERE id = v.id;
  END LOOP;
  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public._checkin_premio_loja_no_acerto() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_checkin_premio_loja_no_acerto
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered'
        AND NEW.payment_status = 'paid' AND NEW.items::text LIKE '%premio-checkin-%')
  EXECUTE FUNCTION public._checkin_premio_loja_no_acerto();
```

## Prova a correr logo a seguir ao "vai" (transação desfeita)

O mesmo guião do pedido demo (relatório RELATORIO-D.md, "Prova 2"): cliente demo chega ao dia 10,
reserva o vale, `create_order` em dinheiro na Sabores do Brasil, estafeta demo leva até ao fim
(`driver_advance_order` pickedUp → onTheWay, `driver_finish_cash_order`), e
`compute_partner_weekly_settlement('sabores-brasil-guarda', now(), false)` antes e depois:
esperado **+5,40 € em partner_share** e o vale com `pago_loja_em` preenchido.

## Reversão

```sql
DROP TRIGGER IF EXISTS trg_checkin_premio_loja_no_acerto ON public.orders;
DROP FUNCTION IF EXISTS public._checkin_premio_loja_no_acerto();
```
