#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PROPOSTA 🔴 ZONA VERMELHA — ramo TVDE no `supabase/functions/stripe-webhook/index.ts`.

Porque e um script e nao uma edicao directa:
    `.claude/settings.json` NEGA Edit/Write/MultiEdit em
    `./supabase/functions/stripe-webhook/**` (a Trava protege-dinheiro).
    Isso e propositado: o webhook da Stripe e zona 🔴 = PROPOSE-ONLY.
    Este ficheiro E a proposta — legivel, revisivel, e aplicavel de uma vez
    so DEPOIS de o Danilo dizer "vai".

Como aplicar (so apos "vai"):
    python .claude/.ai/propostas/tvde-pagamento-2026-08-13/aplicar_stripe_webhook.py --aplicar

Como so ver o que muda (default, nao escreve nada):
    python .claude/.ai/propostas/tvde-pagamento-2026-08-13/aplicar_stripe_webhook.py

Garantias:
    - Idempotente: se ja estiver aplicado, sai com aviso e NAO duplica.
    - Verifica TODAS as ancoras antes de escrever qualquer byte. Falta uma -> aborta.
    - Guarda backup .bak ao lado do original.
    - Nao toca em NENHUM ramo de entregas, reservas ou wallet.
"""

import argparse
import io
import os
import shutil
import sys

ALVO = os.path.join('supabase', 'functions', 'stripe-webhook', 'index.ts')

# ─────────────────────────────────────────────────────────────────────────────
# BLOCO 1 — helpers TVDE, inseridos entre o `createClient` e o `Deno.serve`.
# ─────────────────────────────────────────────────────────────────────────────

ANCORA_1 = """const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

