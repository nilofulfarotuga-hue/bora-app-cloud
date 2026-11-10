// [GPS parado · 10/11/2026] Posição do serviço de fundo pelo segredo do
// batimento (driver_posicao_segredo). Testa a decisão sobre a resposta do
// servidor, que é o que faz a posição continuar depois de o token de 1 h
// caducar (Valdemir, 10/11: batimento de agora, posição de há 4 h 23 min).
import 'package:bora_app/services/foreground_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resultadoPosicaoComSegredo', () {
    test('ok=true → posição gravada', () {
      expect(resultadoPosicaoComSegredo(200, '{"ok":true,"em":"2026-11-10T18:00:00Z"}'),
          ResultadoPosicaoSegredo.enviada);
    });

    test('estafeta desligado no servidor → não insiste', () {
      expect(resultadoPosicaoComSegredo(200, '{"ok":false,"error":"offline"}'),
          ResultadoPosicaoSegredo.desligado);
    });

    test('segredo recusado → larga o segredo e tenta o token', () {
      expect(resultadoPosicaoComSegredo(200, '{"ok":false,"error":"forbidden"}'),
          ResultadoPosicaoSegredo.largarSegredo);
    });

    test('função ainda não publicada (404) → tenta o token sem largar o segredo', () {
      expect(resultadoPosicaoComSegredo(404, '{"code":"PGRST202"}'),
          ResultadoPosicaoSegredo.tentarToken);
    });

    test('erro do servidor ou corpo estranho → tenta o token', () {
      expect(resultadoPosicaoComSegredo(500, 'erro'), ResultadoPosicaoSegredo.tentarToken);
      expect(resultadoPosicaoComSegredo(200, 'não é json'), ResultadoPosicaoSegredo.tentarToken);
      expect(resultadoPosicaoComSegredo(200, '[1,2]'), ResultadoPosicaoSegredo.tentarToken);
      expect(resultadoPosicaoComSegredo(200, '{"ok":false,"error":"outro"}'),
          ResultadoPosicaoSegredo.tentarToken);
    });

    test('a marca da versão é a desta entrega (a ronda usa-a para apertar a janela)', () {
      expect(kGpsParadoVersao, 20261110);
    });
  });
}
