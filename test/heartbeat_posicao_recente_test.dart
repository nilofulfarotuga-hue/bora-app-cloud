import 'package:bora_app/services/heartbeat_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ronda-fecho-2026-09-22 · A10] Online = heartbeat E GPS fresco. O servidor
/// deixa de oferecer a quem tem a posição com mais de 180 s; a app nativa só
/// escrevia posição quando o estafeta se mexia 50 m, e um estafeta PARADO
/// ficava sem pedidos. O tick do heartbeat passa a mandar a última posição
/// conhecida — mas só se ainda servir. Esta é a regra que decide isso.
///
/// O relógio é injectado: sem isso o teste dependia da hora da máquina.
void main() {
  final agora = DateTime.utc(2026, 9, 23, 10, 0, 0);
  DateTime ha(Duration d) => agora.subtract(d);

  test('posição de há 1 minuto ainda serve — manda-se essa', () {
    expect(
      HeartbeatService.posicaoRecente(ha(const Duration(minutes: 1)),
          agora: agora),
      isTrue,
    );
  });

  test('4 min 59 s ainda serve — a fronteira não escorrega', () {
    expect(
      HeartbeatService.posicaoRecente(
          ha(const Duration(minutes: 4, seconds: 59)),
          agora: agora),
      isTrue,
    );
  });

  test('exactamente 5 minutos já não serve — pede-se uma nova', () {
    expect(
      HeartbeatService.posicaoRecente(ha(const Duration(minutes: 5)),
          agora: agora),
      isFalse,
    );
    expect(
      HeartbeatService.posicaoRecente(ha(const Duration(minutes: 30)),
          agora: agora),
      isFalse,
    );
  });

  test('relógio do telemóvel adiantado: idade negativa conta como recente', () {
    final futuro = agora.add(const Duration(seconds: 90));
    expect(HeartbeatService.posicaoRecente(futuro, agora: agora), isTrue);
  });

  test('a hora vem em UTC ou local, e dá o mesmo', () {
    final local = ha(const Duration(minutes: 1)).toLocal();
    expect(HeartbeatService.posicaoRecente(local, agora: agora), isTrue);
    final localVelha = ha(const Duration(minutes: 6)).toLocal();
    expect(HeartbeatService.posicaoRecente(localVelha, agora: agora), isFalse);
  });
}
