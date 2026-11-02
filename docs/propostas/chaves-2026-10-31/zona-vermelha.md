# Chaves — o que falta nas funções de zona vermelha (31/10/2026)

> **Estado a 02/11/2026:** pontos 1 a 5 **aplicados** pela Claude.ai a 01/11 (missão
> zona-vermelha-2026-11-01: refund v28, dispatch-engine v64, stripe-webhook v38, client-cancel-order v32;
> finalize v15 espelhada no repo). Provado a 02/11: varredor 99 funções, 0 com padrão proibido; vigia
> 50/50 ok (refund e dispatch-engine já respondem `{"pong":true}`). Falta só o ponto 6 (abaixo).

Missão `chaves-varredura-2026-10-31`. Autorização do Danilo de 31/10 12:19 ("Sim, eu autorizo… dá uma
varredura em tudo… e aí sim, publica"). A `bora-tranca` do PC **nega** editar e publicar estas pastas
(`refund/`, `finalize-order-from-intent/`, `dispatch-engine/`, `stripe-webhook/`, `client-cancel-order/`):
não se contornou. Tudo o resto da missão foi publicado e provado (ver `docs/SEGURANCA-CHAVES.md`, secção
de 31/10). Quem aplica isto é quem publica sem a tranca — a Claude.ai pelo MCP (`get_edge_function` →
mudar → `deploy_edge_function` com o `_shared` completo), como fez com a `finalize-order-from-intent` v15.

A regra é sempre a mesma, e o `_shared/chaves.ts` do repo já tem tudo (13 testes verdes):
`chamadaDoServidor(req)` (chave secreta nova em `apikey` ou `Bearer`, ou a service_role legada
**confirmada no Auth**), `chamadaDeAdmin(req)`, `utilizadorDoPedido(req)`, `respostaAoPing(req, cors)`.
Publicar com `_shared/chaves.ts` e `_shared/keys.ts` do repo (são um superconjunto dos que estão no ar).

## 1. `refund` (v26 no ar) — PRIORIDADE 1: os reembolsos do painel admin falham

**Defeito.** `jwtRole(bearer) !== 'service_role'` → 401 "admin only". O banco
(`client_cancel_appointment`, `client_cancel_reservation`, `partner_cancel_appointment`,
`admin_tvde_refund_ride`) manda a service_role legada e passa; o **`admin-payments` manda a chave
nova (`secretKey()`) e leva 401** → o reembolso pedido no painel dá `refund_failed`.

**Mudança (sobre a versão do AR, que tem o texto novo do aviso "No MB Way chega normalmente na hora"):**

```ts
// no topo
import { chamadaDoServidor, chamadaDeAdmin, respostaAoPing } from '../_shared/chaves.ts';
import { secretKey } from '../_shared/keys.ts';
// apagar a função jwtRole inteira

// no handler, em vez do bloco `const role = jwtRole(...)`:
  const autorizado = (await chamadaDoServidor(req)) || (await chamadaDeAdmin(req));
  if (!autorizado) {
    return new Response(JSON.stringify({ error: 'unauthorized: admin only' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  const pong = await respostaAoPing(req, corsHeaders);
  if (pong) return pong;

// e o cliente admin passa a: const serviceKey = secretKey() || (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
```

O aviso ao cliente (`notify-client` com `user_id`) **já passou a funcionar** sem mexer no `refund`: a
`notify-client` publicada a 31/10 aceita `user_id`/`order_id` além de `clientId`/`orderId` (antes
dava sempre 400 e o cliente nunca sabia do reembolso).

**Provas a fazer depois de publicar (sem dinheiro):** do banco, `{"ping":true}` com a legada, com a
`sb_secret` em Bearer e só em `apikey` → 200 `{"pong":true}`; de fora, JWT forjado → 401; sem nada → 401.

## 2. `finalize-order-from-intent` — v15 já está no ar (Claude.ai, 31/10 12:27); falta só o repo

O repo ainda tem a v14 (lê o `role` do JWT). O próximo deploy a partir do repo **repunha o defeito**.
Copiar o ar para o repo, tal e qual: `supabase functions download finalize-order-from-intent --use-api`
e substituir `supabase/functions/finalize-order-from-intent/index.ts`. As três diferenças são o
comentário v15, os dois imports (`chamadaDoServidor, chamadaDeAdmin` e `secretKey`), o cliente admin
com `secretKey()`, e `const autorizado = (await chamadaDoServidor(req)) || (await chamadaDeAdmin(req));`
no lugar do `jwtRole`.

## 3. `dispatch-engine` (v62 no ar) — A3

Hoje passa (aceita a variável de ambiente e a legada confirmada no Auth), mas recusa a chave nova só em
`apikey` e qualquer chave secreta com outro nome, e lê o papel do JWT à mão. Mudança — dentro de
`autorizar(...)`, trocar tudo até ao ramo do utilizador por:

```ts
  if (await chamadaDoServidor(req)) return { ok: true }
  const u = await utilizadorDoPedido(req)
  if (!u) return { ok: false, reason: 'sem_sessao_valida' }
  // … daqui para baixo fica o que já existe para admin/estafeta/cliente/parceiro, usando u.id / u.email
```

e apagar `lerPayload` e `servicoOk`. Mesmo desenho que o `notify-driver` v44, publicado e provado a 31/10
(do banco 3/3 = 200; forjado 403; sem nada 403).

## 4. `stripe-webhook` (v36 no ar) — A10 e bloco C

a) **As 4 chamadas a outras funções** (`notify-partner` ×2, `finalize-order-from-intent`,
`dispatch-engine`) passam a mandar também `apikey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` ao lado
do `Authorization: Bearer …` (padrão da Supabase; as funções de destino já aceitam os dois).

