// web/firebase-messaging-sw.js — service worker de push da PWA (estafeta).
//
// [Estafeta web 2026-09-16] O plugin firebase_messaging (web) regista este
// ficheiro sozinho na raiz do site quando a app pede o token. As Edge Functions
// da Bora mandam mensagens DATA-ONLY (sem bloco `notification`), por isso é
// AQUI que a notificação visível nasce quando a página está fechada ou em
// segundo plano — no iPhone (16.4+, só com a Bora no ecrã principal) o Safari
// exige mesmo que cada push mostre uma notificação, senão retira a permissão.
//
// A config vem de firebase-config.js (única fonte, partilhada com a app).
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');
importScripts('firebase-config.js');

var cfg = self.boraFirebaseConfig || {};
var configurado = cfg.apiKey && cfg.apiKey.charAt(0) !== '<';

if (configurado) {
  firebase.initializeApp({
    apiKey: cfg.apiKey,
    authDomain: cfg.authDomain,
    projectId: cfg.projectId,
    storageBucket: cfg.storageBucket,
    messagingSenderId: cfg.messagingSenderId,
    appId: cfg.appId
  });

  var messaging = firebase.messaging();

  // Textos por tipo quando a Edge não manda título/corpo (rede de segurança).
  function textos(d) {
    var t = d.type || '';
    if (t === 'new_order_offer') {
      return {
        title: '🛵 Novo pedido — ' + (d.vendorName || 'Bora'),
        body: 'Tens uma oferta para aceitar. Toca para abrir.'
      };
    }
    if (t === 'driver_offline') {
      return { title: 'Ficaste desligado', body: 'Abre a Bora para voltares a receber pedidos.' };
    }
    return { title: d.title || 'Bora', body: d.body || '' };
  }

  messaging.onBackgroundMessage(function (payload) {
    var d = (payload && payload.data) || {};
    var tx = textos(d);
    var title = d.title || tx.title;
    var body = d.body || tx.body;
    var url = d.url || (d.orderId
      ? (self.location.origin + '/#/driver?order=' + d.orderId)
      : (self.location.origin + '/#/driver'));
    var urgente = d.type === 'new_order_offer' || d.type === 'order_reassigned' || d.type === 'order_preassigned';
    return self.registration.showNotification(title, {
      body: body,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: (d.type || 'bora') + ':' + (d.orderId || ''),
      renotify: true,
      requireInteraction: urgente,
      vibrate: urgente ? [300, 100, 300, 100, 300] : [100],
      data: { url: url, type: d.type || '', orderId: d.orderId || '' }
    });
  });
}

// Tocar na notificação: foca a Bora se já estiver aberta, senão abre-a.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || (self.location.origin + '/#/driver');
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (lista) {
      for (var i = 0; i < lista.length; i++) {
        var c = lista[i];
        if (c.url && c.url.indexOf(self.location.origin) === 0 && 'focus' in c) {
          try { c.navigate(url); } catch (e) {}
          return c.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
