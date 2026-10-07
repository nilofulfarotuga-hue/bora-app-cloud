import 'package:bora_app/utils/rastreio_interpolacao.dart';
import 'package:bora_app/utils/marcador_animado.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// [Rastreio em tempo real · 07/10/2026] A regra do condutor EXACTO no mapa
/// do cliente — pura, sem mapa nem rede. Cicatrizes: carro a andar para trás
/// quando uma resposta velha chegava depois de uma nova; carro a apontar
/// para norte a andar para sul (heading a zero); 12 × 80 ms fixos com
/// amostras de 4-5 s (deslizava 1 s, parava 3); esquinas cortadas.
void main() {
  // Guarda (40.537, -7.266). 0.0001° de latitude ≈ 11 m.
  const base = LatLng(40.5370, -7.2660);
  final t0 = DateTime.utc(2026, 10, 7, 20, 0, 0);

  AmostraPosicao am(double dLat, double dLng, int segundos,
          {double? heading, double? v}) =>
      AmostraPosicao(
        ponto: LatLng(base.latitude + dLat, base.longitude + dLng),
        em: t0.add(Duration(seconds: segundos)),
        heading: heading,
        velocidadeKmh: v,
      );

  group('nunca anda para trás no tempo', () {
    test('amostra mais antiga do que a última aceite é ignorada', () {
      final i = InterpoladorDePosicao();
      expect(i.aceitar(am(0, 0, 0, v: 30)), isNotNull);
      expect(i.aceitar(am(0.0010, 0, 5, v: 30)), isNotNull);
      // chega agora uma resposta ATRASADA (t = 2 s): fora.
      final velha = i.aceitar(am(0.0005, 0, 2, v: 30));
      expect(velha, isNull);
      expect(i.ultimaAmostra!.em, t0.add(const Duration(seconds: 5)));
      expect(i.posicaoMostrada!.latitude, closeTo(base.latitude + 0.0010, 1e-9),
          reason: 'a posição mostrada não pode recuar');
    });

    test('a MESMA amostra pelas duas portas (Realtime + poll) é ignorada', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0, v: 30));
      expect(i.aceitar(am(0.0010, 0, 5, v: 30)), isNotNull);
      expect(i.aceitar(am(0.0010, 0, 5, v: 30)), isNull,
          reason: 'hora igual = mesma leitura; aceitá-la saltava para o fim');
    });

    test('a primeira amostra assenta sem animar', () {
      final i = InterpoladorDePosicao();
      final p = i.aceitar(am(0, 0, 0))!;
      expect(p.imediato, isTrue);
      expect(p.pontos, hasLength(1));
    });
  });

  group('rumo', () {
    test('o heading do aparelho manda quando ele anda', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0, heading: 90, v: 30));
      expect(i.rumo, closeTo(90, 1e-9));
    });

    test('heading a ZERO com velocidade > 0 → rumo entre os dois últimos pontos',
        () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0, heading: 0, v: 30));
      expect(i.rumo, isNull, reason: 'um ponto só não dá rumo');
      // andou para ESTE (lng sobe): rumo ≈ 90°, não 0° (norte).
      i.aceitar(am(0, 0.0010, 5, heading: 0, v: 30));
      expect(i.rumo, closeTo(90, 1.0));
      // e depois para SUL: suavizado, mas a caminhar para 180°.
      i.aceitar(am(-0.0010, 0.0010, 10, heading: 0, v: 30));
      expect(i.rumo, greaterThan(90));
    });

    test('heading nulo com velocidade desconhecida → rumo entre pontos', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0));
      i.aceitar(am(0.0010, 0, 5)); // norte
      expect(i.rumo, anyOf(closeTo(0, 1.0), closeTo(360, 1.0)));
    });

    test('parado não gira à toa (mantém o rumo anterior)', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0, heading: 90, v: 30));
      i.aceitar(am(0.00002, 0.00001, 5, heading: 0, v: 0)); // ruído de 2 m
      expect(i.rumo, closeTo(90, 1e-9));
    });

    test('rumoEntre e suavizaRumo', () {
      expect(rumoEntre(base, LatLng(base.latitude + 0.001, base.longitude)),
          closeTo(0, 0.01));
      expect(rumoEntre(base, LatLng(base.latitude, base.longitude + 0.001)),
          closeTo(90, 0.5));
      // 350° → 10° passa pelo 0°, não dá a volta ao círculo.
      final r = suavizaRumo(350, 10);
      expect(r, anyOf(lessThan(20), greaterThan(350)));
    });
  });

  group('duração = intervalo real entre amostras', () {
    test('amostras de 4 s em 4 s → animação de ~4 s, não 12×80 ms', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0, v: 30));
      final p = i.aceitar(am(0.0010, 0, 4, v: 30))!;
      expect(p.duracao.inMilliseconds, 4000);
      expect(p.pontos.length, greaterThanOrEqualTo(12));
      expect(p.imediato, isFalse);
    });

    test('buraco de 60 s não vira 60 s de carro a deslizar (tecto)', () {
      final i = InterpoladorDePosicao(tetoMs: 8000);
      i.aceitar(am(0, 0, 0, v: 30));
      final p = i.aceitar(am(0.0050, 0, 60, v: 30))!;
      expect(p.duracao.inMilliseconds, 8000);
    });

    test('com intervalo esperado, o tecto é 2× esse intervalo', () {
      final i = InterpoladorDePosicao(tetoMs: 8000);
      i.aceitar(am(0, 0, 0, v: 30));
      final p = i.aceitar(am(0.0050, 0, 60, v: 30), intervaloEsperadoMs: 2000)!;
      expect(p.duracao.inMilliseconds, 4000);
    });

    test('parado com salto pequeno é ruído: assenta sem animar', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0, v: 0));
      final p = i.aceitar(am(0.00005, 0, 4, v: 0))!; // ~5 m
      expect(p.imediato, isTrue);
    });

    test('sinal velho assenta sem animar', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0, 0, v: 30));
      final p = i.aceitar(am(0.0010, 0, 4, v: 30), animar: false)!;
      expect(p.imediato, isTrue);
    });
  });

  group('por cima da rota', () {
    // Rota em L: sobe 110 m para norte e vira para este 110 m.
    final rota = <LatLng>[
      base,
      LatLng(base.latitude + 0.0010, base.longitude),
      LatLng(base.latitude + 0.0010, base.longitude + 0.0013),
    ];

    test('com rota, os pontos ficam em cima da linha (dobra a esquina)', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0.0001, 0, 0, v: 30));
      final p = i.aceitar(am(0.0010, 0.0010, 5, v: 30), rota: rota)!;
      expect(p.sobreRota, isTrue);
      // Nenhum ponto corta a esquina: todos a < 3 m da polilinha.
      for (final q in p.pontos) {
        final naPerna1 = (q.longitude - base.longitude).abs() < 0.00003 &&
            q.latitude <= base.latitude + 0.0010 + 1e-9;
        final naPerna2 =
            (q.latitude - (base.latitude + 0.0010)).abs() < 0.00003;
        expect(naPerna1 || naPerna2, isTrue,
            reason: 'ponto $q fora da rota (esquina cortada)');
      }
      // Sem heading do aparelho, o rumo por passo segue a estrada: começa a
      // norte e acaba a este.
      expect(p.rumoPorPasso.last, closeTo(90, 25));
      expect(p.pontos.last.latitude, closeTo(base.latitude + 0.0010, 1e-6));
    });

    test('sem rota, linha recta (o ponto do meio é a média)', () {
      final i = InterpoladorDePosicao(passosBase: 2, msPorPasso: 100000);
      i.aceitar(am(0, 0, 0, v: 30));
      final p = i.aceitar(am(0.0010, 0.0010, 5, v: 30))!;
      expect(p.sobreRota, isFalse);
      expect(p.pontos, hasLength(2));
      expect(p.pontos.first.latitude, closeTo(base.latitude + 0.0005, 1e-9));
      expect(p.pontos.last.latitude, closeTo(base.latitude + 0.0010, 1e-9));
    });

    test('longe da rota (>60 m) não se cola à linha', () {
      final i = InterpoladorDePosicao();
      i.aceitar(am(0, 0.0020, 0, v: 30)); // ~170 m a este da rota
      final p = i.aceitar(am(0.0010, 0.0020, 5, v: 30), rota: rota)!;
      expect(p.sobreRota, isFalse);
    });
  });

  group('MarcadorAnimado (o relógio à volta)', () {
    test('anima até à amostra e chama onFrame; amostra velha é ignorada',
        () async {
      var frames = 0;
      final m = MarcadorAnimado(
        interpolador: InterpoladorDePosicao(chaoMs: 240, msPorPasso: 20),
        onFrame: () => frames++,
      );
      expect(m.aceitar(am(0, 0, 0, v: 30)), isTrue);
      expect(m.posicao, isNotNull);
      expect(m.aceitar(am(0.0010, 0, 1, v: 30)), isTrue);
      expect(m.aceitar(am(0.0005, 0, 0, v: 30)), isFalse,
          reason: 'mais antiga');
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(m.posicao!.latitude, closeTo(base.latitude + 0.0010, 1e-9));
      expect(frames, greaterThan(5));
      expect(m.expirado(const Duration(seconds: 30)), isFalse);
      m.dispose();
    });

    test('limpar esquece tudo e expirado reconhece ausência', () {
      final m = MarcadorAnimado();
      m.aceitar(am(0, 0, 0));
      m.limpar();
      expect(m.posicao, isNull);
      expect(m.expirado(const Duration(seconds: 1)), isTrue);
      m.dispose();
    });
  });
}
