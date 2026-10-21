// [A2 · 21/10/2026] Carro a deslizar pelo canal privado da corrida.
// Prova as peças sem rede: a mensagem do canal vira amostra, o motorista não
// manda mais do que uma por intervalo, o canal fecha quando a corrida acaba,
// sem canal (rede em baixo) nada rebenta e a base volta a mandar, e o marcador
// desliza ENTRE as posições (não salta).
import 'package:bora_app/services/tvde_posicao_ao_vivo.dart';
import 'package:bora_app/utils/marcador_animado.dart';
import 'package:bora_app/utils/rastreio_interpolacao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Transporte falso: guarda o que se enviou e deixa o teste "entregar"
/// mensagens e decidir se o canal entra ou falha.
class CanalFalso implements CanalPosicao {
  CanalFalso(this.topico);

  final String topico;
  void Function(Map<String, dynamic>)? _cb;
  void Function(bool, Object?)? _estado;
  final enviadas = <Map<String, dynamic>>[];
  bool fechado = false;
  bool ligou = false;

  @override
  void aoReceber(void Function(Map<String, dynamic> payload) callback) => _cb = callback;

  @override
  void ligar(void Function(bool ligado, Object? erro) estado) {
    ligou = true;
    _estado = estado;
  }

  void entrou() => _estado?.call(true, null);
  void falhou(Object erro) => _estado?.call(false, erro);
  void entregar(Map<String, dynamic> m) => _cb?.call(m);

  @override
  Future<bool> enviar(Map<String, dynamic> payload) async {
    enviadas.add(payload);
    return true;
  }

  @override
  Future<void> fechar() async => fechado = true;
}

