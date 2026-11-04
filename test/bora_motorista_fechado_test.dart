// Missão fechar-bora-motorista (04/11/2026): o Bora Motorista (TVDE de
// passageiros) fecha nas apps com `platform_settings.tvde_app_visivel`.
// Estes testes provam o FECHADO: começa fechado (na dúvida, esconde), e
// fechado não se desenha nem o ladrilho, nem a "Nova categoria", nem as
// encomendas pelo motor TVDE, nem o papel "Corridas de passageiros", nem os
// avisos de corridas no sininho. Reabrir volta a mostrar tudo.
import 'package:bora_app/services/in_app_notifications_service.dart';
import 'package:bora_app/services/papeis_de_trabalho.dart';
import 'package:bora_app/services/tvde_visibilidade.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:bora_app/widgets/caixa_de_papeis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _caixa() => MaterialApp(
      home: Scaffold(
        body: CaixaDePapeis(
          iniciais: const [
            PapelDeTrabalho(papel: 'driver', aceita: true),
            PapelDeTrabalho(papel: 'delivery', aceita: true),
            PapelDeTrabalho(papel: 'cleaner', aceita: true),
          ],
        ),
      ),
    );

void main() {
  // Tem de correr primeiro: o estado de arranque, antes de qualquer leitura.
  test('o interruptor começa FECHADO e por ler (na dúvida, esconde)', () {
    expect(TvdeVisibilidade.lido, isFalse);
    expect(TvdeVisibilidade.aberto, isFalse);
  });

  test('sem servidor (Supabase por iniciar) a leitura falha e fica fechado',
      () async {
    await TvdeVisibilidade.refresh();
    expect(TvdeVisibilidade.aberto, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  group('TvdeStore', () {
    test('fechado: nada do Bora Motorista na home', () {
      TvdeVisibilidade.definirParaTeste(false);
      final s = TvdeStore();
      addTearDown(s.dispose);
      expect(s.appVisivel, isFalse);
      expect(s.mostrarBoraMotorista, isFalse);
      expect(s.mostrarCategoriaPorDescobrir, isFalse);
      expect(s.encomendasEnabled, isFalse);
    });

    test('avisa quem o ouve quando o interruptor muda, e deixa de ouvir '
        'depois do dispose', () {
      TvdeVisibilidade.definirParaTeste(false);
      final s = TvdeStore();
      var avisos = 0;
      s.addListener(() => avisos++);
      TvdeVisibilidade.definirParaTeste(true);
      expect(avisos, 1);
      expect(s.appVisivel, isTrue);
      s.dispose();
      // Depois do dispose mudar o interruptor não rebenta (ouvinte tirado).
      TvdeVisibilidade.definirParaTeste(false);
      expect(avisos, 1);
    });
  });

  group('caixa "O que queres aceitar?"', () {
    testWidgets('fechado: sem "Corridas de passageiros"', (tester) async {
      TvdeVisibilidade.definirParaTeste(false);
      await tester.pumpWidget(_caixa());
      expect(find.text('Corridas de passageiros'), findsNothing);
      expect(find.text('Entregas'), findsOneWidget);
      expect(find.text('Limpeza'), findsOneWidget);
    });

    testWidgets('aberto: volta a aparecer', (tester) async {
      TvdeVisibilidade.definirParaTeste(true);
      addTearDown(() => TvdeVisibilidade.definirParaTeste(false));
      await tester.pumpWidget(_caixa());
      expect(find.text('Corridas de passageiros'), findsOneWidget);
    });
  });

  test('sininho: os avisos de corridas reconhecem-se pelo tipo', () {
    expect(eAvisoDoBoraMotorista({'kind': 'tvde_cancel_comp'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'tvde_goodwill_credit'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'ride_update'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'cashback'}), isFalse);
    expect(eAvisoDoBoraMotorista({'kind': 'order_weight_adjusted'}), isFalse);
    expect(eAvisoDoBoraMotorista({'kind': null}), isFalse);
  });
}
