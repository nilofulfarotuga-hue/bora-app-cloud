// =============================================================================
// _shared/connect_conta.ts — Stripe Connect com DUAS contas de plataforma (M7, 08/11/2026).
//
// Regra do Danilo (stripe-duas-contas, 01/11): a Stripe PESSOAL fica só para o Bora Motorista
// (TVDE); a da EMPRESA fica para tudo o resto. As contas Connect (parceiros, estafetas) passam
// a nascer na empresa quando o interruptor platform_settings.stripe_connect_conta_nova = 'empresa'.
// Por defeito o interruptor é 'pessoal' — nada muda até a Claude.ai/Danilo o virar.
//
// NÃO move dinheiro: só cria a conta Express, guarda o id e devolve links.
// Tolerante à migração por aplicar: sem a coluna stripe_account_owner, tudo conta como 'pessoal'.
// =============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { contaGravada, stripePara, type ContaStripe } from './stripe_contas.ts';

// deno-lint-ignore no-explicit-any
type Cliente = any;

export type PapelConnect = 'partner' | 'provider' | 'driver' | 'cleaner';

export const TABELAS_CONNECT: Record<PapelConnect, string> = {
  partner: 'restaurants',
  provider: 'service_providers',
  driver: 'drivers',
  cleaner: 'cleaners',
};

/** A Stripe só aceita http(s) nos Account Links; o retorno é sempre o web app. */
export const RETORNO_CONNECT = 'https://bora-app-web.pages.dev';

export const SETTING_CONTA_NOVA = 'stripe_connect_conta_nova';

export function ehPapelConnect(valor: unknown): valor is PapelConnect {
  return typeof valor === 'string' && valor in TABELAS_CONNECT;
}

export interface LinhaConnect {
  id: string | number;
  name?: string | null;
  stripe_account_id?: string | null;
  stripe_account_status?: string | null;
  stripe_account_owner?: string | null;
}

export type DecisaoConnect =
  | { acao: 'usar'; conta: ContaStripe; accountId: string }
  | { acao: 'criar'; conta: ContaStripe; contaAntiga: { conta: ContaStripe; accountId: string } | null };

/**
 * Decide, sem rede, o que fazer com a conta Connect de uma linha.
 * - Sem conta → criar na conta-alvo.
 * - Conta na conta-alvo → usar.
 * - Conta noutra plataforma (ex.: pessoal) e alvo diferente → criar nova no alvo
 *   (a antiga fica registada na auditoria; não se apaga nada na Stripe).
 */
export function decidirContaConnect(linha: LinhaConnect, alvo: ContaStripe): DecisaoConnect {
  const accountId = (linha.stripe_account_id ?? '').trim();
  const dona = contaGravada(linha.stripe_account_owner);
  if (!accountId) return { acao: 'criar', conta: alvo, contaAntiga: null };
  if (dona === alvo) return { acao: 'usar', conta: dona, accountId };
  return { acao: 'criar', conta: alvo, contaAntiga: { conta: dona, accountId } };
}

/** Lê o interruptor. Qualquer falha ou valor estranho = 'pessoal' (o caminho que já funcionava). */
export async function lerContaConnectNova(admin: Cliente): Promise<ContaStripe> {
  try {
    const { data, error } = await admin
      .from('platform_settings')
      .select('value')
      .eq('key', SETTING_CONTA_NOVA)
      .maybeSingle();
    if (error || !data) return 'pessoal';
    return contaGravada(data.value);
  } catch {
    return 'pessoal';
  }
}

/** Conta Stripe (cliente) que gere a conta Connect já gravada na linha. */
export function stripeDaLinhaConnect(linha: LinhaConnect): { stripe: Stripe; conta: ContaStripe } {
  const conta = contaGravada(linha.stripe_account_owner);
  return { stripe: stripePara(conta), conta };
}