void main() {
  const base = LatLng(40.5370, -7.2660); // Guarda; 0,0001° lat ≈ 11 m
  final t0 = DateTime.utc(2026, 10, 21, 12, 0, 0);

  group('mensagem do canal → amostra', () {
    test('lê lat/lng/heading/velocidade; a hora de chegada manda na ordem', () {
      final chegada = t0.add(const Duration(seconds: 7));
      final a = amostraDePayloadPosicao({
        'lat': 40.5371,
        'lng': -7.2661,
        'heading': 90.0,
        'speed_kmh': 32.5,
        'em': '2026-10-21T11:59:00Z', // relógio do motorista adiantado/atrasado
      }, chegada: chegada)!;
      expect(a.ponto.latitude, 40.5371);
      expect(a.ponto.longitude, -7.2661);
      expect(a.heading, 90.0);
      expect(a.velocidadeKmh, 32.5);
      expect(a.em, chegada, reason: 'ordena pela chegada, não pelo relógio do telemóvel dele');
    });

    test('lixo não vira posição (nunca se desenha no meio do mar)', () {
      expect(amostraDePayloadPosicao({'lat': 'x', 'lng': -7.2}), isNull);
      expect(amostraDePayloadPosicao({'lng': -7.2}), isNull);
      expect(amostraDePayloadPosicao({'lat': 0, 'lng': 0}), isNull);
      expect(amostraDePayloadPosicao({'lat': 91, 'lng': -7.2}), isNull);
      expect(amostraDePayloadPosicao({'lat': 40.5, 'lng': double.nan}), isNull);
    });

    test('o que o motorista envia ida e volta dá o mesmo ponto', () {
      final p = payloadDePosicao(lat: 40.5372, lng: -7.2662, heading: 45, speedKmh: 20, em: t0);
      final a = amostraDePayloadPosicao(p)!;
      expect(a.ponto, const LatLng(40.5372, -7.2662));
      expect(a.em, t0);
      expect(p['em'], '2026-10-21T12:00:00.000Z');
    });

    test('nome do canal e fases com posição', () {
      expect(topicoPosicaoAoVivo('abc'), 'tvde_pos:abc');
      for (final s in ['motorista_atribuido', 'motorista_a_caminho', 'motorista_chegou', 'em_andamento']) {
        expect(tvdeCorridaComPosicao(s), isTrue, reason: s);
      }
      for (final s in ['solicitada', 'finalizada', 'cancelada_cliente', 'sem_motorista', null]) {
        expect(tvdeCorridaComPosicao(s), isFalse, reason: '$s');
      }
    });
  });

  group('motorista: emissor com travão', () {
    test('não manda antes de o canal entrar; depois no máximo 1 por intervalo', () {
      var agora = t0;
      late CanalFalso canal;
      final e = PosicaoAoVivoEmissor(
        rideId: 'r1',
        intervalo: const Duration(seconds: 2),
        fabrica: (t) => canal = CanalFalso(t),
        relogio: () => agora,
      )..iniciar();
      expect(canal.topico, 'tvde_pos:r1');
      expect(e.emitir(lat: 40.5, lng: -7.2), isFalse, reason: 'canal ainda não entrou');
      canal.entrou();
      expect(e.emitir(lat: 40.5, lng: -7.2), isTrue);
      agora = agora.add(const Duration(milliseconds: 700));
      expect(e.emitir(lat: 40.5001, lng: -7.2), isFalse);
      agora = agora.add(const Duration(milliseconds: 900));
      expect(e.emitir(lat: 40.5002, lng: -7.2), isFalse);
      agora = agora.add(const Duration(milliseconds: 500)); // 2,1 s
      expect(e.emitir(lat: 40.5003, lng: -7.2, heading: 10, speedKmh: 30), isTrue);
      expect(canal.enviadas.length, 2);
      expect(canal.enviadas.last['lat'], 40.5003);
      expect(canal.enviadas.last['speed_kmh'], 30);
    });

    test('canal recusado (sem permissão / sem rede): não manda e não rebenta', () async {
      late CanalFalso canal;
      final e = PosicaoAoVivoEmissor(rideId: 'r1', fabrica: (t) => canal = CanalFalso(t))..iniciar();
      canal.falhou('Unauthorized');
      expect(e.estado, EstadoCanalPosicao.falhou);
      expect(e.emitir(lat: 40.5, lng: -7.2), isFalse);
      await e.parar();
      expect(canal.fechado, isTrue);
    });

    test('intervalo abaixo de 1 s é corrigido para 1 s (bateria/rede)', () {
      final e = PosicaoAoVivoEmissor(rideId: 'r', intervalo: const Duration(milliseconds: 100));
      expect(e.intervalo, const Duration(seconds: 1));
    });
  });

  group('cliente: o canal abre com a corrida e fecha no fim', () {
    test('a caminho → abre; mesma corrida não reabre; finalizada → fecha', () async {
      final canais = <CanalFalso>[];
      final recebidas = <AmostraPosicao>[];
      final s = SincronizadorPosicaoAoVivo(
        onAmostra: recebidas.add,
        fabrica: (t) {
          final c = CanalFalso(t);
          canais.add(c);
          return c;
        },
      );
      s.sincronizar(rideId: 'r1', status: 'solicitada');
      expect(canais, isEmpty, reason: 'à procura ainda não há posição');
      s.sincronizar(rideId: 'r1', status: 'motorista_a_caminho');
      expect(canais.length, 1);
      expect(canais.single.topico, 'tvde_pos:r1');
      canais.single.entrou();
      s.sincronizar(rideId: 'r1', status: 'em_andamento');
      expect(canais.length, 1, reason: 'mesma corrida: o canal fica o mesmo');
      canais.single.entregar({'lat': 40.5371, 'lng': -7.2661});
      expect(recebidas.length, 1);
      s.sincronizar(rideId: 'r1', status: 'finalizada');
      expect(canais.single.fechado, isTrue, reason: 'acabou a corrida: canal fechado');
      expect(s.ouvinte, isNull);
      canais.single.entregar({'lat': 40.5372, 'lng': -7.2661});
      expect(recebidas.length, 1, reason: 'mensagem atrasada depois de fechar: fora');
    });

    test('outra corrida → fecha a velha e abre a nova; interruptor desligado → fecha', () {
      final canais = <CanalFalso>[];
      final s = SincronizadorPosicaoAoVivo(
        onAmostra: (_) {},
        fabrica: (t) {
          final c = CanalFalso(t);
          canais.add(c);
          return c;
        },
      );
      s.sincronizar(rideId: 'r1', status: 'motorista_chegou');
      s.sincronizar(rideId: 'r2', status: 'motorista_a_caminho');
      expect(canais.length, 2);
      expect(canais[0].fechado, isTrue);
      expect(canais[1].topico, 'tvde_pos:r2');
      s.ligado = false;
      s.sincronizar(rideId: 'r2', status: 'motorista_a_caminho');
      expect(canais[1].fechado, isTrue);
      expect(canais.length, 2, reason: 'desligado não abre canal nenhum');
    });

    test('sem rede: o canal falha, ninguém rebenta, e a base volta a mandar', () {
      late CanalFalso canal;
      var recebidas = 0;
      final o = PosicaoAoVivoOuvinte(
        rideId: 'r1',
        onAmostra: (_) => recebidas++,
        fabrica: (t) => canal = CanalFalso(t),
      )..iniciar();
      expect(o.estado, EstadoCanalPosicao.aLigar);
      canal.falhou('timedOut');
      expect(o.estado, EstadoCanalPosicao.falhou);
      expect(recebidas, 0);

      // O ecrã continua com a base (driver_locations + poll): sem nada do
      // canal, a porta da base aplica sempre.
      final fonte = FonteDoCarro();
      expect(fonte.chegouDaBase(t0), isFalse);
      expect(fonte.chegouDaBase(t0.add(const Duration(seconds: 5))), isFalse);
    });

    test('fábrica a rebentar (sem Supabase) → estado falhou, sem excepção', () {
      final o = PosicaoAoVivoOuvinte(
        rideId: 'r1',
        onAmostra: (_) {},
        fabrica: (_) => throw StateError('sem Supabase'),
      );
      expect(o.iniciar, returnsNormally);
      expect(o.estado, EstadoCanalPosicao.falhou);
    });
  });

  group('uma porta de cada vez', () {
    test('canal vivo → a base é ignorada; canal calado → a base volta (recomeça)', () {
      final f = FonteDoCarro(validadeCanal: const Duration(seconds: 7));
      expect(f.chegouDoCanal(t0), isTrue, reason: 'primeira do canal: troca de fonte');
      expect(f.chegouDoCanal(t0.add(const Duration(seconds: 2))), isFalse);
      expect(f.chegouDaBase(t0.add(const Duration(seconds: 4))), isNull);
      expect(f.chegouDaBase(t0.add(const Duration(seconds: 9))), isNull,
          reason: '7 s depois da última do canal ainda conta como vivo');
      expect(f.chegouDaBase(t0.add(const Duration(seconds: 10))), isTrue,
          reason: 'canal calado: a base manda e o marcador recomeça');
      expect(f.chegouDaBase(t0.add(const Duration(seconds: 14))), isFalse);
      expect(f.noCanal, isFalse);
    });
  });

  testWidgets('o carro DESLIZA entre duas posições do canal (não salta)', (tester) async {
    var agora = t0;
    late CanalFalso canal;
    final marcador = MarcadorAnimado();
    final o = PosicaoAoVivoOuvinte(
      rideId: 'r1',
      fabrica: (t) => canal = CanalFalso(t),
      relogio: () => agora,
      onAmostra: (a) => marcador.aceitar(a, intervaloEsperadoMs: 2000),
    )..iniciar();
    canal.entrou();

    canal.entregar({'lat': base.latitude, 'lng': base.longitude, 'speed_kmh': 40});
    expect(marcador.posicao, base, reason: 'a primeira posição assenta');

    agora = agora.add(const Duration(seconds: 2));
    const fim = LatLng(40.5372, -7.2660); // ~22 m a norte em 2 s
    canal.entregar({'lat': fim.latitude, 'lng': fim.longitude, 'speed_kmh': 40});
    expect(marcador.posicao, base, reason: 'ainda não andou: vai deslizar');

    await tester.pump(const Duration(milliseconds: 1000));
    final meio = marcador.posicao!;
    expect(meio.latitude, greaterThan(base.latitude));
    expect(meio.latitude, lessThan(fim.latitude), reason: 'a meio do caminho, não no fim');

    await tester.pump(const Duration(milliseconds: 1500));
    expect(marcador.posicao!.latitude, closeTo(fim.latitude, 1e-9));
    expect(o.recebidas, 2);

    await o.parar();
    expect(canal.fechado, isTrue);
    marcador.dispose();
  });
}
