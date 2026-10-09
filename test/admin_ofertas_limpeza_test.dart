import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/widgets/admin/ofertas_limpeza_em_aberto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [fecho-total-2026-10-09 · Bloco 4.E] Cartão "Ofertas em aberto" da limpeza
/// (painel admin).
///
/// O que estes testes trancam:
///  (a) cada oferta mostra profissional, hora da limpeza em Lisboa
///      (dd/MM HH:mm), ganho em € grande, "expira em X min"/"expirou",
///      "Tocou N vezes · último às HH:mm" e "Aparelho registrado: Não" a
///      vermelho;
///  (b) sem ofertas diz "Nenhuma oferta à espera agora.";
///  (c) o interruptor "Repetir o toque da oferta" pede motivo (opcional),
///      chama `admin_set_cleaning_offer_reping` e cancelar não chama nada.
///
/// A RPC é uma função falsa injetada: nunca toca na rede.
final _agora = DateTime.utc(2026, 10, 10, 12, 0);

class _RpcFalso {
  _RpcFalso({this.vazio = false});
  final bool vazio;
  bool repeticao = true;
  final chamadas = <(String, Map<String, dynamic>)>[];

  int get chamadasReping =>
      chamadas.where((c) => c.$1 == 'admin_set_cleaning_offer_reping').length;

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, Map<String, dynamic>.from(params)));
    switch (fn) {
      case 'admin_cleaning_offers':
        return {
          'repeticao_ligada': repeticao,
          'ofertas': vazio
              ? <Map<String, dynamic>>[]
              : [
                  {
                    'booking_id': 'b-1',
                    // 13:30 UTC = 14:30 em Lisboa (horário de verão).
                    'marcada_para': '2026-10-10T13:30:00Z',
                    'cidade': 'Guarda',
                    'ganho_profissional_cents': 2550,
                    'expira_em': '2026-10-10T12:05:00Z',
                    'expirada': false,
                    'profissional': 'Ana Costa',
                    'profissional_user_id': 'u-ana',
                    'toques': 3,
                    // 11:58 UTC = 12:58 em Lisboa.
                    'ultimo_toque': '2026-10-10T11:58:00Z',
                    'aparelho_registado': false,
                    'teste': false,
                  },
                  {
                    'booking_id': 'b-2',
                    // Dezembro: Lisboa = UTC.
                    'marcada_para': '2026-12-01T09:00:00Z',
                    'cidade': 'Guarda',
                    'ganho_profissional_cents': 1800,
                    'expira_em': '2026-10-10T11:50:00Z',
                    'expirada': true,
                    'profissional': 'Bia Lopes',
                    'profissional_user_id': 'u-bia',
                    'toques': 0,
                    'ultimo_toque': null,
                    'aparelho_registado': true,
                    'teste': true,
                  },
                ],
        };
      case 'admin_set_cleaning_offer_reping':
        final antes = repeticao;
        repeticao = params['p_ligado'] == true;
        return {'ok': true, 'antes': antes, 'depois': repeticao};
      default:
        return null;
    }
  }
}

Future<void> _montar(WidgetTester t, _RpcFalso rpc) async {
  // Telemóvel de 360 px: nada pode estourar.
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: OfertasLimpezaEmAberto(rpc: rpc.call, agora: () => _agora),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('textos de prazo e de toques', () {
    expect(textoExpiraOferta(DateTime.utc(2026, 10, 10, 12, 5), _agora),
        'expira em 5 min');
    expect(
        textoExpiraOferta(DateTime.utc(2026, 10, 10, 12, 0, 30), _agora),
        'expira em menos de 1 min');
    expect(textoExpiraOferta(DateTime.utc(2026, 10, 10, 11, 0), _agora),
        'expirou');
    expect(
        textoExpiraOferta(DateTime.utc(2026, 10, 10, 13, 0), _agora,
            expirada: true),
        'expirou');
    expect(textoToquesOferta(0, null), 'Ainda não tocou');
    expect(textoToquesOferta(1, null), 'Tocou 1 vez');
    expect(textoToquesOferta(4, DateTime.utc(2026, 1, 15, 9, 7)),
        'Tocou 4 vezes · último às 09:07');
  });

  testWidgets('mostra cada oferta com hora de Lisboa, ganho e aparelho',
      (t) async {
    final rpc = _RpcFalso();
    await _montar(t, rpc);

    expect(find.text('Ofertas em aberto (2)'), findsOneWidget);
    expect(find.text('Ana Costa'), findsOneWidget);
    expect(find.text('Limpeza: 10/10 14:30 · Guarda'), findsOneWidget);
    expect(find.text('€25.50'), findsOneWidget);
    expect(find.text('expira em 5 min'), findsOneWidget);
    expect(find.text('Tocou 3 vezes · último às 12:58'), findsOneWidget);

    expect(find.text('Bia Lopes'), findsOneWidget);
    expect(find.text('Limpeza: 01/12 09:00 · Guarda'), findsOneWidget);
    expect(find.text('€18.00'), findsOneWidget);
    expect(find.text('expirou'), findsOneWidget);
    expect(find.text('Ainda não tocou'), findsOneWidget);
    expect(find.text('TESTE'), findsOneWidget);

    // "Não" a vermelho (sem aparelho o aviso não chega); "Sim" a verde.
    final nao = t.widget<Text>(find.text('Não'));
    expect(nao.style?.color, AppColors.error);
    expect(find.text(' — sem celular registrado o aviso não chega'),
        findsOneWidget);
    final sim = t.widget<Text>(find.text('Sim'));
    expect(sim.style?.color, AppColors.primary);

    expect(t.widget<Switch>(find.byKey(const ValueKey('switch_repetir_toque')))
        .value, isTrue);
  });

  testWidgets('sem ofertas diz que não há nenhuma à espera', (t) async {
    await _montar(t, _RpcFalso(vazio: true));
    expect(find.text('Nenhuma oferta à espera agora.'), findsOneWidget);
    expect(find.text('Ofertas em aberto (0)'), findsOneWidget);
  });

  testWidgets('interruptor do toque repetido: cancelar não chama; confirmar '
      'chama com motivo opcional', (t) async {
    final rpc = _RpcFalso();
    await _montar(t, rpc);
    final interruptor = find.byKey(const ValueKey('switch_repetir_toque'));

    await t.tap(interruptor);
    await t.pumpAndSettle();
    expect(find.text('Desligar o toque repetido?'), findsOneWidget);
    expect(find.text('Motivo (opcional)'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(rpc.chamadasReping, 0);

    await t.tap(interruptor);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Desligar'));
    await t.pumpAndSettle();

    final c = rpc.chamadas
        .singleWhere((c) => c.$1 == 'admin_set_cleaning_offer_reping');
    expect(c.$2, {'p_ligado': false, 'p_motivo': ''});
    expect(find.text('Toque repetido desligado.'), findsOneWidget);
    expect(t.widget<Switch>(interruptor).value, isFalse);
  });
}
