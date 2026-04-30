import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ─── Category mapping ES → PT ────────────────────────────────────────────────

function mapCategoryPT(catES: string): string {
  const lower = catES.toLowerCase();
  if (/aceite|arroz|legumbre|pasta|conserva|tomate|salsa|azucar|harina|vinagre|sopa|caldo/.test(lower)) return 'Mercearia';
  if (/agua|refresco|cerveza|vino|cafe|zumo|infusion|ron|cava|whisky|licor|sidra/.test(lower)) return 'Bebidas';
  if (/aperitivo|patatas|frutos secos|snack|aceituna/.test(lower)) return 'Snacks';
  if (/chocolate|caramelo|dulce|cacao/.test(lower)) return 'Chocolates e Doces';
  if (/bebe|infantil|nino/.test(lower)) return 'Bebé';
  if (/carne|pollo|ternera|cerdo|cordero|pavo/.test(lower)) return 'Carne';
  if (/pescado|marisco|salmon|atun|merluza|bacalao/.test(lower)) return 'Peixe';
  if (/congelado/.test(lower)) return 'Congelados';
  if (/detergente|limpieza|suavizante|fregasuelos/.test(lower)) return 'Limpeza';
  if (/fruta|fresa|platano|naranja|manzana/.test(lower)) return 'Frutas';
  if (/verdura|hortaliza|lechuga|cebolla|zanahoria/.test(lower)) return 'Legumes';
  if (/higiene|jabon|desodorante|gel|champu|papel/.test(lower)) return 'Higiene';
  if (/lacteo|leche|yogur|mantequilla|margarina|nata/.test(lower)) return 'Laticínios';
  if (/queso|embutido|charcuteria|jamon|salchich|chorizo/.test(lower)) return 'Charcutaria';
  if (/mascota|gato|perro/.test(lower)) return 'Animais';
  if (/pan |bolleria|galleta|bizcocho|croissant/.test(lower)) return 'Padaria';
  if (/menaje|hogar|cocina|casa|basura/.test(lower)) return 'Casa';
  return 'Mercearia';
}

// ─── Mercadona updater (legado, preservado) ─────────────────────────────────

async function updateMercadona(): Promise<{ inserted: number; updated: number; errors: number }> {
  const RESTAURANT_ID = 'mercadona-guarda';
  const HEADERS = { 'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json' };

  let inserted = 0;
  let updated = 0;
  let errors = 0;

  const topRes = await fetch('https://tienda.mercadona.es/api/categories/', { headers: HEADERS });
  if (!topRes.ok) throw new Error(`Mercadona top-level fetch failed: ${topRes.status}`);
  const topData = await topRes.json();

  for (const top of (topData.results ?? [])) {
    for (const sub of (top.categories ?? [])) {
      await new Promise((r) => setTimeout(r, 300));

      const subRes = await fetch(`https://tienda.mercadona.es/api/categories/${sub.id}/`, { headers: HEADERS });
      if (!subRes.ok) { errors++; continue; }
      const subData = await subRes.json();

      for (const innerSub of (subData.categories ?? [])) {
        const category = mapCategoryPT(innerSub.name ?? '');

        for (const product of (innerSub.products ?? [])) {
          const price = parseFloat(product.price_instructions?.bulk_price ?? '0');
          const row = {
            id: `merc-${product.id}`,
            restaurant_id: RESTAURANT_ID,
            name: product.display_name ?? '',
            price,
            photo_url: product.thumbnail ?? '',
            category,
            unit: product.packaging ?? '',
            description: innerSub.name ?? '',
            is_available: true,
            is_popular: false,
            is_on_sale: false,
          };

          const { error } = await supabase.from('products').upsert(row, { onConflict: 'id' });
          if (error) { errors++; } else { updated++; }
        }
      }
    }
  }

  return { inserted, updated, errors };
}

// ─── SFCC helpers (Fase 5 — Continente + Auchan) ─────────────────────────────

type SfccConfig = {
  restaurantId: string;
  idPrefix: string;
  sourceBase: string;
  host: string;
  sitePath: string;
  parser: 'impression' | 'gtm';
  catalogMarker: RegExp;
};

const SFCC: Record<string, SfccConfig> = {
  continente: {
    restaurantId: 'continente-guarda',
    idPrefix: 'cnt-',
    sourceBase: 'continente_sfcc_bestsellers',
    host: 'www.continente.pt',
    sitePath: '/on/demandware.store/Sites-continente-Site/default',
    parser: 'impression',
    catalogMarker: /Sites-col-master-catalog/i,
  },
  auchan: {
    restaurantId: 'auchan-guarda',
    idPrefix: 'auc-',
    sourceBase: 'auchan_sfcc_bestsellers',
    host: 'www.auchan.pt',
    sitePath: '/on/demandware.store/Sites-AuchanPT-Site/pt',
    parser: 'gtm',
    catalogMarker: /Sites-auchan-pt-master-catalog/i,
  },
};

