import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bora_app/models/online_resultado.dart';
import 'package:bora_app/screens/admin/admin_estafetas_fila_screen.dart';
import 'package:bora_app/screens/driver/minha_conta_screen.dart';
import 'package:bora_app/services/minha_conta.dart';
import 'package:bora_app/services/trabalho_em_curso.dart';
import 'package:bora_app/utils/pedido_agendado.dart';
import 'package:bora_app/widgets/barra_falta_conta.dart';
import 'package:bora_app/widgets/proximo_trabalho_card.dart';

/// Missão m2-estafeta-conta-fila-2026-11-08 — ecrãs e regras à volta da
/// "A minha conta", da faixa do trabalho em curso e do pedido agendado.
void main() {
  EstadoMinhaConta estado(List<(String, EstadoItemConta, bool)> itens,
          {int divida = 0}) =>
      EstadoMinhaConta(
        dividaCents: divida,
        itens: [
          for (final (chave, e, bloqueia) in itens)
            ItemConta(
              chave: chave,
              rotulo: switch (chave) {
                'selfie' => 'Foto pessoal (selfie)',
                'iban' => 'IBAN (para receberes)',
                'fiscal' => 'NIF e atividade aberta nas Finanças',
                'morada' => 'Morada',
                _ => chave,
              },
              rotuloCurto: switch (chave) {
                'fiscal' => 'NIF',
                'iban' => 'IBAN',
                _ => chave,
              },
              estado: e,
              bloqueiaOnline: bloqueia,
              kindFoto: chave == 'selfie' ? 'selfie' : null,
            ),
        ],
      );

  Widget app(Widget w) => MaterialApp(home: w);

  group('MinhaContaScreen', () {
    testWidgets('vermelhos com o botão para tratar ali; verdes sem botão',
        (t) async {
      await t.pumpWidget(app(MinhaContaScreen(
        carregar: () async => estado([
          ('selfie', EstadoItemConta.falta, false),
          ('iban', EstadoItemConta.falta, false),
          ('fiscal', EstadoItemConta.falta, true),
          ('morada', EstadoItemConta.ok, false),
        ]),
      )));
      await t.pumpAndSettle();
      expect(find.text('A minha conta'), findsOneWidget);
      expect(find.textContaining('Faltam tratar 3 coisas'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('minha_conta_item_selfie')),
              matching: find.text('Enviar foto')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('minha_conta_item_iban')),
              matching: find.text('Escrever')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('minha_conta_item_fiscal')),
              matching: find.text('Confirmar')),
          findsOneWidget);
      expect(find.text('Sem isto não podes ficar online.'), findsOneWidget);
      // Verde: sem botão.
      expect(
          find.descendant(
              of: find.byKey(const Key('minha_conta_item_morada')),
              matching: find.byType(OutlinedButton)),
          findsNothing);
    });

    testWidgets('IBAN errado não sai do diálogo', (t) async {
      await t.pumpWidget(app(MinhaContaScreen(
        carregar: () async =>
            estado([('iban', EstadoItemConta.falta, false)]),
      )));
      await t.pumpAndSettle();
      await t.tap(find.text('Escrever'));
      // O campo tem autofocus: o cursor pisca e o pumpAndSettle nunca para.
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byType(TextField), 'PT50000201231234567890155');
      await t.tap(find.text('Enviar'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Confere o IBAN: PT seguido de 23 números.'),
          findsOneWidget);
    });

    testWidgets('tudo verde: "Está tudo em ordem"', (t) async {
      await t.pumpWidget(app(MinhaContaScreen(
        carregar: () async => estado([
          ('selfie', EstadoItemConta.ok, false),
          ('iban', EstadoItemConta.ok, false),
        ]),
      )));
      await t.pumpAndSettle();
      expect(find.text('Está tudo em ordem com a tua conta.'), findsOneWidget);
    });

    testWidgets('sem resposta: diz e deixa tentar de novo', (t) async {
      await t.pumpWidget(app(MinhaContaScreen(carregar: () async => null)));
      await t.pumpAndSettle();
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  });

  group('BarraFaltaConta', () {
    testWidgets('mostra "Falta: …" e some quando não falta nada', (t) async {
      await t.pumpWidget(app(Scaffold(
        body: BarraFaltaConta(
          carregar: () async => estado([
            ('fiscal', EstadoItemConta.falta, false),
            ('iban', EstadoItemConta.falta, false),
          ], divida: 147),
        ),
      )));
      await t.pumpAndSettle();
      expect(find.text('Falta: NIF e IBAN'), findsOneWidget);

      await t.pumpWidget(app(Scaffold(
        body: BarraFaltaConta(
          key: const Key('outra'),
          carregar: () async =>
              estado([('iban', EstadoItemConta.ok, false)]),
        ),
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('barra_falta_conta')), findsNothing);
    });
  });

  group('folha do Online', () {
    testWidgets('lista o que impede e tem "Tratar"', (t) async {
      await t.pumpWidget(app(Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => mostrarFolhaParaFicarOnline(ctx, [
                const ItemConta(
                    chave: 'fiscal',
                    rotulo: 'NIF e atividade aberta nas Finanças',
                    rotuloCurto: 'NIF',
                    estado: EstadoItemConta.falta,
                    bloqueiaOnline: true),
              ]),
              child: const Text('Online'),
            ),
          ),
        ),
      )));
      await t.tap(find.text('Online'));
      await t.pumpAndSettle();
      expect(find.text('Para ficares online falta:'), findsOneWidget);
      expect(find.text('NIF e atividade aberta nas Finanças'), findsOneWidget);
      expect(find.text('Tratar'), findsOneWidget);
    });
  });

  group('OnlineResultado lê as faltas do servidor', () {
    test('CONTA_NAO_APROVADA com faltas', () {
      final r = OnlineResultado.daResposta({
        'ok': false,
        'codigo': 'CONTA_NAO_APROVADA',
        'mensagem': 'A tua conta ainda não está aprovada.',
        'faltas': ['foto pessoal (selfie)', 'matrícula'],
      });
      expect(r.ok, isFalse);
      expect(r.faltas, ['foto pessoal (selfie)', 'matrícula']);
      expect(r.mensagemComFaltas,
          contains('Falta enviar: foto pessoal (selfie) e matrícula.'));
    });
    test('sem faltas a frase fica igual', () {
      final r = OnlineResultado.daResposta(
          {'ok': false, 'codigo': 'CONTA_BLOQUEADA', 'mensagem': 'Bloqueada.'});
      expect(r.faltas, isEmpty);
      expect(r.mensagemComFaltas, r.mensagem);
    });
  });

  group('faixa do trabalho em curso', () {
    final agora = DateTime(2026, 11, 8, 18, 20);
    TrabalhoEmCurso limpeza(String estado, DateTime? quando) => TrabalhoEmCurso(
          categoria: 'limpeza',
          bookingId: 'ae42a171',
          estado: estado,
          morada: 'Guarda',
          ganhoCents: 0,
          agendadoPara: quando,
        );

    test('o caso de 08/11: aceite para sábado NÃO é "a decorrer"', () {
      final t = limpeza('accepted', DateTime(2026, 11, 14, 14, 0));
      expect(t.eParaMaisTarde(agora), isTrue);
      expect(t.textoProxima, 'Próxima limpeza: sábado 14:00');
    });
    test('aceite para daqui a 2 h já conta (sai de casa)', () {
      expect(
          limpeza('accepted', agora.add(const Duration(hours: 2)))
              .eParaMaisTarde(agora),
          isFalse);
    });
    test('a caminho conta sempre, mesmo marcada para mais tarde', () {
      expect(
          limpeza('on_the_way', agora.add(const Duration(days: 2)))
              .eParaMaisTarde(agora),
          isFalse);
    });
    test('sem hora marcada fica como estava (falha aberta)', () {
      expect(limpeza('accepted', null).eParaMaisTarde(agora), isFalse);
    });
    test('lê scheduled_at do servidor', () {
      final t = TrabalhoEmCurso.fromJson({
        'tem': true,
        'categoria': 'limpeza',
        'booking_id': 'x',
        'estado': 'accepted',
        'scheduled_at': '2026-11-14T14:00:00+00:00',
      });
      expect(t!.agendadoPara, isNotNull);
      expect(t.tabela, 'cleaning_bookings');
    });
  });

  testWidgets('cartão pequeno "Próxima limpeza" (fora da faixa)', (t) async {
    await t.pumpWidget(app(Scaffold(
      body: ProximoTrabalhoCard(
        categoria: 'limpeza',
        carregar: () async => TrabalhoEmCurso(
          categoria: 'limpeza',
          bookingId: 'ae42a171',
          estado: 'accepted',
          morada: '',
          ganhoCents: 0,
          agendadoPara: DateTime(2026, 11, 14, 14, 0),
        ),
      ),
    )));
    await t.pumpAndSettle();
    expect(find.text('Próxima limpeza: sábado 14:00'), findsOneWidget);
  });

  group('pedido agendado (bloco 5)', () {
    final agora = DateTime(2026, 11, 8, 18, 45);
    test('Jyosmi: chamado às 18:45, pronto às 19:15', () {
      expect(
          textoPedidoAgendado(
            scheduledFor: DateTime(2026, 11, 8, 19, 15),
            readyAtPromised: null,
            agora: agora,
          ),
          'Pedido agendado — fica pronto às 19:15');
    });
    test('a hora prometida pela loja manda', () {
      expect(
          textoPedidoAgendado(
            scheduledFor: DateTime(2026, 11, 8, 19, 0),
            readyAtPromised: DateTime(2026, 11, 8, 19, 20),
            agora: agora,
          ),
          'Pedido agendado — fica pronto às 19:20');
    });
    test('já pronto (ou quase) e pedido imediato: nada', () {
      expect(
          textoPedidoAgendado(
              scheduledFor: DateTime(2026, 11, 8, 18, 46),
              readyAtPromised: null,
              agora: agora),
          isNull);
      expect(
          textoPedidoAgendado(
              scheduledFor: null,
              readyAtPromised: DateTime(2026, 11, 8, 19, 20),
              agora: agora),
          isNull);
    });
  });

  group('painel: estafetas — fila e documentos', () {
    testWidgets('fase, o que falta e os botões', (t) async {
      await t.pumpWidget(app(AdminEstafetasFilaScreen(
        carregar: (filtro) async => [
          LinhaEstafetaFila(
            userId: 'e355fde0',
            nome: 'Vasco',
            approvalStatus: 'approved',
            fase: FaseCandidato.aprovado,
            conta: estado([
              ('selfie', EstadoItemConta.ok, false),
              ('iban', EstadoItemConta.falta, false),
              ('fiscal', EstadoItemConta.falta, false),
            ]),
          ),
          LinhaEstafetaFila(
            userId: 'd333a35c',
            nome: 'Artur',
            approvalStatus: 'pending',
            fase: FaseCandidato.filaDeEspera,
            conta: estado([('selfie', EstadoItemConta.ok, false)]),
          ),
        ],
      )));
      await t.pumpAndSettle();
      expect(find.text('Vasco'), findsOneWidget);
      expect(find.textContaining('Aprovado · falta: IBAN e NIF'), findsOneWidget);
      expect(find.text('Na fila de espera'), findsOneWidget);
      await t.tap(find.text('Artur'));
      await t.pumpAndSettle();
      expect(find.text('Aprovar (só o Danilo)'), findsOneWidget);
      expect(find.text('Marcar atividade confirmada'), findsOneWidget);
      expect(find.byKey(const Key('admin_fila_filtro_na_fila')), findsOneWidget);
    });
  });
}
