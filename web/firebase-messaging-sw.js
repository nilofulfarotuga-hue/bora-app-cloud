// web/firebase-messaging-sw.js — service worker de push da PWA (estafeta,
// cliente e parceiro — os três registam token na web desde 07/10/2026).
//
// [Estafeta web 2026-09-16] O plugin firebase_messaging (web) regista este
// ficheiro sozinho na raiz do site quando a app pede o token. As Edge Functions
// da Bora mandam mensagens DATA-ONLY (sem bloco `notification`), por isso é
// AQUI que a notificação visível nasce quando a página está fechada ou em
// segundo plano — no iPhone (16.4+, só com a Bora no ecrã principal) o Safari
// exige mesmo que cada push mostre uma notificação, senão retira a permissão.
//
// A config vem de firebase-config.js (única fonte, partilhada com a app).
// [Paridade 2026-09-21] 12.19.0 = a versão do JS SDK que o firebase_core_web
// 3.12.0 (par do firebase_core 4.15 / firebase_messaging 16.7) carrega na
// app. O service worker e a app têm de correr o MESMO SDK.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
importScripts('firebase-config.js');

var cfg = self.boraFirebaseConfig || {};
var configurado = cfg.apiKey && cfg.apiKey.charAt(0) !== '<';

// [Web 07/10/2026] Para onde abre o toque na notificação, pelo TIPO do aviso.
// Antes mandava tudo para /#/driver — o cliente e o parceiro (que passaram a
// registar token na web neste dia) aterravam no ecrã do estafeta.
//   estafeta → /#/driver?order=…      parceiro → /#/partner?order=…
//   cliente  → /#/client?order=…      sem tipo conhecido → /#/
// Um `url` explícito no payload manda sempre; `audience`/`role` (driver |
// partner | client) manda a seguir; só depois é que o tipo decide.
var TIPOS_ESTAFETA = {
  new_order_offer: 1, order_reassigned: 1, order_preassigned: 1,
  order_unassigned: 1, driver_offline: 1, new_tvde_ride_offer: 1,
  tvde_ride_offer: 1, tvde_reservation: 1, tvde_stop: 1
};
var TIPOS_PARCEIRO = {
  new_order: 1, order_cancelled_partner: 1, appointment_new: 1,
  appointment_cancelled: 1, appointment: 1, reservation_new: 1,
  reservation_cancelled: 1, reservation: 1, service: 1
};
var TIPOS_CLIENTE = {
  order_status: 1, appointment_status: 1, reservation_status: 1,
  purchase_finalized: 1, order_delivered: 1, order_ready: 1,
  cleaning_status: 1, custom: 1
};
function boraDestinoDoAviso(d, origem) {
  d = d || {};
  if (d.url) {
    return (d.url.charAt(0) === '/' ? origem : '') + d.url;
  }
  var id = d.orderId || d.order_id || '';
  var q = id ? '?order=' + encodeURIComponent(id) : '';
  var papel = (d.audience || d.role || d.to_role || '').toString().toLowerCase();
  var t = (d.type || '').toString();
  if (!papel) {
    if (TIPOS_ESTAFETA[t]) papel = 'driver';
    else if (TIPOS_PARCEIRO[t]) papel = 'partner';
    else if (TIPOS_CLIENTE[t]) papel = 'client';
  }
  if (papel === 'driver') return origem + '/#/driver' + q;
  if (papel === 'partner') return origem + '/#/partner' + q;
  if (papel === 'client') return origem + '/#/client' + q;
  return origem + '/#/' + q;
}
self.boraDestinoDoAviso = boraDestinoDoAviso;

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
    var url = boraDestinoDoAviso(d, self.location.origin);
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
  var dados = (event.notification && event.notification.data) || {};
  // `data.url` já vem resolvido pelo tipo (ver boraDestinoDoAviso); se faltar
  // (aviso montado por outro caminho), decide-se agora pelos mesmos dados.
  var url = dados.url || boraDestinoDoAviso(dados, self.location.origin);
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
