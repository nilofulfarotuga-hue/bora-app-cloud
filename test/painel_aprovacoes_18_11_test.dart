// painel-aprovacoes-2026-11-18: os botões de aprovar / pedir documentos que
// "não faziam nada" (Shelen, 18/11 20:26-20:37). Sem rede: funções puras,
// janelas e leitura das fontes.
//
// O que se viu em produção: o Danilo, no iPhone, em "Aprovações de
// Entregadores" → ficha da Shelen. "Pedir documentos em falta" chegou três
// vezes à app dela (in_app_notifications 20:27:47, 20:28:23, 20:37:17), mas o
// "Pedido enviado" ia num SnackBar POR BAIXO da ficha. "Aprovar" abria a
// janela "Faltam documentos" com o botão final cinzento até se escrever a
// justificação e marcar a caixa — e a ficha não tinha botão de aprovar.
import 'dart:io';

import 'package:bora_app/screens/admin/_admin_rpc_errors.dart';
import 'package:bora_app/screens/shared/documentos_em_falta_screen.dart';
import 'package:bora_app/widgets/admin_documentos.dart';
import 'package:bora_app/widgets/admin_robo_documentos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

void main() {
  group('aviso "Faltam documentos" no sino abre o ecrã de pendências', () {
    test('aviso novo: o papel vem em related_id', () {
      expect(
          papelDoAvisoDeDocumentos(
              {'kind': 'documentos_em_falta', 'related_id': 'cleaner'}),
          'cleaner');
      expect(
          papelDoAvisoDeDocumentos(
              {'kind': 'documentos_em_falta', 'related_id': 'washer'}),
          'washer');
      expect(
          papelDoAvisoDeDocumentos(
              {'kind': 'documentos_em_falta', 'related_id': 'qualquer'}),
          'driver');
    });

    test('avisos antigos (admin_push, como os da Shelen) também abrem', () {
      expect(
          papelDoAvisoDeDocumentos({
            'kind': 'admin_push',
            'title': 'Faltam documentos na tua candidatura',
            'body': 'Na tua conta de estafeta falta: número do documento e '
                'foto do veículo.',
          }),
          'driver');
      expect(
          papelDoAvisoDeDocumentos({
            'kind': 'admin_push',
            'title': 'Faltam documentos na tua candidatura',
            'body': 'Na tua conta de profissional de limpeza falta: IBAN.',
          }),
          'cleaner');
    });

    test('outros avisos não abrem este ecrã', () {
      expect(
          papelDoAvisoDeDocumentos(
              {'kind': 'admin_push', 'title': 'Promoção', 'body': 'x'}),
          isNull);
      expect(papelDoAvisoDeDocumentos({'kind': 'cancellation'}), isNull);
    });

    test('o sino e o toque no telemóvel estão ligados ao ecrã', () {
      final sino = _ler('lib/screens/notifications_screen.dart');
      expect(sino, contains('papelDoAvisoDeDocumentos(n)'));
      expect(sino, contains('DocumentosEmFaltaScreen(papel: papelDocs)'));
      final push = _ler('lib/services/notification_service.dart');
      expect(push, contains("data['kind'] == kKindDocumentosEmFalta"));
      // Os três caminhos do toque: app aberta, em segundo plano (no iPhone é
      // sempre este) e fechada (arranque a frio).
      expect(
          'abrirDocumentosEmFaltaDoAviso('.allMatches(push).length -
              1, // a definição
          greaterThanOrEqualTo(3));
      expect(push,
          contains("msg.data['kind']?.toString() == kKindDocumentosEmFalta"));
    });
  });

  group('erros novos em PT-BR', () {
    PostgrestException pg(String m, [String? c]) =>
        PostgrestException(message: m, code: c);
    test('motivo curto da exceção', () {
      expect(humanizeAdminRpcError(pg('motivo_excecao_curto')),
          'Escreva o motivo da exceção (mínimo 10 letras).');
    });
    test('atividade_por_aprovar já não manda desligar o interruptor', () {
      final t = humanizeAdminRpcError(pg('atividade_por_aprovar'));
      expect(t, contains('Aprovar comprovativo'));
      expect(t, contains('exceção do admin'));
      expect(t, isNot(contains('Desligar o interruptor')));
    });
    test('função ainda por instalar é reconhecida (usa a porta antiga)', () {
      expect(
          funcaoAindaNaoInstalada(pg('Could not find the function', 'PGRST202')),
          isTrue);
      expect(funcaoAindaNaoInstalada(pg('admin_required')), isFalse);
      expect(funcaoAindaNaoInstalada(Exception('x')), isFalse);
    });
  });

  group('janelas do painel', () {
    testWidgets('o resultado aparece POR CIMA da ficha (bottom sheet)',
        (t) async {
      late BuildContext folha;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: c,
                  isScrollControlled: true,
                  builder: (sCtx) {
                    folha = sCtx;
                    return const SizedBox(
                        height: 600, child: Text('ficha da pessoa'));
                  },
                ),
                child: const Text('abrir ficha'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir ficha'));
      await t.pumpAndSettle();
      final fut = avisoResultadoAdmin(folha,
          titulo: 'Pedido enviado', texto: 'A pessoa recebeu o aviso.');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin-resultado-ok')), findsOneWidget);
      // Está mesmo à frente: o toque no OK chega lá (não fica tapado).
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await fut;
      expect(find.byKey(const Key('admin-resultado-ok')), findsNothing);
      expect(find.text('ficha da pessoa'), findsOneWidget);
    });

    testWidgets(
        '"Falta aprovar o comprovativo" já não é um beco: aprovar ali ou exceção',
        (t) async {
      final linha = <String, dynamic>{
        'user_id': 'u1',
        'name': 'Pessoa Teste',
        '_atividade': {
          'obrigatoria': true,
          'atividade_status': 'em_analise',
          'documento_path': 'u1/c.png',
        },
      };
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      })));
      final fut = avisarSeAtividadePorAprovar(ctx, linha,
          papel: 'cleaner', entidadeId: 'id-1');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('atividade-ver-comprovativo')), findsOneWidget);
      expect(find.byKey(const Key('atividade-aprovar-comprovativo-agora')),
          findsOneWidget);
      expect(find.byKey(const Key('atividade-aprovar-excecao')), findsOneWidget);

      // Exceção: sem motivo, o botão diz o que falta (não fica calado).
      await t.tap(find.byKey(const Key('atividade-aprovar-excecao')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin-excecao-dialogo')), findsOneWidget);
      await t.tap(find.byKey(const Key('admin-excecao-confirmar')));
      await t.pumpAndSettle();
      expect(find.text('Escreva o motivo com pelo menos 10 letras.'),
          findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(await fut, isFalse);
    });

    testWidgets('sem papel/id a janela não oferece a exceção', (t) async {
      final linha = <String, dynamic>{
        'user_id': 'u1',
        '_atividade': {
          'obrigatoria': true,
          'atividade_status': 'por_enviar',
          'documento_path': null,
        },
      };
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      })));
      final fut = avisarSeAtividadePorAprovar(ctx, linha);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('atividade-aprovar-excecao')), findsNothing);
      expect(find.byKey(const Key('atividade-aprovar-comprovativo-agora')),
          findsNothing);
      await t.tap(find.text('Entendi'));
      await t.pumpAndSettle();
      expect(await fut, isFalse);
    });
  });

  group('fontes: cada caminho de aprovação tem os botões', () {
    test('ficha do estafeta tem Aprovar, Rejeitar e Exceção', () {
      final f = _ler('lib/screens/admin/admin_driver_approval_screen.dart');
      expect(f, contains("Key('ficha-estafeta-aprovar')"));
      expect(f, contains("Key('ficha-estafeta-rejeitar')"));
      expect(f, contains("Key('ficha-estafeta-excecao')"));
      // O botão da janela "Faltam documentos" já não fica cinzento.
      expect(f, isNot(contains('onPressed: (acknowledged && justOk)')));
    });
    test('ficha de limpeza/lavagem/Casa tem a exceção', () {
      final f = _ler('lib/screens/admin/admin_ficha_prestador.dart');
      expect(f, contains("Key('ficha-prestador-excecao')"));
    });
    test('as janelas de aprovar passam o papel para a exceção', () {
      for (final (ficheiro, papel) in [
        ('lib/screens/admin/admin_cleaning_cleaners_screen.dart', "'cleaner'"),
        ('lib/screens/admin/admin_carwash_screen.dart', "'washer'"),
        ('lib/screens/admin/admin_papeis_screen.dart', 'tipo'),
        (
          'lib/screens/admin/admin_service_provider_detail_screen.dart',
          "'service_provider'"
        ),
        ('lib/screens/admin/admin_driver_approval_screen.dart', "'driver'"),
      ]) {
        final f = _ler(ficheiro);
        expect(f, contains('papel: $papel'), reason: ficheiro);
      }
    });
    test('comprovativo de atividade: a folha fecha antes de cada ação', () {
      final f =
          _ler('lib/screens/admin/admin_comprovativo_atividade_screen.dart');
      expect(f, contains("_fecharEDepois(ctx, () => _decidir(l, 'aprovar'))"));
      expect(f, contains("_fecharEDepois(ctx, () => _decidir(l, 'recusar'))"));
      expect(f,
          contains("_fecharEDepois(ctx, () => _decidir(l, 'pedir_de_novo'))"));
      // Antes fechava o ecrã inteiro ao fechar a folha depois do sucesso.
      expect(f, isNot(contains('if (mounted) Navigator.of(context).maybePop();')));
    });
    test('a migração mexe na trava sem a desligar', () {
      final m = _ler(
          'supabase/migrations/20261128145223_painel_aprovacoes_excecao_e_pedir_docs.sql');
      expect(m, contains("RAISE EXCEPTION 'atividade_por_aprovar'"));
      expect(m, contains("current_setting('bora.excecao_atividade', true)"));
      expect(m, contains('public.is_admin()'));
      expect(m, contains("'excecao_admin'"));
      expect(m, contains("'prestador_aprovado_excecao'"));
      expect(m, isNot(contains('DISABLE TRIGGER')));
      // service_providers.id é TEXT em produção: com p_id uuid a função
      // falhava em TODOS os papéis ("operator does not exist: text = uuid").
      expect(m, contains('p_papel text, p_id text, p_motivo text'));
      expect(m, contains('admin_appointment_provider_approve(p_id);'));
      expect(m, contains("s.id = p_id;"));
    });
  });
}
