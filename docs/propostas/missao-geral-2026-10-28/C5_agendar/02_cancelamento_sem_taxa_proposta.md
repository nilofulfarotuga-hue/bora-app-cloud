# C5 · Proposta 02 — Cancelar até 1 h antes, sem taxa (pedidos agendados)

Item 5 do adendo 5 (29/10/2026). **NÃO APLICADA.** Mexe em taxas de cancelamento e em Edge Functions
(`supabase/functions/**`), por isso é só proposta: **"⚠️ ISTO MEXE EM DINHEIRO. Está tudo pronto — confirma
que eu aplico."** Precisa do "autorizo" do Danilo e do revisor independente.

## O que a regra do Danilo pede

"Cancelamento pelo cliente até 1 h antes [da hora agendada] sem taxa."

## O que o código faz hoje (lido, não deduzido)

Três Edge Functions calculam a taxa do cancelamento do cliente, todas com `getCancelFees()` +
`computeCancelFeeEur()` de `supabase/functions/_shared/platform_settings.ts`:

| Função | Onde calcula a taxa |
|---|---|
| `client-cancel-order` | `index.ts` ~linha 100-103: `tier === 'grace' ? 0 : computeCancelFeeEur(tier, total, fees)` |
| `cancel-order-with-choice` | `index.ts` ~linha 128: `computeCancelFeeEur(t, totalEur, fees)` |
| `execute-cancellation` | `index.ts` ~linha 129: `computeCancelFeeEur(t, totalEur, fees)` |

Os escalões (`client-cancel-order`, `baseTier`): `created / preparing / callingDriver` = `before_dispatch`;
`driverAccepted` = `after_accept`; `pickedUp / onTheWay` = `after_pickup`; e `grace` (taxa 0) se o pedido tem
menos de `cancel_grace_seconds` (180 s) e ainda sem estafeta. As taxas vêm de `platform_settings`:
`cancel_fee_before_dispatch_cents`, `cancel_fee_after_accept_cents`, `cancel_fee_after_pickup_ratio`.

Um comentário em `lib/screens/order_details_screen.dart` (~linha 335) diz que
`cancel_fee_before_dispatch_cents = 0 em produção` ("padrão Uber/Glovo"). **Isto está por confirmar com um
SELECT** (não tenho acesso à base nesta missão):

```sql
select key, value from public.platform_settings where key like 'cancel_%' order by key;
```

## Conclusão para o Danilo, em português simples

- Se `cancel_fee_before_dispatch_cents` for mesmo 0, **"cancelar até 1 h antes sem taxa" já acontece hoje**:
  um pedido agendado só passa a "estafeta chamado" perto da hora marcada (proposta 01: hora marcada − 8 min), e
  antes disso está em `created`/`preparing` sem estafeta, que é o escalão `before_dispatch` com taxa 0.
- O que falta é **garantir** a regra para o dia em que alguém suba essa taxa, e **não depender** de um número
  que está noutra tabela. A proposta abaixo põe a regra por escrito, só para pedidos agendados.

## O que se propõe

Um escalão novo `agendado_gratis` (taxa 0) para quem cancela um pedido agendado **sem estafeta atribuído** e
**a pelo menos 60 minutos do início da janela**. Dentro dos 60 minutos mantêm-se as regras de hoje.

### 1. Definição (dinheiro → só com o "autorizo")

```sql
insert into public.platform_settings (key, value, description, category) values
  ('scheduled_orders_free_cancel_minutes', '60'::jsonb,
   'Pedidos agendados: o cliente cancela sem taxa até X minutos antes do início da janela (sem estafeta atribuído).',
   'scheduling')
on conflict (key) do nothing;
```

### 2. Código comum (`supabase/functions/_shared/platform_settings.ts`)

```ts
// C5 (29/10/2026): pedido agendado cancelado a ≥ N min do início da janela, sem estafeta → taxa 0.
export async function scheduledFreeCancelMinutes(admin: any): Promise<number> {
  try {
    const { data } = await admin.from('platform_settings').select('value')
      .eq('key', 'scheduled_orders_free_cancel_minutes').maybeSingle();
    const n = Number(data?.value);
    return Number.isFinite(n) && n > 0 ? n : 60;
  } catch (_) { return 60; }
}

export function isScheduledFreeCancel(
  order: { scheduled_for?: string | null; assigned_driver_id?: string | null },
  minutes: number,
  now = Date.now(),
): boolean {
  if (!order.scheduled_for || order.assigned_driver_id) return false;
  const quando = new Date(order.scheduled_for).getTime();
  return Number.isFinite(quando) && (quando - now) >= minutes * 60_000;
}
```

### 3. Em cada uma das três funções

1. Acrescentar `scheduled_for` ao `select(...)` do pedido (as três já leem o pedido; falta esta coluna).
2. Mudar só a linha da taxa:

```ts
const livre = isScheduledFreeCancel(order, await scheduledFreeCancelMinutes(admin));
const feeEur = (tier === 'grace' || livre) ? 0
  : Number(computeCancelFeeEur(tier as any, totalEur, fees).toFixed(2));
```

   (`cancel-order-with-choice` e `execute-cancellation` usam `t` em vez de `tier`; é a mesma troca.)
3. Devolver `agendado_gratis: livre` na resposta (para o ecrã mostrar "sem custo").

Nada mais muda: o reembolso (cartão / carteira / tokens), o claim atómico e o resto ficam como estão.

### 4. App (fora desta missão: `order_details_screen.dart` é zona proibida)

O diálogo de cancelar lê as taxas por `get_setting` (linhas ~350-355) e **mostra** uma taxa; para um agendado
com `scheduledFor − agora ≥ 60 min` deve mostrar 0 e o texto "Podes cancelar sem custo até 1 h antes.". Já está
escrito na app como frase traduzível no seletor do carrinho (`Podes cancelar sem custo até 1 h antes.`), só
visível com o interruptor ligado.

## Prova a pedir ao revisor (todas em transação desfeita ou com pedido de teste de dinheiro)

1. SELECT dos `cancel_*` (acima) — dizer o valor real de `cancel_fee_before_dispatch_cents`.
2. Pedido agendado de teste (dinheiro, loja de teste): cancelar a 90 min da janela → `cancel_fee = 0`.
3. O mesmo a 30 min da janela → a taxa do escalão de hoje (zero se a setting for zero).
4. Pedido NÃO agendado: taxa exatamente igual à de hoje (regressão).
5. Pedido agendado com estafeta já atribuído, a 90 min: **não** é grátis (estafeta já atribuído).
6. Cartão: reembolso total e `refund_amount` certo; carteira/tokens: devolução igual à de hoje.

## Riscos

- O estafeta só é chamado perto da hora (proposta 01); se o Danilo pedir para chamar mais cedo (ex.: 2 h), o
  escalão `after_accept` aparece antes dos 60 min e a regra deixa de ser "grátis até 1 h antes" na prática.
- Pagamento em dinheiro: o cancelamento tardio cria dívida na carteira (`wallet_debit_cancel_fee`); o escalão
  grátis não cria. Confirmar que nenhum vigia conta "cancelamentos grátis" como abuso.
