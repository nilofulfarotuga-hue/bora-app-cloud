Deno.serve((_req: Request) => new Response("desligada", { status: 410 }));