const SFCC_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'X-Requested-With': 'XMLHttpRequest',
  'Accept-Language': 'pt-PT,pt;q=0.9',
  'Accept': 'text/html,application/xhtml+xml',
};

const decodeEntities = (s: string) =>
  s
    // XML/HTML core
    .replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    // Portuguese / Latin-1 named entities
    .replace(/&aacute;/g, 'á').replace(/&Aacute;/g, 'Á')
    .replace(/&agrave;/g, 'à').replace(/&Agrave;/g, 'À')
    .replace(/&atilde;/g, 'ã').replace(/&Atilde;/g, 'Ã')
    .replace(/&acirc;/g, 'â').replace(/&Acirc;/g, 'Â')
    .replace(/&auml;/g, 'ä').replace(/&Auml;/g, 'Ä')
    .replace(/&aring;/g, 'å').replace(/&Aring;/g, 'Å')
    .replace(/&eacute;/g, 'é').replace(/&Eacute;/g, 'É')
    .replace(/&egrave;/g, 'è').replace(/&Egrave;/g, 'È')
    .replace(/&ecirc;/g, 'ê').replace(/&Ecirc;/g, 'Ê')
    .replace(/&euml;/g, 'ë').replace(/&Euml;/g, 'Ë')
    .replace(/&iacute;/g, 'í').replace(/&Iacute;/g, 'Í')
    .replace(/&igrave;/g, 'ì').replace(/&Igrave;/g, 'Ì')
    .replace(/&icirc;/g, 'î').replace(/&Icirc;/g, 'Î')
    .replace(/&iuml;/g, 'ï').replace(/&Iuml;/g, 'Ï')
    .replace(/&oacute;/g, 'ó').replace(/&Oacute;/g, 'Ó')
    .replace(/&ograve;/g, 'ò').replace(/&Ograve;/g, 'Ò')
    .replace(/&otilde;/g, 'õ').replace(/&Otilde;/g, 'Õ')
    .replace(/&ocirc;/g, 'ô').replace(/&Ocirc;/g, 'Ô')
    .replace(/&ouml;/g, 'ö').replace(/&Ouml;/g, 'Ö')
    .replace(/&uacute;/g, 'ú').replace(/&Uacute;/g, 'Ú')
    .replace(/&ugrave;/g, 'ù').replace(/&Ugrave;/g, 'Ù')
    .replace(/&ucirc;/g, 'û').replace(/&Ucirc;/g, 'Û')
    .replace(/&uuml;/g, 'ü').replace(/&Uuml;/g, 'Ü')
    .replace(/&ccedil;/g, 'ç').replace(/&Ccedil;/g, 'Ç')
    .replace(/&ntilde;/g, 'ñ').replace(/&Ntilde;/g, 'Ñ')
    .replace(/&szlig;/g, 'ß')
    .replace(/&euro;/g, '€').replace(/&pound;/g, '£')
    .replace(/&nbsp;/g, ' ').replace(/&shy;/g, '')
    .replace(/&reg;/g, '®').replace(/&copy;/g, '©').replace(/&trade;/g, '™')
    // Numeric decimal entities &#NNN;
    .replace(/&#(\d+);/g, (_: string, n: string) => String.fromCharCode(parseInt(n, 10)))
    // Numeric hex entities &#xHHH;
    .replace(/&#x([0-9a-fA-F]+);/g, (_: string, h: string) => String.fromCharCode(parseInt(h, 16)));

function titleCase(s: string): string {
  return s.toLowerCase().split(/\s+/)
    .map((w) => w.length ? w[0].toUpperCase() + w.slice(1) : w).join(' ');
}

function normCategory(raw: string): string {
  const parts = raw.split('/').map((p) => p.replace(/-/g, ' ').trim())
    .filter((p) => p && !/^(produtos|catalogo)/i.test(p))
    .map(titleCase);
  return parts.slice(0, 3).join(' / ');
}

async function fetchSfccPage(cfg: SfccConfig, start: number): Promise<string> {
  const url =
    `https://${cfg.host}${cfg.sitePath}/Search-UpdateGrid` +
    `?srule=best-sellers&start=${start}&sz=48&cgid=root`;
  const res = await fetch(url, { headers: SFCC_HEADERS });
  if (!res.ok) throw new Error(`HTTP ${res.status} at start=${start}`);
  return await res.text();
}

type ParsedRow = {
  pid: string;
  name: string;
  price: number;
  brand: string | null;
  category: string | null;
  photo_url: string;
};

function parseImpression(html: string, cfg: SfccConfig): ParsedRow[] {
  const rows: ParsedRow[] = [];
  const re = /data-product-tile-impression='([^']+)'[\s\S]{0,6000}?<img[^>]+(?:data-src|src)="([^"]+)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    try {
      const json = JSON.parse(decodeEntities(m[1]));
      const img = decodeEntities(m[2]);
      if (/\/badges\//i.test(img)) continue;
      if (!cfg.catalogMarker.test(img)) continue;
      const pid = String(json.id ?? json.sku ?? '').trim();
      const name = String(json.name ?? '').trim();
      const price = Number(json.price ?? 0);
      if (!pid || !name || !(price > 0)) continue;
      rows.push({
        pid, name, price,
        brand: json.brand ? String(json.brand) : null,
        category: json.category ? String(json.category) : null,
        photo_url: img,
      });
    } catch { /* skip */ }
  }
  return rows;
}

