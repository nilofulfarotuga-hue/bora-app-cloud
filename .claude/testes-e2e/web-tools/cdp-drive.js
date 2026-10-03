// Driver E2E via Chrome DevTools Protocol usando SÓ built-ins do Node 24
// (global WebSocket + fetch + child_process). Sem Playwright, sem npm install.
// Toca botões da app Flutter (CanvasKit) por COORDENADAS e grava screenshots.
//
// Uso:
//   node cdp-drive.js <url> <shotsDir> [stepsFile.json] [bootMs]
//
// stepsFile.json = array de passos, executados por ordem. Cada passo:
//   { "shot": "nome" }              → grava <shotsDir>/nome.png
//   { "click": [x, y] }             → tap nas coords CSS (dpr 1 ⇒ ≈ px do screenshot)
//   { "type": "texto" }             → insere texto (Input.insertText) no campo focado
//   { "key": "Enter" }              → tecla especial
//   { "sleep": 4000 }               → espera ms
//   { "log": "mensagem" }           → imprime marcador
// Sem stepsFile → sequência default (só arranque + screenshot da RoleScreen).
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const url = process.argv[2] || 'http://127.0.0.1:8099/';
const shotsDir = path.resolve(process.argv[3] || '.claude/testes-e2e/web-logs/shots');
const stepsFile = process.argv[4];
const bootMs = parseInt(process.argv[5] || '12000', 10);
fs.mkdirSync(shotsDir, { recursive: true });

const steps = stepsFile
  ? JSON.parse(fs.readFileSync(stepsFile, 'utf8'))
  : [{ sleep: bootMs }, { shot: '01_role_screen' }];

const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = 9333;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const userDir = path.join(require('os').tmpdir(), 'bora-cdp-' + PORT);
const chrome = spawn(CHROME, [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
  '--window-size=1400,2200', `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${userDir}`, 'about:blank',
], { stdio: 'ignore' });

let ws;
let msgId = 0;
const pending = new Map();
function send(method, params = {}) {
  const id = ++msgId;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((res) => pending.set(id, res));
}
async function click(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await sleep(60);
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
}
async function typeText(text) {
  await send('Input.insertText', { text });
}
async function key(name) {
  const map = { Enter: { key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 },
                Tab: { key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 } };
  const k = map[name]; if (!k) return;
  await send('Input.dispatchKeyEvent', { type: 'keyDown', ...k });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', ...k });
}
async function evalJs(expression) {
  const { result } = await send('Runtime.evaluate', { expression, returnByValue: true });
  return result ? result.value : null;
}
// Liga a árvore de semântica do Flutter (cria nós DOM <flt-semantics> com aria-label).
async function enableA11y() {
  await evalJs(`(function(){const ph=document.querySelector('flt-semantics-placeholder');if(ph){ph.click();return 'clicked';}return 'noph';})()`);
  await sleep(800);
}
// Toca no elemento de semântica cujo aria-label contém `text` (auto-calibra coords).
async function tapText(text) {
  const v = await evalJs(`(function(){
    var ns=[].slice.call(document.querySelectorAll('flt-semantics[aria-label]'));
    var el=ns.filter(function(n){return n.getAttribute('aria-label').indexOf(${JSON.stringify(text)})>=0;})[0];
    if(!el)return null;var r=el.getBoundingClientRect();
    return {x:r.left+r.width/2,y:r.top+r.height/2,label:el.getAttribute('aria-label')};
  })()`);
  if (!v) { console.log('TAPTEXT_NOTFOUND ' + text); return false; }
  await click(v.x, v.y);
  console.log('TAPTEXT ' + JSON.stringify(text) + ' @ ' + Math.round(v.x) + ',' + Math.round(v.y));
  return true;
}
// Foca o input de um campo de texto (por aria-label) e escreve.
async function typeInto(label, text) {
  const ok = await evalJs(`(function(){
    var ns=[].slice.call(document.querySelectorAll('flt-semantics'));
    var el=ns.filter(function(n){var a=n.getAttribute('aria-label')||'';return a.indexOf(${JSON.stringify(label)})>=0;})[0];
    if(!el)return null;var inp=el.querySelector('input,textarea');if(!inp)return 'noinput';
    inp.focus();return 'ok';
  })()`);
  if (ok !== 'ok') { console.log('TYPEINTO_FAIL ' + label + ' -> ' + ok); return false; }
  await sleep(200);
  await typeText(text);
  console.log('TYPEINTO ' + label + ' = ' + JSON.stringify(text));
  return true;
}
async function shot(name) {
  const { data } = await send('Page.captureScreenshot', { format: 'png' });
  const p = path.join(shotsDir, name + '.png');
  const buf = Buffer.from(data, 'base64');
  fs.writeFileSync(p, buf);
  console.log(`SHOT ${p} (${buf.length} bytes)`);
}

(async () => {
  try {
    let target;
    for (let i = 0; i < 30; i++) {
      try {
        const r = await fetch(`http://127.0.0.1:${PORT}/json`);
        const list = await r.json();
        target = list.find((t) => t.type === 'page');
        if (target) break;
      } catch (_) {}
      await sleep(500);
    }
    if (!target) throw new Error('sem target CDP');
    console.log('CDP_TARGET ' + target.webSocketDebuggerUrl);

    ws = new WebSocket(target.webSocketDebuggerUrl);
    ws.addEventListener('message', (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result || {}); pending.delete(m.id); }
    });
    await new Promise((res) => ws.addEventListener('open', res));

    await send('Page.enable');
    await send('Runtime.enable');
    // Força um viewport determinístico: screenshot px == input px (dpr 1).
    await send('Emulation.setDeviceMetricsOverride', {
      width: 1400, height: 2200, deviceScaleFactor: 1, mobile: false,
    });
    await send('Page.navigate', { url });
    console.log('NAV ' + url);

    for (const s of steps) {
      if ('log' in s) console.log('LOG ' + s.log);
      if ('sleep' in s) await sleep(s.sleep);
      if ('click' in s) { await click(s.click[0], s.click[1]); console.log(`CLICK ${s.click[0]},${s.click[1]}`); }
      if ('type' in s) { await typeText(s.type); console.log(`TYPE ${JSON.stringify(s.type)}`); }
      if ('key' in s) { await key(s.key); console.log(`KEY ${s.key}`); }
      if ('shot' in s) await shot(s.shot);
    }
    console.log('DRIVE_DONE');
  } catch (e) {
    console.log('DRIVE_ERROR ' + (e && e.message));
  } finally {
    try { ws && ws.close(); } catch (_) {}
    try { chrome.kill(); } catch (_) {}
    setTimeout(() => process.exit(0), 500);
  }
})();
