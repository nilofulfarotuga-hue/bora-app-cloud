// Prova real do client-assistant e do support-chatbot (missão embeddings-supabase-2026-11-03).
// Sessão da conta de teste e2e_client_a@boraapp.test por link mágico (sem senha, sem email enviado).
// NUNCA imprime chaves nem o token. Uso:
//   node prova_assistente.mjs assistente <platform> "<mensagem>"
//   node prova_assistente.mjs suporte "<mensagem>"
import fs from 'node:fs';

const RAIZ = 'C:/BoraLocal/projetosflutter/bora_app';
const env = Object.fromEntries(
  fs.readFileSync(`${RAIZ}/backend/.env`, 'utf8').split(/\r?\n/).filter((l) => l.includes('='))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim().replace(/^"|"$/g, '')]),
);
const dd = JSON.parse(fs.readFileSync(`${RAIZ}/.dart_defines`, 'utf8').replace(/^﻿/, ''));
const URL = 'https://ojykpzwqrtusfeakzrna.supabase.co';
const SRV = env.SUPABASE_SERVICE_ROLE_KEY;
const PUB = dd.SUPABASE_ANON_KEY;
const EMAIL = 'e2e_client_a@boraapp.test';

async function sessao() {
  const g = await fetch(`${URL}/auth/v1/admin/generate_link`, {
    method: 'POST',
    headers: { apikey: SRV, Authorization: `Bearer ${SRV}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', email: EMAIL }),
  });
  const gj = await g.json();
  const th = gj?.properties?.hashed_token ?? gj?.hashed_token;
  if (!th) throw new Error(`generate_link ${g.status}`);
  const v = await fetch(`${URL}/auth/v1/verify`, {
    method: 'POST', headers: { apikey: PUB, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: th }),
  });
  const vj = await v.json();
  if (!vj.access_token) throw new Error(`verify ${v.status}`);
  return vj.access_token;
}

const [modo, a1, a2] = process.argv.slice(2);
const token = await sessao();
const t0 = Date.now();
if (modo === 'assistente') {
  const r = await fetch(`${URL}/functions/v1/client-assistant`, {
    method: 'POST',
    headers: { apikey: PUB, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    // como a app: morada de entrega (centro da Guarda) para o cesto poder ter entrega calculada
    body: JSON.stringify({ message: a2, platform: a1, dropoff_lat: 40.5373, dropoff_lng: -7.2676, apartment_delivery: false }),
  });
  const txt = await r.text();
  let j = {};
  try { j = JSON.parse(txt); } catch { /* corpo não-JSON */ }
  console.log(JSON.stringify({
    http: r.status, ms: Date.now() - t0, ok: j.ok, plataforma: a1, motor_vetores: j.motor_vetores,
    erro: j.error ?? null, erro_tecnico: j.erro_tecnico ?? null, propostas: (j.propostas ?? []).length,
    acoes: (j.acoes ?? []).map((x) => x.tipo), motor_texto: j.motor ?? j.usage?.model ?? null,
    texto: String(j.texto ?? txt).replace(/\s+/g, ' ').slice(0, 260),
    conversa: j.conversation_id ? String(j.conversation_id).slice(0, 8) : null,
  }));
} else if (modo === 'suporte') {
  const r = await fetch(`${URL}/functions/v1/support-chatbot`, {
    method: 'POST',
    headers: { apikey: PUB, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: a1 }),
  });
  const txt = await r.text();
  let j = {};
  try { j = JSON.parse(txt); } catch { /* corpo não-JSON */ }
  console.log(JSON.stringify({
    http: r.status, ms: Date.now() - t0, escalated: j.escalated ?? null,
    reply: String(j.reply ?? txt).replace(/\s+/g, ' ').slice(0, 260),
  }));
} else {
  console.log('modo desconhecido');
}
