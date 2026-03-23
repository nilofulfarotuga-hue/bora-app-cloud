'use strict';

require('dotenv').config();

const express = require('express');
const cors    = require('cors');
const Stripe  = require('stripe');

// ─── Guard: fail fast if secret key is missing ───────────────────────────────

if (!process.env.STRIPE_SECRET_KEY) {
  console.error('FATAL: STRIPE_SECRET_KEY is not set. Copy .env.example to .env and fill it in.');
  process.exit(1);
}

// ─── Firebase Admin SDK (lazy-initialized, non-fatal if missing) ──────────────
//
// Requires ./firebase-service-account.json — download from Firebase console:
//   Project Settings → Service Accounts → Generate new private key

let _admin    = null;
let _fcmReady = false;

function getFCM() {
  if (_fcmReady) return _admin ? _admin.messaging() : null;

  _fcmReady = true;
  try {
    const serviceAccount = require('./firebase-service-account.json');
    _admin = require('firebase-admin');
    if (!_admin.apps.length) {
      _admin.initializeApp({ credential: _admin.credential.cert(serviceAccount) });
    }
    console.log('[FCM] Firebase Admin initialized');
  } catch (err) {
    console.warn('[FCM] Firebase Admin not available —', err.message);
    _admin = null;
  }
  return _admin ? _admin.messaging() : null;
}

// ─── Supabase client (service role — never exposed to the frontend) ───────────

const { createClient } = require('@supabase/supabase-js');
let _supabase = null;

function getSupabase() {
  if (_supabase) return _supabase;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.warn('[Supabase] SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set');
    return null;
  }
  _supabase = createClient(url, key);
  return _supabase;
}

const stripe = Stripe(process.env.STRIPE_SECRET_KEY);
const app    = express();

app.use(cors());
app.use(express.json());

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Convert euros (float) to Stripe cents (integer). */
function toCents(euros) {
  return Math.round(euros * 100);
}

/** Validate that a value is a positive finite number. */
function isPositiveNumber(v) {
  return typeof v === 'number' && Number.isFinite(v) && v > 0;
}

// ─── Health check ─────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => res.json({ ok: true }));

// ─── POST /create-payment-intent ──────────────────────────────────────────────
//
// Called by Flutter after the order is persisted in Supabase.
// The returned clientSecret is used by flutter_stripe to confirm payment.
// The paymentIntentId is stored on the order row.
//
// INPUT  { orderId: string, amount: number }   ← amount in euros (e.g. 28.00)
// OUTPUT { clientSecret: string, paymentIntentId: string }

