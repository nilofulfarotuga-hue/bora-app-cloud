import 'dart:async';
import 'dart:io';

import 'package:bora_app/models/carwash_models.dart';
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/services/oferta_trabalho_aviso.dart';
import 'package:bora_app/services/roles_service.dart';
import 'package:bora_app/stores/cleaner_store.dart';
import 'package:bora_app/stores/washer_store.dart';
import 'package:bora_app/widgets/trabalho_oferta_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [09/10/2026 · Mayra · missão fecho-total Bloco 4] A Mayra (só faz limpeza)
/// aceitou uma limpeza mas o aviso não tocou a sério: a oferta chegava como
/// notificação de estado (sem ecrã inteiro, sem som em ciclo, sem botões), o
/// push data-only chegava SEM TEXTO, e o cartão só existia dentro do ecrã da
/// limpeza. Estes testes seguram as três metades.

CleaningBooking _limpeza({
  String id = 'b-limpeza-1',
  int ganho = 1250,
  DateTime? expira,
  String? cleanerId,
}) =>
    CleaningBooking.fromSupabase(<String, dynamic>{
      'id': id,
      'status': 'scheduled',
      'scheduled_at': '2026-10-10T09:00:00Z',
      'address_city': 'Guarda',
      'cleaner_earnings_cents': ganho,
      'total_cents': 2000,
      'offer_cleaner_id': 'c-1',
      'offer_expires_at': (expira ?? DateTime.now().add(const Duration(minutes: 10)))
          .toUtc()
          .toIso8601String(),
      if (cleanerId != null) 'cleaner_id': cleanerId,
    });

CarwashBooking _lavagem({String id = 'b-lavagem-1', DateTime? expira}) =>
    CarwashBooking.fromSupabase(<String, dynamic>{
      'id': id,
      'status': 'scheduled',
      'scheduled_at': '2026-10-10T10:00:00Z',
      'address_street': 'Rua do Teste 1',
      'address_city': 'Guarda',
      'washer_earnings_cents': 900,
      'offer_expires_at': (expira ?? DateTime.now().add(const Duration(minutes: 10)))
          .toUtc()
          .toIso8601String(),
    });

