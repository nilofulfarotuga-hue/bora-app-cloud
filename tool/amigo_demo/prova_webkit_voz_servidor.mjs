// Prova (pendências 09/11/2026, bloco I): no WebKit (o motor do Safari) com emulação de iPhone e SEM
// speechSynthesis, o Amigo pede a voz ao servidor (aqui a Edge FALSA da demo, ?voz_servidor=falso) e toca-a
// num elemento <audio>, desbloqueado no primeiro toque.
// Corre em dois motores: o WebKit (o do Safari; o do Windows NÃO toca áudio — dá NotSupportedError mesmo com
// canPlayType "probably" — e aí prova-se que o Amigo volta à legenda sem erro) e o Chromium com emulação de
// iPhone e o speechSynthesis apagado (prova que o áudio do servidor toca de facto e que o 1.º toque o desbloqueia).
// Uso: node tool/amigo_demo/prova_webkit_voz_servidor.mjs <pasta-do-build-web> <pasta-de-saida> [playwright]
//   (build: flutter build web -t tool/amigo_demo/main.dart --release -o <pasta-do-build-web>)
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { mkdirSync, readFileSync, writeFileSync, existsSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

const [raiz, saida = 'prova-webkit-voz', pw = 'C:/BoraLocal/projetosflutter/partsflow_demo/node_modules/playwright'] = process.argv.slice(2);
const require = createRequire(import.meta.url);
const { webkit, chromium, devices } = require(pw);
mkdirSync(saida, { recursive: true });

const tipos = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf', '.css': 'text/css', '.svg': 'image/svg+xml' };
const servidor = createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p.endsWith('/')) p += 'index.html';
  const f = join(raiz, p);
  if (!existsSync(f) || !statSync(f).isFile()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': tipos[extname(f)] ?? 'application/octet-stream' });
  res.end(readFileSync(f));
}).listen(18793, '127.0.0.1');
const url = 'http://127.0.0.1:18793/?voz_servidor=falso';

async function prova(motor, nome, semVoz) {
  const browser = await motor.launch();
  const ctx = await browser.newContext({ ...devices['iPhone 13'], locale: 'pt-PT' });
  if (semVoz) await ctx.addInitScript(() => { try { delete window.speechSynthesis; delete window.SpeechSynthesisUtterance; } catch (_) {} });
  const page = await ctx.newPage();
  const pasta = `${saida}/${nome}`;
  mkdirSync(pasta, { recursive: true });
  const consola = [];
  page.on('console', (m) => { const t = m.text(); if (/Amigo/.test(t)) consola.push(t); });
  await page.goto(url);
  await page.waitForTimeout(7000);
  const temSpeech = await page.evaluate(() => 'speechSynthesis' in window);
  const antes = await page.evaluate(() => ({ audio_criado: !!window.__amigoAudio, desbloqueado: !!window.__amigoAudioDesbloqueado }));
  await page.screenshot({ path: `${pasta}/1-inicio.png` });
  // o toque em "Começar" é o 1.º gesto: desbloqueia o <audio> e abre o ecrã do Amigo
  const vp = page.viewportSize();
  await page.touchscreen.tap(vp.width / 2, vp.height / 2);
  const amostras = [];
  for (let i = 0; i < 30; i++) {
    await page.waitForTimeout(200);
    amostras.push(await page.evaluate(() => {
      const a = window.__amigoAudio;
      return a ? { t: Math.round(performance.now()), src: String(a.src).slice(0, 22), paused: a.paused,
        currentTime: Number(a.currentTime.toFixed(2)), duration: Number.isFinite(a.duration) ? Number(a.duration.toFixed(2)) : null,
        ended: a.ended, erro: a.error ? a.error.code : null } : null;
    }));
    if (i === 12) await page.screenshot({ path: `${pasta}/2-a-falar.png` });
  }
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${pasta}/3-depois.png` });
  const depois = await page.evaluate(() => ({ desbloqueado: !!window.__amigoAudioDesbloqueado, play_dentro_do_toque: window.__amigoAudioToques ?? 0 }));
  const tocou = amostras.filter((a) => a && !a.paused && a.currentTime > 0 && /^data:audio\/wav/.test(a.src));
  const r = {
    motor: nome, navegador: `${nome} ${browser.version()}`, aparelho: 'iPhone 13 (emulado)',
    speechSynthesis_no_navegador: temSpeech,
    antes_do_toque: antes,
    depois_do_toque: depois,
    amostras_a_tocar: tocou.length,
    maior_currentTime_s: tocou.reduce((m, a) => Math.max(m, a.currentTime), 0),
    duracao_s: tocou.find((a) => a.duration)?.duration ?? null,
    erros_do_audio: [...new Set(amostras.filter((a) => a?.erro).map((a) => a.erro))],
    amostras,
    consola,
  };
  writeFileSync(`${pasta}/resultado.json`, JSON.stringify(r, null, 2));
  await browser.close();
  return { ...r, amostras: `${amostras.length} amostras` };
}

const resultados = [await prova(webkit, 'webkit', false), await prova(chromium, 'chromium-sem-speech', true)];
console.log(JSON.stringify({ url, resultados }, null, 2));
servidor.close();
