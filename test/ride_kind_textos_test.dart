import 'dart:io';

import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/l10n/strings_en.dart';
import 'package:bora_app/models/ride_kind.dart';
import 'package:bora_app/models/ride_kind_textos.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/admin/admin_tvde_acertos_tipo_tab.dart';
import 'package:bora_app/screens/driver/tvde/tvde_ride_active_screen.dart'
    show textoDoAvisoDeCancelamento;
import 'package:bora_app/stores/tvde_store.dart' show tvdeParamTipo;
import 'package:bora_app/widgets/tvde/filtro_tipo_tvde.dart';
import 'package:bora_app/widgets/tvde/tvde_offer_overlay_host.dart'
    show mensagemDeOfertaFalhada;
import 'package:bora_app/widgets/tvde/tvde_roundtrip_driver_notice.dart';
import 'package:flutter_test/flutter_test.dart';

/// 21/10/2026 · fechar-pendencias A1 — Encomendas = cópia exacta do Bora
/// Motorista, só com outras palavras. Estes testes guardam a camada de
/// etiquetas: nenhuma frase de passageiro numa encomenda, o passageiro igual
/// a antes, e o dinheiro intacto nas frases (marcadores {0}, {1}…).

/// Chamada a uma etiqueta no código: `'texto'.trK(` / `.trArgsK(` / `.rk(` / `.rkArgs(`.
final RegExp _chamada = RegExp(
  r"""'((?:\\.|[^'\\\n])*)'(\s*)\.(trK|trArgsK|rk|rkArgs)\(""",
);

List<({String ficheiro, String chave, bool colada})> _chamadasNoCodigo() {
  final out = <({String ficheiro, String chave, bool colada})>[];
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final s = f.readAsStringSync();
    for (final m in _chamada.allMatches(s)) {
      // Duas literais seguidas ('a ' 'b'.rk()) são UMA string para o Dart: a
      // etiqueta recebia a frase inteira e a chave do mapa (só a 2.ª metade)
      // nunca batia. Cicatriz de 21/10 — juntar as frases numa só.
      final antes = s.substring(0, m.start).trimRight();
      final colada = antes.endsWith("'") || antes.endsWith('"');
      out.add((
        ficheiro: f.path.replaceAll(r'\', '/'),
        chave: m.group(1)!.replaceAll(r"\'", "'"),
        colada: colada,
      ));
    }
  }
  return out;
}

