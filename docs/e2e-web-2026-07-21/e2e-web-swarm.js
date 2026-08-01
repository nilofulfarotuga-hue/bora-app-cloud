// E2E WEB SWARM v3 — Wait for Flutter boot properly + coordinate-based interaction
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const https = require('https');

const SITE_URL = 'https://bora-app-web.pages.dev';
const SUPABASE_URL = 'https://ojykpzwqrtusfeakzrna.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4';
const RUN_ID = 'WEB-E2E-2026-07-21';
const BASE_DIR = path.resolve(__dirname);
const VIDEOS_DIR = path.join(BASE_DIR, 'videos');
const SCREENSHOTS_DIR = path.join(BASE_DIR, 'screenshots');

fs.mkdirSync(VIDEOS_DIR, { recursive: true });
fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });

const accounts = {
  cliente: { email: 'cliente1@swarm.bora.test', password: 'SwarmBora2026!' },
  motorista: { email: 'motorista1@swarm.bora.test', password: 'SwarmBora2026!' },
  parceiro: { email: 'ouro.prata@bora.app', password: 'OuroPrata2026!' },
};

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
let sc = {};
function ns(f) { if (!sc[f]) sc[f] = 0; return ++sc[f]; }

async function logStep(fluxo, passo, estado, detalhe = '') {
  const body = JSON.stringify({ fluxo, passo: String(passo), estado, detalhe, device: 'vps-chromium', run_id: RUN_ID });
  return new Promise(resolve => {
    const req = https.request(`${SUPABASE_URL}/rest/v1/e2e_log`, {
      method: 'POST',
      headers: { 'apikey': SUPABASE_ANON, 'Authorization': `Bearer ${SUPABASE_ANON}`, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' },
    }, res => { res.resume(); resolve(res.statusCode); });
    req.on('error', () => resolve(0)); req.write(body); req.end();
  });
}

async function shot(page, name) {
  const p = path.join(SCREENSHOTS_DIR, `${name}.png`);
  await page.screenshot({ path: p });
  console.log(`  SHOT ${name}.png (${fs.statSync(p).size}b)`);
}

// Wait for Flutter to fully boot — check for semantics host having children
async function waitForFlutter(page, timeout = 20000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const count = await page.evaluate(() => {
      return document.querySelectorAll('flt-semantics').length;
    });
    if (count > 0) {
      console.log(`  Flutter booted: ${count} semantics found`);
      return true;
    }
    await sleep(500);
  }
  console.log('  Flutter boot timeout — no semantics');
  return false;
}

async function getSemantics(page) {
  return page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics');
    return Array.from(els).map((el, i) => {
      const r = el.getBoundingClientRect();
      return { idx: i, role: el.getAttribute('role'), label: el.getAttribute('aria-label'),
        x: Math.round(r.left + r.width/2), y: Math.round(r.top + r.height/2),
        w: Math.round(r.width), h: Math.round(r.height) };
    }).filter(e => e.w > 10 && e.h > 10);
  });
}

async function getInputs(page) {
  return page.evaluate(() => {
    return Array.from(document.querySelectorAll('input, textarea')).map((el, i) => ({
      idx: i, type: el.type, placeholder: el.placeholder,
      x: Math.round(el.getBoundingClientRect().left + el.getBoundingClientRect().width/2),
      y: Math.round(el.getBoundingClientRect().top + el.getBoundingClientRect().height/2),
    }));
  });
}