b) **Finalize recusado = pedido perdido.** Hoje só `>= 500` faz a Stripe repetir. O 401 de 31/10 11:41
(Dayane, 18,41 €) passou como "ok". Mudança:

```ts
if (res.status >= 500 || res.status === 401 || res.status === 403) {
  falha(`finalize-order-from-intent ${res.status}: ${resBody.slice(0, 300)}`); // 500 → a Stripe repete
}
```

(o finalize é idempotente pelo rascunho, repetir não cria dois pedidos; e o vigia
`_cron_vigia_pago_sem_pedido` cura e avisa em 3–8 min se ainda assim falhar.)

c) **Pagamento sem etiqueta** (os dois ramos `missing metadata.draft_id and order_id`, linhas ~696 e
~897): além do `console.error`, gravar o aviso no sininho do painel:

```ts
await supabase.from('admin_notifications').insert({
  event_type: 'pagamento_sem_etiqueta',
  severity: 'high',
  entity_type: 'payment_intent',
  entity_id: intent.id,
  summary: `Pagamento de ${(Number(intent.amount_received ?? intent.amount ?? 0) / 100).toFixed(2)} € sem pedido nem rascunho (${intent.description ?? 'sem descrição'})`,
  payload: { pi: intent.id, amount: intent.amount, amount_received: intent.amount_received,
             description: intent.description ?? null, customer: intent.customer ?? null,
             metadata: intent.metadata ?? {}, livemode: intent.livemode, evento: event.id },
  deep_link: '/admin/orphans',
});
```

(um erro no insert não pode partir o webhook: `try { … } catch (_) {}`.)

## 5. `client-cancel-order` (v30 no ar)

As duas chamadas a `notify-admin-urgent` são `admin.functions.invoke(...)` dentro de `try {} catch {}`:
o supabase-js já manda `apikey` + `Bearer`, por isso passam. Falta só não falharem em silêncio: trocar por
`chamarFuncao(admin, 'client-cancel-order', 'notify-admin-urgent', { … })` de `_shared/chamadas.ts`
(4 testes verdes), que escreve a falha em `e2e_log` (fluxo `edge-chamada-falhou`).

## 6. `stripe-webhook` — afinação do aviso "pagamento sem etiqueta" (02/11/2026)

Os 4 pagamentos sem etiqueta de 18/10 a 27/10 eram **todos `card_present`** (cobrados ao vivo com o
telemóvel, Tap to Pay da Stripe): 186,00 € e 291,53 € são as contas semanais do Jai e do Vansh; os dois de
5,00 € não têm pista nenhuma na Stripe. Nenhum é um pedido da app perdido. Com a v38, cada cobrança ao
vivo do Danilo põe um aviso **alto** no sininho. Sugestão, em `avisarPagamentoSemEtiqueta`:

```ts
const aoVivo = (intent.payment_method_types ?? []).includes('card_present');
// severity: aoVivo ? 'low' : (sucesso ? 'high' : 'medium')
// summary:  aoVivo ? `Cobrança ao vivo (Tap to Pay) de ${valor} € — sem pedido (normal)` : …
```

Só muda o aviso; o dinheiro e o resto do webhook ficam iguais.