Set<String> _marcadores(String s) =>
    RegExp(r'\{(\d+)\}').allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  tearDown(() => BoraLang.notifier.value = AppLang.pt);

  group('a varredura das etiquetas', () {
    final chamadas = _chamadasNoCodigo();

    test('encontra as chamadas (senão o teste passava a olhar para nada)', () {
      expect(chamadas.length, greaterThan(100));
    });

    test('nenhuma etiqueta é a 2.ª metade de duas literais coladas', () {
      final coladas = chamadas.where((c) => c.colada).toList();
      expect(coladas, isEmpty,
          reason: 'Junta as frases numa só literal: ${coladas.map((c) => '${c.ficheiro}: ${c.chave}').join('\n')}');
    });

    test('toda a frase com palavra de passageiro tem a versão de encomenda', () {
      final faltam = chamadas
          .where((c) => kPalavrasDePassageiro.hasMatch(c.chave))
          .where((c) => !kTextosEncomendas.containsKey(c.chave))
          .map((c) => '${c.ficheiro}: ${c.chave}')
          .toSet();
      expect(faltam, isEmpty,
          reason: 'Frases sem entrada em kTextosEncomendas:\n${faltam.join('\n')}');
    });

    test('o mapa não tem entradas mortas (cada chave é usada no código)', () {
      final usadas = chamadas.map((c) => c.chave).toSet();
      final mortas = kTextosEncomendas.keys.where((k) => !usadas.contains(k)).toList();
      expect(mortas, isEmpty, reason: 'Entradas sem uso: $mortas');
    });
  });

  group('o mapa das encomendas', () {
    test('nenhum texto de encomenda tem "corrida/motorista/viagem/passageiro/boleia"', () {
      final sujos = kTextosEncomendas.entries
          .where((e) => kPalavrasDePassageiro.hasMatch(e.value.$1))
          .map((e) => e.value.$1)
          .toList();
      expect(sujos, isEmpty, reason: sujos.join('\n'));
    });

    test('nenhum inglês de encomenda fala de ride/driver/trip/passenger', () {
      final sujos = kTextosEncomendas.entries
          .where((e) => kPalavrasDePassageiroEn.hasMatch(e.value.$2))
          .map((e) => e.value.$2)
          .toList();
      expect(sujos, isEmpty, reason: sujos.join('\n'));
    });

    test('os marcadores {0},{1}… são os mesmos — o dinheiro passa intacto', () {
      for (final e in kTextosEncomendas.entries) {
        final m = _marcadores(e.key);
        expect(_marcadores(e.value.$1), m, reason: 'PT: ${e.key}');
        expect(_marcadores(e.value.$2), m, reason: 'EN: ${e.key}');
      }
    });

    test('nenhum valor vazio', () {
      for (final e in kTextosEncomendas.entries) {
        expect(e.value.$1.trim(), isNotEmpty, reason: e.key);
        expect(e.value.$2.trim(), isNotEmpty, reason: e.key);
      }
    });
  });

  group('trK / rk', () {
    test('passageiros em português = exactamente o texto de sempre', () {
      expect('Cancelar corrida'.trK(RideKind.passageiros), 'Cancelar corrida');
      expect('Cheguei ao passageiro'.rk(RideKind.passageiros), 'Cheguei ao passageiro');
      expect('Motorista a caminho · chega em ~{0} min'
              .trArgsK(RideKind.passageiros, [4]),
          'Motorista a caminho · chega em ~4 min');
    });

    test('passageiros em inglês = o mesmo inglês de antes (kStringsEn)', () {
      BoraLang.notifier.value = AppLang.en;
      expect('Cancelar corrida'.trK(RideKind.passageiros), kStringsEn['Cancelar corrida']);
    });

    test('encomenda em português e em inglês', () {
      expect('Cancelar corrida'.trK(RideKind.encomendas), 'Cancelar entrega');
      expect('Iniciar viagem'.rk(RideKind.encomendas), 'Recolhi a encomenda');
      expect('Finalizar viagem'.rk(RideKind.encomendas), 'Entreguei a encomenda');
      expect('Solicitar corrida'.trK(RideKind.encomendas), 'Pedir entrega');
      BoraLang.notifier.value = AppLang.en;
      expect('Cancelar corrida'.trK(RideKind.encomendas), 'Cancel delivery');
      expect('Motorista a caminho · chega em ~{0} min'.trArgsK(RideKind.encomendas, [3]),
          'Courier on the way to pick up · arrives in ~3 min');
    });

    test('frase sem versão de encomenda fica como está (nunca uma chave crua)', () {
      expect('Destino'.trK(RideKind.encomendas), 'Destino');
    });
  });

  group('tipo da corrida', () {
    test('lido da base: só "encomendas" é encomenda', () {
      expect(rideKindFromDb('encomendas'), RideKind.encomendas);
      expect(rideKindFromDb('passageiros'), RideKind.passageiros);
      expect(rideKindFromDb(null), RideKind.passageiros);
      expect(rideKindFromDb('passageiro'), RideKind.passageiros);
      expect(RideKind.encomendas.db, 'encomendas');
      expect(RideKind.passageiros.db, 'passageiros');
    });

    Map<String, dynamic> base() => {
          'id': 'r1',
          'client_id': 'c1',
          'status': 'solicitada',
          'origin_lat': 40.5,
          'origin_lng': -7.2,
          'dest_lat': 40.6,
          'dest_lng': -7.3,
          'est_distance_km': 3,
          'est_fare_cents': 500,
          'driver_earn_cents': 400,
        };

    test('TvdeRide sem a coluna (resposta antiga) = passageiros', () {
      final r = TvdeRide.fromMap(base());
      expect(r.rideKind, RideKind.passageiros);
      expect(r.isEncomenda, isFalse);
    });

    test('TvdeRide de encomenda e o dinheiro igual', () {
      final r = TvdeRide.fromMap({...base(), 'ride_kind': 'encomendas'});
      expect(r.isEncomenda, isTrue);
      expect(r.estFareCents, 500);
      expect(r.driverEarnCents, 400);
    });

    test('a chamada de passageiros às RPCs fica igual à de antes (sem p_ride_kind)', () {
      expect(tvdeParamTipo(RideKind.passageiros), isEmpty);
      expect(tvdeParamTipo(RideKind.encomendas), {'p_ride_kind': 'encomendas'});
    });
  });

  group('frases do estafeta fora dos ecrãs', () {
    test('cliente cancelou: passageiros igual, encomenda com entrega', () {
      expect(textoDoAvisoDeCancelamento(null), 'O cliente cancelou a corrida.');
      expect(textoDoAvisoDeCancelamento(null, rideKind: RideKind.encomendas),
          'O cliente cancelou a entrega.');
    });

    test('oferta falhada', () {
      expect(mensagemDeOfertaFalhada('x'), 'Esta corrida já não está disponível.');
      expect(mensagemDeOfertaFalhada('x', rideKind: RideKind.encomendas),
          'Esta encomenda já não está disponível.');
      expect(mensagemDeOfertaFalhada('queue_full', rideKind: RideKind.encomendas),
          'Já tens uma entrega em fila — só podes levar uma de cada vez.');
    });

    test('pacote ida-e-volta: o ganho continua a ser o número que manda', () {
      final volta = TvdeRide.fromMap({
        'id': 'r2',
        'client_id': 'c1',
        'status': 'motorista_a_caminho',
        'origin_lat': 40.5,
        'origin_lng': -7.2,
        'dest_lat': 40.6,
        'dest_lng': -7.3,
        'est_distance_km': 10,
        'est_fare_cents': 0,
        'driver_earn_cents': 855,
        'roundtrip_credit_id': 'v1',
        'is_return_leg': true,
        'ride_kind': 'encomendas',
      });
      final t = TvdeRoundtripDriverNotice.messageFor(volta, 1760);
      expect(t, contains('€8.55'));
      expect(t, contains('entrega'));
      expect(kPalavrasDePassageiro.hasMatch(t), isFalse, reason: t);
    });
  });

  group('painel (PT-BR)', () {
    final linhas = <Map<String, dynamic>>[
      {'id': 'a', 'ride_kind': 'passageiros', 'corridas': 2, 'ganho_cents': 800, 'dinheiro_em_mao_cents': 500, 'online_cents': 500},
      {'id': 'b', 'ride_kind': 'encomendas', 'corridas': 1, 'ganho_cents': 400, 'dinheiro_em_mao_cents': 500, 'online_cents': 0},
      {'id': 'c', 'corridas': 1, 'ganho_cents': 400, 'dinheiro_em_mao_cents': 0, 'online_cents': 500},
    ];

    test('filtro por tipo (linha antiga sem ride_kind = passageiros)', () {
      expect(filtrarPorTipoTvde(linhas, 'todos').length, 3);
      expect(filtrarPorTipoTvde(linhas, 'encomendas').map((l) => l['id']), ['b']);
      expect(filtrarPorTipoTvde(linhas, 'passageiros').map((l) => l['id']), ['a', 'c']);
      expect(rotuloTipoTvde('encomendas'), 'Encomenda');
    });

    test('acerto partido por tipo soma ao cêntimo', () {
      final s = somarAcertosPorTipo(linhas);
      expect(s['passageiros']!.corridas, 3);
      expect(s['passageiros']!.ganho, 1200);
      expect(s['encomendas']!.ganho, 400);
      expect(s['encomendas']!.dinheiro, 500);
    });
  });
}
