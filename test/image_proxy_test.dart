// Prova da correcção das imagens (2026-08-25): no web, as fotos dos catálogos
// vinham de CDNs de terceiros SEM cabeçalho CORS — o browser bloqueava e o
// Flutter web ficava com o espaço reservado cinzento em vez da foto (o que o
// Danilo apanhou no iPhone). Passam a ser pedidas ao proxy do próprio site.
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/utils/image_proxy.dart';

void main() {
  test('CDN de terceiros (sem CORS) passa a ir pelo proxy do site', () {
    for (final externa in const [
      'https://drn10k7huei54.cloudfront.net/media/big-mac.jpg',      // McDonald's
      'https://production-uq-menu-maker-item-images.s3.eu-west-3.amazonaws.com/x.png', // KFC
      'https://glovo.dhmedia.io/image/produto.jpeg',                  // mercados
      'https://www.continente.pt/dw/image/leite.jpg',
    ]) {
      final saida = proxiarSeExterna(externa);
      expect(saida.startsWith('/img?u='), isTrue,
          reason: '$externa tinha de passar pelo proxy');
      expect(Uri.decodeQueryComponent(saida.substring('/img?u='.length)),
          externa,
          reason: 'a URL original tem de sobreviver intacta ao encode');
    }
  });

  test('o nosso Storage (já serve CORS *) fica intacto', () {
    const nossa =
        'https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/restaurant-assets/sabores-brasil-guarda/grandes-real.jpg';
    expect(proxiarSeExterna(nossa), nossa);
  });

  test('vazios, http simples e domínios desconhecidos ficam intactos', () {
    expect(proxiarSeExterna(''), '');
    expect(proxiarSeExterna('http://sem-tls.example/x.jpg'),
        'http://sem-tls.example/x.jpg');
    expect(proxiarSeExterna('https://dominio-que-nao-conhecemos.pt/x.jpg'),
        'https://dominio-que-nao-conhecemos.pt/x.jpg',
        reason: 'o proxy tem allowlist — nunca é um proxy aberto');
  });

  test('fora da web nada é reescrito (no telemóvel nunca houve problema)', () {
    // kIsWeb é false nos testes de VM — imagemParaMostrar devolve intacto.
    const externa = 'https://drn10k7huei54.cloudfront.net/media/big-mac.jpg';
    expect(imagemParaMostrar(externa), externa);
    expect(imagemParaMostrarOpcional(null), isNull);
    expect(imagemParaMostrarOpcional('  '), isNull);
  });
}
