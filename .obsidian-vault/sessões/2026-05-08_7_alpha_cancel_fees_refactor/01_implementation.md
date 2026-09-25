# Sessão 7-α — Implementation Notes

## Helper `_shared/platform_settings.ts`

### Design

- `getCancelFees()` → `Promise<CancelFees>` com cache em-memory
  TTL 5min.
- Fallback defensivo: se DB falha ou retorna 0 rows, retorna
  `FALLBACK_FEES` (€1.50/€2.50/1.00 alinhados com prod 2026-05-08)
  e regista WARN visível em Edge Function logs.
- `parseJsonbNumber(val, fallback)` lida com `number` ou `string`
  vindos de JSONB (defensive parsing).
- `getAdminClient()` lazy-init usando `SUPABASE_URL` +
  `SUPABASE_SERVICE_ROLE_KEY`. Throws se env vars ausentes (capturado
  pelo try/catch do `getCancelFees`).
- `computeCancelFeeEur(tier, totalEur, fees)` — wrapper conveniente
  para os 4 estados de tier (`before_dispatch | after_accept |
  after_pickup | invalid`).

### Cache strategy

```typescript
interface CacheEntry { fees: CancelFees; fetchedAt: number; }
let cache: CacheEntry | null = null;
const CACHE_TTL_MS = 5 * 60 * 1000;
```

Cache é por Edge Function process (Deno isolate). Não é compartilhada
entre regiões/instances. Trade-off: simplicidade vs propagation delay
máx. 5min após settings change.

## Refactor pattern aplicado nas 3 Edge Fns

### ANTES

```typescript
import {
  CANCEL_FEE_BEFORE_DISPATCH_EUR,
  CANCEL_FEE_AFTER_ACCEPT_EUR,
  CANCEL_FEE_AFTER_PURCHASE_RATIO,
} from '../_shared/business_rules.ts';

function feeEur(t: Tier, total: number): number {
  switch (t) {
    case 'before_dispatch': return CANCEL_FEE_BEFORE_DISPATCH_EUR;
    case 'after_accept': return CANCEL_FEE_AFTER_ACCEPT_EUR;
    case 'after_pickup': return total * CANCEL_FEE_AFTER_PURCHASE_RATIO;
    default: return 0;
  }
}

const fee = Number(feeEur(t, totalEur).toFixed(2));
```

### DEPOIS

```typescript
import { getCancelFees, computeCancelFeeEur } from '../_shared/platform_settings.ts';

const fees = await getCancelFees();
const fee = Number(computeCancelFeeEur(t, totalEur, fees).toFixed(2));
```

(Função local removida.)

### Notas por função

- **`client-cancel-order/index.ts`** — função local chamava-se
  `computeFeeEur` (não `feeEur`); idempotency key Stripe preservada.
- **`cancel-order-with-choice/index.ts`** — handler async,
  `await getCancelFees()` integra naturalmente; wallet path e Stripe
  path ambos beneficiam.
- **`execute-cancellation/index.ts`** — admin-only path; mesma
  estratégia. Audit log inalterado.

## Decisões

- **PT-PT em logs WARN**: mensagens `[platform_settings] DB error
  reading cancel fees, using fallback` — visíveis no painel Supabase.
- **Fallback values alinhados** com prod actual (2026-05-08):
  €1.50 / €2.50 / 1.00. Se settings forem removidas da DB, helper
  continua a funcionar com estes valores.
- **Cache scope**: por Edge Function process (não compartilhado
  entre regiões/instances). Trade-off: simplicidade vs propagation
  delay.
- **Async handlers preservados**: as 3 fns já eram
  `Deno.serve(async ...)`, integração `await getCancelFees()` é
  trivial.

## Não tocado

- `business_rules.ts` (mantém constantes para uso noutras partes do
  código + fallback defensivo do helper).
- `tier resolution` logic (mesmas 3 categorias before_dispatch /
  after_accept / after_pickup).
- Stripe refund / wallet credit / RPC calls.
- `notify-client` invocation.
- `admin-cancel-order`, `admin-cancel-reservation` (não importavam
  `business_rules` — confirmado em A0).
- `create-payment-intent`, `create-mbway-payment-intent`,
  `charge-extra` (limpas — confirmado).
- `dispatch-engine` (driver fees, fora scope).

## Validação

- F2.5: ZERO refs `CANCEL_FEE_*` ou `business_rules` em `index.ts`
  das 3 fns.
- F2.7: ZERO smart quotes detectadas em todos os 4 ficheiros.
- F3.5: Versões confirmadas via `supabase functions list`:
  v12 / v4 / v3 ACTIVE.
- `deno check` passa no helper.
- `deno check` falha nas 3 fns com `Could not find npm:@types/node` —
  pre-existente (validado correndo o mesmo check em HEAD via stash),
  environmental do esm.sh Stripe, não bloqueia
  `supabase functions deploy` (runtime resolve diferente).

## Trade-offs documentados

- Primeira chamada após cache miss paga 1 query Postgres (~30ms na
  região eu-west-1).
- Settings change não é instantânea — máx. 5min de delay por
  instância.
- Fallback defensivo significa que se BD falha sem barulho, fees
  continuam a ser cobrados pelos valores antigos. WARN no log é a
  detecção.

## Referência

- BR §49 — Cancel Fees Runtime Refactor
  (`.claude/.ai/business_rules.md`).
