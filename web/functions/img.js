// Proxy de imagens do Bora — Cloudflare Pages Function (rota /img).
//
// PORQUÊ (2026-08-25): no telemóvel do Danilo as fotos dos produtos não
// apareciam em loja nenhuma do web. A causa é CORS: as imagens dos catálogos
// vêm de CDNs de terceiros (glovo.dhmedia.io, cloudfront do McDonald's, S3 do
// KFC, continente.pt, ...) que respondem SEM `access-control-allow-origin`.
// O Android não liga a CORS e mostra tudo; o browser bloqueia, e o Flutter web
// (CanvasKit) precisa de ler os pixels para os desenhar no canvas — sem CORS
// fica só o espaço reservado cinzento.
//
// Esta função corre no MESMO domínio do site, portanto o pedido do browser é
// same-origin e não há CORS nenhum. A imagem é buscada servidor-a-servidor,
// onde CORS não se aplica.
//
// Segurança: só reencaminha para domínios da lista abaixo (nada de proxy
// aberto), só GET, e só devolve respostas cujo content-type é imagem.

const DOMINIOS_PERMITIDOS = new Set([
  'glovo.dhmedia.io',
  'prod-mercadona.imgix.net',
  'www.continente.pt',
  'tb-static.uber.com',
  'images.deliveryhero.io',
  'www.pingodoce.pt',
  'production-uq-menu-maker-item-images.s3.eu-west-3.amazonaws.com',
  'gps.burgerkingencasa.es',
  'drn10k7huei54.cloudfront.net',
  'www.pizzahut.pt',
  'imgproxy-retcat.assets.schwarz',
  'www.auchan.pt',
  'www.wells.pt',
  'www.worten.pt',
  'media.leroymerlin.pt',
  'www.kiwoko.pt',
  'www.zippy.pt',
  'static.mcdonalds.pt',
  'www.kfc.pt',
  'www.google.com',            // favicons usados como logo de loja
  'ojykpzwqrtusfeakzrna.supabase.co',
]);

export async function onRequestGet({ request }) {
  const pedido = new URL(request.url);
  const alvo = pedido.searchParams.get('u');
  if (!alvo) return new Response('falta u', { status: 400 });

  let destino;
  try {
    destino = new URL(alvo);
  } catch (_) {
    return new Response('url invalida', { status: 400 });
  }
  if (destino.protocol !== 'https:' || !DOMINIOS_PERMITIDOS.has(destino.hostname)) {
    return new Response('dominio nao permitido', { status: 403 });
  }

  const resposta = await fetch(destino.toString(), {
    method: 'GET',
    headers: { 'User-Agent': 'BoraApp/1.0 (+https://bora-app-web.pages.dev)' },
    cf: { cacheTtl: 86400, cacheEverything: true },
  });
  if (!resposta.ok) return new Response('origem falhou', { status: 502 });

  const tipo = resposta.headers.get('content-type') || '';
  // Alguns CDNs mandam binary/octet-stream para JPEG — aceitar e corrigir.
  const ehImagem = tipo.startsWith('image/') ||
      tipo === 'binary/octet-stream' || tipo === 'application/octet-stream';
  if (!ehImagem) return new Response('nao e imagem', { status: 415 });

  const cabecalhos = new Headers();
  cabecalhos.set('content-type', tipo.startsWith('image/') ? tipo : 'image/jpeg');
  cabecalhos.set('cache-control', 'public, max-age=86400, immutable');
  cabecalhos.set('access-control-allow-origin', '*');
  return new Response(resposta.body, { status: 200, headers: cabecalhos });
}
