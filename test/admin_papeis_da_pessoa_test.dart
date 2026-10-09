import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/widgets/admin/papeis_da_pessoa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [fecho-total-2026-10-09 · Bloco 4.E] "Papéis desta pessoa" (painel admin).
///
/// O que estes testes trancam:
///  (a) os estados do servidor viram PT-BR (Aprovado, Em análise, Recusado,
///      Suspenso, Sem perfil) e o nome técnico do papel nunca aparece cru;
///  (b) mudar o interruptor PEDE o motivo e NÃO chama `admin_set_user_role`
///      sem 3 letras (nem ao cancelar);
///  (c) com motivo, chama com `p_user_id`/`p_papel`/`p_ativo`/`p_motivo` certos
///      e mostra "antes → depois";
///  (d) cada código de erro do servidor vira uma frase simples, e a exceção do
///      gatilho de conformidade aparece em PT-BR.
///
/// A RPC é uma função falsa injetada: estes testes nunca tocam na rede.
class _RpcFalso {
  _RpcFalso({this.respostaSet});

  final chamadas = <(String, Map<String, dynamic>)>[];

  /// Se definida, manda na resposta de `admin_set_user_role` (pode lançar).
  final Object? Function(Map<String, dynamic> params)? respostaSet;

  Map<String, dynamic> papeis = {
    'estafeta': {'estado': 'approved', 'ligado': true, 'ja_foi_aprovado': true},
    'limpeza': {'estado': 'suspended'},
    'lavagem': null,
  };

  int get chamadasSet =>
      chamadas.where((c) => c.$1 == 'admin_set_user_role').length;

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, Map<String, dynamic>.from(params)));
    switch (fn) {
      case 'admin_user_roles':
        return papeis;
      case 'admin_set_user_role':
        if (respostaSet != null) return respostaSet!(params);
        // Comportamento do servidor: desligar estafeta aprovado → rejected.
        final papel = params['p_papel'] as String;
        final antes = (papeis[papel] as Map)['estado'] as String;
        final depois = params['p_ativo'] == true
            ? 'approved'
            : (papel == 'estafeta' ? 'rejected' : 'suspended');
        papeis = {
          ...papeis,
          papel: {...(papeis[papel] as Map), 'estado': depois, 'ligado': false},
        };
        return {'ok': true, 'papel': papel, 'antes': antes, 'depois': depois};
      default:
        return null;
    }
  }
}