app.post('/create-payment-intent', async (req, res) => {
  const { orderId, amount } = req.body;

  if (!orderId || typeof orderId !== 'string' || orderId.trim() === '') {
    return res.status(400).json({ error: 'orderId is required' });
  }
  if (!isPositiveNumber(amount)) {
    return res.status(400).json({ error: 'amount must be a positive number (euros)' });
  }

  try {
    const intent = await stripe.paymentIntents.create({
      amount:   toCents(amount),
      currency: 'eur',
      metadata: { orderId: orderId.trim() },
      automatic_payment_methods: { enabled: true },
    });

    res.json({
      clientSecret:    intent.client_secret,
      paymentIntentId: intent.id,
    });
  } catch (err) {
    console.error('[create-payment-intent]', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /refund ─────────────────────────────────────────────────────────────
//
// Called when finalTotal < paymentBufferTotal (driver bought less than estimated).
// Issues a partial refund of the surplus to the customer.
//
// INPUT  { paymentIntentId: string, amount: number }   ← amount in euros
// OUTPUT { refundId: string }

app.post('/refund', async (req, res) => {
  const { paymentIntentId, amount } = req.body;

  if (!paymentIntentId || typeof paymentIntentId !== 'string') {
    return res.status(400).json({ error: 'paymentIntentId is required' });
  }
  if (!isPositiveNumber(amount)) {
    return res.status(400).json({ error: 'amount must be a positive number (euros)' });
  }

  try {
    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId,
      amount:         toCents(amount),
    });

    res.json({ refundId: refund.id });
  } catch (err) {
    console.error('[refund]', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /charge-extra ───────────────────────────────────────────────────────
//
// Called when finalTotal > paymentBufferTotal (driver spent more than estimated).
// Creates a new PaymentIntent for the shortfall amount.
//
// INPUT  { amount: number, customerId?: string }   ← amount in euros
// OUTPUT { clientSecret: string, paymentIntentId: string }

app.post('/charge-extra', async (req, res) => {
  const { amount, customerId } = req.body;

  if (!isPositiveNumber(amount)) {
    return res.status(400).json({ error: 'amount must be a positive number (euros)' });
  }

  const intentParams = {
    amount:   toCents(amount),
    currency: 'eur',
    metadata: { type: 'extra_charge' },
    automatic_payment_methods: { enabled: true },
  };

  if (customerId && typeof customerId === 'string' && customerId.trim() !== '') {
    intentParams.customer = customerId.trim();
  }

  try {
    const intent = await stripe.paymentIntents.create(intentParams);

    res.json({
      clientSecret:    intent.client_secret,
      paymentIntentId: intent.id,
    });
  } catch (err) {
    console.error('[charge-extra]', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /notify-drivers ─────────────────────────────────────────────────────
//
// Broadcasts a push notification to every online driver that has an FCM token.
// Called by Flutter when an order transitions to status=callingDriver.
//
// INPUT  { orderId, title, body, sound }
// OUTPUT { success: true, sent: number, failed: number }

app.post('/notify-drivers', async (req, res) => {
  const { orderId, title, body, sound } = req.body;

  if (!orderId || typeof orderId !== 'string' || orderId.trim() === '') {
    return res.status(400).json({ error: 'orderId is required' });
  }
  if (!title || !body) {
    return res.status(400).json({ error: 'title and body are required' });
  }

  const fcm = getFCM();
  if (!fcm) {
    return res.status(503).json({ error: 'FCM not configured (firebase-service-account.json missing)' });
  }

  const supabase = getSupabase();
  if (!supabase) {
    return res.status(503).json({ error: 'Supabase not configured' });
  }

  try {
    const { data, error } = await supabase
      .from('drivers')
      .select('fcm_token')
      .eq('is_online', true)
      .not('fcm_token', 'is', null);

    if (error) throw error;

    const tokens = (data || [])
      .map(d => d.fcm_token)
      .filter(t => typeof t === 'string' && t.trim() !== '');

    if (tokens.length === 0) {
      console.log(`[notify-drivers] No online drivers with FCM tokens for order ${orderId}`);
      return res.json({ success: true, sent: 0, failed: 0 });
    }

    const soundName = typeof sound === 'string' && sound.trim() !== '' ? sound.trim() : 'bora_alert';

    // sendEachForMulticast is available in firebase-admin >= 11 and handles
    // partial failures per-token (unlike the deprecated sendMulticast).
    const batchResponse = await fcm.sendEachForMulticast({
      tokens,
      notification: { title, body },
      android: {
        notification: { sound: soundName },
      },
      apns: {
        payload: { aps: { sound: `${soundName}.wav` } },
      },
    });

    console.log(
      `[notify-drivers] order=${orderId} sent=${batchResponse.successCount} failed=${batchResponse.failureCount}`
    );

    return res.json({
      success: true,
      sent:    batchResponse.successCount,
      failed:  batchResponse.failureCount,
    });
  } catch (err) {
    console.error('[notify-drivers]', err.message);
    return res.status(500).json({ error: err.message });
  }
});

// ─── POST /notify-client ──────────────────────────────────────────────────────
//
// Sends a push notification to a specific client identified by phone number.
// Called by Flutter at driverAccepted, pickedUp, and delivered transitions.
//
// INPUT  { clientPhone, title, body, sound }
// OUTPUT { success: true, sent: 0|1 }

app.post('/notify-client', async (req, res) => {
  const { clientPhone, title, body, sound } = req.body;

  if (!clientPhone || typeof clientPhone !== 'string' || clientPhone.trim() === '') {
    return res.status(400).json({ error: 'clientPhone is required' });
  }
  if (!title || !body) {
    return res.status(400).json({ error: 'title and body are required' });
  }

  const fcm = getFCM();
  if (!fcm) {
    return res.status(503).json({ error: 'FCM not configured (firebase-service-account.json missing)' });
  }

  const supabase = getSupabase();
  if (!supabase) {
    return res.status(503).json({ error: 'Supabase not configured' });
  }

  try {
    // maybeSingle() returns null (not an error) when no row is found.
    const { data, error } = await supabase
      .from('clients')
      .select('fcm_token')
      .eq('phone', clientPhone.trim())
      .not('fcm_token', 'is', null)
      .maybeSingle();

    if (error) throw error;

    const token = data?.fcm_token;
    if (!token || typeof token !== 'string' || token.trim() === '') {
      console.log(`[notify-client] No FCM token for phone ${clientPhone}`);
      return res.json({ success: true, sent: 0 });
    }

    const soundName = typeof sound === 'string' && sound.trim() !== '' ? sound.trim() : 'bora_alert';

    await fcm.send({
      token,
      notification: { title, body },
      android: {
        notification: { sound: soundName },
      },
      apns: {
        payload: { aps: { sound: `${soundName}.wav` } },
      },
    });

    console.log(`[notify-client] phone=${clientPhone} title="${title}"`);
    return res.json({ success: true, sent: 1 });
  } catch (err) {
    console.error('[notify-client]', err.message);
    return res.status(500).json({ error: err.message });
  }
});

// ─── Start ────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
app.listen(PORT, () =>
  console.log(`BORA payment server running on http://localhost:${PORT}`)
);