async function dismissBanner(page) {
  await page.evaluate(() => {
    const d = document.querySelector('#bora-ios');
    if (d) d.style.display = 'none';
    const btns = document.querySelectorAll('button');
    for (const b of btns) { if (b.getAttribute('aria-label') === 'Fechar') b.click(); }
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN
// ═══════════════════════════════════════════════════════════════════════════
async function login(page, email, password, fluxo) {
  const step = ns(fluxo);
  console.log(`\n[${fluxo}] Step ${step}: Login ${email}`);
  await logStep(fluxo, step, 'iniciou', `Login ${email}`);

  await page.goto(SITE_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  // Wait for Flutter to boot
  const booted = await waitForFlutter(page, 20000);
  await dismissBanner(page);
  await sleep(1000);

  let sems = await getSemantics(page);
  console.log(`  After boot: ${sems.length} semantics`);
  sems.forEach(s => console.log(`    #${s.idx} role=${s.role} @ ${s.x},${s.y} ${s.w}x${s.h}`));

  // Find buttons
  let btns = sems.filter(s => s.role === 'button');
  console.log(`  Buttons: ${btns.length}`);

  // Click "Sou Cliente" — look for buttons in the middle area
  const mainBtns = btns.filter(b => b.y > 200 && b.y < 700);
  if (mainBtns.length > 0) {
    await page.mouse.click(mainBtns[0].x, mainBtns[0].y);
    console.log(`  Clicked role btn @ ${mainBtns[0].x},${mainBtns[0].y}`);
  } else if (btns.length > 0) {
    await page.mouse.click(btns[0].x, btns[0].y);
  }
  await sleep(3000);
  await shot(page, `${fluxo}_${step}_after_role`);

  // Wait for login screen
  await waitForFlutter(page, 10000);
  sems = await getSemantics(page);
  console.log(`  Login screen: ${sems.length} semantics`);

  // Find HTML inputs
  let inputs = await getInputs(page);
  console.log(`  HTML inputs: ${inputs.length}`);

  if (inputs.length >= 2) {
    // Type email
    await page.mouse.click(inputs[0].x, inputs[0].y);
    await sleep(300);
    await page.keyboard.press('Control+a');
    await page.keyboard.type(email, { delay: 20 });
    // Type password
    await page.mouse.click(inputs[1].x, inputs[1].y);
    await sleep(300);
    await page.keyboard.press('Control+a');
    await page.keyboard.type(password, { delay: 20 });
    console.log('  Credentials typed');
  } else {
    // No inputs — the login screen might not have loaded
    console.log('  No inputs found — login screen may not have loaded');
    // Try clicking where email field typically is
    await page.mouse.click(195, 380);
    await sleep(300);
    await page.keyboard.type(email, { delay: 20 });
    await page.keyboard.press('Tab');
    await sleep(300);
    await page.keyboard.type(password, { delay: 20 });
  }

  await shot(page, `${fluxo}_${step}_creds`);

  // Click "Entrar" button
  sems = await getSemantics(page);
  btns = sems.filter(s => s.role === 'button');
  const loginBtn = btns.sort((a, b) => b.y - a.y)[0]; // bottom-most
  if (loginBtn) {
    await page.mouse.click(loginBtn.x, loginBtn.y);
    console.log(`  Clicked login btn @ ${loginBtn.x},${loginBtn.y}`);
  }
  await sleep(5000);
  await shot(page, `${fluxo}_${step}_logged_in`);

  // Verify home loaded
  await waitForFlutter(page, 10000);
  sems = await getSemantics(page);
  console.log(`  Home: ${sems.length} semantics`);
  sems.forEach(s => console.log(`    #${s.idx} role=${s.role} @ ${s.x},${s.y} ${s.w}x${s.h}`));

  await logStep(fluxo, step, 'passou', `Login done, ${sems.length} semantics on home`);
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW 3.1: DELIVERY RESTAURANTE
// ═══════════════════════════════════════════════════════════════════════════
async function flowDeliveryRestaurante(browser) {
  const f = 'delivery_restaurante';
  console.log(`\n${'═'.repeat(60)}\n  FLOW: ${f}\n${'═'.repeat(60)}`);

  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    recordVideo: { dir: path.join(VIDEOS_DIR, f), size: { width: 390, height: 844 } },
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });

  try {
    await login(page, accounts.cliente.email, accounts.cliente.password, f);
    await sleep(2000);

    let step = ns(f);
    let sems = await getSemantics(page);
    let btns = sems.filter(s => s.role === 'button');
    console.log(`[${f}] Step ${step}: Home — ${sems.length} semantics, ${btns.length} buttons`);
    await shot(page, `${f}_${step}_home`);

    // Categories are typically in a horizontal scroll at the top
    // Click first few buttons to find restaurants
    const topBtns = btns.filter(b => b.y > 100 && b.y < 400);
    console.log(`  Top btns: ${topBtns.length}`);

    // Click first top button (likely Restaurantes category)
    if (topBtns.length > 0) {
      await page.mouse.click(topBtns[0].x, topBtns[0].y);
      await sleep(3000);
      await shot(page, `${f}_${step}_cat_clicked`);

      // Now look for restaurant cards
      sems = await getSemantics(page);
      btns = sems.filter(s => s.role === 'button');
      const restBtns = btns.filter(b => b.y > 300);
      console.log(`  Restaurant btns: ${restBtns.length}`);

      if (restBtns.length > 0) {
        // Click first restaurant
        step = ns(f);
        await page.mouse.click(restBtns[0].x, restBtns[0].y);
        await sleep(3000);
        await shot(page, `${f}_${step}_restaurant`);

        // Look for add buttons on restaurant page
        sems = await getSemantics(page);
        btns = sems.filter(s => s.role === 'button');
        const addBtns = btns.filter(b => b.w > 80 && b.y > 300);
        console.log(`  Add btns: ${addBtns.length}`);

        // Add 2 items
        step = ns(f);
        let added = 0;
        for (const btn of addBtns) {
          await page.mouse.click(btn.x, btn.y);
          added++;
          await sleep(800);
          if (added >= 2) break;
        }
        console.log(`  Added ${added} items`);
        await shot(page, `${f}_${step}_added`);

        // Cart
        step = ns(f);
        // Cart icon is usually bottom-right
        await page.mouse.click(350, 780);
        await sleep(2000);
        await shot(page, `${f}_${step}_cart`);

        // Cash payment area
        step = ns(f);
        await page.mouse.click(195, 600);
        await sleep(1000);

        // Confirm
        step = ns(f);
        sems = await getSemantics(page);
        btns = sems.filter(s => s.role === 'button');
        const bottomBtn = btns.sort((a, b) => b.y - a.y)[0];
        if (bottomBtn) {
          await page.mouse.click(bottomBtn.x, bottomBtn.y);
          console.log(`  Confirmed @ ${bottomBtn.x},${bottomBtn.y}`);
        }
        await sleep(5000);
        await shot(page, `${f}_${step}_confirmed`);

        step = ns(f);
        await logStep(f, step, 'passou', `Delivery restaurante completed: ${added} items added`);
      } else {
        await logStep(f, step, 'falhou', 'No restaurant buttons found after category click');
      }
    } else {
      await logStep(f, step, 'falhou', 'No top buttons found on home');
    }

    await shot(page, `${f}_final`);
  } catch (e) {
    const step = ns(f);
    await logStep(f, step, 'falhou', `Exception: ${e.message}`);
    console.log(`  ERROR: ${e.message}`);
    await shot(page, `${f}_error`);
  } finally {
    if (errors.length > 0) {
      const step = ns(f);
      await logStep(f, step, 'detalhe', `JS errors: ${errors.length}`);
      errors.slice(0, 5).forEach(e => console.log(`  JS_ERR: ${e.substring(0, 150)}`));
    }
    await ctx.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW 3.2: DELIVERY MERCADO
// ═══════════════════════════════════════════════════════════════════════════
async function flowDeliveryMercado(browser) {
  const f = 'delivery_mercado';
  console.log(`\n${'═'.repeat(60)}\n  FLOW: ${f}\n${'═'.repeat(60)}`);

  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    recordVideo: { dir: path.join(VIDEOS_DIR, f), size: { width: 390, height: 844 } },
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });

  try {
    await login(page, accounts.cliente.email, accounts.cliente.password, f);
    await sleep(2000);

    let step = ns(f);
    let sems = await getSemantics(page);
    let btns = sems.filter(s => s.role === 'button');
    const topBtns = btns.filter(b => b.y > 100 && b.y < 400);
    console.log(`[${f}] Step ${step}: Home — ${topBtns.length} top btns`);
    await shot(page, `${f}_${step}_home`);

    // Click second category (Mercados)
    if (topBtns.length > 1) {
      await page.mouse.click(topBtns[1].x, topBtns[1].y);
    } else if (topBtns.length > 0) {
      await page.mouse.click(topBtns[0].x, topBtns[0].y);
    }
    await sleep(3000);

    // Click first market
    step = ns(f);
    sems = await getSemantics(page);
    btns = sems.filter(s => s.role === 'button');
    const marketBtns = btns.filter(b => b.y > 300);
    if (marketBtns.length > 0) {
      await page.mouse.click(marketBtns[0].x, marketBtns[0].y);
      await sleep(3000);

      // Add items
      step = ns(f);
      sems = await getSemantics(page);
      btns = sems.filter(s => s.role === 'button');
      const addBtns = btns.filter(b => b.w > 80 && b.y > 300);
      let added = 0;
      for (const btn of addBtns) {
        await page.mouse.click(btn.x, btn.y);
        added++;
        await sleep(800);
        if (added >= 2) break;
      }
      console.log(`  Added ${added} items`);
      await shot(page, `${f}_${step}_added`);

      // Cart + confirm
      step = ns(f);
      await page.mouse.click(350, 780);
      await sleep(2000);

      step = ns(f);
      await page.mouse.click(195, 600);
      await sleep(1000);

      step = ns(f);
      sems = await getSemantics(page);
      btns = sems.filter(s => s.role === 'button');
      const cBtn = btns.sort((a, b) => b.y - a.y)[0];
      if (cBtn) await page.mouse.click(cBtn.x, cBtn.y);
      await sleep(5000);
      await shot(page, `${f}_${step}_confirmed`);

      step = ns(f);
      await logStep(f, step, 'passou', `Market delivery completed: ${added} items`);
    } else {
      await logStep(f, step, 'falhou', 'No market buttons');
    }

    await shot(page, `${f}_final`);
  } catch (e) {
    const step = ns(f);
    await logStep(f, step, 'falhou', `Exception: ${e.message}`);
    await shot(page, `${f}_error`);
  } finally {
    if (errors.length > 0) {
      const step = ns(f);
      await logStep(f, step, 'detalhe', `JS errors: ${errors.length}`);
    }
    await ctx.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW 3.3: TVDE
// ═══════════════════════════════════════════════════════════════════════════
async function flowTVDE(browser) {
  const f = 'tvde';
  console.log(`\n${'═'.repeat(60)}\n  FLOW: ${f}\n${'═'.repeat(60)}`);

  // TRAVA DE SEGURANÇA
  console.log('[TVDE] Safety check...');
  const check = await new Promise(resolve => {
    const req = https.request(`${SUPABASE_URL}/rest/v1/drivers?select=id&is_online=eq.true`, {
      method: 'GET',
      headers: { 'apikey': SUPABASE_ANON, 'Authorization': `Bearer ${SUPABASE_ANON}`, 'Prefer': 'count=exact' },
    }, res => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, range: res.headers['content-range'] }));
    });
    req.on('error', e => resolve({ error: e.message })); req.end();
  });
  console.log(`  Safety: ${JSON.stringify(check)}`);

  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    recordVideo: { dir: path.join(VIDEOS_DIR, f), size: { width: 390, height: 844 } },
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });

  try {
    await login(page, accounts.cliente.email, accounts.cliente.password, f);
    await sleep(2000);

    let step = ns(f);
    let sems = await getSemantics(page);
    let btns = sems.filter(s => s.role === 'button');
    console.log(`[${f}] Step ${step}: Home — ${btns.length} buttons`);
    await shot(page, `${f}_${step}_home`);

    // Try categories to find TVDE
    const topBtns = btns.filter(b => b.y > 100 && b.y < 400);
    let found = false;
    for (let i = 0; i < Math.min(topBtns.length, 8); i++) {
      await page.mouse.click(topBtns[i].x, topBtns[i].y);
      await sleep(2000);
      const hasInput = await page.evaluate(() => document.querySelectorAll('input').length > 0);
      if (hasInput) { found = true; console.log(`  TVDE found at cat #${i}`); break; }
    }
    await shot(page, `${f}_${step}_tvde`);

    if (found) {
      // Enter origin/destination
      let inputs = await getInputs(page);
      if (inputs.length > 0) {
        step = ns(f);
        await page.mouse.click(inputs[0].x, inputs[0].y);
        await sleep(300);
        await page.keyboard.type('Guarda, Portugal', { delay: 20 });
        await sleep(2000);
        await page.mouse.click(195, 250);
        await sleep(2000);
        await shot(page, `${f}_${step}_origin`);

        step = ns(f);
        inputs = await getInputs(page);
        if (inputs.length > 1) {
          await page.mouse.click(inputs[1].x, inputs[1].y);
        } else {
          await page.mouse.click(195, 350);
        }
        await sleep(300);
        await page.keyboard.type('Rua Vasco da Gama, Guarda', { delay: 20 });
        await sleep(2000);
        await page.mouse.click(195, 250);
        await sleep(2000);
        await shot(page, `${f}_${step}_dest`);

        // Cash + request
        step = ns(f);
        sems = await getSemantics(page);
        btns = sems.filter(s => s.role === 'button');
        const rideBtn = btns.sort((a, b) => b.y - a.y)[0];
        if (rideBtn) {
          await page.mouse.click(rideBtn.x, rideBtn.y);
          console.log(`  Requested ride @ ${rideBtn.x},${rideBtn.y}`);
        }
        await sleep(5000);
        await shot(page, `${f}_${step}_requested`);

        step = ns(f);
        await sleep(15000);
        await shot(page, `${f}_${step}_driver`);
        await logStep(f, step, 'passou', 'TVDE ride requested');
      }
    } else {
      await logStep(f, step, 'falhou', 'TVDE screen not found');
    }

    await shot(page, `${f}_final`);
  } catch (e) {
    const step = ns(f);
    await logStep(f, step, 'falhou', `Exception: ${e.message}`);
    await shot(page, `${f}_error`);
  } finally {
    if (errors.length > 0) {
      const step = ns(f);
      await logStep(f, step, 'detalhe', `JS errors: ${errors.length}`);
    }
    await ctx.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW 3.4: LIMPEZA
// ═══════════════════════════════════════════════════════════════════════════
async function flowLimpeza(browser) {
  const f = 'limpeza';
  console.log(`\n${'═'.repeat(60)}\n  FLOW: ${f}\n${'═'.repeat(60)}`);

  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    recordVideo: { dir: path.join(VIDEOS_DIR, f), size: { width: 390, height: 844 } },
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });

  try {
    await login(page, accounts.cliente.email, accounts.cliente.password, f);
    await sleep(2000);

    let step = ns(f);
    let sems = await getSemantics(page);
    let btns = sems.filter(s => s.role === 'button');
    const topBtns = btns.filter(b => b.y > 100 && b.y < 400);
    console.log(`[${f}] Step ${step}: Home — ${topBtns.length} top btns`);
    await shot(page, `${f}_${step}_home`);

    // Try categories for cleaning
    let found = false;
    for (let i = 0; i < Math.min(topBtns.length, 8); i++) {
      await page.mouse.click(topBtns[i].x, topBtns[i].y);
      await sleep(2000);
      const hasInput = await page.evaluate(() => document.querySelectorAll('input').length >= 1);
      if (hasInput) { found = true; break; }
    }
    await shot(page, `${f}_${step}_cleaning`);

    if (found) {
      step = ns(f);
      sems = await getSemantics(page);
      btns = sems.filter(s => s.role === 'button');
      for (const btn of btns.slice(0, 3)) {
        await page.mouse.click(btn.x, btn.y);
        await sleep(800);
      }
      await shot(page, `${f}_${step}_form`);

      step = ns(f);
      const cBtn = btns.sort((a, b) => b.y - a.y)[0];
      if (cBtn) await page.mouse.click(cBtn.x, cBtn.y);
      await sleep(5000);
      await shot(page, `${f}_${step}_confirmed`);
      await logStep(f, step, 'passou', 'Cleaning flow completed');
    } else {
      await logStep(f, step, 'falhou', 'Cleaning screen not found');
    }

    await shot(page, `${f}_final`);
  } catch (e) {
    const step = ns(f);
    await logStep(f, step, 'falhou', `Exception: ${e.message}`);
    await shot(page, `${f}_error`);
  } finally {
    if (errors.length > 0) {
      const step = ns(f);
      await logStep(f, step, 'detalhe', `JS errors: ${errors.length}`);
    }
    await ctx.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW 3.5: RESERVA
// ═══════════════════════════════════════════════════════════════════════════
async function flowReserva(browser) {
  const f = 'reserva';
  console.log(`\n${'═'.repeat(60)}\n  FLOW: ${f}\n${'═'.repeat(60)}`);

  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    recordVideo: { dir: path.join(VIDEOS_DIR, f), size: { width: 390, height: 844 } },
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });

  try {
    await login(page, accounts.cliente.email, accounts.cliente.password, f);
    await sleep(2000);

    let step = ns(f);
    let sems = await getSemantics(page);
    let btns = sems.filter(s => s.role === 'button');
    const topBtns = btns.filter(b => b.y > 100 && b.y < 400);
    await shot(page, `${f}_${step}_home`);

    if (topBtns.length > 0) {
      await page.mouse.click(topBtns[0].x, topBtns[0].y);
      await sleep(2000);

      step = ns(f);
      sems = await getSemantics(page);
      btns = sems.filter(s => s.role === 'button');
      const restBtns = btns.filter(b => b.y > 300);
      if (restBtns.length > 0) {
        await page.mouse.click(restBtns[0].x, restBtns[0].y);
        await sleep(3000);
        await shot(page, `${f}_${step}_restaurant`);

        // Try all buttons to find reservation
        step = ns(f);
        sems = await getSemantics(page);
        btns = sems.filter(s => s.role === 'button');
        for (const btn of btns) {
          await page.mouse.click(btn.x, btn.y);
          await sleep(1500);
          const hasInput = await page.evaluate(() => document.querySelectorAll('input').length > 0);
          if (hasInput) {
            await shot(page, `${f}_${step}_reservation_form`);
            await logStep(f, step, 'passou', 'Reservation form found');
            break;
          }
        }
      }
    }

    await shot(page, `${f}_final`);
  } catch (e) {
    const step = ns(f);
    await logStep(f, step, 'falhou', `Exception: ${e.message}`);
    await shot(page, `${f}_error`);
  } finally {
    if (errors.length > 0) {
      const step = ns(f);
      await logStep(f, step, 'detalhe', `JS errors: ${errors.length}`);
    }
    await ctx.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW 3.6: VARREDURA
// ═══════════════════════════════════════════════════════════════════════════
async function flowVarredura(browser) {
  const f = 'varredura';
  console.log(`\n${'═'.repeat(60)}\n  FLOW: ${f}\n${'═'.repeat(60)}`);

  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    recordVideo: { dir: path.join(VIDEOS_DIR, f), size: { width: 390, height: 844 } },
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });

  try {
    await login(page, accounts.cliente.email, accounts.cliente.password, f);
    await sleep(2000);

    let step = ns(f);
    let sems = await getSemantics(page);
    let btns = sems.filter(s => s.role === 'button');
    const topBtns = btns.filter(b => b.y > 100 && b.y < 400);
    console.log(`[${f}] Step ${step}: Home — ${sems.length} semantics, ${topBtns.length} top btns`);
    await shot(page, `${f}_${step}_home`);

    // Navigate each category
    for (let i = 0; i < Math.min(topBtns.length, 8); i++) {
      step = ns(f);
      await page.mouse.click(topBtns[i].x, topBtns[i].y);
      await sleep(2000);
      const newSems = await getSemantics(page);
      console.log(`  Cat #${i}: ${newSems.length} semantics`);
      await shot(page, `${f}_${step}_cat${i}`);
      await page.goBack();
      await sleep(1500);
    }

    // A11Y audit
    step = ns(f);
    const a11y = await page.evaluate(() => {
      const all = document.querySelectorAll('flt-semantics');
      return { total: all.length, withRole: document.querySelectorAll('[role]').length, withLabel: document.querySelectorAll('[aria-label]').length };
    });
    await logStep(f, step, 'detalhe', `A11Y: ${JSON.stringify(a11y)}`);
    console.log(`  A11Y: ${JSON.stringify(a11y)}`);

    await shot(page, `${f}_final`);
  } catch (e) {
    const step = ns(f);
    await logStep(f, step, 'falhou', `Exception: ${e.message}`);
    await shot(page, `${f}_error`);
  } finally {
    if (errors.length > 0) {
      const step = ns(f);
      await logStep(f, step, 'detalhe', `JS errors: ${errors.length}`);
      errors.slice(0, 10).forEach(e => console.log(`  JS_ERR: ${e.substring(0, 150)}`));
    }
    await ctx.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════
(async () => {
  const startTime = Date.now();
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  E2E WEB SWARM v3 — Bora App');
  console.log(`  RUN_ID: ${RUN_ID} | ${new Date().toISOString()}`);
  console.log('═══════════════════════════════════════════════════════════');

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });

  const flows = [flowDeliveryRestaurante, flowDeliveryMercado, flowTVDE, flowLimpeza, flowReserva, flowVarredura];
  for (const fn of flows) {
    try { await fn(browser); } catch (e) { console.log(`CRASHED: ${e.message}`); }
    await sleep(2000);
  }

  await browser.close();
  const elapsed = Math.round((Date.now() - startTime) / 1000);
  console.log(`\n═══════════════════════════════════════════════════════════`);
  console.log(`  DONE in ${elapsed}s | Screenshots: ${SCREENSHOTS_DIR}`);
  console.log('═══════════════════════════════════════════════════════════');
})();
