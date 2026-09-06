# Patch pronto — guarda `store_coming_soon` no checkout (2026-07-31)

**Não foi aplicado. Está bloqueado por duas travas que só o Danilo destranca à mão.**
Este ficheiro tem o patch exato para aplicar em segundos assim que destrancares.

Autorização do Danilo: **"VAI"** (2026-07-31, nesta sessão).

---

## Porque é que não avancei

Duas travas **independentes**, e nenhuma delas é para eu contornar:

| # | Trava | O que bloqueia | Onde |
|---|---|---|---|
| 1 | Deny de permissões | `Edit` / `Write` / `MultiEdit` em `./supabase/functions/create-payment-intent/**` e `create-mbway-payment-intent/**` | `.claude/settings.json` → `permissions.deny` |
| 2 | Trava protege-dinheiro | `deploy_edge_function` para slugs em `PROTSLUG` (inclui as duas) | `.claude/hooks/protege-banco.sh` linha 52 |

Mesmo que eu escrevesse o ficheiro por outra via, a **#2 continuava a impedir o
deploy** — ficava só um ficheiro alterado em zona 🔴 sem chegar a produção, que é
pior do que não mexer. E o próprio `.claude/settings.json` está listado no
`CLAUDE.md` como zona protegida que eu não edito.

O ponto destas travas é exatamente este: um agente com uma autorização plausível
no chat **não** deve conseguir mexer sozinho no checkout. Respeitei-o.

---

## Estado atual (verificado)

- **Backup da versão em produção guardado:**
  `.claude/.ai/backups/edge-functions/2026-07-31/create-payment-intent.v32.DEPLOYED.ts`
  `sha256 = 53b95c67cfe5b2b073677735549bdf79c7fa317489e878b374751ebaa2638ec4`
- **`create-payment-intent`**: deploy #32. O `version: 32` da API é o **contador de
  deploys**, não a versão do código — o cabeçalho do código diz `v28` tanto no
  deployed como no repo.
- **Drift repo ↔ deployed:** o deployed tem 231 linhas, o repo 328. Verifiquei bloco
  a bloco: a diferença é **só comentários e quebras de linha** — a lógica é a mesma
  (ambos têm Mode A e Mode B, mesma ordem, mesmas chamadas). Ainda assim, **o patch
  abaixo é sobre o DEPLOYED**, que é a verdade.
- O ficheiro local foi restaurado ao HEAD (`git checkout --`) — o
  `supabase functions download` do backup tinha-o sobreposto. Não deixei drift.

---

## O patch — `create-payment-intent`

### Mode A (`modeLegacy`) — 2 alterações

**A1.** Acrescentar `restaurant_id` ao SELECT (só lê mais uma coluna; não toca em
nenhum valor):

```diff
   const { data: order, error: dbError } = await supabase
-    .from('orders').select('price, payment_buffer_total').eq('id', order_id).maybeSingle();
+    .from('orders').select('price, payment_buffer_total, restaurant_id').eq('id', order_id).maybeSingle();
```

**A2.** Guarda logo a seguir ao `if (!order)`, **antes** de toda a aritmética e
**muito antes** do `stripe.paymentIntents.create`:

```diff
   if (!order) return json({ error: 'Order not found' }, 404);
+
+  // "Em breve" (2026-07-31): loja fechada a pedidos NUNCA chega ao Stripe.
+  // Só rejeita — não altera preço, comissão, markup nem buffer.
+  if (await isStoreComingSoon(supabase, order.restaurant_id as string | null)) {
+    return json(COMING_SOON_BODY, 400);
+  }
+
   const serverPrice = order.price as number;
```

### Mode B (`modeNew`) — 1 alteração

Guarda logo a seguir à autenticação, **antes do `quote_order_pricing`** (que fica
intocado), **antes do insert em `payment_drafts`** e **antes do Stripe**. A loja vem
em `cart.restaurant_id` — a mesma chave que o `quote_order_pricing` lê em
`p_input->>'restaurant_id'`:

```diff
   cart.user_id = user.id;
   cart.payment_method = 'card';
+
+  // "Em breve" (2026-07-31): rejeitar ANTES do quote, do draft e do Stripe.
+  {
+    const admin0 = createClient(supabaseUrl, serviceKey);
+    if (await isStoreComingSoon(admin0, cart?.restaurant_id ?? null)) {
+      return json(COMING_SOON_BODY, 400);
+    }
+  }
 
   const { data: quote, error: quoteErr } = await userClient.rpc('quote_order_pricing', { p_input: cart });
```

### Helper — acrescentar no fim do ficheiro

