// Diagnóstico: lista modelos disponíveis para esta API key
const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY');

Deno.serve(async (req: Request) => {
  if (!GEMINI_API_KEY) return new Response('NO KEY', { status: 500 });

  // Lista modelos disponíveis
  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_API_KEY}&pageSize=50`
  );
  const data = await resp.json();

  // Filtra só os que suportam generateContent
  const models = (data.models ?? []).filter((m: any) =>
    m.supportedGenerationMethods?.includes('generateContent')
  ).map((m: any) => m.name);

  return new Response(JSON.stringify({ total: models.length, models }), {
    headers: { 'Content-Type': 'application/json' }
  });
});
