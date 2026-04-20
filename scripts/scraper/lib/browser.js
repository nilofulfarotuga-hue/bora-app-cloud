import { chromium } from 'playwright';

const USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
];

export async function launchBrowser() {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled',
      '--disable-infobars',
    ],
  });
  return browser;
}

export async function newPage(browser) {
  const ua = USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
  const context = await browser.newContext({
    userAgent: ua,
    viewport: { width: 1366, height: 768 },
    locale: 'pt-PT',
    timezoneId: 'Europe/Lisbon',
    extraHTTPHeaders: {
      'Accept-Language': 'pt-PT,pt;q=0.9,en;q=0.8',
    },
  });

  // Remove webdriver fingerprint
  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
  });

  const page = await context.newPage();
  return { page, context };
}

/** Random delay between min and max ms */
export function sleep(min = 800, max = 2500) {
  const ms = Math.floor(Math.random() * (max - min) + min);
  return new Promise(r => setTimeout(r, ms));
}

/** Retry wrapper — retries fn up to `attempts` times on error */
export async function withRetry(fn, attempts = 3, label = '') {
  for (let i = 1; i <= attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      console.warn(`  ⚠ ${label} — tentativa ${i}/${attempts}: ${err.message}`);
      if (i === attempts) throw err;
      await sleep(30000, 35000); // espera 30 s antes de retry
    }
  }
}
