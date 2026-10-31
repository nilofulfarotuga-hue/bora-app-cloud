import 'package:bora_app/models/casa_models.dart';
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/screens/handyman/handyman_ganhos_screen.dart';
import 'package:bora_app/screens/handyman/handyman_home_screen.dart';
import 'package:bora_app/screens/handyman/handyman_trabalho_screen.dart';
import 'package:bora_app/services/oferta_trabalho_aviso.dart';
import 'package:bora_app/stores/cleaner_store.dart';
import 'package:bora_app/stores/handyman_store.dart';
import 'package:bora_app/stores/washer_store.dart';
import 'package:bora_app/widgets/bora/bora.dart';
import 'package:bora_app/widgets/trabalho_oferta_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CASA E MANUTENÇÃO — ecrãs do PROFISSIONAL, sem rede: o número grande é o
/// ganho, a oferta mostra a zona (nunca a porta), um botão por estado, e
/// concluir sem foto de depois fica bloqueado.

CasaOferta _oferta({
  String id = 'ped-1',
  bool convite = false,
  bool jaOrcei = false,
  int? ganho = 2550,
}) =>
    CasaOferta.fromJson({
      'pedido_id': id,
      'tipo': convite ? 'convite_orcamento' : 'oferta',
      'oficio': 'montagem',
      'oficio_nome': 'Montagem de móveis',
      'servico_nome': 'Montar roupeiro',
      'modo': convite ? 'orcamento' : 'fixo',
      'descricao': 'Roupeiro de 3 portas',
      'localidade': 'Guarda',
      'distancia_km': 3.24,
      'scheduled_at': '2026-11-08T10:00:00Z',
      'duracao_min': 90,
      'ganho_cents': ganho,
      'total_cents': 3000,
      'expira_em':
          DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(),
      'orcamentos_recebidos': 1,
      'ja_orcei': jaOrcei,
    });

CasaPedido _pedido(String estado, {List<String> fotos = const []}) =>
    CasaPedido.fromJson({
      'id': 'ped-9',
      'estado': estado,
      'servico_nome': 'Trocar sifão',
      'fotos': [
        for (var i = 0; i < fotos.length; i++)
          {'id': 'f$i', 'tipo': fotos[i], 'storage_path': 'u/ped-9/x_$i.jpg'},
      ],
    });

CasaPerfil _aprovado() => CasaPerfil.fromJson(const {
      'perfil': {'id': 'pro-1', 'approval_status': 'approved'},
      'comissao_pct': 15,
    });

Widget _app(Widget filho) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: filho)),
    );

