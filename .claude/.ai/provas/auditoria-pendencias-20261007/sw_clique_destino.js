// Prova (07/10/2026): corre o web/firebase-messaging-sw.js REAL num browser
// falso e verifica para onde o toque na notificação abre, pelo tipo do aviso.
// Antes: tudo para /#/driver. Uso: node sw_clique_destino.js <caminho do sw>
const fs = require('fs');
const codigo = fs.readFileSync(process.argv[2], 'utf8');

const origem = 'https://app.boraguarda.com';
const listeners = {};
let mostradas = [];
let abertas = [];

global.self = {
  location: { origin: origem },
  addEventListener: (nome, fn) => { listeners[nome] = fn; },
  registration: { showNotification: (t, o) => { mostradas.push({ t, o }); return Promise.resolve(); } },
  boraFirebaseConfig: { apiKey: 'AIza-falsa' },
};
let onBg = null;
global.firebase = {
  initializeApp: () => {},
  messaging: () => ({ onBackgroundMessage: (fn) => { onBg = fn; } }),
};
global.importScripts = () => {};
global.clients = {
  matchAll: () => Promise.resolve([]),
  openWindow: (url) => { abertas.push(url); return Promise.resolve(); },
};

new Function(codigo)();

const casos = [
  // [payload, destino esperado]
  [{ type: 'new_order_offer', orderId: 'A1' }, origem + '/#/driver?order=A1'],
  [{ type: 'order_reassigned', orderId: 'A2' }, origem + '/#/driver?order=A2'],
  [{ type: 'driver_offline' }, origem + '/#/driver'],
  [{ type: 'new_order', orderId: 'P1' }, origem + '/#/partner?order=P1'],
  [{ type: 'appointment_new' }, origem + '/#/partner'],
  [{ type: 'order_status', orderId: 'C1' }, origem + '/#/client?order=C1'],
  [{ type: 'purchase_finalized', order_id: 'C2' }, origem + '/#/client?order=C2'],
  [{ type: 'reservation_status' }, origem + '/#/client'],
  [{ type: 'chat', order_id: 'X', audience: 'partner' }, origem + '/#/partner?order=X'],
  [{ type: 'desconhecido_qualquer' }, origem + '/#/'],
  [{ type: 'order_status', url: '/#/loja/abc' }, origem + '/#/loja/abc'],
  [{ url: 'https://outro.exemplo/x' }, 'https://outro.exemplo/x'],
  [{}, origem + '/#/'],
];

let falhas = 0;
for (const [d, esperado] of casos) {
  const obtido = self.boraDestinoDoAviso(d, origem);
  const ok = obtido === esperado;
  if (!ok) falhas++;
  console.log((ok ? 'OK  ' : 'ERRO') + ' ' + JSON.stringify(d) + ' -> ' + obtido + (ok ? '' : '  (esperado ' + esperado + ')'));
}

(async () => {
  // Caminho inteiro: push em segundo plano -> notificação -> clique -> janela.
  await onBg({ data: { type: 'order_status', orderId: 'C9', title: 'Pedido', body: 'A caminho' } });
  const n = mostradas[0];
  const evento = { notification: { data: n.o.data, close: () => {} }, waitUntil: (p) => p };
  await listeners.notificationclick(evento);
  const esperado = origem + '/#/client?order=C9';
  const ok = abertas[0] === esperado;
  if (!ok) falhas++;
  console.log((ok ? 'OK  ' : 'ERRO') + ' clique do cliente abre ' + abertas[0]);

  // Notificação sem url (montada por outro caminho): decide-se no clique.
  abertas = [];
  await listeners.notificationclick({ notification: { data: { type: 'new_order', orderId: 'P7' }, close: () => {} }, waitUntil: (p) => p });
  const ok2 = abertas[0] === origem + '/#/partner?order=P7';
  if (!ok2) falhas++;
  console.log((ok2 ? 'OK  ' : 'ERRO') + ' clique sem url abre ' + abertas[0]);

  console.log('falhas=' + falhas);
  process.exit(falhas ? 1 : 0);
})();
