// Desativada. Foi um diagnostico pontual de 2026-09-07 para descobrir que o
// projeto nao tinha RESEND_API_KEY. Ja nao lista nada do ambiente.
Deno.serve(() => new Response(JSON.stringify({ ok: false, error: 'desativada' }), {
  status: 410, headers: { 'Content-Type': 'application/json' },
}))
