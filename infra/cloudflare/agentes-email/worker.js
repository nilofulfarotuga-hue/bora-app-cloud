// Worker "agentes-email" (Cloudflare Email Routing) — missão agentes-email-2026-10-21.
//
// E-mail de fora para <agente>@boraguarda.com → regra do Email Routing → ESTE Worker → Edge
// Function agentes-email-receber (Supabase) → tabela public.agentes_email.
//
// O segredo partilhado vive SÓ como secret do Worker (AGENTES_EMAIL_SEGREDO) e no cofre do banco
// (agentes_email_key). Nunca neste ficheiro.
//
// Respostas da Edge:
//   200 → entregue (ou repetido; a Edge não duplica)
//   404 → endereço que não é de nenhum agente → recusa definitiva (o remetente recebe aviso)
//   413 → grande demais → recusa definitiva
//   outro (403, 5xx, rede) → erro lançado → falha temporária, o servidor de origem volta a tentar

const EDGE = 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/agentes-email-receber';
const MAX_BYTES = 25 * 1024 * 1024;

export default {
  async email(message, env) {
    if (message.rawSize > MAX_BYTES) {
      message.setReject('Mensagem demasiado grande (maximo 25 MB).');
      return;
    }
    if (!env.AGENTES_EMAIL_SEGREDO) throw new Error('agentes-email: falta o secret AGENTES_EMAIL_SEGREDO');

    const cru = await new Response(message.raw).arrayBuffer();
    const r = await fetch(EDGE, {
      method: 'POST',
      headers: {
        'content-type': 'message/rfc822',
        'x-agentes-email-segredo': env.AGENTES_EMAIL_SEGREDO,
        'x-agentes-email-para': String(message.to || ''),
        'x-agentes-email-de': String(message.from || ''),
      },
      body: cru,
    });

    if (r.ok) return;
    if (r.status === 404) {
      message.setReject('Este endereco nao existe em boraguarda.com.');
      return;
    }
    if (r.status === 413) {
      message.setReject('Mensagem demasiado grande.');
      return;
    }
    const corpo = (await r.text().catch(() => '')).slice(0, 200);
    throw new Error(`agentes-email: Edge respondeu ${r.status} ${corpo}`);
  },

  async fetch() {
    return new Response('agentes-email: este Worker so recebe e-mail.', { status: 404 });
  },
};