Future<void> _montar(WidgetTester t, _RpcFalso rpc,
    {VoidCallback? aoMudar}) async {
  // Telemóvel de 360 px: nada pode estourar.
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PapeisDaPessoa(
          userId: 'u-1',
          nome: 'Maria Silva',
          rpc: rpc.call,
          aoMudar: aoMudar,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Switch _switch(WidgetTester t, String papel) =>
    t.widget<Switch>(find.byKey(ValueKey('papel_switch_$papel')));

void main() {
  group('traduções', () {
    test('estados do servidor em PT-BR', () {
      expect(rotuloEstadoPapel('approved'), 'Aprovado');
      expect(rotuloEstadoPapel('pending'), 'Em análise');
      expect(rotuloEstadoPapel('rejected'), 'Recusado');
      expect(rotuloEstadoPapel('suspended'), 'Suspenso');
      expect(rotuloEstadoPapel(null), 'Sem perfil');
      expect(rotuloEstadoPapel('qualquer_coisa'), 'Estado desconhecido');
    });

    test('nome do papel nunca sai cru (PADRAO_BORA 1.16)', () {
      expect(rotuloPapelPessoa('estafeta'), 'Estafeta (entregas)');
      expect(rotuloPapelPessoa('limpeza'), 'Limpeza');
      expect(rotuloPapelPessoa('lavagem'), 'Lavagem de carros');
      expect(rotuloPapelPessoa('driver'), 'Outro papel');
      expect(rotuloPapelPessoa('washer'), isNot(contains('washer')));
    });

    test('cada código de erro vira uma frase simples', () {
      expect(mensagemErroPapel('motivo_obrigatorio'),
          'Falta o motivo: escreva pelo menos 3 letras.');
      expect(mensagemErroPapel('papel_invalido'),
          'Papel inválido: só dá para mexer em estafeta, limpeza ou lavagem.');
      expect(mensagemErroPapel('sem_perfil'),
          'Esta pessoa não tem cadastro nesse papel.');
      expect(mensagemErroPapel('usa_aprovacao_normal'),
          contains('Aprove pela tela de candidaturas'));
      expect(mensagemErroPapel('trabalho_em_curso'),
          contains('tem um trabalho em andamento'));
      // Código novo do servidor: não se esconde, mas vem dentro de uma frase.
      expect(mensagemErroPapel('codigo_novo'),
          'Não deu certo (resposta do servidor: codigo_novo).');
      expect(mensagemErroPapel(null),
          'Não deu certo (resposta do servidor: sem código).');
    });

    test('motivo precisa de 3 letras sem contar espaços', () {
      expect(motivoValido(''), isFalse);
      expect(motivoValido('  ab  '), isFalse);
      expect(motivoValido('abc'), isTrue);
    });
  });

  group('interruptor por papel', () {
    testWidgets('mostra o estado de cada papel vindo do servidor',
        (t) async {
      final rpc = _RpcFalso();
      await _montar(t, rpc);

      expect(find.text('Papéis desta pessoa — Maria Silva'), findsOneWidget);
      expect(find.text('Aprovado · online agora (app ligada)'), findsOneWidget);
      expect(find.text('Suspenso'), findsOneWidget);
      expect(find.text('Sem perfil'), findsOneWidget);
      expect(_switch(t, 'estafeta').value, isTrue);
      expect(_switch(t, 'limpeza').value, isFalse);
      // Sem cadastro de lavagem: interruptor desligado e sem ação.
      expect(_switch(t, 'lavagem').onChanged, isNull);
      expect(rpc.chamadas.single.$1, 'admin_user_roles');
      expect(rpc.chamadas.single.$2, {'p_user_id': 'u-1'});
      expect(find.textContaining('Ligar só repõe quem já foi aprovado antes'),
          findsOneWidget);
    });

    testWidgets('pede o motivo e NÃO chama o servidor sem motivo', (t) async {
      final rpc = _RpcFalso();
      await _montar(t, rpc);

      await t.tap(find.byKey(const ValueKey('papel_switch_estafeta')));
      await t.pumpAndSettle();
      expect(find.text('Desligar Estafeta (entregas)?'), findsOneWidget);
      expect(find.text('Motivo (obrigatório)'), findsOneWidget);

      // Vazio → não fecha, não chama.
      await t.tap(find.widgetWithText(FilledButton, 'Desligar'));
      await t.pumpAndSettle();
      expect(find.text('Escreva o motivo (mínimo 3 letras).'), findsOneWidget);
      expect(rpc.chamadasSet, 0);

      // Duas letras (com espaços) → continua sem chamar.
      await t.enterText(find.byKey(const ValueKey('campo_motivo')), '  ab  ');
      await t.tap(find.widgetWithText(FilledButton, 'Desligar'));
      await t.pumpAndSettle();
      expect(find.text('Escreva o motivo (mínimo 3 letras).'), findsOneWidget);
      expect(rpc.chamadasSet, 0);

      // Cancelar → fecha sem chamar, interruptor fica como estava.
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(rpc.chamadasSet, 0);
      expect(_switch(t, 'estafeta').value, isTrue);
    });

    testWidgets('com motivo chama admin_set_user_role e mostra antes → depois',
        (t) async {
      final rpc = _RpcFalso();
      var mudou = 0;
      await _montar(t, rpc, aoMudar: () => mudou++);

      await t.tap(find.byKey(const ValueKey('papel_switch_estafeta')));
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const ValueKey('campo_motivo')), '  Documento vencido  ');
      await t.tap(find.widgetWithText(FilledButton, 'Desligar'));
      await t.pumpAndSettle();

      final set = rpc.chamadas.where((c) => c.$1 == 'admin_set_user_role');
      expect(set, hasLength(1));
      expect(set.single.$2, {
        'p_user_id': 'u-1',
        'p_papel': 'estafeta',
        'p_ativo': false,
        'p_motivo': 'Documento vencido',
      });
      expect(
          find.text('Estafeta (entregas): Aprovado → Recusado. Fica registrado '
              'no histórico (admin_audit_log).'),
          findsOneWidget);
      // Recarregou do servidor: agora aparece Recusado e o interruptor desligado.
      expect(find.text('Recusado'), findsOneWidget);
      expect(_switch(t, 'estafeta').value, isFalse);
      expect(mudou, 1);
    });

    testWidgets('traduz o código de erro devolvido pelo servidor', (t) async {
      final rpc = _RpcFalso(
          respostaSet: (_) => {'ok': false, 'error': 'trabalho_em_curso'});
      var mudou = 0;
      await _montar(t, rpc, aoMudar: () => mudou++);

      await t.tap(find.byKey(const ValueKey('papel_switch_estafeta')));
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const ValueKey('campo_motivo')), 'Pedido da loja');
      await t.tap(find.widgetWithText(FilledButton, 'Desligar'));
      await t.pumpAndSettle();

      expect(rpc.chamadasSet, 1);
      expect(find.text(mensagemErroPapel('trabalho_em_curso')), findsOneWidget);
      final txt = t.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('papeis_resultado')),
          matching: find.byType(Text)));
      expect(txt.style?.color, AppColors.error);
      expect(mudou, 0);
      expect(_switch(t, 'estafeta').value, isTrue);
    });

    testWidgets('religar mostra a mensagem do gatilho de conformidade',
        (t) async {
      final rpc = _RpcFalso(
          respostaSet: (_) => throw const PostgrestException(
              message: 'conformidade_incompleta: faltam nif, iban'));
      await _montar(t, rpc);

      // Limpeza suspensa → interruptor desligado → tocar = pedir para LIGAR.
      await t.tap(find.byKey(const ValueKey('papel_switch_limpeza')));
      await t.pumpAndSettle();
      expect(find.text('Ligar Limpeza?'), findsOneWidget);
      await t.enterText(
          find.byKey(const ValueKey('campo_motivo')), 'Voltou ao trabalho');
      await t.tap(find.widgetWithText(FilledButton, 'Ligar'));
      await t.pumpAndSettle();

      final set = rpc.chamadas.lastWhere((c) => c.$1 == 'admin_set_user_role');
      expect(set.$2['p_papel'], 'limpeza');
      expect(set.$2['p_ativo'], true);
      expect(find.text('Ativação bloqueada: faltam dados legais (NIF, IBAN).'),
          findsOneWidget);
    });
  });
}
