// Pingo Doce SFCC best-sellers scraper (HTTP direct, no Playwright needed)
import https from 'https';
import fs from 'fs';

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'X-Requested-With': 'XMLHttpRequest',
  'Accept-Language': 'pt-PT,pt;q=0.9',
  'Accept': 'text/html,application/xhtml+xml',
};

function httpGet(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: HEADERS }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(new Error('timeout')); });
  });
}

const decode = (s) =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
   .replace(/&lt;/g, '<').replace(/&gt;/g, '>');

function titleCase(s) {
  return s.toLowerCase().split(/\s+/).map((w) => w.length ? w[0].toUpperCase() + w.slice(1) : w).join(' ');
}

function parsePage(html) {
  const rows = [];
  const re = /data-gtm-info='([^']+)'[\s\S]{0,6000}?<img[^>]+class="product-tile-component-image"[^>]*src="([^"]+)"/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    try {
      const json = JSON.parse(decode(m[1]));
      const img = decode(m[2]);
      if (/\/badges\//i.test(img)) continue;
      if (!/Sites-pingo-doce-master/i.test(img)) continue;
      const item = (json.items && json.items[0]) || {};
      const pid = String(item.item_id || '').trim();
      const name = String(item.item_name || '').trim();
      const price = Number(item.price ?? json.value ?? 0);
      if (!pid || !name || !(price > 0)) continue;
      rows.push({
        pid,
        name: titleCase(name),
        price,
        brand: item.item_brand ? titleCase(String(item.item_brand)) : null,
        category: item.item_category ? String(item.item_category).trim() : null,
        photo_url: img,
      });
    } catch {}
  }
  return rows;
}

const outPath = 'scripts/scraper/_pd_bestsellers_raw.json';
const byPid = new Map();
const MAX_PAGES = 130;
const SLEEP_MS = 1000;

const startTime = Date.now();
let emptyStreak = 0;

for (let p = 0; p < MAX_PAGES; p++) {
  const start = p * 48;
  const url = `https://www.pingodoce.pt/on/demandware.store/Sites-pingo-doce-Site/default/Search-UpdateGrid?srule=best-sellers&start=${start}&sz=48&cgid=root`;
  try {
    const { status, body } = await httpGet(url);
    if (status !== 200) {
      console.log(`page ${p} status ${status}, stop`);
      break;
    }
    const rows = parsePage(body);
    let newCount = 0;
    for (const r of rows) if (!byPid.has(r.pid)) { byPid.set(r.pid, r); newCount++; }
    if (p % 5 === 0) {
      console.log(`page=${p} scraped_total=${byPid.size} new=${newCount} elapsed=${Math.round((Date.now()-startTime)/1000)}s`);
    }
    if (rows.length === 0) {
      emptyStreak++;
      if (emptyStreak >= 3) { console.log('3 empty pages in a row — stopping'); break; }
    } else {
      emptyStreak = 0;
    }
    // incremental save every 10 pages
    if (p % 10 === 9) {
      fs.writeFileSync(outPath, JSON.stringify([...byPid.values()], null, 0));
    }
  } catch (e) {
    console.log(`page ${p} error: ${String(e).slice(0, 120)}`);
  }
  if (p < MAX_PAGES - 1) await new Promise((r) => setTimeout(r, SLEEP_MS));
}

fs.writeFileSync(outPath, JSON.stringify([...byPid.values()], null, 0));
console.log(`DONE total_unique=${byPid.size} duration=${Math.round((Date.now()-startTime)/1000)}s`);
