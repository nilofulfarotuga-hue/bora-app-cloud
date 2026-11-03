// Ecrãs REAIS da app web (produção, visitante sem conta) para o reel do Fuku: loja, caixas, caixa no carrinho.
const { chromium } = require('C:/BoraLocal/projetosflutter/bora_app/videos/node_modules/playwright');
const out = process.argv[2];
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Users/danil/AppData/Local/ms-playwright/chromium-1234/chrome-win64/chrome.exe' });
  const p = await b.newPage({ viewport: { width: 390, height: 720 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  await p.goto('https://app.boraguarda.com/#/loja/fuku-sushi-guarda', { timeout: 90000 });
  await p.waitForSelector('flt-semantics-placeholder, flutter-view', { timeout: 90000 });
  await p.waitForTimeout(8000);
  await p.evaluate(() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); });
  await p.waitForTimeout(3000);
  await p.screenshot({ path: `${out}/app-1-loja.png` });
  const leaf = async (re) => {
    for (const e of await p.$$('flt-semantics')) {
      const t = ((await e.getAttribute('aria-label')) || (await e.innerText()) || '').trim();
      if (re.test(t) && !t.includes('\n')) return e;
    }
    return null;
  };
  // abrir a categoria Caixas de sushi (só caixas no ecrã)
  await p.mouse.click(149, 525); await p.waitForTimeout(3500);
  await p.screenshot({ path: `${out}/app-2-caixas.png` });
  const cx = +process.argv[3] || 0, cy = +process.argv[4] || 0;
  if (!cx) { await b.close(); return; }
  // toque marcado: guardar onde se tocou
  require('fs').writeFileSync(`${out}/toque.json`, JSON.stringify({ x: cx, y: cy }));
  await p.mouse.click(cx, cy); await p.waitForTimeout(1500);
  await p.screenshot({ path: `${out}/app-3a-uma.png` });
  await p.mouse.click(cx, cy); await p.waitForTimeout(2500);
  await p.screenshot({ path: `${out}/app-3-no-carrinho.png` });
  const l2 = (await p.$$eval('flt-semantics', els => els.map(x => (x.getAttribute('aria-label') || x.innerText || '').trim()).filter(t => t && !t.includes(String.fromCharCode(10)))));
  console.log('barra:', l2.filter(t => /carrinho/i.test(t)).join(' | '));
  await b.close(); return;
  const e = await leaf(/^T1 Sashimi Salm/);
  const bb = await e.boundingBox();
  await p.mouse.click(bb.x + bb.width / 2, bb.y + bb.height - 18);
  await p.waitForTimeout(1200);
  await p.mouse.click(bb.x + bb.width / 2, bb.y + bb.height - 18);
  await p.waitForTimeout(2500);
  await p.screenshot({ path: `${out}/app-3-no-carrinho.png` });
  const l = (await p.$$eval('flt-semantics', els => els.map(x => (x.getAttribute('aria-label') || x.innerText || '').trim()).filter(t => t && !t.includes('\n'))));
  console.log('carrinho:', l.filter(t => /carrinho/i.test(t)).join(' | '));
  console.log('T1 bbox', JSON.stringify(bb));
  await b.close();
})().catch(e => { console.log('ERRO', e.message); process.exit(1); });