Deno.serve(async (req: Request) => {"""

NOVO_1 = """const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

// ─────────────────────────────────────────────────────────────────────────────
// TVDE (2026-08-13) — corridas TVDE no webhook.
//
// Os PaymentIntents criados por `tvde-payment` / `tvde-plan-payment` levam
// metadata.kind = 'tvde_ride' | 'tvde_roundtrip' | 'tvde_stop'. Antes desta
// versao caiam TODOS no `else` do payment_intent.succeeded e so escreviam
// "missing metadata.draft_id and order_id" no log — o servidor NUNCA marcava a
// corrida como paga, logo o trigger `tr_tvde_dispatch_on_paid` ->
// `tvde_offer_to_next` -> `tr_notify_tvde_driver_on_offer` -> Edge Fn
// `notify-tvde-driver` nunca disparava e nenhum motorista era chamado.
// So o poll do cliente (`confirm_ride_payment`, 3s/120s) marcava pago — e o
// MB Way demora mais do que isso, por isso na pratica ficava por marcar.
//
// PROVA (logs de producao, 2026-08-13 19:01:45 UTC):
//   [stripe-webhook] payment_intent.succeeded missing metadata.draft_id and
//   order_id: pi_3U43sVGlT3R2jCYp0fulK3tK
// -> corrida 09c01c88-cc50-419d-951e-15c7abc033, tried_driver_ids = {}.
// ─────────────────────────────────────────────────────────────────────────────

const TVDE_TERMINAL_STATUSES = ['cancelada_cliente', 'cancelada_motorista', 'no_show'];

/** Le a corrida ligada a um PI TVDE. Devolve null (e loga) se nao existir. */
async function tvdeFetchRide(rideId: string) {
  const { data, error } = await supabase
    .from('tvde_rides')
    .select('id, status, payment_status, est_fare_cents, final_fare_cents, cancel_fee_cents')
    .eq('id', rideId)
    .maybeSingle();
  if (error) {
    console.error('[stripe-webhook] tvde ride fetch failed:', error.message, rideId);
    return null;
  }
  if (!data) console.error('[stripe-webhook] tvde ride not found:', rideId);
  return data;
}

/**
 * `payment_intent.succeeded` de um PI TVDE.
 *
 * Caminho feliz: marca `payment_status='succeeded'` e DEIXA O TRIGGER despachar.
 * Nunca chamar `tvde_offer_to_next` a mao aqui — duplicaria a oferta.
 *
 * Dinheiro que entra DEPOIS da corrida morrer: refund automatico com o mesmo
 * calculo da accao `refund` do tvde-payment — refund = max(0, min(pago-taxa, pago)).
 * "pago" vem da Stripe (`amount_received`), a unica verdade do que foi mesmo
 * cobrado; `est_fare_cents` e so a estimativa gravada na corrida.
 */
async function tvdeHandleSucceeded(intent: Stripe.PaymentIntent, kind: string) {
  const rideId = intent.metadata?.ride_id ?? '';

  // `tvde_stop` ja e fechado por `confirm_stop_payment` (que ADICIONA a parada
  // via tvde_add_stop e faz refund se a adicao falhar). Duplicar aqui criaria
  // parada a dobrar — so log, como pedido.
  if (kind === 'tvde_stop') {
    console.log('[stripe-webhook] tvde stop paid (no-op — fechado por confirm_stop_payment):',
      intent.id, 'ride:', rideId || '(sem ride_id)');
    return;
  }

  // `tvde_roundtrip` (pacote ida-e-volta) NAO leva ride_id na metadata: paga um
  // VALE, e a ligacao a corrida de ida so acontece em `activate_roundtrip`
  // (tvde-plan-payment), chamado pelo cliente. Sem ride_id nao ha nada a marcar
  // aqui — fica o log explicito para nao parecer silencio.
  if (!rideId) {
    console.warn('[stripe-webhook] tvde PI succeeded sem metadata.ride_id — nada a marcar:',
      intent.id, 'kind:', kind);
    return;
  }

  const ride = await tvdeFetchRide(rideId);
  if (!ride) return;

  if (TVDE_TERMINAL_STATUSES.includes(String(ride.status))) {
    const paidCents = Number(intent.amount_received ?? 0);
    const feeCents = Math.max(0, Number(ride.cancel_fee_cents ?? 0));
    const refundCents = Math.max(0, Math.min(paidCents - feeCents, paidCents));
    if (refundCents >= 1) {
      try {
        await stripe.refunds.create(
          { payment_intent: intent.id, amount: refundCents },
          { idempotencyKey: `tvde-late-refund-${intent.id}-${refundCents}` },
        );
      } catch (e) {
        console.error('[stripe-webhook] tvde late refund failed:', e, intent.id);
        return; // nao mentir no payment_status se o refund nao passou
      }
    }
    // `refunded` SO quando dinheiro voltou mesmo. Zero devolvido = kept_cancel_fee.
    const newStatus = refundCents <= 0
      ? 'kept_cancel_fee'
      : (feeCents > 0 ? 'partial_refund' : 'refunded');
    await supabase.from('tvde_rides')
      .update({ payment_status: newStatus }).eq('id', rideId);
    console.warn('[stripe-webhook] tvde late payment on terminal ride:', rideId,
      'status:', ride.status, 'paid:', paidCents, 'fee:', feeCents,
      'refunded:', refundCents, '->', newStatus);
    return;
  }

  if (ride.payment_status === 'succeeded') {
    console.log('[stripe-webhook] tvde ride ja estava paga (idempotente):', rideId, intent.id);
    return;
  }

  const { error } = await supabase
    .from('tvde_rides')
    .update({ payment_status: 'succeeded' })
    .eq('id', rideId);
  if (error) {
    console.error('[stripe-webhook] tvde ride paid UPDATE failed:', error.message, rideId);
    return;
  }
  console.log('[stripe-webhook] tvde ride paid:', rideId, 'kind:', kind, 'intent:', intent.id);
}

/** `payment_intent.processing` — MB Way empurrado, a aguardar o cliente. */
async function tvdeHandleProcessing(intent: Stripe.PaymentIntent, kind: string) {
  const rideId = intent.metadata?.ride_id ?? '';
  if (kind === 'tvde_stop' || !rideId) return;
  const { error } = await supabase
    .from('tvde_rides')
    .update({ payment_status: 'processing' })
    .eq('id', rideId)
    .neq('payment_status', 'succeeded');
  if (error) {
    console.error('[stripe-webhook] tvde ride processing UPDATE failed:', error.message, rideId);
    return;
  }
  console.log('[stripe-webhook] tvde ride processing:', rideId, 'intent:', intent.id);
}

/** `payment_intent.payment_failed` / `.canceled` — cancela a corrida. */
async function tvdeHandleFailed(intent: Stripe.PaymentIntent, kind: string, eventType: string) {
  const rideId = intent.metadata?.ride_id ?? '';
  if (kind === 'tvde_stop' || !rideId) {
    console.warn('[stripe-webhook] tvde PI', eventType, 'sem ride_id (ou stop) — ignorado:',
      intent.id, 'kind:', kind);
    return;
  }
  const failureMsg = intent.last_payment_error?.message ?? eventType;
  // `tvde_cancel_ride` e SECURITY DEFINER e aceita admin/dono. Aqui corre com
  // service_role (auth.uid() IS NULL -> is_admin() decide), actor 'cliente'.
  const { error } = await supabase.rpc('tvde_cancel_ride', {
    p_ride_id: rideId,
    p_actor: 'cliente',
    p_reason: 'payment_failed',
  });
  if (error) {
    // `ride_already_terminal` e esperado (o cliente ja tinha cancelado) — nao e erro.
    const msg = error.message ?? '';
    if (msg.includes('ride_already_terminal')) {
      console.log('[stripe-webhook] tvde ride ja terminal em', eventType, ':', rideId);
    } else {
      console.error('[stripe-webhook] tvde cancel on', eventType, 'failed:', msg, rideId);
    }
    return;
  }
  console.warn('[stripe-webhook] tvde ride canceled by', eventType, ':', rideId, failureMsg);
}

Deno.serve(async (req: Request) => {"""

# ─────────────────────────────────────────────────────────────────────────────
# BLOCO 2 — despacho TVDE em `payment_intent.succeeded`, ANTES de draft/order.
# ─────────────────────────────────────────────────────────────────────────────

ANCORA_2 = """      // ⭐ NOVO v23 (2026-05-12 BUG #1 frontend) — debt settle via metadata
      const debtSettleCents = parseInt(intent.metadata?.debt_settle_cents ?? '0');"""

NOVO_2 = """      // ⭐ TVDE (2026-08-13) — corridas TVDE. Tem de vir ANTES dos ramos
      // draft_id / order_id (entregas): um PI TVDE nao tem nenhum dos dois e
      // caia no `else` a escrever "missing metadata" sem marcar nada.
      const tvdeKind = String(intent.metadata?.kind ?? '');
      if (tvdeKind.startsWith('tvde_')) {
        await tvdeHandleSucceeded(intent, tvdeKind);
        break;
      }

      // ⭐ NOVO v23 (2026-05-12 BUG #1 frontend) — debt settle via metadata
      const debtSettleCents = parseInt(intent.metadata?.debt_settle_cents ?? '0');"""

# ─────────────────────────────────────────────────────────────────────────────
# BLOCO 3 — `payment_intent.processing`.
# ─────────────────────────────────────────────────────────────────────────────

ANCORA_3 = """    case 'payment_intent.processing': {
      const intent = event.data.object as Stripe.PaymentIntent;
      console.log('[stripe-webhook] payment processing (MBWay awaiting confirm):', intent.id);
      break;
    }"""

NOVO_3 = """    case 'payment_intent.processing': {
      const intent = event.data.object as Stripe.PaymentIntent;
      console.log('[stripe-webhook] payment processing (MBWay awaiting confirm):', intent.id);
      const tvdeKind = String(intent.metadata?.kind ?? '');
      if (tvdeKind.startsWith('tvde_')) {
        await tvdeHandleProcessing(intent, tvdeKind);
      }
      break;
    }"""

# ─────────────────────────────────────────────────────────────────────────────
# BLOCO 4 — `payment_intent.payment_failed` / `.canceled`.
# ─────────────────────────────────────────────────────────────────────────────

ANCORA_4 = """    case 'payment_intent.payment_failed':
    case 'payment_intent.canceled': {
      const intent = event.data.object as Stripe.PaymentIntent;
"""

NOVO_4 = """    case 'payment_intent.payment_failed':
    case 'payment_intent.canceled': {
      const intent = event.data.object as Stripe.PaymentIntent;

      // ⭐ TVDE (2026-08-13) — antes dos ramos de reserva/draft/order.
      const tvdeKindFail = String(intent.metadata?.kind ?? '');
      if (tvdeKindFail.startsWith('tvde_')) {
        await tvdeHandleFailed(intent, tvdeKindFail, event.type);
        break;
      }
"""

BLOCOS = [
    ('helpers TVDE (tvdeFetchRide / Succeeded / Processing / Failed)', ANCORA_1, NOVO_1),
    ('despacho TVDE em payment_intent.succeeded', ANCORA_2, NOVO_2),
    ('ramo TVDE em payment_intent.processing', ANCORA_3, NOVO_3),
    ('ramo TVDE em payment_failed / canceled', ANCORA_4, NOVO_4),
]

MARCA_JA_APLICADO = 'tvdeHandleSucceeded'


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--aplicar', action='store_true',
                    help='escreve mesmo o ficheiro (default: so mostra)')
    ap.add_argument('--alvo', default=ALVO)
    args = ap.parse_args()

    if not os.path.isfile(args.alvo):
        print(f'[X] nao encontrei {args.alvo} — corre a partir da raiz de bora_app/')
        return 2

    with io.open(args.alvo, encoding='utf-8') as fh:
        src = fh.read()

    if MARCA_JA_APLICADO in src:
        print('[!] JA APLICADO — o ficheiro ja tem o ramo TVDE. Nada a fazer.')
        return 0

    # Verificar TODAS as ancoras antes de mexer num unico byte.
    faltam = [nome for nome, ancora, _ in BLOCOS if src.count(ancora) != 1]
    if faltam:
        print('[X] ABORTADO — ancoras em falta ou ambiguas:')
        for nome in faltam:
            print(f'    - {nome}')
        print('    O ficheiro mudou desde a proposta. Rever a mao.')
        return 2

    novo = src
    for _, ancora, subst in BLOCOS:
        novo = novo.replace(ancora, subst, 1)

    print(f'[OK] 4/4 ancoras encontradas em {args.alvo}')
    print(f'     {len(src.splitlines())} linhas -> {len(novo.splitlines())} linhas '
          f'(+{len(novo.splitlines()) - len(src.splitlines())})')

    if not args.aplicar:
        print('\n[i] MODO PROPOSTA (nada escrito). Para aplicar: --aplicar')
        return 0

    shutil.copy2(args.alvo, args.alvo + '.bak')
    with io.open(args.alvo, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(novo)
    print(f'[OK] escrito. Backup em {args.alvo}.bak')
    print('[!] FALTA O DEPLOY — este script so muda o ficheiro local.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
