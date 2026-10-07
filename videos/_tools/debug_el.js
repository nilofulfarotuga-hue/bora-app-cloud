// debug_el.js <html> <t> <id> — imprime rect/opacidade/transform de um elemento num instante
const path = require('path'); const { chromium } = require('playwright');
const [html, t, id] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 854, height: 480 } });
  p.on('pageerror', e => console.log('ERR', e.message));
  await p.goto('file:///' + path.resolve(html).split('\\').join('/'));
  await p.waitForFunction(() => window.__ready === true); await p.evaluate(t => seek(t), parseFloat(t));
  console.log(await p.evaluate(id => { const k = document.getElementById(id); const i = k.querySelector('img'); const r = k.getBoundingClientRect(); const cs = getComputedStyle(k); const room = document.getElementById('room'); const q = room ? room.getBoundingClientRect() : null; return JSON.stringify({ rect: [r.x, r.y, r.width, r.height], op: cs.opacity, vis: cs.visibility, tr: k.style.transform, nat: i && i.naturalWidth, imgH: i && i.getBoundingClientRect().height, roomPos: room && getComputedStyle(room).position, roomRect: q && [q.x, q.y, q.width, q.height] }); }, id));
  await b.close();
})();
