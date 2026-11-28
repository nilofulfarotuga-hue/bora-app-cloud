// cleaning-plan-charge/regras.ts — a parte pura (sem rede) do robô que cobra os planos de limpeza.
// Missão limpeza-planos-fecho-2026-11-28 (Bloco B, PROPOSTA). Testes: regras_test.ts.

/** Resultado de uma tentativa, nas palavras que cleaning_plan_charge_result entende. */
export type Resultado = 'succeeded' | 'processing' | 'requires_action' | 'card_error' | 'transient';

/** Estado de um PaymentIntent já criado → resultado. */
export function resultadoDoPi(status: string | null | undefined): Resultado {
  switch (status) {
    case 'succeeded': return 'succeeded';
    case 'processing': return 'processing';
    case 'requires_action':
    case 'requires_confirmation': return 'requires_action';
    case 'requires_payment_method':
    case 'canceled': return 'card_error';
    default: return 'transient';
  }
}

/**
 * Erro da Stripe ao criar/confirmar fora de sessão → resultado.
 * Cartão recusado/expirado conta como tentativa; o banco a pedir autenticação passa a
 * 'requires_action'; rede ou erro da Stripe que não é do cartão NÃO conta (repete com a mesma chave).
 */
export function resultadoDoErro(err: unknown): { resultado: Resultado; piId: string | null; mensagem: string } {
  // deno-lint-ignore no-explicit-any
  const e = (err ?? {}) as any;
  const tipo = String(e?.type ?? e?.rawType ?? '');
  const codigo = String(e?.code ?? e?.raw?.code ?? '');
  const pi = e?.raw?.payment_intent ?? e?.payment_intent ?? null;
  const piId = typeof pi?.id === 'string' ? pi.id : null;
  const mensagem = String(e?.message ?? e?.raw?.message ?? 'erro').slice(0, 300);
  if (codigo === 'authentication_required' || pi?.status === 'requires_action') {
    return { resultado: 'requires_action', piId, mensagem };
  }
  if (tipo === 'StripeCardError' || tipo === 'card_error') {
    return { resultado: 'card_error', piId, mensagem };
  }
  return { resultado: 'transient', piId, mensagem };
}

/** Chave de idempotência da Stripe por tentativa (vem já feita do banco; aqui só se confere). */
export function chaveValida(chave: unknown): chave is string {
  return typeof chave === 'string' && /^cleaning-plan-(visit|month)-[0-9a-f-]+(-\d{4}-\d{2})?-a\d+$/.test(chave);
}

/** "Bora · Limpeza plano · 12/2026" ou "Bora · Bora Empresas · 12/2026 · Ótica X · NIF 123456789". */
export function descricao(c: { segment?: string | null; period_month?: string | null; company_name?: string | null; billing_nif?: string | null }): string {
  const partes = ['Bora', c.segment === 'empresa' ? 'Bora Empresas' : 'Limpeza plano'];
  if (c.period_month) partes.push(c.period_month);
  if (c.segment === 'empresa' && c.company_name) partes.push(c.company_name);
  if (c.segment === 'empresa' && c.billing_nif) partes.push(`NIF ${c.billing_nif}`);
  return partes.join(' · ').slice(0, 350);
}

/** Resumo que o robô devolve. */
export interface Resumo { cobradas: number; falhadas: number; autenticacao: number; presas: number; devolvidas: number; erros: number }
export function resumoVazio(): Resumo { return { cobradas: 0, falhadas: 0, autenticacao: 0, presas: 0, devolvidas: 0, erros: 0 }; }
export function contar(r: Resumo, resultado: Resultado): Resumo {
  const n = { ...r };
  if (resultado === 'succeeded') n.cobradas++;
  else if (resultado === 'card_error') n.falhadas++;
  else if (resultado === 'requires_action') n.autenticacao++;
  else n.presas++;   // processing (o webhook acaba) ou rede (repete com a mesma chave)
  return n;
}

/** Texto do email "o pagamento não passou — troca o cartão" (HTML simples, PT-PT). */
export function emailTrocarCartao(o: { amountCents: number; final: boolean; quando: string }): { assunto: string; html: string } {
  const euros = (o.amountCents / 100).toFixed(2).replace('.', ',') + ' €';
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return o.final
    ? {
      assunto: 'A tua limpeza foi desmarcada: o pagamento não passou',
      html: `<p>Olá,</p><p>Não conseguimos cobrar ${esc(euros)} no teu cartão pela limpeza de ${esc(o.quando)}, por isso desmarcámos essa limpeza e não pagas nada.</p><p>Para as próximas, troca o cartão na app: <b>Limpeza → O meu plano → Trocar cartão</b>.</p><p>Bora</p>`,
    }
    : {
      assunto: 'O pagamento da tua limpeza não passou — troca o cartão',
      html: `<p>Olá,</p><p>O pagamento de ${esc(euros)} da tua limpeza${o.quando ? ' de ' + esc(o.quando) : ''} não passou. Vamos tentar outra vez.</p><p>Para não perderes a limpeza, troca o cartão na app: <b>Limpeza → O meu plano → Trocar cartão</b>.</p><p>Bora</p>`,
    };
}
