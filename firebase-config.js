// web/firebase-config.js — config Firebase da WEB (PWA do estafeta).
//
// ÚNICA FONTE para a app Flutter (lida em runtime via window.boraFirebaseConfig,
// ver lib/services/web_presence_web.dart) e para o service worker
// firebase-messaging-sw.js (importScripts). Não duplicar noutro sítio.
//
// São valores PÚBLICOS por desenho (vão para o navegador de qualquer pessoa):
// apiKey/appId/messagingSenderId identificam o projecto, não dão acesso a nada
// — o que protege os dados é a RLS do Supabase e as regras do Firebase.
// A vapidKey é a chave PÚBLICA do par Web Push (Firebase → Cloud Messaging →
// Web configuration → Web Push certificates).
//
// App web "Bora Web (PWA estafeta)" registada no projecto boraapp-d2bea a
// 17/09/2026 (missão estafeta-web-2026-09-16); par de chaves Web Push gerado
// no mesmo dia. Se um dia se apagar a app web ou se rodar o par de chaves na
// consola, é AQUI que se actualiza — e o token web de todos os estafetas
// deixa de valer até abrirem a Bora outra vez.
self.boraFirebaseConfig = {
  apiKey:            "AIzaSyAM6p70Na9Vqy59Lw9KJ55GJvP0XobYzPY",
  authDomain:        "boraapp-d2bea.firebaseapp.com",
  projectId:         "boraapp-d2bea",
  storageBucket:     "boraapp-d2bea.firebasestorage.app",
  messagingSenderId: "765097014497",
  appId:             "1:765097014497:web:f80ae480cd6802d14ef3a0",
  measurementId:     "G-4NKQNP53CR",
  vapidKey:          "BLH3O2nv9WY711RjWoEo-vE8gqnu8WhLH9wsSuyvbdPCiI-usb76_cln1gpYsuZQDFEaOEx5HZXI99yZF0MUDgQ"
};
