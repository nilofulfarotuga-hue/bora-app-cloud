// Redesenho didático da Limpeza (28/11/2026, pedido do Danilo pela Claude.ai): a primeira escolha em
// 3 cartões grandes; o plano (casa) e as empresas em passos curtos, uma pergunta por ecrã, com
// "Passo X de N", Continuar e Voltar; a opção escolhida em verde cheio com visto; o preço dentro de
// cada frequência com quanto se poupa; resumo simples; os 7 dias numa linha; o −/+ das horas logo ali.
// Sem servidor: a loja falsa devolve os preços como o cleaning_plan_quote. Fotos em test/golden/_fotos/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/models/cleaning_plan_models.dart';
import 'package:bora_app/screens/client/cleaning/cleaning_plan_wizard_screen.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/cleaning_plan_store.dart';
import 'package:bora_app/widgets/escolha_tipo_limpeza.dart';

import 'fabrica_de_fotos.dart';

/// Os preços por hora de cleaning_plan_prices (20261128114406), como o servidor os devolve.
const _porHora = {
  'casa': {'once': 1200, 'biweekly': 1100, 'weekly': 1000, 'multi_weekly': 980},
  'empresa': {'once': 1500, 'weekly_1': 1400, 'weekly_2': 1300, 'weekly_3plus': 1200},
};
const _rotulos = {
  'once': 'Uma vez', 'biweekly': 'De 15 em 15 dias', 'weekly': 'Semanal', 'multi_weekly': 'Mais de uma vez por semana',
  'weekly_1': '1 vez por semana', 'weekly_2': '2 vezes por semana', 'weekly_3plus': '3 ou mais vezes por semana',
};

class _LojaFalsa extends CleaningPlanStore {
  @override
  Future<CleaningPlanQuote?> quote({
    required String segment,
    required String frequency,
    required int hours,
    required int daysPerWeek,
    required int teamSize,
    required String productsBy,
    double? lat,
    double? lng,
  }) async {
    final tabela = _porHora[segment]!;
    final ph = tabela[frequency]!;
    final produtos = segment == 'casa' && productsBy == 'cleaner' ? 300 : 0;
    final total = ph * hours * teamSize + produtos;
    final semana = switch (frequency) {
      'once' => 0.0,
      'biweekly' => 0.5,
      'weekly' || 'weekly_1' => 1.0,
      'weekly_2' => 2.0,
      _ => daysPerWeek.toDouble(),
    };
    final mes = frequency == 'once' ? 1.0 : double.parse((semana * 52 / 12).toStringAsFixed(2));
    return CleaningPlanQuote.fromJson({
      'segment': segment, 'frequency': frequency, 'label': _rotulos[frequency], 'hours': hours, 'team_size': teamSize,
      'client_cents_per_hour': ph, 'pro_cents_per_hour': (ph * 0.85).round(), 'labor_cents': ph * hours * teamSize,
      'products_cents': produtos, 'products_included': segment == 'empresa', 'travel_fee_cents': 0,
      'total_per_visit_cents': total, 'pro_earnings_cents': 0, 'visits_per_month': mes,
      'approx_month_cents': (total * mes).round(), 'min_hours': segment == 'empresa' ? 1 : 2,
      'ladder': [for (final e in tabela.entries) {'frequency': e.key, 'label': _rotulos[e.key], 'client_cents_per_hour': e.value}],
    });
  }

  @override
  Future<Map<String, int>> duracoesPorTipologia() async => const {'t0_t1': 180, 't2': 240, 't3': 300, 't4plus': 360};
}

Widget _assistente(String segment) => ChangeNotifierProvider<CartStore>(
      create: (_) => CartStore(),
      child: CleaningPlanWizardScreen(segment: segment, storeOverride: _LojaFalsa()),
    );

