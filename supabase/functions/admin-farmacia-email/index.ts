// Edge Fn admin-farmacia-email — missão farmacias-loja-2026-11-14, Bloco 5 (painel admin).
//
// Troca o e-mail de LOGIN da conta do dono de uma farmácia (Supabase Auth) e o e-mail da loja
// (restaurants.email, que vários ecrãs antigos ainda usam para ligar a loja ao dono) pelo
// e-mail verdadeiro da farmácia. Por defeito também troca a senha por uma aleatória que ninguém
// conhece, para a senha de demonstração deixar de entrar.
//
// O link para a farmácia CRIAR a senha NÃO é mandado aqui: o painel chama logo a seguir a função
// que já existe, support-password-reset ({ user_id, email: <novo> }), que manda o e-mail de
// recuperação para a página /#/redefinir-palavra-passe e grava 'password_reset_sent' na auditoria.
//
// Porque é Edge Function e não SQL: mudar o e-mail de uma conta precisa da Auth Admin API (chave
// secreta). Não existia nenhuma função para isto (14/11: só sessao-convidado e upload-avatar usam
// auth.admin.updateUserById, para outras coisas).
//
// Quem pode chamar: só admin (app_metadata.role = 'admin', sessão confirmada no Auth pelo
// utilizadorDoPedido — a mesma regra de support-password-reset, admin-force-driver-logout e do
// public._is_admin). Só lojas category = 'pharmacy'. Recusa quando o dono é admin.
//
// Pedido:  POST { restaurant_id: string, novo_email: string, invalidar_senha?: boolean (true) }
// Resposta: { ok, user_id, email_antes, email_novo, senha_invalidada, loja_atualizada, users_atualizado }
// Erros:   401 unauthorized · 403 forbidden / dono_e_admin · 400 email_invalido / pedido_invalido
//          404 farmacia_nao_encontrada · 409 sem_dono / email_em_uso · 500 auth_falhou / loja_falhou

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { chaveSecreta, utilizadorDoPedido } from '../_shared/chaves.ts';

