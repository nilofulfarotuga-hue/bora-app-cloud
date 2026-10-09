// aplicar-gaveta — RETIRADA a 08/10/2026.
// Existiu a 07/10/2026 para aplicar migrações da gaveta platform_settings.staged_*
// pela ligação interna (SUPABASE_DB_URL), porque a API de gestão do Supabase estava
// doente. A 08/10 a API voltou a responder (COMMENT ON TABLE public.assistant_knowledge
// pelo MCP execute_sql), por isso esta função deixa de tocar na base: devolve 410 a tudo.
// Gavetas por aplicar usam o caminho normal (apply_migration), nunca esta porta.

Deno.serve(() =>
  new Response(JSON.stringify({ ok: false, error: 'gone', detalhe: 'aplicar-gaveta retirada a 2026-10-08' }), {
    status: 410,
    headers: { 'Content-Type': 'application/json' },
  })
);
