import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/screens/admin/admin_pendencias_operacao_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden/fabrica_de_fotos.dart' show carregaFonteInter;

/// [ronda-fecho-2026-09-22 · BLOCO E] Tela "Pendências de operação" (admin).
///
/// O que estes testes trancam:
///  (a) as 8 caixas aparecem, pela ordem, com os totais no cabeçalho, e nada
///      estoura a 360×800 nem a 1024×768;
///  (b) "Avisar por push" chama `admin_driver_avisar_gps` com o `p_driver`
///      da linha e mostra o resultado numa SnackBar;
///  (c) "Corrigir km e libertar" abre o diálogo com a distância da ida
///      pré-preenchida, aceita 2.43 e chama `admin_tvde_ride_release_hold`
///      com `p_est_distance_km` 2.43 e `p_cancelar` false;
///  (d) "Cancelar corrida presa" pede confirmação e só chama
///      `tvde_cancel_ride` depois do "Sim";
///  (e) sem nada pendente a tela diz "Nada pendente";
///  (f) o botão "Abrir" só aparece para rotas que existem em `main.dart`.
///
/// A tela recebe `carregar` e `chamarRpc` falsos: nunca toca no Supabase.
class _RpcFalso {
  final chamadas = <(String, Map<String, dynamic>)>[];

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, Map<String, dynamic>.from(params)));
    switch (fn) {
      case 'admin_driver_avisar_gps':
        return {'ok': true, 'driver': 'Euliney Fernandes', 'gps_age_s': 1140};
      case 'admin_tvde_ride_release_hold':
        return {
          'ok': true,
          'ride_id': params['p_ride_id'],
          'accao': params['p_cancelar'] == true ? 'cancelada' : 'libertada',
          'est_distance_km': params['p_est_distance_km'],
          'driver_earn_cents': 350,
        };
      case 'admin_tvde_reservation_force_search':
        return true;
      case 'admin_release_stuck_reservation':
        return {'ok': true, 'status': 'cancelled_by_admin'};
      default:
        return null;
    }
  }
}