/**
 * Garante uma conta Connect na plataforma certa e devolve o cliente Stripe dessa plataforma.
 * Quando cria, grava stripe_account_id + estado 'pending' (+ stripe_account_owner se não for 'pessoal').
 */
export async function garantirContaConnect(
  admin: Cliente,
  papel: PapelConnect,
  linha: LinhaConnect,
  metadata: Record<string, string>,
): Promise<{ stripe: Stripe; conta: ContaStripe; accountId: string; criada: boolean }> {
  const alvo = await lerContaConnectNova(admin);
  const decisao = decidirContaConnect(linha, alvo);
  const stripe = stripePara(decisao.conta);

  if (decisao.acao === 'usar') {
    return { stripe, conta: decisao.conta, accountId: decisao.accountId, criada: false };
  }

  const account = await stripe.accounts.create({
    type: 'express',
    country: 'PT',
    default_currency: 'eur',
    capabilities: { transfers: { requested: true } },
    business_type: papel === 'partner' || papel === 'provider' ? 'company' : 'individual',
    metadata: { ...metadata, bora_role: papel, bora_row_id: String(linha.id), bora_plataforma: decisao.conta },
  });

  const atualizacao: Record<string, unknown> = {
    stripe_account_id: account.id,
    stripe_account_status: 'pending',
    stripe_charges_enabled: false,
    stripe_payouts_enabled: false,
  };
  // Só escreve a coluna nova quando é preciso (a migração pode ainda não estar aplicada).
  if (decisao.conta !== 'pessoal' || decisao.contaAntiga) atualizacao.stripe_account_owner = decisao.conta;

  const { error } = await admin.from(TABELAS_CONNECT[papel]).update(atualizacao).eq('id', linha.id);
  if (error) throw new Error(`connect_gravar_falhou: ${error.message}`);

  if (decisao.contaAntiga) {
    // Auditoria da troca de plataforma (nunca se apaga a conta antiga na Stripe).
    await admin.from('stripe_connect_events').insert({
      event_id: `bora_troca_${papel}_${linha.id}_${Date.now()}`,
      type: 'bora.conta_connect_trocada',
      account_id: decisao.contaAntiga.accountId,
      payload: {
        papel,
        row_id: String(linha.id),
        de: decisao.contaAntiga.conta,
        para: decisao.conta,
        conta_antiga: decisao.contaAntiga.accountId,
        conta_nova: account.id,
      },
    });
  }

  return { stripe, conta: decisao.conta, accountId: account.id, criada: true };
}

/** Link para a pessoa: cadastro (Account Link, expira em minutos) ou, se já ativa, o painel Express. */
export async function linkConnect(
  stripe: Stripe,
  accountId: string,
  ativa: boolean,
): Promise<{ url: string; kind: 'onboarding' | 'login' }> {
  if (ativa) {
    const login = await stripe.accounts.createLoginLink(accountId);
    return { url: login.url, kind: 'login' };
  }
  const link = await stripe.accountLinks.create({
    account: accountId,
    type: 'account_onboarding',
    refresh_url: `${RETORNO_CONNECT}/connect/refresh`,
    return_url: `${RETORNO_CONNECT}/connect/return`,
  });
  return { url: link.url, kind: 'onboarding' };
}

/** Segredos de assinatura aceites pelo webhook de contas conectadas (pessoal primeiro). */
export function segredosWebhookConnect(): Array<{ conta: ContaStripe; segredo: string }> {
  const lista: Array<{ conta: ContaStripe; segredo: string }> = [];
  const pessoal = (Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET') ?? '').trim();
  const empresa = (Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET_EMPRESA') ?? '').trim();
  if (pessoal) lista.push({ conta: 'pessoal', segredo: pessoal });
  if (empresa) lista.push({ conta: 'empresa', segredo: empresa });
  return lista;
}

/** Token de convite válido: 40 a 128 caracteres hexadecimais. */
export function tokenConviteValido(token: unknown): token is string {
  return typeof token === 'string' && /^[0-9a-f]{40,128}$/.test(token);
}
