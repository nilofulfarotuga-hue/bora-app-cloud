// cleaning-plan/regras.ts — a parte pura (sem rede) da Edge que guarda o cartão dos planos.
// Missão limpeza-planos-fecho-2026-11-28 (Bloco B, PROPOSTA). Testes: regras_test.ts.

export const ACOES = ['setup', 'confirm_setup', 'action_secret', 'confirm_action'] as const;
export type Acao = typeof ACOES[number];

export function acaoValida(a: unknown): a is Acao {
  return typeof a === 'string' && (ACOES as readonly string[]).includes(a);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function uuidValido(v: unknown): v is string {
  return typeof v === 'string' && UUID.test(v);
}

/** Só se guarda/troca o cartão de um plano do próprio cliente ainda aberto. */
export function motivoRecusaSetup(o: { planoDoCliente: boolean; status: string | null | undefined }): string | null {
  if (!o.planoDoCliente) return 'plan_not_found';
  if (!['pending_card', 'active', 'paused'].includes(String(o.status ?? ''))) return 'plan_closed';
  return null;
}

/** O SetupIntent tem de estar 'succeeded', ser deste plano e deste cliente, e ter cartão. */
export function motivoRecusaConfirmar(o: {
  status: string | null | undefined; metaPlanId: unknown; metaUserId: unknown; metaKind: unknown;
  planId: string; userId: string; temCartao: boolean;
}): string | null {
  if (o.metaKind !== 'cleaning_plan_setup' || o.metaPlanId !== o.planId) return 'setup_not_completed';
  if (o.metaUserId !== o.userId) return 'setup_not_completed';
  if (o.status !== 'succeeded' || !o.temCartao) return 'setup_not_completed';
  return null;
}

/** confirm_action: o que a app vê ('succeeded' | 'processing' | 'failed') e o que se grava. */
export function depoisDoBanco(status: string | null | undefined): { app: 'succeeded' | 'processing' | 'failed'; resultado: string | null } {
  switch (status) {
    case 'succeeded': return { app: 'succeeded', resultado: 'succeeded' };
    case 'processing': return { app: 'processing', resultado: 'processing' };
    case 'requires_action':
    case 'requires_confirmation': return { app: 'failed', resultado: null };          // ainda por confirmar: não mexe
    default: return { app: 'failed', resultado: 'card_error' };                       // recusado / cancelado
  }
}

/** Mensagem ao cliente: sempre uma das palavras que a app traduz, nunca o erro cru. */
export function erroParaApp(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e ?? '');
  for (const k of ['plan_closed', 'plan_not_found', 'setup_not_completed', 'nada_para_confirmar', 'stripe_indisponivel']) {
    if (m.includes(k)) return k;
  }
  return 'erro';
}