// CORS inline (valores idênticos aos de _shared/cors.ts).
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function resposta(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function senhaAleatoria(): string {
  const b = new Uint8Array(24);
  crypto.getRandomValues(b);
  return btoa(String.fromCharCode(...b)).replace(/[^A-Za-z0-9]/g, '') + 'Aa1!';
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return resposta({ ok: false, error: 'method_not_allowed' }, 405);

  // ── Quem chama: só admin com sessão confirmada no Auth ─────────────────────────────────────
  const quem = await utilizadorDoPedido(req);
  if (!quem) return resposta({ ok: false, error: 'unauthorized' }, 401);
  if (quem.app_metadata?.role !== 'admin') {
    console.warn('[admin-farmacia-email] nao-admin tentou aceder:', quem.id);
    return resposta({ ok: false, error: 'forbidden' }, 403);
  }

  // ── Pedido ─────────────────────────────────────────────────────────────────────────────────
  let corpo: { restaurant_id?: unknown; novo_email?: unknown; invalidar_senha?: unknown };
  try {
    corpo = await req.json();
  } catch {
    return resposta({ ok: false, error: 'pedido_invalido' }, 400);
  }
  const restaurantId = typeof corpo.restaurant_id === 'string' ? corpo.restaurant_id.trim() : '';
  const novo = typeof corpo.novo_email === 'string' ? corpo.novo_email.trim().toLowerCase() : '';
  const invalidarSenha = corpo.invalidar_senha !== false;
  if (!restaurantId) return resposta({ ok: false, error: 'pedido_invalido' }, 400);
  if (!EMAIL_RE.test(novo) || novo.length > 254) {
    return resposta({ ok: false, error: 'email_invalido' }, 400);
  }

  const admin = createClient(SUPABASE_URL, chaveSecreta(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ── Farmácia e dono ────────────────────────────────────────────────────────────────────────
  const { data: loja, error: eLoja } = await admin
    .from('restaurants')
    .select('id, name, category, email, user_id, user_')
    .eq('id', restaurantId)
    .maybeSingle();
  if (eLoja) {
    console.error('[admin-farmacia-email] leitura da loja falhou:', eLoja.message);
    return resposta({ ok: false, error: 'leitura_falhou', detail: eLoja.message }, 500);
  }
  if (!loja || loja.category !== 'pharmacy') {
    return resposta({ ok: false, error: 'farmacia_nao_encontrada' }, 404);
  }
  const donoId: string | null = loja.user_id ?? loja.user_ ?? null;
  if (!donoId) return resposta({ ok: false, error: 'sem_dono' }, 409);

  const { data: dono, error: eDono } = await admin.auth.admin.getUserById(donoId);
  if (eDono || !dono?.user) {
    console.error('[admin-farmacia-email] dono nao encontrado no Auth:', eDono?.message);
    return resposta({ ok: false, error: 'sem_dono' }, 409);
  }
  if ((dono.user.app_metadata as Record<string, unknown> | null)?.role === 'admin') {
    return resposta({ ok: false, error: 'dono_e_admin' }, 403);
  }
  const emailAntes = dono.user.email ?? null;

  // ── 1. Conta de login (Auth) ───────────────────────────────────────────────────────────────
  const mudaEmail = (emailAntes ?? '').toLowerCase() !== novo;
  if (mudaEmail || invalidarSenha) {
    const atributos: { email?: string; email_confirm?: boolean; password?: string } = {};
    if (mudaEmail) {
      atributos.email = novo;
      atributos.email_confirm = true; // o admin confirma: a farmácia entra pelo link de criar senha
    }
    if (invalidarSenha) atributos.password = senhaAleatoria();
    const { error: eUpd } = await admin.auth.admin.updateUserById(donoId, atributos);
    if (eUpd) {
      // deno-lint-ignore no-explicit-any
      const codigo = (eUpd as any)?.code ?? '';
      const emUso = codigo === 'email_exists' || /already|registered|exists/i.test(eUpd.message ?? '');
      await auditar(admin, quem, restaurantId, {
        ok: false, user_id: donoId, email_antes: emailAntes, email_novo: novo, erro: eUpd.message,
      });
      if (emUso) return resposta({ ok: false, error: 'email_em_uso' }, 409);
      console.error('[admin-farmacia-email] updateUserById falhou:', eUpd.message);
      return resposta({ ok: false, error: 'auth_falhou', detail: eUpd.message }, 500);
    }
  }

  // ── 2. E-mail da loja (contacto e ligação antiga loja↔dono) ────────────────────────────────
  const { error: eLojaUpd } = await admin.from('restaurants').update({ email: novo }).eq('id', restaurantId);
  if (eLojaUpd) {
    console.error('[admin-farmacia-email] restaurants.email falhou:', eLojaUpd.message);
    await auditar(admin, quem, restaurantId, {
      ok: false, user_id: donoId, email_antes: emailAntes, email_novo: novo,
      auth_mudou: mudaEmail, erro: `restaurants: ${eLojaUpd.message}`,
    });
    return resposta({ ok: false, error: 'loja_falhou', detail: eLojaUpd.message, auth_mudou: mudaEmail }, 500);
  }

  // ── 3. Espelho em public.users (não há gatilho que o faça ao mudar o e-mail no Auth) ───────
  const { error: eUsers, count } = await admin
    .from('users')
    .update({ email: novo }, { count: 'exact' })
    .eq('id', donoId);
  if (eUsers) console.error('[admin-farmacia-email] public.users falhou (nao bloqueia):', eUsers.message);

  await auditar(admin, quem, restaurantId, {
    ok: true, user_id: donoId, email_antes: emailAntes, email_novo: novo,
    senha_invalidada: invalidarSenha, users_atualizado: !eUsers && (count ?? 0) > 0,
  });

  console.log(`[admin-farmacia-email] OK loja=${restaurantId} user=${donoId}`);
  return resposta({
    ok: true,
    user_id: donoId,
    email_antes: emailAntes,
    email_novo: novo,
    senha_invalidada: invalidarSenha,
    loja_atualizada: true,
    users_atualizado: !eUsers && (count ?? 0) > 0,
  });
});

// A auditoria nunca derruba o pedido, mas também não desaparece em silêncio: falha fica no log.
async function auditar(
  // deno-lint-ignore no-explicit-any
  admin: any,
  quem: { id: string; email?: string },
  restaurantId: string,
  detalhes: Record<string, unknown>,
): Promise<void> {
  const { error } = await admin.from('admin_audit_log').insert({
    admin_id: quem.id,
    admin_email: quem.email ?? null,
    action: 'farmacia_email_login',
    entity_type: 'restaurant',
    entity_id_text: restaurantId,
    details: detalhes,
  });
  if (error) console.error('[admin-farmacia-email] auditoria falhou:', error.message);
}
