# Proposta — cancelar o pedido devolve também o vale de DESCONTO do check-in (04/11/2026)

## O erro

O gatilho `trg_checkin_premio_pedido_cancelado` em `orders` só dispara quando os artigos do
pedido têm `premio-checkin-` no texto. Um pedido com vale de **desconto** não tem artigo-prémio,
por isso, ao cancelar, o vale fica "usado" para sempre.

Prova em rollback (conta demo, dinheiro, Continente, 7× iogurte Yopro):
`create_order` com o vale → total 40,43 € passa a 37,43 €, estafeta 5,57 € igual, vale `usado`
com o `pedido_id`; `admin_cancel_order` → o vale continua `usado`.

## O SQL (uma linha; a trava `protege-banco.sh` bloqueia DDL em gatilhos de `orders` nesta sessão)

```sql
CREATE OR REPLACE TRIGGER trg_checkin_premio_pedido_cancelado
  AFTER UPDATE OF status ON public.orders FOR EACH ROW
  WHEN ((new.status = ANY (ARRAY['cancelled'::text, 'rejected'::text]))
        AND (old.status IS DISTINCT FROM new.status))
  EXECUTE FUNCTION _checkin_premio_pedido_cancelado();
```

Só tira o filtro dos artigos. A função já procura os vales por `pedido_id` (há o índice
`checkin_premios_vales_pedido`), por isso o custo num cancelamento sem vale é uma leitura vazia.
A regra de devolver só antes de um estafeta aceitar (`_checkin_premio_pode_voltar`) não muda.

## Nota sobre a prova

Com a conta demo a devolução não se consegue mostrar: o gatilho `a_trg_pedido_demo_caixa_fechada`
põe o pedido demo logo em `driverAccepted`, e um pedido já aceite não devolve o vale (de propósito).
Depois de aplicar, provar com `motivo` do vale: num pedido demo cancelado passa a ter
"o vale não volta" — sinal de que o gatilho disparou.