function parseGtm(html: string, cfg: SfccConfig): ParsedRow[] {
  const rows: ParsedRow[] = [];
  const re = /data-gtm="([^"]+)"[\s\S]{0,8000}?<img[^>]+(?:data-src|src)="([^"]+)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    try {
      const json = JSON.parse(decodeEntities(m[1]));
      const img = decodeEntities(m[2]);
      if (/\/badges\//i.test(img)) continue;
      if (!cfg.catalogMarker.test(img)) continue;
      const pid = String(json.id ?? json.item_id ?? '').trim();
      const nameRaw = String(json.name ?? json.item_name ?? '').trim();
      const price = Number(json.price ?? 0);
      if (!pid || !nameRaw || !(price > 0)) continue;
      rows.push({
        pid,
        name: titleCase(nameRaw),
        price,
        brand: json.brand ? titleCase(String(json.brand)) : null,
        category: json.category ? normCategory(String(json.category))
          : json.item_category ? normCategory(String(json.item_category)) : null,
        photo_url: img,
      });
    } catch { /* skip */ }
  }
  return rows;
}

async function updateSfccMarket(
  marketKey: 'continente' | 'auchan',
  pages: number,
  sleepMs: number,
  maxUpdates: number,
): Promise<{ run_id: string; scraped: number; inserted: number; updated: number; failed: number; duration_ms: number; status: string; error: string | null }> {
  const cfg = SFCC[marketKey];
  const started = Date.now();

  const { data: runIns, error: runErr } = await supabase
    .from('product_update_runs')
    .insert({
      market: cfg.restaurantId,
      source: `${cfg.sourceBase}_auto`,
      status: 'running',
    })
    .select('id')
    .single();
  if (runErr || !runIns) throw new Error(`cannot open run: ${runErr?.message}`);
  const runId = runIns.id as string;

  let scraped = 0;
  let inserted = 0;
  let updated = 0;
  let failed = 0;
  let errorMsg: string | null = null;

  try {
    const byPid = new Map<string, ParsedRow>();
    for (let p = 0; p < pages; p++) {
      try {
        const html = await fetchSfccPage(cfg, p * 48);
        const rows = cfg.parser === 'impression'
          ? parseImpression(html, cfg)
          : parseGtm(html, cfg);
        for (const r of rows) if (!byPid.has(r.pid)) byPid.set(r.pid, r);
        scraped = byPid.size;
      } catch (e) {
        failed++;
        console.error(`page ${p} failed`, e);
      }
      if (p < pages - 1) await new Promise((r) => setTimeout(r, sleepMs));
    }

    const allIds = [...byPid.keys()].map((pid) => `${cfg.idPrefix}${pid}`);
    // Fetch existing ids in chunks (in() has URL length limits)
    const existingSet = new Set<string>();
    for (let i = 0; i < allIds.length; i += 500) {
      const chunk = allIds.slice(i, i + 500);
      const { data: ex } = await supabase.from('products').select('id').in('id', chunk);
      for (const r of ex ?? []) existingSet.add(r.id as string);
    }

    const toInsert: Array<Record<string, unknown>> = [];
    const toUpdate: Array<Record<string, unknown>> = [];
    const today = new Date().toISOString().slice(0, 10);
    for (const [pid, r] of byPid) {
      const id = `${cfg.idPrefix}${pid}`;
      const common = {
        name: r.name,
        price: r.price,
        category: r.category,
        brand_low: r.brand,
        photo_url: r.photo_url,
        image_source: 'L1',
        needs_photo: false,
        is_available: true,
      };
      if (existingSet.has(id)) {
        toUpdate.push({ id, ...common });
      } else {
        toInsert.push({
          id,
          restaurant_id: cfg.restaurantId,
          source: `${cfg.sourceBase}_${today}`,
          ...common,
        });
      }
    }

    for (let i = 0; i < toInsert.length; i += 200) {
      const chunk = toInsert.slice(i, i + 200);
      const { error } = await supabase.from('products').insert(chunk);
      if (error) { failed += chunk.length; console.error('insert chunk error', error); }
      else { inserted += chunk.length; }
    }

    const cap = Math.min(toUpdate.length, maxUpdates);
    for (let i = 0; i < cap; i++) {
      const u = toUpdate[i];
      const { error } = await supabase.from('products').update({
        name: u.name,
        price: u.price,
        photo_url: u.photo_url,
        category: u.category,
        brand_low: u.brand_low,
        is_available: true,
      }).eq('id', u.id);
      if (error) failed++; else updated++;
    }
  } catch (e) {
    errorMsg = String(e instanceof Error ? e.message : e);
  }

  const durationMs = Date.now() - started;
  const status = errorMsg ? 'error' : 'ok';
  await supabase.from('product_update_runs').update({
    scraped, inserted, updated, failed,
    duration_ms: durationMs, status, error: errorMsg,
  }).eq('id', runId);

  return { run_id: runId, scraped, inserted, updated, failed, duration_ms: durationMs, status, error: errorMsg };
}

