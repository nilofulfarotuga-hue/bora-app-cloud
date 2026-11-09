// Lê a consola do Chrome do Android (emulador) pelo protocolo das DevTools, para as provas da
// demonstração do Amigo (tool/amigo_demo). Antes: adb forward tcp:9222 localabstract:chrome_devtools_remote
// Uso: node tool/amigo_demo/ouvir_consola_android.mjs <segundos> <saida.txt>
import { writeFileSync, appendFileSync } from 'node:fs';

const [segs = '80', saida = 'consola-android.txt'] = process.argv.slice(2);
writeFileSync(saida, '');
const paginas = await (await fetch('http://127.0.0.1:9222/json')).json();
const pagina = paginas.find((p) => (p.url || '').includes('8791'));
if (!pagina) { console.log('sem página da demo', paginas.map((p) => p.url)); process.exit(1); }
const ws = new WebSocket(pagina.webSocketDebuggerUrl);
let id = 0;
const enviar = (method, params = {}) => ws.send(JSON.stringify({ id: ++id, method, params }));
ws.onopen = () => {
  enviar('Runtime.enable');
  setTimeout(() => enviar('Runtime.evaluate', {
    expression: `JSON.stringify(speechSynthesis.getVoices().filter(v => v.lang.toLowerCase().startsWith('pt')).map(v => v.name + ' | ' + v.lang + ' | local=' + v.localService))`,
  }), 1500);
};
ws.onmessage = (m) => {
  const j = JSON.parse(m.data);
  if (j.method === 'Runtime.consoleAPICalled') {
    const t = j.params.args.map((a) => a.value ?? a.description ?? '').join(' ');
    if (t.includes('Amigo')) { appendFileSync(saida, t + '\n'); console.log(t); }
  } else if (j.result?.result?.value && String(j.result.result.value).startsWith('[')) {
    const t = '[vozes pt no Chrome do Android] ' + j.result.result.value;
    appendFileSync(saida, t + '\n'); console.log(t);
  }
};
setTimeout(() => { ws.close(); process.exit(0); }, Number(segs) * 1000);