Future<void> _continuar(WidgetTester tester, int vezes) async {
  for (var i = 0; i < vezes; i++) {
    await tester.tap(find.byKey(const Key('plano-continuar')));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// A cor de fundo da opção com esta chave.
Color? _cor(WidgetTester tester, String chave) => tester
    .widget<Material>(find.descendant(of: find.byKey(Key(chave)), matching: find.byType(Material)).first)
    .color;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  group('a primeira escolha: 3 cartões grandes', () {
    for (final t in kTamanhos) {
      testWidgets('cartões no ecrã ${t.$1}', (tester) async {
        String? escolhida;
        await fotografaTela(
          tester,
          nome: 'limpeza_escolha_cartoes',
          tamanho: t,
          tela: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(child: SingleChildScrollView(child: EscolhaTipoLimpeza(onEscolha: (k) => escolhida = k))),
          ),
        );
        expect(find.text('Só uma vez'), findsOneWidget);
        expect(find.text('Todas as semanas, mais barato'), findsOneWidget);
        expect(find.text('Para a minha loja ou empresa'), findsOneWidget);
        expect(find.text('desde 9,80 €/h'), findsOneWidget);
        expect(find.text('desde 12 €/h'), findsNWidgets(2));
        expect(find.text('Popular'), findsOneWidget, reason: 'o selo Popular é o único laranja do ecrã');
        await tester.tap(find.byKey(const Key('limpeza-escolha-plano')));
        expect(escolhida, 'plano');
      });
    }
  });

  group('plano da casa: 5 passos', () {
    testWidgets('anda pelos passos, a escolhida fica verde e o resumo é simples', (tester) async {
      await fotografaTela(tester, nome: 'limpeza_plano_casa_passo1', tamanho: ('pequeno', kEcraPequeno), tela: _assistente('casa'));
      expect(find.text('Passo 1 de 5'), findsOneWidget);
      expect(find.byKey(const Key('plano-voltar')), findsNothing, reason: 'no 1.º passo não há Voltar');
      // a sugestão das horas tem o −/+ logo ali
      expect(find.text('Sugerimos 4 h para esta casa. Podes mudar.'), findsOneWidget);
      expect(find.byKey(const Key('plano-horas-mais')), findsOneWidget);
      expect(find.text('4 h'), findsOneWidget);
      expect(_cor(tester, 'plano-tamanho-t2'), AppColors.primary, reason: 'escolhida = verde cheio');
      expect(_cor(tester, 'plano-tamanho-t3'), isNot(AppColors.primary));
      await tester.tap(find.byKey(const Key('plano-tamanho-t3')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_cor(tester, 'plano-tamanho-t3'), AppColors.primary);
      expect(find.text('5 h'), findsOneWidget, reason: 'T3 sugere 5 h');
      await tester.tap(find.byKey(const Key('plano-horas-menos')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('4 h'), findsOneWidget);

      await _continuar(tester, 1);
      expect(find.text('Passo 2 de 5'), findsOneWidget);
      expect(find.text('Com que frequência?'), findsOneWidget);
      expect(find.text('10,00 €/h'), findsOneWidget, reason: 'o preço vive dentro da opção');
      expect(find.text('Poupas €8,00 por limpeza'), findsOneWidget, reason: 'semanal, 4 h: 2 € × 4 h face a uma vez');
      expect(find.text('Preço por hora'), findsNothing, reason: 'sem a tabela de barras');
      expect(_cor(tester, 'plano-freq-weekly'), AppColors.primary);

      await _continuar(tester, 1);
      expect(find.text('Passo 3 de 5'), findsOneWidget);
      // os 7 dias numa só linha (o Dom não cai sozinho para baixo), no ecrã mais pequeno
      final y = {for (var d = 1; d <= 7; d++) tester.getTopLeft(find.byKey(Key('plano-dia-$d'))).dy};
      expect(y.length, 1, reason: 'Seg a Dom na mesma linha');

      await _continuar(tester, 1);
      expect(find.text('Passo 4 de 5'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Rua da Prova 1');
      await _continuar(tester, 1);
      expect(find.text('Passo 5 de 5'), findsOneWidget);
      expect(find.text('€40,00 por limpeza'), findsOneWidget);
      expect(find.text('cerca de 4 limpezas por mês'), findsOneWidget);
      expect(find.text('Pagas no cartão na véspera de cada limpeza, só quando a profissional está confirmada.'), findsOneWidget);
      expect(find.byKey(const Key('plano-mes-de-uma-vez')), findsNothing, reason: 'na casa não se pergunta como pagar');
      expect(find.textContaining('≈'), findsNothing, reason: 'sem "≈ X € por mês"');
      expect(find.textContaining('em média'), findsNothing);
      expect(find.byKey(const Key('plano-comecar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('plano-voltar')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Passo 4 de 5'), findsOneWidget, reason: 'Voltar recua um passo');
    });

    for (final t in kTamanhos) {
      for (var passo = 1; passo <= 5; passo++) {
        testWidgets('foto do passo $passo no ecrã ${t.$1}', (tester) async {
          await fotografaTela(
            tester,
            nome: 'limpeza_plano_casa_passo$passo',
            tamanho: t,
            tela: _assistente('casa'),
            interagir: (tester) async {
              for (var i = 1; i < passo; i++) {
                if (i == 4) await tester.enterText(find.byType(TextField).first, 'Rua da Prova 1');
                await _continuar(tester, 1);
              }
            },
          );
          expect(find.text('Passo $passo de 5'), findsOneWidget);
        });
      }
    }
  });

  group('Bora Empresas: 6 passos', () {
    testWidgets('espaço → frequência e horas → dias → morada → fatura → resumo', (tester) async {
      await fotografaTela(tester, nome: 'limpeza_plano_empresa_passo1', tamanho: ('pequeno', kEcraPequeno), tela: _assistente('empresa'));
      expect(find.text('Passo 1 de 6'), findsOneWidget);
      expect(_cor(tester, 'plano-espaco-loja'), AppColors.primary);
      await tester.tap(find.byKey(const Key('plano-espaco-otica')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_cor(tester, 'plano-espaco-otica'), AppColors.primary);
      expect(_cor(tester, 'plano-espaco-loja'), isNot(AppColors.primary));

      await _continuar(tester, 1);
      expect(find.text('Passo 2 de 6'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('plano-horas')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('1 h'), findsOneWidget, reason: 'empresa: mínimo 1 h, as horas no mesmo passo');
      expect(find.text('Poupas €1,00 por limpeza'), findsOneWidget);

      await _continuar(tester, 1);
      expect(find.text('Passo 3 de 6'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget, reason: 'a hora à escolha da empresa (20:00 por defeito)');

      await _continuar(tester, 1);
      await tester.enterText(find.byType(TextField).first, 'Rua da Ótica 7');
      await _continuar(tester, 1);
      expect(find.text('Passo 5 de 6'), findsOneWidget);
      expect(find.text('Dados para a fatura'), findsOneWidget);
      // sem dados não continua
      await _continuar(tester, 1);
      expect(find.text('Passo 5 de 6'), findsOneWidget);
      expect(find.text('Falta o nome da empresa.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Ótica Prova');
      await tester.enterText(find.byType(TextField).at(1), '123456789');
      await tester.enterText(find.byType(TextField).at(2), 'faturas@otica.pt');
      await _continuar(tester, 1);
      expect(find.text('Passo 6 de 6'), findsOneWidget);
      expect(find.byKey(const Key('plano-mes-de-uma-vez')), findsOneWidget, reason: 'o mês de uma vez só nas empresas');
      expect(find.text('Pagas no cartão na véspera de cada limpeza, só quando a profissional está confirmada.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plano-mes-de-uma-vez')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_cor(tester, 'plano-mes-de-uma-vez'), AppColors.primary);
      expect(find.text('Pagas no cartão no início de cada mês, só as limpezas com profissional confirmada.'), findsOneWidget);
    });

    for (var passo = 1; passo <= 6; passo++) {
      testWidgets('foto do passo $passo (empresa, ecrã pequeno)', (tester) async {
        await fotografaTela(
          tester,
          nome: 'limpeza_plano_empresa_passo$passo',
          tamanho: ('pequeno', kEcraPequeno),
          tela: _assistente('empresa'),
          interagir: (tester) async {
            for (var i = 1; i < passo; i++) {
              if (i == 4) await tester.enterText(find.byType(TextField).first, 'Rua da Ótica 7');
              if (i == 5) {
                await tester.enterText(find.byType(TextField).at(0), 'Ótica Prova');
                await tester.enterText(find.byType(TextField).at(1), '123456789');
                await tester.enterText(find.byType(TextField).at(2), 'faturas@otica.pt');
              }
              await _continuar(tester, 1);
            }
          },
        );
        expect(find.text('Passo $passo de 6'), findsOneWidget);
      });
    }
  });
}