void main() {
  group('o aviso (push data-only)', () {
    test('título e corpo vêm do data — a lavagem deixa de chegar sem texto', () {
      final t = textoDoAvisoDeTrabalho(
        data: {'title': 'Nova lavagem', 'body': 'Ganhas €9,00'},
        notifTitle: null,
        notifBody: null,
        tituloDeRecurso: '🚿 Bora Lavagem',
      );
      expect(t.titulo, 'Nova lavagem');
      expect(t.corpo, 'Ganhas €9,00');
    });

    test('sem data usa o notification; sem nada, nunca fica vazio', () {
      final a = textoDoAvisoDeTrabalho(
        data: const {},
        notifTitle: 'Do FCM',
        notifBody: 'Corpo do FCM',
        tituloDeRecurso: 'X',
      );
      expect((a.titulo, a.corpo), ('Do FCM', 'Corpo do FCM'));
      final b = textoDoAvisoDeTrabalho(
        data: const {'title': '  ', 'body': ''},
        tituloDeRecurso: '🧹 Bora Limpeza',
      );
      expect(b.titulo, '🧹 Bora Limpeza');
      expect(b.corpo, isNotEmpty);
    });

    test('categorias, tipos e a RPC de recusar', () {
      expect(categoriaDaOfertaDeTrabalho('cleaning_offer'), 'limpeza');
      expect(categoriaDaOfertaDeTrabalho('carwash_offer'), 'lavagem');
      expect(categoriaDaOfertaDeTrabalho('cleaning_status'), isNull);
      expect(tipoDaOfertaDeTrabalho('lavagem'), 'carwash_offer');
      expect(rpcRecusarOfertaDeTrabalho('limpeza'), 'cleaner_reject_booking');
      expect(rpcRecusarOfertaDeTrabalho('lavagem'), 'washer_reject_booking');
    });

    test('botões: Aceitar abre a app; Recusar não abre e cala o aviso', () {
      final a = ofertaTrabalhoNotificationActions();
      expect(a.map((x) => x.id), [kTrabalhoAceitarAction, kTrabalhoRecusarAction]);
      expect(a[0].showsUserInterface, isTrue);
      expect(a[0].cancelNotification, isFalse);
      expect(a[1].showsUserInterface, isFalse);
      expect(a[1].cancelNotification, isTrue);
    });

    test('depois de responder, a repetição do minuto seguinte não volta a tocar',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      esquecerOfertasTrabalhoTratadas();
      expect(await ofertaTrabalhoJaTratada('b-9'), isFalse);
      await marcarOfertaTrabalhoTratada('b-9');
      expect(await ofertaTrabalhoJaTratada('b-9'), isTrue);
      // Lida só do disco (o outro isolate não partilha memória).
      esquecerOfertasTrabalhoTratadas();
      expect(await ofertaTrabalhoJaTratada('b-9'), isTrue);
      // Passados 31 min a marca já não vale.
      expect(
          await ofertaTrabalhoJaTratada('b-9',
              agora: DateTime.now().add(const Duration(minutes: 31))),
          isFalse);
    });

    test('o código da app: oferta toca como a do estafeta e lê o texto do data',
        () {
      final app =
          File('lib/services/notification_service.dart').readAsStringSync();
      for (final caso in ["case 'cleaning_offer':", "case 'carwash_offer':"]) {
        final i = app.indexOf(caso);
        expect(i, isNonNegative, reason: caso);
        final ramo = app.substring(i, app.indexOf('case ', i + caso.length + 30));
        expect(ramo, contains('textoDoAvisoDeTrabalho('));
        expect(ramo, contains('mostrarOfertaDeTrabalho('));
      }
      // O Recusar sem abrir a app passa pela RPC certa.
      expect(app, contains('rpcRecusarOfertaDeTrabalho(categoria)'));
      final aviso =
          File('lib/services/oferta_trabalho_aviso.dart').readAsStringSync();
      expect(aviso, contains('fullScreenIntent: true'));
      expect(aviso, contains('ongoing: true'));
      expect(aviso, contains('Int32List.fromList(<int>[4])'),
          reason: 'som em ciclo (FLAG_INSISTENT), como o estafeta');
      expect(aviso, contains("'bora_alert'"));
    });
  });

  group('a entrada de quem tem vários papéis', () {
    RolesSummary r({String? d, String? c, String? w}) => RolesSummary.fromJson({
          'has_driver': d != null,
          'driver_status': d,
          'has_cleaner': c != null,
          'cleaner_status': c,
          'has_washer': w != null,
          'washer_status': w,
        });

    test('só limpeza aprovada → entra direto na limpeza (caso Mayra)', () {
      expect(entradaDoPrestador(r(d: 'rejected', c: 'approved')),
          EntradaDoPrestador.limpeza);
    });

    test('vários papéis → abre no último modo usado', () {
      final todos = r(d: 'approved', c: 'approved', w: 'approved');
      expect(entradaDoPrestador(todos), EntradaDoPrestador.estafeta);
      expect(entradaDoPrestador(todos, ultimoModo: 'limpeza'),
          EntradaDoPrestador.limpeza);
      expect(entradaDoPrestador(todos, ultimoModo: 'lavagem'),
          EntradaDoPrestador.lavagem);
    });

    test('último modo que já não está aprovado não conta', () {
      expect(
          entradaDoPrestador(r(d: 'approved', c: 'suspended'),
              ultimoModo: 'limpeza'),
          EntradaDoPrestador.estafeta);
    });

    test('trabalho à espera num papel manda mais do que o último modo', () {
      final dois = r(d: 'approved', c: 'approved');
      expect(
          entradaDoPrestador(dois,
              ultimoModo: 'estafeta',
              pendente: const TrabalhoPendente(limpeza: true)),
          EntradaDoPrestador.limpeza);
      // O estafeta ligado nunca é tirado do ecrã dele.
      expect(
          entradaDoPrestador(dois,
              ultimoModo: 'limpeza',
              pendente:
                  const TrabalhoPendente(estafeta: true, limpeza: true)),
          EntradaDoPrestador.estafeta);
      // Trabalho num papel não aprovado não conta.
      expect(
          entradaDoPrestador(r(d: 'approved', w: 'pending'),
              pendente: const TrabalhoPendente(lavagem: true)),
          EntradaDoPrestador.estafeta);
    });

    test('[revisão 09/10] escolher limpeza/lavagem NUNCA desmonta o estafeta',
        () {
      // O ecrã do estafeta é onde vivem o batimento, o GPS e o cartão das
      // ofertas de entrega (caso Ney): limpeza e lavagem abrem POR CIMA.
      final botao =
          File('lib/widgets/profile_switcher_button.dart').readAsStringSync();
      expect(botao, isNot(contains('if (base == UserRole.driver) return;')));
      final portao =
          File('lib/widgets/portao_do_prestador.dart').readAsStringSync();
      final i = portao.indexOf('void didChangeDependencies()');
      final corpo = portao.substring(i, portao.indexOf('bool _papelAprovado', i));
      expect(corpo, contains('pedida != EntradaDoPrestador.estafeta'),
          reason: 'o portão só segue sozinho a troca PARA o estafeta');
      // Com outro modo guardado, o estafeta aprovado espera pelo servidor.
      expect(portao, contains("(modo == null || modo == 'estafeta')"));
    });

    test('[revisão 09/10] só falha de REDE mantém a oferta para tentar outra vez',
        () {
      expect(falhaDeRede(TimeoutException('x')), isTrue);
      expect(falhaDeRede(Exception('SocketException: Failed host lookup')), isTrue);
      expect(falhaDeRede(Exception('offer_no_longer_valid')), isFalse);
    });

    test('modo ↔ entrada', () {
      expect(modoDaEntrada(EntradaDoPrestador.limpeza), 'limpeza');
      expect(modoDaEntrada(EntradaDoPrestador.nenhuma), isNull);
      expect(entradaDoModo('lavagem'), EntradaDoPrestador.lavagem);
      expect(entradaDoModo('cliente'), isNull);
    });
  });

  group('o cartão global da oferta (ecrã inteiro, som em ciclo)', () {
    late CleanerStore limpeza;
    late WasherStore lavagem;
    late int somTocou;
    late int somParou;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      esquecerOfertasTrabalhoTratadas();
      limpeza = CleanerStore();
      lavagem = WasherStore();
      somTocou = 0;
      somParou = 0;
    });

    Future<void> montar(WidgetTester tester, {DateTime Function()? agora}) =>
        tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<CleanerStore>.value(value: limpeza),
            ChangeNotifierProvider<WasherStore>.value(value: lavagem),
          ],
          child: MaterialApp(
            home: const Scaffold(body: Text('ecrã de baixo')),
            builder: (context, child) => TrabalhoOfertaOverlayHost(
              ligarSessao: false,
              agora: agora,
              tocarSom: () async => somTocou++,
              pararSom: () async => somParou++,
              child: child!,
            ),
          ),
        ));

    testWidgets('sem oferta não desenha nada nem toca', (tester) async {
      await montar(tester);
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsNothing);
      expect(somTocou, 0);
    });

    testWidgets('oferta de limpeza: ganho em grande, por cima de tudo, a tocar',
        (tester) async {
      limpeza.debugDefinirOfertas([_limpeza(ganho: 1250)]);
      await montar(tester);
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsOneWidget);
      expect(find.text('Nova limpeza'), findsOneWidget);
      expect(find.text('€12,50'), findsOneWidget);
      expect(find.text('o teu ganho'), findsOneWidget);
      expect(find.text('10/10 10:00'), findsOneWidget,
          reason: '09:00 UTC = 10:00 em Lisboa (horário de verão)');
      expect(somTocou, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(somTocou, 1, reason: 'toca uma vez em ciclo, não reinicia');
    });

    testWidgets('Recusar pede dois toques e o cartão sai logo', (tester) async {
      limpeza.debugDefinirOfertas([_limpeza()]);
      await montar(tester);
      await tester.pump();
      // No primeiro segundo o Recusar não faz nada (toque para o ecrã de baixo).
      await tester.tap(find.byKey(const Key('trabalho_oferta_recusar')));
      await tester.pump();
      expect(find.text('Confirmar recusa'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.tap(find.byKey(const Key('trabalho_oferta_recusar')));
      await tester.pump();
      expect(find.text('Confirmar recusa'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trabalho_oferta_recusar')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsNothing);
      expect(somParou, greaterThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('oferta já aceite ou expirada não aparece', (tester) async {
      limpeza.debugDefinirOfertas([
        _limpeza(id: 'a', cleanerId: 'c-1'),
        _limpeza(
            id: 'b', expira: DateTime.now().subtract(const Duration(minutes: 1))),
      ]);
      await montar(tester);
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsNothing);
    });

    testWidgets('quando o prazo passa o cartão sai sozinho', (tester) async {
      var agora = DateTime.now();
      limpeza.debugDefinirOfertas(
          [_limpeza(expira: agora.add(const Duration(seconds: 3)))]);
      await montar(tester, agora: () => agora);
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsOneWidget);
      agora = agora.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsNothing);
      expect(somParou, greaterThanOrEqualTo(1));
    });

    testWidgets(
        'a trabalhar como estafeta: faixa compacta no fundo, sem tapar e sem som',
        (tester) async {
      limpeza.debugDefinirOfertas([_limpeza(ganho: 3400)]);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<CleanerStore>.value(value: limpeza),
          ChangeNotifierProvider<WasherStore>.value(value: lavagem),
        ],
        child: MaterialApp(
          home: const Scaffold(body: Text('mapa da entrega')),
          builder: (context, child) => TrabalhoOfertaOverlayHost(
            ligarSessao: false,
            debugEstafetaOcupado: true,
            tocarSom: () async => somTocou++,
            pararSom: () async => somParou++,
            child: child!,
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_compacta')), findsOneWidget);
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsNothing);
      expect(find.text('Nova limpeza · €34,00'), findsOneWidget);
      expect(somTocou, 0, reason: 'o som em ciclo é da oferta de entrega');
      // O ecrã de baixo continua tocável (não há fundo escuro por cima).
      expect(find.text('mapa da entrega').hitTestable(), findsOneWidget);
    });

    testWidgets('lavagem só aparece a lavador aprovado', (tester) async {
      lavagem.debugDefinir(ofertas: [_lavagem()]);
      await montar(tester);
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsNothing);
      lavagem.debugDefinir(
          perfil: WasherProfile.fromSupabase(const {
        'id': 'w-1',
        'user_id': 'u-1',
        'approval_status': 'approved',
        'is_active': true,
      }));
      await tester.pump();
      expect(find.text('Nova lavagem'), findsOneWidget);
      expect(find.text('€9,00'), findsOneWidget);
    });
  });
}
