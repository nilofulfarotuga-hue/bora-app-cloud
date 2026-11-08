// =============================================================================
// connect-convite — link PERMANENTE de cadastro Stripe Connect (M7, 08/11/2026).
//
// Porquê: o Account Link da Stripe expira em poucos minutos, mas o link que vai por WhatsApp
// ao parceiro/estafeta tem de funcionar quando ele o abrir. Este endpoint recebe o convite
// (?t=<token>, criado no painel por admin_connect_convite) e, a cada abertura, gera um link
// novo da Stripe e redireciona (302).
//
// verify_jwt = false (quem abre não tem sessão). A segurança é o token: 64 caracteres
// aleatórios, guardado em public.connect_convites (só service role), revogável no painel.
// - Conta ainda por ativar → link de cadastro (onboarding) na plataforma certa.
// - Conta já ativa → painel Express da Stripe (a Stripe pede código por SMS ao dono).
// Não move dinheiro. Não devolve dados pessoais: só redireciona ou mostra uma página simples.
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import {
  ehPapelConnect,
  garantirContaConnect,
  linkConnect,
  TABELAS_CONNECT,
  tokenConviteValido,
} from '../_shared/connect_conta.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', secretKey() ?? '');

function pagina(titulo: string, texto: string, status = 200): Response {
  const html = `<!doctype html><html lang="pt-PT"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Bora</title>
<style>body{font-family:Inter,Arial,sans-serif;background:#f6f7f6;color:#1f2937;margin:0;padding:32px 16px}
.c{max-width:420px;margin:0 auto;background:#fff;border-radius:16px;padding:24px;box-shadow:0 2px 10px #0001}
h1{color:#16A34A;font-size:20px;margin:0 0 12px}p{line-height:1.5}</style></head>
<body><div class="c"><h1>${titulo}</h1><p>${texto}</p></div></body></html>`;
  return new Response(html, { status, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}

const AJUDA = 'Se precisares de ajuda, fala com a Bora pelo WhatsApp 937 501 673.';

Deno.serve(async (req: Request) => {
  if (req.method !== 'GET') return new Response('method_not_allowed', { status: 405 });

  const token = new URL(req.url).searchParams.get('t') ?? '';
  if (!tokenConviteValido(token)) {
    return pagina('Link incompleto', `Este link de cadastro não está completo. ${AJUDA}`, 400);
  }

  try {
    const { data: convite, error: convErr } = await admin
      .from('connect_convites')
      .select('token, role, row_id, revogado_em, usos')
      .eq('token', token)
      .maybeSingle();
    if (convErr) throw new Error(`convite_lookup: ${convErr.message}`);
    if (!convite || convite.revogado_em || !ehPapelConnect(convite.role)) {
      return pagina('Link já não é válido', `Este link de cadastro foi substituído ou cancelado. ${AJUDA}`, 410);
    }

    const tabela = TABELAS_CONNECT[convite.role];
    const { data: linha, error: linhaErr } = await admin
      .from(tabela)
      .select('*')
      .eq('id', convite.row_id)
      .maybeSingle();
    if (linhaErr) throw new Error(`linha_lookup: ${linhaErr.message}`);
    if (!linha) {
      return pagina('Link já não é válido', `Não encontrámos a conta deste link. ${AJUDA}`, 404);
    }

    const { stripe, conta, accountId, criada } = await garantirContaConnect(admin, convite.role, linha, {
      bora_convite: 'true',
    });
    const ativa = !criada && linha.stripe_account_status === 'enabled';
    const link = await linkConnect(stripe, accountId, ativa);

    await admin
      .from('connect_convites')
      .update({ usos: (convite.usos ?? 0) + 1, ultimo_uso_em: new Date().toISOString() })
      .eq('token', token);

    console.log('[connect-convite]', convite.role, convite.row_id, '->', accountId, 'plataforma:', conta, link.kind);
    return new Response(null, { status: 302, headers: { Location: link.url, 'Cache-Control': 'no-store' } });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[connect-convite] erro:', msg);
    return pagina('Não foi possível abrir agora', `Tenta outra vez daqui a uns minutos. ${AJUDA}`, 503);
  }
});