/// Mapa com a forma real do RPC `admin_pendencias_operacao` (23/09/2026),
/// com pelo menos um item em cada secção.
Map<String, dynamic> _dados({bool vazio = false}) {
  final agora = DateTime.now().toUtc();
  String ha(Duration d) => agora.subtract(d).toIso8601String();
  String daqui(Duration d) => agora.add(d).toIso8601String();

  if (vazio) {
    return {
      'gerado_em': agora.toIso8601String(),
      'gps_limite_s': 180,
      'totais': {for (final s in kSecoesPendencias) s.chave: 0},
      for (final s in kSecoesPendencias) s.chave: <Map<String, dynamic>>[],
    };
  }

  return {
    'gerado_em': agora.toIso8601String(),
    'gps_limite_s': 180,
    'totais': {
      'taloes': 1,
      'pagamentos_falhados': 1,
      'pacotes_sem_volta': 1,
      'voltas_retidas': 1,
      'cancelamentos_taxa_sem_estafeta': 1,
      'reservas_falhadas': 2,
      'motoristas_gps_parado': 1,
      'estafetas_sem_push': 1,
    },
    'taloes': [
      {
        'receipt_id': 'rc-1',
        'order_id': 'ord-77',
        'vendor_name': 'Continente Guarda',
        'driver_uid': 'u-est-1',
        'driver_name': 'Ney Silva',
        'valor_cents': 2345,
        'created_at': ha(const Duration(hours: 3)),
        'is_test_order': false,
        'accao': {
          'rpc': 'admin_mark_receipt_paid | admin_mark_receipt_paid_external '
              '| admin_reject_receipt',
          'rota': '/admin/reembolsos',
          'p_receipt_id': 'rc-1',
        },
      },
    ],
    'pagamentos_falhados': [
      {
        'ride_id': 'ride-pag-1',
        'created_at': ha(const Duration(minutes: 40)),
        'status': 'solicitada',
        'payment_method': 'mbway',
        'payment_status': 'requires_action',
        'cancel_reason': null,
        'payment_intent_id': 'pi_123',
        'est_fare_cents': 650,
        'origin_label': 'Rua da Sé, Guarda',
        'dest_label': 'Hospital Sousa Martins',
        'client_id': 'c-1',
        'client_name': 'Maria Antunes',
        'client_phone': '910000001',
        'preso': true,
        'accao': {
          'rota': '/admin/tvde/pagamentos',
          'rpc':
              "tvde_cancel_ride(p_ride_id, 'cliente', 'admin_stuck_payment')",
          'tel': '910000001',
        },
      },
    ],
    'pacotes_sem_volta': [
      {
        'credit_id': 'cred-1',
        'status': 'ativo',
        'paid_cents': 800,
        'pago_online': true,
        'created_at': ha(const Duration(hours: 5)),
        'expires_at': daqui(const Duration(hours: 19)),
        'outbound_ride_id': 'ride-ida-1',
        'ida_status': 'concluida',
        'origin_label': 'Guarda Gare',
        'dest_label': 'Praça Velha',
        'client_id': 'c-2',
        'client_name': 'João Pires',
        'client_phone': '910000002',
        'accao': {
          'rota': '/admin/tvde/ida-e-volta',
          'tel': '910000002',
          'nota': 'Vale ativo: o cliente pode chamar a volta na app.',
        },
      },
    ],
    'voltas_retidas': [
      {
        'ride_id': 'ride-volta-1',
        'created_at': ha(const Duration(minutes: 25)),
        'hold_reason': 'distancia_suspeita',
        'hold_at': ha(const Duration(minutes: 25)),
        'est_distance_km': 9.8,
        'driver_earn_cents': 350,
        'origin_label': 'Praça Velha',
        'dest_label': 'Guarda Gare',
        'ida_km': 2.1,
        'detalhe': 'volta 9.8 km vs ida 2.1 km',
        'client_id': 'c-3',
        'client_name': 'Ana Lopes',
        'client_phone': '910000003',
        'accao': {
          'rpc': 'admin_tvde_ride_release_hold',
          'p_ride_id': 'ride-volta-1',
          'nota': 'Corrigir a distância (km) e libertar, ou cancelar e '
              'devolver o vale.',
        },
      },
    ],
    'cancelamentos_taxa_sem_estafeta': [
      {
        'kind': 'pedido',
        'id': 'ord-90',
        'customer_name': 'Rui Matos',
        'vendor_name': 'Sabores de Casa',
        'fee_cents': 150,
        'cancelled_at': ha(const Duration(days: 2)),
        'cancel_reason': 'client_changed_mind',
        'refund_status': 'none',
        'payment_method': 'card',
        'accao': {
          'rota': '/admin/orders/ord-90',
          'nota': 'Perdoar a taxa é dinheiro real: só com o vai do Danilo '
              '(wallet_*).',
        },
      },
    ],
    'reservas_falhadas': [
      {
        'kind': 'corrida_marcada',
        'id': 'ride-res-1',
        'quando': daqui(const Duration(hours: 2)),
        'status': 'agendada',
        'reservation_status': 'sem_motorista',
        'origin_label': 'Guarda Gare',
        'dest_label': 'Aeroporto do Porto',
        'payment_method': 'card',
        'client_name': 'Carla Dias',
        'client_phone': '910000004',
        'motivo': 'Ninguém aceitou a reserva',
        'accao': {
          'rota': '/admin/tvde/reservas',
          'rpc': 'admin_tvde_reservation_force_search | '
              'admin_tvde_reservation_set_driver | '
              'admin_tvde_reservation_cancel',
          'p_ride_id': 'ride-res-1',
        },
      },
      {
        'kind': 'mesa',
        'id': 'res-mesa-1',
        'quando': daqui(const Duration(hours: 6)),
        'status': 'pending_payment',
        'reservation_status': null,
        'origin_label': 'Sabores de Casa',
        'dest_label': null,
        'payment_method': 'cash',
        'client_name': 'Pedro Rocha',
        'client_phone': '910000005',
        'motivo': 'Reserva de mesa presa em pending_payment há mais de 60 min',
        'accao': {
          'rota': '/admin/reservas/presas',
          'rpc': 'admin_release_stuck_reservation',
          'p_reservation_id': 'res-mesa-1',
        },
      },
    ],
    'motoristas_gps_parado': [
      {
        'user_id': 'u-gps-1',
        'driver_id': 'd-gps-1',
        'name': 'Euliney Fernandes',
        'phone': '910000006',
        'vehicle_type': 'car',
        'heartbeat_age_s': 3,
        'gps_age_s': 1140,
        'gps_fresco': false,
        'last_platform': 'android_app',
        'tem_notificacoes': true,
        'accao': {
          'rpc': 'admin_driver_avisar_gps',
          'p_driver': 'u-gps-1',
          'rota': '/admin/drivers',
          'tel': '910000006',
        },
      },
    ],
    'estafetas_sem_push': [
      {
        'user_id': 'u-push-1',
        'driver_id': 'd-push-1',
        'name': 'Valdemir Costa',
        'phone': '910000007',
        'heartbeat_age_s': 12,
        'last_platform': 'web',
        'accao': {
          'rota': '/admin/drivers',
          'tel': '910000007',
          'nota': 'Pedir para abrir a app e tocar em Ativar notificações.',
        },
      },
    ],
  };
}