```ts
// ── "Em breve" (coming_soon) — 2026-07-31 ─────────────────────────────────
// Bloqueio só no Flutter não chega (app modificada contorna). Isto não altera
// nenhum valor cobrado: só recusa criar o PaymentIntent.
// Defesa em profundidade: há também trigger BEFORE INSERT em `orders`.
const COMING_SOON_BODY = {
  error: 'store_coming_soon',
  code: 'STORE_COMING_SOON',
  message: 'Esta loja ainda não está a aceitar pedidos.',
};

// Falha de leitura → false (não inventa bloqueio); o trigger da BD é a rede final.
// deno-lint-ignore no-explicit-any
async function isStoreComingSoon(admin: any, restaurantId: string | null): Promise<boolean> {
  if (!restaurantId) return false;
  try {
    const { data, error } = await admin
      .from('restaurants').select('coming_soon').eq('id', restaurantId).maybeSingle();
    if (error) {
      console.error('[coming-soon] lookup failed:', error.message);
      return false;
    }
    return data?.coming_soon === true;
  } catch (err) {
    console.error('[coming-soon] lookup threw:', err);
    return false;
  }
}
```

---

## O patch — `create-mbway-payment-intent`

Já preparado na sessão anterior e **igualmente bloqueado**. Mesmo helper, mais:

```diff
     const { data: order, error: dbErr } = await supabase
       .from('orders')
-      .select('payment_buffer_total, payment_method, payment_status')
+      .select('payment_buffer_total, payment_method, payment_status, restaurant_id')
       .eq('id', order_id)
       .maybeSingle();
```

e a guarda antes do `const amountCents = ...` (portanto antes do
`stripe.paymentIntents.create` que faz `confirm: true` e dispara o push MB WAY):

```diff
+    if (await isStoreComingSoon(supabase, order.restaurant_id as string | null)) {
+      return new Response(JSON.stringify(COMING_SOON_BODY),
+        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
+    }
+
     const amountCents = Math.round((order.payment_buffer_total as number) * 100);
```

---

## Como destrancar e aplicar

1. **Trava #1** — em `.claude/settings.json`, comentar/remover as 6 linhas de `deny`
   destas duas funções (`Edit`/`Write`/`MultiEdit` × 2).
2. **Trava #2** — em `.claude/hooks/protege-banco.sh` linha 52, tirar
   `create-payment-intent|create-mbway-payment-intent` do `PROTSLUG`.
3. Diz-me e eu aplico o patch + faço deploy + corro os testes abaixo.
4. **Voltar a pôr as duas travas a seguir.** Não as deixes abertas.

Se preferires não destrancar nada, também dá para aplicares tu à mão com o diff
acima — são 3 blocos num ficheiro e 2 no outro.

---

## Testes a correr depois do deploy (não os saltar)

| Teste | Esperado |
|---|---|
| Mode A, order de loja NORMAL | 200 + `clientSecret` (continua a criar PI) |
| Mode A, order de loja **Em breve** | 400 `store_coming_soon`, **zero** PIs novos no Stripe |
| Mode B, `cart_input` de loja NORMAL | 200 + draft criado |
| Mode B, `cart_input` de loja **Em breve** | 400 `store_coming_soon`, **zero** PIs e **zero** linhas novas em `payment_drafts` |
| MBWay, order de loja **Em breve** | 400, **sem** push MB WAY no telemóvel |

Verificação objetiva: `SELECT count(*) FROM payment_drafts` antes/depois, e o
dashboard do Stripe (modo live) sem PaymentIntents novos.

---

## ⚠️ Urgência: MAIS ALTA do que eu disse primeiro — corrijo-me

Escrevi antes que isto era quase cosmética. **Está errado para o Mode B.** Verifiquei
o caminho a sério e é assim:

1. `lib/stores/order_store.dart:635` manda `{'cart_input': cartInput}` → **o checkout
   de cartão do app usa o Mode B**, não o legacy.
2. No Mode B **não existe order nenhuma** quando o PaymentIntent é criado. A order só
   nasce **depois** do `payment_intent.succeeded`, no `finalize-order-from-intent`,
   que chama `create_order` com `payment_already_confirmed=TRUE`.
3. O meu trigger `trg_coming_soon_guard_orders` dispara **nesse** insert.

Resultado numa loja "Em breve", por cartão: **o cliente é cobrado e só a seguir é que
a criação do pedido rebenta** (`create_order_failed`). Fica pagamento órfão — dinheiro
levado, pedido nenhum.

**E isto é um bico que o meu próprio trigger de hoje criou.** Antes dele não havia
bloqueio nenhum e a order era criada à mesma; agora é bloqueada no pior momento
possível — depois do pagamento. O trigger continua certo (é a rede final), mas
**precisa deste patch à frente dele** para rejeitar antes do Stripe.

Quão provável é: exige app modificada (o Flutter já bloqueia carrinho e checkout)
**e** uma loja em "Em breve" — há 2 neste momento. Probabilidade baixa, estrago
desagradável.

**Conclusão: o Mode B deixa de ser opcional.** Mode A e MBWay continuam a ser só
melhoria de mensagem de erro (nesses a order já existe, logo o trigger apanha antes
de qualquer cobrança).
