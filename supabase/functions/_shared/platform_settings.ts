// supabase/functions/_shared/platform_settings.ts
//
// Helper para ler settings dinamicos de platform_settings (Postgres)
// em runtime. Substitui constantes hardcoded em business_rules.ts
// para valores que admin pode alterar via painel.
//
// Sessao: 7-alpha-CANCEL-FEES-REFACTOR (2026-05-08)
// Source of truth: tabela platform_settings.
// Fallback: valores hardcoded (defensive -- DB pode falhar).

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export interface CancelFees {
  beforeDispatchEur: number;
  afterAcceptEur: number;
  afterPickupRatio: number;
}

// Fallbacks alinhados com platform_settings prod em 2026-05-08.
// Se BD falhar, helper usa estes valores e regista WARN.
const FALLBACK_FEES: CancelFees = {
  beforeDispatchEur: 1.50,
  afterAcceptEur: 2.50,
  afterPickupRatio: 1.00,
};

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutos

interface CacheEntry {
  fees: CancelFees;
  fetchedAt: number;
}

let cache: CacheEntry | null = null;
let cachedClient: SupabaseClient | null = null;

function getAdminClient(): SupabaseClient {
  if (cachedClient) return cachedClient;
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !serviceKey) {
    throw new Error('platform_settings: SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY ausentes');
  }
  cachedClient = createClient(url, serviceKey);
  return cachedClient;
}

// deno-lint-ignore no-explicit-any
function parseJsonbNumber(val: any, fallback: number): number {
  if (typeof val === 'number' && isFinite(val)) return val;
  if (typeof val === 'string') {
    const n = Number(val);
    if (isFinite(n)) return n;
  }
  return fallback;
}

/**
 * Le os 3 cancel fees de platform_settings.
 *
 * - Cache em memoria (5min) para reduzir queries DB.
 * - Fallback defensivo se BD falhar.
 * - Logging WARN quando usa fallback (visivel em Edge Function logs).
 *
 * Retorna sempre um CancelFees valido -- nunca lanca.
 */
export async function getCancelFees(): Promise<CancelFees> {
  // Cache hit
  if (cache && (Date.now() - cache.fetchedAt) < CACHE_TTL_MS) {
    return cache.fees;
  }

  try {
    const admin = getAdminClient();
    const { data, error } = await admin
      .from('platform_settings')
      .select('key, value')
      .in('key', [
        'cancel_fee_before_dispatch_cents',
        'cancel_fee_after_accept_cents',
        'cancel_fee_after_pickup_ratio',
      ]);

    if (error) {
      console.warn('[platform_settings] DB error reading cancel fees, using fallback:', error.message);
      return FALLBACK_FEES;
    }

    if (!data || data.length === 0) {
      console.warn('[platform_settings] No cancel fee settings found, using fallback');
      return FALLBACK_FEES;
    }

    // deno-lint-ignore no-explicit-any
    const map: Record<string, any> = {};
    for (const row of data) {
      map[row.key] = row.value;
    }

    const beforeCents = parseJsonbNumber(map['cancel_fee_before_dispatch_cents'], FALLBACK_FEES.beforeDispatchEur * 100);
    const afterCents = parseJsonbNumber(map['cancel_fee_after_accept_cents'], FALLBACK_FEES.afterAcceptEur * 100);
    const ratio = parseJsonbNumber(map['cancel_fee_after_pickup_ratio'], FALLBACK_FEES.afterPickupRatio);

    const fees: CancelFees = {
      beforeDispatchEur: beforeCents / 100,
      afterAcceptEur: afterCents / 100,
      afterPickupRatio: ratio,
    };

    cache = { fees, fetchedAt: Date.now() };
    return fees;
  } catch (e) {
    console.warn('[platform_settings] Exception reading cancel fees, using fallback:', e);
    return FALLBACK_FEES;
  }
}

/**
 * Calcula cancel fee em EUR baseado no tier de cancelamento + total da order.
 * Helper conveniente para as 3 Edge Functions de cancelamento.
 */
export function computeCancelFeeEur(
  tier: 'before_dispatch' | 'after_accept' | 'after_pickup' | 'invalid',
  totalEur: number,
  fees: CancelFees,
): number {
  switch (tier) {
    case 'before_dispatch': return fees.beforeDispatchEur;
    case 'after_accept': return fees.afterAcceptEur;
    case 'after_pickup': return totalEur * fees.afterPickupRatio;
    case 'invalid': return 0;
  }
}
