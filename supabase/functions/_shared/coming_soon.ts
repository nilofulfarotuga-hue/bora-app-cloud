// supabase/functions/_shared/coming_soon.ts — v1 (2026-07-31)
//
// Guarda partilhado "Em breve" (coming_soon) para as Edge Functions de
// pagamento. Bloqueio só no Flutter não chega — uma app modificada contorna.
//
// Regra: NUNCA criar um PaymentIntent para uma loja/parceiro em "Em breve".
// A verificação corre ANTES de qualquer chamada ao Stripe.
//
// Não toca em preço, comissão, markup nem taxa — só rejeita.
//
// Defesa em profundidade: existem também triggers BEFORE INSERT em
// `orders`, `appointments` e `reservations` (migrations
// coming_soon_server_guard_functions / _triggers) que levantam o mesmo
// código de erro se algo escapar por aqui.

export const STORE_COMING_SOON = 'STORE_COMING_SOON';

export const COMING_SOON_ORDER_MSG =
  'Esta loja ainda não está a aceitar pedidos.';
export const COMING_SOON_BOOKING_MSG =
  'Este parceiro ainda não está a aceitar marcações.';
export const COMING_SOON_RESERVATION_MSG =
  'Esta loja ainda não está a aceitar reservas.';

/// Corpo de resposta uniforme para o cliente (HTTP 409).
export function comingSoonResponseBody(message: string) {
  return { error: message, code: STORE_COMING_SOON };
}

/// True quando `restaurants.coming_soon = true` para [restaurantId].
///
/// Em caso de erro de leitura devolve `false` (não inventa bloqueio) — os
/// triggers da base de dados continuam a ser a rede de segurança final.
// deno-lint-ignore no-explicit-any
export async function isRestaurantComingSoon(
  admin: any,
  restaurantId: string | null | undefined,
): Promise<boolean> {
  if (!restaurantId) return false;
  try {
    const { data, error } = await admin
      .from('restaurants')
      .select('coming_soon')
      .eq('id', restaurantId)
      .maybeSingle();
    if (error) {
      console.error('[coming-soon] restaurants lookup failed:', error.message);
      return false;
    }
    return data?.coming_soon === true;
  } catch (err) {
    console.error('[coming-soon] restaurants lookup threw:', err);
    return false;
  }
}

/// True quando `service_providers.coming_soon = true` para [providerId].
// deno-lint-ignore no-explicit-any
export async function isProviderComingSoon(
  admin: any,
  providerId: string | null | undefined,
): Promise<boolean> {
  if (!providerId) return false;
  try {
    const { data, error } = await admin
      .from('service_providers')
      .select('coming_soon')
      .eq('id', providerId)
      .maybeSingle();
    if (error) {
      console.error('[coming-soon] providers lookup failed:', error.message);
      return false;
    }
    return data?.coming_soon === true;
  } catch (err) {
    console.error('[coming-soon] providers lookup threw:', err);
    return false;
  }
}
