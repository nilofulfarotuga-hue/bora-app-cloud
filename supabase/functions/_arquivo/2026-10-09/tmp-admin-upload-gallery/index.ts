Deno.serve(async () => {
  // Desactivada apos uso unico (missao redes-fotos-reais-dos-outros-parceiros, 2026-09-08).
  return new Response(JSON.stringify({ error: "disabled" }), { status: 410 });
});
