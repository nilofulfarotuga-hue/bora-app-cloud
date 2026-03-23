/**
 * BORA App — Payment Backend (Node.js / Express + Stripe)
 *
 * Run:
 *   npm install express stripe dotenv
 *   node payment_server.js
 *
 * Required env vars (.env):
 *   STRIPE_SECRET_KEY=sk_live_...
 *   PORT=3000  (optional, defaults to 3000)
 *
 * Flutter app must be built with:
 *   --dart-define=BACKEND_BASE_URL=https://your-backend.com
 *
 * The Stripe SECRET KEY never leaves this server.
 * The Flutter app only receives clientSecret / paymentIntentId.
 */

'use strict';

require('dotenv').config();

const express = require('express');
const Stripe  = require('stripe');

const stripe = Stripe(process.env.STRIPE_SECRET_KEY);
const app    = express();

app.use(express.json());

// ─── Health check ────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => res.json({ ok: true }));

// ─── Create PaymentIntent (called right after order creation) ────────────────
//
// Flutter calls this once the order is persisted in Supabase.
// The returned clientSecret is used by flutter_stripe to confirm payment.
// The paymentIntentId is stored in the order row.
//
// INPUT  { orderId: string, amount: number }   ← amount in euros (e.g. 21.85)
// OUTPUT { clientSecret: string, paymentIntentId: string }

app.post('/create-payment-intent', async (req, res) => {
  const { orderId, amount } = req.body;

  if (!orderId || typeof amount !== 'number' || amount <= 0) {
    return res.status(400).json({ error: 'orderId and positive amount required' });
  }

  try {
    const intent = await stripe.paymentIntents.create({
      amount:   Math.round(amount * 100), // Stripe expects cents
      currency: 'eur',
      metadata: { orderId },
      automatic_payment_methods: { enabled: true },
    });

    res.json({
      clientSecret:    intent.client_secret,
      paymentIntentId: intent.id,
    });
  } catch (err) {
    console.error('create-payment-intent error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Refund surplus buffer to client ─────────────────────────────────────────
//
// Called by OrderStore.processRefund() when finalTotal < paymentBufferTotal.
//
// INPUT  { paymentIntentId: string, amount: number }   ← amount in euros
// OUTPUT { refundId: string }

app.post('/refund', async (req, res) => {
  const { paymentIntentId, amount } = req.body;

  if (!paymentIntentId || typeof amount !== 'number' || amount <= 0) {
    return res.status(400).json({ error: 'paymentIntentId and positive amount required' });
  }

  try {
    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId,
      amount:         Math.round(amount * 100),
    });

    res.json({ refundId: refund.id });
  } catch (err) {
    console.error('refund error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Capture extra charge when real purchase exceeded buffer ─────────────────
//
// Called by OrderStore.processExtraCharge() when finalTotal > paymentBufferTotal.
// Creates a new PaymentIntent for the shortfall amount (the original intent is
// already captured for the buffer amount).
//
// INPUT  { paymentIntentId: string, amount: number }   ← amount in euros
// OUTPUT { newPaymentIntentId: string, clientSecret: string }

app.post('/capture-extra', async (req, res) => {
  const { paymentIntentId, amount } = req.body;

  if (!paymentIntentId || typeof amount !== 'number' || amount <= 0) {
    return res.status(400).json({ error: 'paymentIntentId and positive amount required' });
  }

  try {
    // Retrieve original intent to copy customer / payment method
    const original = await stripe.paymentIntents.retrieve(paymentIntentId);

    const extra = await stripe.paymentIntents.create({
      amount:         Math.round(amount * 100),
      currency:       'eur',
      customer:       original.customer  || undefined,
      payment_method: original.payment_method || undefined,
      confirm:        !!original.payment_method, // auto-confirm if method known
      metadata: {
        originalPaymentIntentId: paymentIntentId,
        type: 'extra_charge',
      },
      automatic_payment_methods: original.payment_method
        ? undefined
        : { enabled: true },
    });

    res.json({
      newPaymentIntentId: extra.id,
      clientSecret:       extra.client_secret,
    });
  } catch (err) {
    console.error('capture-extra error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Start ───────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`BORA payment server running on port ${PORT}`));
