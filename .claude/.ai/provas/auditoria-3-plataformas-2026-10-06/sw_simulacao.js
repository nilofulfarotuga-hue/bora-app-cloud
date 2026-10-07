// Prova: corre o script de versão do web/index.html (o real, tirado do ficheiro)
// com um browser falso e conta que service workers são desregistados.
// Uso: node sw_simulacao.js <caminho do index.html>
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const ini = html.indexOf("var COMMIT = '__BORA_COMMIT__'");
const abre = html.lastIndexOf('<script>', ini);
const fecha = html.indexOf('</script>', ini);
const codigo = html.slice(abre + '<script>'.length, fecha).replace("'__BORA_COMMIT__'", "'antigo'");
const desregistados = [];
const reg = (url) => ({ active: { scriptURL: url }, unregister: () => { desregistados.push(url); return Promise.resolve(true); } });
global.window = { location: { reload: () => { console.log('desregistados=' + JSON.stringify(desregistados)); } } };
global.sessionStorage = { getItem: () => null, setItem: () => {} };
global.document = { addEventListener: () => {}, visibilityState: 'visible' };
global.caches = { keys: () => Promise.resolve([]), delete: () => Promise.resolve(true) };
// O Node 21+ já traz um `navigator` só de leitura: substitui-se à força.
Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { serviceWorker: { getRegistrations: () => Promise.resolve([
  reg('https://app.boraguarda.com/flutter_service_worker.js'),
  reg('https://app.boraguarda.com/firebase-messaging-sw.js'),
]) } } });
global.window.caches = global.caches;
global.fetch = () => Promise.resolve({ ok: true, json: () => Promise.resolve({ commit: 'novo' }) });
global.setInterval = () => 0;
new Function(codigo)();
