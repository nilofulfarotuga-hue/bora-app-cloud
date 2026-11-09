// Prova do adendo 4 (m11): o ecrã do Amigo no WebKit (o motor do Safari) com emulação de iPhone.
// Uso: node tool/amigo_demo/prova_webkit.mjs <url> <pasta-de-saida> [caminho-do-playwright]
// Regista: as vozes pt que o WebKit dá, o estado do botão do som antes e depois do toque, a consola do Amigo
// e capturas. (O WebKit do Windows não traz as vozes do iPhone: aqui prova-se o caminho, não a voz Joana.)
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';

const [url = 'http://127.0.0.1:8792/', saida = 'prova-webkit', pw = 'C:/BoraLocal/projetosflutter/partsflow_demo/node_modules/playwright'] = process.argv.slice(2);
const require = createRequire(import.meta.url);
const { webkit, devices } = require(pw);
mkdirSync(saida, { recursive: true });

const browser = await webkit.launch();
const ctx = await browser.newContext({ ...devices['iPhone 13'], locale: 'pt-PT' });
const page = await ctx.newPage();
const consola = [];
page.on('console', (m) => { const t = m.text(); if (/Amigo/.test(t)) consola.push(t); });
await page.goto(url);
await page.waitForTimeout(6000);
const vozes = await page.evaluate(() => ('speechSynthesis' in window)
  ? speechSynthesis.getVoices().filter((v) => v.lang.toLowerCase().startsWith('pt')).map((v) => `${v.name}|${v.lang}`)
  : 'sem speechSynthesis');
await page.screenshot({ path: `${saida}/1-inicio.png` });
// toque no botão "Começar" (centro do ecrã)
const vp = page.viewportSize();
await page.touchscreen.tap(vp.width / 2, vp.height / 2);
await page.waitForTimeout(5000);
const desbloqueada = await page.evaluate(() => !!window.__amigoVozDesbloqueada);
await page.screenshot({ path: `${saida}/2-amigo.png` });
// toque no ecrã do Amigo (repete se estava bloqueada)
await page.touchscreen.tap(vp.width / 2, vp.height * 0.6);
await page.waitForTimeout(4000);
await page.screenshot({ path: `${saida}/3-depois-do-toque.png` });
const r = { url, navegador: `webkit ${browser.version()}`, aparelho: 'iPhone 13 (emulado)', vozes_pt: vozes, voz_desbloqueada_no_toque: desbloqueada, consola };
writeFileSync(`${saida}/resultado.json`, JSON.stringify(r, null, 2));
console.log(JSON.stringify(r));
await browser.close();