Future<_RpcFalso> _abrir(
  WidgetTester tester, {
  Size tamanho = const Size(1024, 768),
  bool vazio = false,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rpc = _RpcFalso();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: AdminPendenciasOperacaoScreen(
      carregar: () async => _dados(vazio: vazio),
      chamarRpc: rpc.call,
    ),
  ));
  await tester.pumpAndSettle();
  return rpc;
}

/// Rola a lista até o alvo estar mesmo à vista (a lista é preguiçosa: o que
/// está fora do ecrã nem sequer é construído).
Future<void> _rolarAte(WidgetTester tester, Finder alvo) async {
  await tester.scrollUntilVisible(alvo, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(carregaFonteInter);

  group('funções puras', () {
    test('rotaAdminRegistada só deixa abrir rotas que existem em main.dart',
        () {
      expect(rotaAdminRegistada('/admin/tvde/pagamentos'), isTrue);
      expect(rotaAdminRegistada('/admin/robot'), isTrue);
      expect(rotaAdminRegistada('/admin/tvde/reservas'), isTrue);
      expect(rotaAdminRegistada('/admin/orders/ord-90'), isTrue);
      expect(rotaAdminRegistada('/admin/orders/'), isFalse);
      expect(rotaAdminRegistada('/admin/reembolsos'), isTrue);
      expect(rotaAdminRegistada('/admin/tvde/ida-e-volta'), isTrue);
      expect(rotaAdminRegistada('/admin/drivers'), isTrue);
      expect(rotaAdminRegistada('/admin/reservas/presas'), isTrue);
      expect(rotaAdminRegistada(null), isFalse);
      expect(rotaAdminRegistada(''), isFalse);
    });

    test('haQuantoTexto fala em minutos, horas, dias e futuro', () {
      final agora = DateTime(2026, 9, 23, 14, 0);
      expect(
          haQuantoTexto(agora.subtract(const Duration(seconds: 20)),
              agora: agora),
          'agora mesmo');
      expect(
          haQuantoTexto(agora.subtract(const Duration(minutes: 5)),
              agora: agora),
          'há 5 min');
      expect(
          haQuantoTexto(agora.subtract(const Duration(hours: 3)), agora: agora),
          'há 3 h');
      expect(
          haQuantoTexto(agora.subtract(const Duration(days: 3)), agora: agora),
          'há 3 dias');
      expect(
          haQuantoTexto(agora.add(const Duration(minutes: 40)), agora: agora),
          'daqui a 40 min');
      expect(haQuantoTexto(null), '');
    });

    test('km: texto curto e leitura com vírgula ou ponto', () {
      expect(numeroCurto(2.1), '2.1');
      expect(numeroCurto(3), '3');
      expect(numeroCurto(2.43), '2.43');
      expect(kmTexto(null), '? km');
      expect(kmDeTexto('2,43'), 2.43);
      expect(kmDeTexto('2.43'), 2.43);
      expect(kmDeTexto('0'), isNull);
      expect(kmDeTexto('abc'), isNull);
    });

    test('erros do servidor em palavras simples', () {
      expect(mensagemErroPendencias(Exception('ride_not_on_hold')),
          contains('já não está retida'));
      expect(
          mensagemErroPendencias(
              Exception('PostgrestException(message: distancia_invalida)')),
          contains('maior que 0 km'));
      expect(
          mensagemErroPendencias(
              Exception('requires_refund_manual_review: pi_1')),
          contains('só com o vai do Danilo'));
    });
  });

  group('tela', () {
    for (final tamanho in const [Size(360, 800), Size(1024, 768)]) {
      testWidgets(
          '(a) renderiza os 8 títulos e os totais sem estouro a '
          '${tamanho.width.toInt()}×${tamanho.height.toInt()}', (tester) async {
        await _abrir(tester, tamanho: tamanho);

        expect(find.text('Pendências de operação'), findsOneWidget);
        expect(find.textContaining('Gerado às'), findsOneWidget);
        expect(find.textContaining('GPS parado = sem posição há mais de 180 s'),
            findsOneWidget);
        expect(find.text('Nada pendente 🎉'), findsNothing);
        for (final s in kSecoesPendencias) {
          expect(find.text(s.chip), findsOneWidget,
              reason: 'chip de totais "${s.chip}" em falta');
        }
        expect(tester.takeException(), isNull);

        // Pela ordem pedida, cada caixa aparece — e nada estoura pelo caminho.
        for (final s in kSecoesPendencias) {
          await _rolarAte(tester, find.text(s.titulo));
          expect(find.text(s.titulo), findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: 'estouro ao chegar a "${s.titulo}"');
        }
        // Até ao último cartão, para tudo ter sido desenhado uma vez.
        await _rolarAte(
            tester,
            find.text(
                'Pedir para abrir a app e tocar em Ativar notificações.'));
        expect(find.text('GPS parado há 19 min'), findsOneWidget);
        expect(find.textContaining('Sinal (heartbeat) há 3 s'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '(b) "Avisar por push" chama admin_driver_avisar_gps com o p_driver '
        'certo e mostra SnackBar', (tester) async {
      final rpc = await _abrir(tester);
      await _rolarAte(tester, find.text('Avisar por push'));

      await tester.tap(find.text('Avisar por push'));
      await tester.pumpAndSettle();

      expect(rpc.chamadas.length, 1);
      expect(rpc.chamadas.single.$1, 'admin_driver_avisar_gps');
      expect(rpc.chamadas.single.$2, {'p_driver': 'u-gps-1'});
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Aviso enviado a Euliney Fernandes'),
          findsOneWidget);
    });

    testWidgets(
        '(c) "Corrigir km e libertar" abre o diálogo, aceita 2.43 e chama '
        'admin_tvde_ride_release_hold com p_cancelar false', (tester) async {
      final rpc = await _abrir(tester);
      await _rolarAte(tester, find.text('Corrigir km e libertar'));

      await tester.tap(find.text('Corrigir km e libertar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(rpc.chamadas, isEmpty, reason: 'abrir o diálogo não chama nada');
      final campoKm = find.byKey(const Key('pendencias_km'));
      expect(tester.widget<TextField>(campoKm).controller!.text, '2.1',
          reason: 'pré-preenchido com a distância da ida');

      await tester.enterText(campoKm, '2.43');
      await tester.tap(find.text('Libertar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(rpc.chamadas.length, 1);
      final (fn, params) = rpc.chamadas.single;
      expect(fn, 'admin_tvde_ride_release_hold');
      expect(params['p_ride_id'], 'ride-volta-1');
      expect(params['p_est_distance_km'], 2.43);
      expect(params['p_cancelar'], isFalse);
      expect(
          find.textContaining('Volta libertada com 2.43 km'), findsOneWidget);
    });

    testWidgets('(c2) distância inválida não fecha o diálogo nem chama o RPC',
        (tester) async {
      final rpc = await _abrir(tester);
      await _rolarAte(tester, find.text('Corrigir km e libertar'));
      await tester.tap(find.text('Corrigir km e libertar'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('pendencias_km')), '0');
      await tester.tap(find.text('Libertar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Escreve uma distância maior que 0.'), findsOneWidget);
      expect(rpc.chamadas, isEmpty);
    });

    testWidgets(
        '(d) "Cancelar corrida presa" pede confirmação e só chama '
        'tvde_cancel_ride depois de confirmar', (tester) async {
      final rpc = await _abrir(tester);
      await _rolarAte(tester, find.text('Cancelar corrida presa'));

      await tester.tap(find.text('Cancelar corrida presa'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(rpc.chamadas, isEmpty);

      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(rpc.chamadas, isEmpty, reason: 'desistir não chama o RPC');

      await tester.tap(find.text('Cancelar corrida presa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sim, cancelar'));
      await tester.pumpAndSettle();

      expect(rpc.chamadas.length, 1);
      expect(rpc.chamadas.single.$1, 'tvde_cancel_ride');
      expect(rpc.chamadas.single.$2, {
        'p_ride_id': 'ride-pag-1',
        'p_actor': 'cliente',
        'p_reason': 'admin_stuck_payment',
      });
      expect(find.text('Corrida cancelada.'), findsOneWidget);
    });

    testWidgets('(e) mapa com listas vazias mostra "Nada pendente"',
        (tester) async {
      await _abrir(tester, vazio: true);

      expect(find.text('Nada pendente 🎉'), findsOneWidget);
      for (final s in kSecoesPendencias) {
        expect(find.text(s.chip), findsOneWidget);
      }
      expect(find.text('Avisar por push'), findsNothing);
      expect(find.text('Copiar id'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '(f) "Abrir" só para rotas registadas (todas as do RPC já existem)',
        (tester) async {
      await _abrir(tester);

      // Talões apontam para /admin/reembolsos (registada a 23/09): com "Abrir".
      await _rolarAte(tester, find.text('Abrir reembolsos'));
      expect(find.text('Abrir reembolsos'), findsOneWidget);
      // Pagamentos apontam para /admin/tvde/pagamentos (existe): com "Abrir".
      await _rolarAte(tester, find.text('Abrir pagamentos'));
      expect(find.text('Abrir pagamentos'), findsOneWidget);
      // Cancelamento de pedido → /admin/orders/{id} (onGenerateRoute).
      await _rolarAte(tester, find.text('Abrir pedido'));
      expect(find.text('Abrir pedido'), findsOneWidget);
      // GPS parado e sem push apontam ambos para /admin/drivers (registada a
      // 23/09): um "Abrir estafetas" em cada secção.
      await _rolarAte(tester, find.text('Abrir estafetas').first);
      expect(find.text('Abrir estafetas'), findsNWidgets(2));
    });
  });
}