void main() {
  group('o cartão da oferta (painel)', () {
    testWidgets('o número GRANDE é o que o profissional ganha', (tester) async {
      var aceitou = 0;
      await tester.pumpWidget(_app(CasaOfertaCartao(
        oferta: _oferta(ganho: 2550),
        onAceitar: () => aceitou++,
        onRecusar: () {},
      )));
      final ganho = tester.widget<Text>(find.byKey(const Key('casa_ganho_grande')));
      expect(ganho.data, '25,50 €');
      expect(ganho.style?.fontSize, greaterThanOrEqualTo(30));
      // O total do cliente (30 €) não aparece no cartão da oferta.
      expect(find.text('30,00 €'), findsNothing);
      await tester.tap(find.byKey(const Key('casa_oferta_aceitar')));
      expect(aceitou, 1);
    });

    testWidgets('mostra a zona e a distância, nunca a porta', (tester) async {
      await tester.pumpWidget(_app(CasaOfertaCartao(oferta: _oferta())));
      final zona = tester.widget<Text>(find.byKey(const Key('casa_oferta_zona')));
      expect(zona.data, 'Guarda · a 3,2 km');
    });

    testWidgets('convite: "Enviar orçamento" e quantos já orçaram', (tester) async {
      var orcou = 0;
      await tester.pumpWidget(_app(CasaOfertaCartao(
        oferta: _oferta(convite: true, ganho: null),
        maxOrcamentos: 3,
        onOrcar: () => orcou++,
      )));
      expect(find.byKey(const Key('casa_ganho_grande')), findsNothing);
      expect(find.text('Pedido de orçamento — 1 de 3 já orçaram'), findsOneWidget);
      expect(find.text('Enviar orçamento'), findsOneWidget);
      expect(find.byKey(const Key('casa_oferta_aceitar')), findsNothing);
      await tester.tap(find.byKey(const Key('casa_oferta_orcar')));
      expect(orcou, 1);
    });

    testWidgets('convite já orçado não volta a pedir orçamento', (tester) async {
      await tester.pumpWidget(_app(CasaOfertaCartao(
        oferta: _oferta(convite: true, ganho: null, jaOrcei: true),
      )));
      expect(find.text('Já enviaste o teu orçamento.'), findsOneWidget);
      expect(find.text('Enviar orçamento'), findsNothing);
    });
  });

  group('o botão do trabalho', () {
    Future<String?> carregar(WidgetTester tester, CasaPedido p) async {
      String? pedido;
      await tester.pumpWidget(_app(CasaAcaoPrincipal(
        pedido: p,
        onAvancar: (para) => pedido = para,
      )));
      final f = find.byKey(const Key('casa_trabalho_avancar'));
      if (f.evaluate().isEmpty) return null;
      final b = tester.widget<BoraPrimaryButton>(f);
      if (b.onPressed == null) return 'bloqueado';
      await tester.tap(f);
      return pedido;
    }

    testWidgets('um passo por estado', (tester) async {
      expect(await carregar(tester, _pedido('aceite')), 'a_caminho');
      expect(find.text('Estou a caminho'), findsOneWidget);
      expect(await carregar(tester, _pedido('a_caminho')), 'chegou');
      expect(find.text('Cheguei'), findsOneWidget);
      expect(await carregar(tester, _pedido('chegou')), 'em_curso');
      expect(find.text('Iniciar trabalho'), findsOneWidget);
      expect(await carregar(tester, _pedido('concluido')), isNull);
      expect(await carregar(tester, _pedido('cancelado')), isNull);
    });

    testWidgets('concluir sem foto de depois fica bloqueado', (tester) async {
      expect(await carregar(tester, _pedido('em_curso', fotos: const ['antes'])),
          'bloqueado');
      expect(find.byKey(const Key('casa_concluir_bloqueado')), findsOneWidget);
      expect(
          await carregar(
              tester, _pedido('em_curso', fotos: const ['antes', 'depois'])),
          'concluido');
      expect(find.byKey(const Key('casa_concluir_bloqueado')), findsNothing);
    });
  });

  group('ganhos', () {
    testWidgets('a comissão em palavras e o ganho em grande', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CasaGanhosConteudo(
            ganhos: CasaGanhos.fromJson(const {
              'semana': {'ganho_cents': 8500, 'trabalhos': 3},
            }),
            perfil: CasaPerfil.fromJson(const {
              'perfil': {'id': 'p', 'sem_comissao_ate': '2026-12-31'},
              'comissao_pct': 15,
            }),
            agora: DateTime(2026, 11, 1),
          ),
        ),
      ));
      expect(
          tester.widget<Text>(find.byKey(const Key('casa_ganho_grande'))).data,
          '85,00 €');
      expect(
          tester.widget<Text>(find.byKey(const Key('casa_ganhos_comissao'))).data,
          'Sem comissão até 31/12. Depois, o Bora fica com 15% de cada trabalho concluído.');
    });
  });

  group('a oferta da Casa por cima de tudo (ecrã inteiro)', () {
    late CleanerStore limpeza;
    late WasherStore lavagem;
    late HandymanStore casa;
    late int somTocou;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      esquecerOfertasTrabalhoTratadas();
      limpeza = CleanerStore();
      lavagem = WasherStore();
      casa = HandymanStore();
      somTocou = 0;
    });

    Future<void> montar(WidgetTester tester) => tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<CleanerStore>.value(value: limpeza),
            ChangeNotifierProvider<WasherStore>.value(value: lavagem),
            ChangeNotifierProvider<HandymanStore>.value(value: casa),
          ],
          child: MaterialApp(
            home: const Scaffold(body: Text('ecrã de baixo')),
            builder: (context, child) => TrabalhoOfertaOverlayHost(
              ligarSessao: false,
              tocarSom: () async => somTocou++,
              pararSom: () async {},
              child: child!,
            ),
          ),
        ));

    testWidgets('oferta de preço fixo: ganho em grande, zona sem porta, a tocar',
        (tester) async {
      casa.debugDefinir(perfil: _aprovado(), ofertas: [_oferta(ganho: 2550)]);
      await montar(tester);
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsOneWidget);
      expect(find.text('Novo trabalho de casa'), findsOneWidget);
      expect(find.text('Montar roupeiro'), findsOneWidget);
      expect(find.text('€25,50'), findsOneWidget);
      expect(find.text('Guarda · 3,2 km'), findsOneWidget);
      expect(find.text('Aceitar'), findsOneWidget);
      expect(somTocou, 1);
    });

    testWidgets('convite para orçar: sem ganho fixo, "Ver e orçar"', (tester) async {
      casa.debugDefinir(
          perfil: _aprovado(), ofertas: [_oferta(convite: true, ganho: null)]);
      await montar(tester);
      await tester.pump();
      expect(find.text('Pedido de orçamento'), findsOneWidget);
      expect(find.byKey(const Key('trabalho_oferta_convite')), findsOneWidget);
      expect(find.byKey(const Key('trabalho_oferta_ganho')), findsNothing);
      expect(find.text('Ver e orçar'), findsOneWidget);
    });

    testWidgets('profissional ainda não aprovado não recebe o cartão',
        (tester) async {
      casa.debugDefinir(
          perfil: CasaPerfil.fromJson(const {
            'perfil': {'id': 'pro-1', 'approval_status': 'pending'},
          }),
          ofertas: [_oferta()]);
      await montar(tester);
      await tester.pump();
      expect(find.byKey(const Key('trabalho_oferta_cartao')), findsNothing);
      expect(somTocou, 0);
    });

    testWidgets('a limpeza continua primeiro e a Casa espera a vez',
        (tester) async {
      limpeza.debugDefinirOfertas([
        CleaningBooking.fromSupabase(<String, dynamic>{
          'id': 'b-limpeza-1',
          'status': 'scheduled',
          'scheduled_at': '2026-10-10T09:00:00Z',
          'address_city': 'Guarda',
          'cleaner_earnings_cents': 1250,
          'total_cents': 2000,
          'offer_cleaner_id': 'c-1',
          'offer_expires_at': DateTime.now()
              .add(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
        }),
      ]);
      casa.debugDefinir(perfil: _aprovado(), ofertas: [_oferta()]);
      await montar(tester);
      await tester.pump();
      expect(find.text('Nova limpeza'), findsOneWidget);
      expect(find.text('Novo trabalho de casa'), findsNothing);
    });
  });

  test('ofertaDeTrabalhoParaMostrar sem o store da Casa continua a funcionar', () {
    final v = ofertaDeTrabalhoParaMostrar(
      limpeza: CleanerStore(),
      lavagem: WasherStore(),
      respondidas: const {},
      agora: DateTime.now(),
    );
    expect(v, isNull);
  });

  test('ofertaDeTrabalhoParaMostrar põe a Casa com zona e convite', () {
    final casa = HandymanStore()
      ..debugDefinir(
          perfil: _aprovado(), ofertas: [_oferta(convite: true, ganho: null)]);
    final v = ofertaDeTrabalhoParaMostrar(
      limpeza: CleanerStore(),
      lavagem: WasherStore(),
      casa: casa,
      respondidas: const {},
      agora: DateTime.now(),
    );
    expect(v?.categoria, 'casa');
    expect(v?.convite, isTrue);
    expect(v?.ganhoCents, 0);
    expect(v?.morada, 'Guarda · 3,2 km');
    expect(
        ofertaDeTrabalhoParaMostrar(
          limpeza: CleanerStore(),
          lavagem: WasherStore(),
          casa: casa,
          respondidas: const {'ped-1'},
          agora: DateTime.now(),
        ),
        isNull,
        reason: 'já respondida neste aparelho');
  });
}
