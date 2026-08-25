import 'package:flutter/foundation.dart' show kIsWeb;

/// Reescrita de URLs de imagem para o proxy do próprio site — só na WEB.
///
/// PORQUÊ (2026-08-25): as fotos dos catálogos vêm de CDNs de terceiros
/// (glovo.dhmedia.io, cloudfront do McDonald's, S3 do KFC, continente.pt...)
/// que respondem sem `access-control-allow-origin`. O browser bloqueia a
/// leitura dos pixels e o Flutter web fica com o espaço reservado cinzento em
/// vez da foto — foi o que o Danilo apanhou no iPhone, em todas as lojas com
/// catálogo importado. No Android não acontece: CORS é uma regra de browser.
///
/// A app passa a pedir essas imagens a `/img?u=<url>`, uma função do próprio
/// site (mesmo domínio → sem CORS), que as vai buscar servidor-a-servidor.
/// Ver `web/functions/img.js` — tem a mesma lista de domínios.
///
/// Fora da web devolve a URL intacta: no telemóvel nunca houve problema e não
/// há motivo para acrescentar um salto.
const Set<String> _dominiosProxiados = {
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
  'www.google.com',
};

/// Devolve a URL que a app deve pedir para [url].
///
/// Mantém intacto o que já vem do nosso Storage (serve com CORS `*`), o que
/// não é http(s), e tudo o que corre fora da web.
String imagemParaMostrar(String? url) {
  final u = url?.trim() ?? '';
  if (!kIsWeb) return u;
  return proxiarSeExterna(u);
}

/// A decisão em si, sem o guard da plataforma — separada para ser testável
/// fora da web (os testes correm na VM, onde `kIsWeb` é sempre false).
String proxiarSeExterna(String url) {
  if (url.isEmpty || !url.startsWith('https://')) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !_dominiosProxiados.contains(uri.host)) return url;
  return '/img?u=${Uri.encodeQueryComponent(url)}';
}

/// Igual a [imagemParaMostrar] mas preserva o `null` — para campos opcionais
/// (ex.: `hero_image_url`), onde uma string vazia enganaria as guardas de
/// fallback que testam `!= null`.
String? imagemParaMostrarOpcional(String? url) {
  final u = imagemParaMostrar(url);
  return u.isEmpty ? null : u;
}