// ─── Cross-match updater (Pingo Doce, Lidl, Intermarché) — legado ───────────

async function updateCrossMatch(market: string): Promise<{ message: string }> {
  const marketMap: Record<string, string> = {
    pingodoce: 'pingodoce-guarda',
    lidl: 'lidl-guarda',
    intermarche: 'intermarche-guarda',
  };

  const restaurantId = marketMap[market];
  if (!restaurantId) return { message: `Unknown market: ${market}` };

  const { data: products, error } = await supabase
    .from('products')
    .select('id, name, price')
    .eq('restaurant_id', restaurantId)
    .or('photo_url.is.null,photo_url.eq.');

  if (error) throw error;
  if (!products?.length) return { message: `No products without photos for ${market}` };

  // T11: pre-fetch mercadona restaurant ids by NAME (not by id-prefix), so the
  // refactor restaurants.id TEXT->UUID (decisions/2026-04-29-restaurants-id-uuid-refactor.md)
  // does not break this code. Lookup is constant per call (~5 rows).
  const { data: mercRestaurants } = await supabase
    .from('restaurants')
    .select('id')
    .ilike('name', 'Mercadona%');
  const mercIds: string[] = (mercRestaurants ?? []).map((r: { id: string }) => r.id);

  if (mercIds.length === 0) {
    return { message: `No Mercadona restaurants found — cannot enrich photos for ${market}` };
  }

  let matched = 0;

  for (const product of products) {
    const { data: mercProducts } = await supabase
      .from('products')
      .select('id, name, photo_url, price')
      .in('restaurant_id', mercIds)
      .ilike('name', `%${product.name.split(' ')[0]}%`)
      .limit(1);

    if (mercProducts?.length) {
      const merc = mercProducts[0];
      const priceDiff = Math.abs(product.price - merc.price) / (merc.price || 1);

      const updates: Record<string, unknown> = {};
      if (!product.photo_url && merc.photo_url) updates.photo_url = merc.photo_url;
      if (priceDiff > 0.1) updates.price = merc.price;

      if (Object.keys(updates).length) {
        await supabase.from('products').update(updates).eq('id', product.id);
        matched++;
      }
    }
  }

  return { message: `Cross-matched ${matched} products for ${market}` };
}

// ─── Main handler ────────────────────────────────────────────────────────────

serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    const market: string = body.market ?? 'mercadona';
    const pages: number = Math.min(Math.max(Number(body.pages ?? 30), 1), 90);
    const sleepMs: number = Math.max(Number(body.sleepMs ?? 1000), 1000); // BR §27.5
    const maxUpdates: number = Math.min(Math.max(Number(body.maxUpdates ?? 500), 0), 2000);

    let result: unknown;

    switch (market) {
      case 'mercadona':
        result = await updateMercadona();
        break;
      case 'continente':
      case 'auchan':
        result = await updateSfccMarket(market, pages, sleepMs, maxUpdates);
        break;
      case 'pingodoce':
      case 'lidl':
      case 'intermarche':
        result = await updateCrossMatch(market);
        break;
      case 'restaurants':
        result = { message: 'Restaurant menu update not yet implemented' };
        break;
      default:
        return new Response(JSON.stringify({ error: `Unknown market: ${market}` }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
    }

    return new Response(JSON.stringify({ ok: true, market, result }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
