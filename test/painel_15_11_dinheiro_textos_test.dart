import 'dart:convert';
import 'dart:io';

import 'package:bora_app/screens/admin/admin_acertos_semana_screen.dart';
import 'package:bora_app/screens/admin/admin_businesses_screen.dart'
    show kReimportarComerciosExplicacao;
import 'package:bora_app/screens/admin/admin_continente_prices_screen.dart'
    show kContinentePvprAviso;
import 'package:bora_app/screens/admin/admin_orphan_payments_screen.dart'
    show kExcluirRascunhoIndisponivel;
import 'package:bora_app/screens/admin/admin_receipts_screen.dart'
    show kTalaoEntregadorSemLeitura, kTalaoFiltroEntregadorSemLeitura;
import 'package:bora_app/screens/admin/admin_tokens_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Painel 15/11/2026 — textos e chamadas de leitura do dinheiro (auditoria
/// S2/S3). Nenhum valor, conta, preço ou operação de dinheiro mudou; prova-se:
///  1. o DAC7 chama admin_dac7_report com 'p_year' (a assinatura do servidor);
///  2. a lista de Tokens só lê colunas que existem (is_used/used_at) e diz
///     porque vem curta;
///  3. o MB Way da Bora tem exemplo neutro e explicação;
///  4. "Reenviar recibos" pergunta antes de mandar a TODOS;
///  5. "Pagar" passou a "Copiar MB Way e valor"; "Reabrir" explica o que faz;
///  6. "Excluir rascunho" fica desligado com o motivo; "Criar pedido" igual;
///  7. talões, Comércios, Continente e Despacho dizem por palavras o que não
///     funciona ou o que o botão desfaz.
/// Servidor falso (MockClient) com o SDK verdadeiro; dados inventados.

const _json = {'content-type': 'application/json; charset=utf-8'};

final List<Map<String, dynamic>> _chamadas = [];

final Map<String, Object?> _semana = {
  'items': [
    {
      'type': 'driver',
      'subject_id': 'estafeta-teste',
      'name': 'Estafeta Teste',
      'email': 'estafeta@teste.invalid',
      'mbway': '900000001',
      'net_cents': 1234,
      'direction': 'bora_pays',
      'paid_status': 'pending',
      'email_status': 'sent',
      'breakdown': <Object?>[],
    },
    {
      'type': 'partner',
      'subject_id': 'loja-teste',
      'name': 'Loja Teste',
      'mbway': '',
      'net_cents': 500,
      'direction': 'owes_bora',
      'paid_status': 'received',
      'paid_at': '2026-11-10T10:00:00Z',
      'email_status': 'sent',
      'breakdown': <Object?>[],
      'reabrir_permitido': true,
    },
  ],
  'weeks': ['2026-11-09'],
  'week_start': '2026-11-09',
  'week_end': '2026-11-15',
  'totais': {
    'pagar_cents': 1234,
    'receber_cents': 500,
    'saldo_cents': -734,
    'n_por_tratar': 1,
  },
  'bora_mbway': '',
  'emails_enabled': true,
};

Future<http.Response> _servidor(http.Request req) async {
  final p = req.url.path;
  Map<String, dynamic> corpo() => req.body.isEmpty
      ? {}
      : Map<String, dynamic>.from(jsonDecode(req.body) as Map);
  http.Response ok(Object? o) =>
      http.Response(jsonEncode(o), 200, headers: _json, request: req);
  if (p.endsWith('/rest/v1/bora_tokens')) {
    _chamadas.add({
      'tabela': 'bora_tokens',
      'select': req.url.queryParameters['select'],
    });
    return ok(<Object?>[]);
  }
  if (p.endsWith('/rpc/admin_weekly_closeout_list')) return ok(_semana);
  if (p.endsWith('/rpc/admin_avisos_fecho')) {
    return ok({
      'fecho_travado': <Object?>[],
      'pedidos_no_vermelho': [
        {
          'order_id': 'pedido-vermelho-1',
          'vendor_name': 'Loja Teste',
          'cliente_pagou': 10,
          'mercadoria': 9,
          'estafeta': 3.8,
          'sobrou_para_a_bora': -2.8,
          'quando': '2026-11-10T12:00:00Z',
        },
      ],
    });
  }
  if (p.endsWith('/rpc/admin_resend_weekly_digest')) {
    _chamadas.add({'rpc': 'admin_resend_weekly_digest', ...corpo()});
    return ok({'ok': true});
  }
  return ok(<Object?>[]);
}

Future<void> _servidorResponde(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Future<void> _abrir(WidgetTester tester, Widget ecra) async {
  tester.view.physicalSize = const Size(1400, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ecra));
  await _servidorResponde(tester);
}

Future<void> _animar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String _ler(String ficheiro) =>
    File('lib/screens/admin/$ficheiro').readAsStringSync();

/// Junta literais de texto adjacentes ('a '\n   'b' → 'a b') para procurar
/// frases inteiras no código.
String _juntarLiterais(String src) =>
    src.replaceAll(RegExp(r"'\s*\n\s*'"), '');

/// O pedaço do código entre dois marcadores (o primeiro tem de existir).
String _entre(String src, String inicio, String fim) {
  final i = src.indexOf(inicio);
  expect(i, greaterThanOrEqualTo(0), reason: 'falta "$inicio"');
  final f = src.indexOf(fim, i + inicio.length);
  return src.substring(i, f < 0 ? src.length : f);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(_servidor),
    );
  });

  setUp(_chamadas.clear);

  group('fonte', () {
    final fecho = _ler('admin_fecho_mensal_screen.dart');
    final tokens = _ler('admin_tokens_screen.dart');
    final acertos = _ler('admin_acertos_semana_screen.dart');
    final orfaos = _ler('admin_orphan_payments_screen.dart');
    final taloes = _ler('admin_receipts_screen.dart');
    final comercios = _ler('admin_businesses_screen.dart');
    final continente = _ler('admin_continente_prices_screen.dart');
    final despacho = _ler('admin_dispatch_settings_screen.dart');

    test('DAC7 manda p_year (admin_dac7_report(p_year int))', () {
      expect(fecho,
          contains("rpc('admin_dac7_report', params: {'p_year': _ano})"));
      expect(fecho, isNot(contains("'p_ano'")));
    });

    test('Tokens: a leitura direta só pede colunas que existem', () {
      final m = RegExp(r"\.from\('bora_tokens'\)\s*\.select\('([^']*)'\)")
          .firstMatch(tokens);
      expect(m, isNotNull, reason: 'falta a leitura de bora_tokens');
      final colunas = m!.group(1)!;
      expect(colunas, isNot(contains('is_active')));
      expect(colunas, isNot(contains('reason')));
      expect(colunas, contains('is_used'));
      expect(colunas, contains('used_at'));
      // O erro já não é engolido: aparece por palavras.
      expect(tokens, contains('_allGrantsErro = humanizeAdminRpcError(e)'));
      expect(tokens, contains('Text(kTokensListaLimitada'));
    });

    test('Tokens: atribuir e revogar continuam a chamar as mesmas funções', () {
      expect(tokens, contains("rpc('admin_grant_tokens'"));
      expect(tokens, contains("rpc('admin_revoke_token_grant'"));
      expect(tokens, contains("rpc('admin_get_user_tokens'"));
    });

    test('MB Way da Bora: exemplo neutro e explicação no campo', () {
      expect(acertos, contains("hintText: '9XX XXX XXX'"));
      // Nenhum número de telemóvel de verdade como exemplo.
      expect(RegExp(r"hintText: '\d{9}'").hasMatch(acertos), isFalse);
      expect(acertos, contains('helperText: kMbwayBoraExplicacao'));
    });

    test('Reenviar recibos pergunta ANTES de chamar o servidor', () {
      final resend = _entre(acertos, 'Future<void> _resend() async {',
          'Future<void> _exportar() async {');
      final pergunta = resend.indexOf('showDialog<bool>(');
      final sai = resend.indexOf('if (ok != true || !mounted) return;');
      final envia = resend.indexOf("rpc('admin_resend_weekly_digest'");
      expect(pergunta, greaterThan(0));
      expect(sai, greaterThan(pergunta));
      expect(envia, greaterThan(sai),
          reason: 'o envio a todos só depois do sim');
      expect(resend,
          contains("'Reenviar o recibo desta semana por email para TODOS?'"));
    });

    test('"Pagar" passou a "Copiar MB Way e valor"; "Reabrir" explica-se', () {
      expect(acertos, isNot(contains("const Text('Pagar')")));
      expect(acertos, contains("const Text('Copiar MB Way e valor')"));
      expect(acertos, contains("message: 'O pagamento você faz no app do banco'"));
      expect(acertos,
          contains("'Voltar para pendente e recalcular com os dados de hoje'"));
      // A operação de dinheiro não mudou.
      expect(acertos, contains("rpc('admin_set_settlement_state'"));
      expect(acertos, contains("'p_status': owes ? 'received' : 'paid'"));
    });

    test('Excluir rascunho desligado com o motivo; Criar pedido igual', () {
      expect(orfaos, contains('static const bool _excluirRascunhoDisponivel = false;'));
      expect(orfaos, contains('onDelete:'));
      expect(orfaos, contains('_excluirRascunhoDisponivel ? _deleteDraft : null'));
      expect(orfaos, contains('onPressed: apagar == null ? null : () => apagar(row)'));
      expect(orfaos, contains("const Text('Excluir rascunho')"));
      expect(orfaos, contains("key: ValueKey('excluir_rascunho_indisponivel')"));
      expect(orfaos, contains(
          ".invoke('finalize-order-from-intent', body: {'payment_intent_id': pi})"));
    });

    test('Talões: sem leitura dos pedidos diz-se por palavras, mesma consulta', () {
      expect(taloes, contains(".select('id, assigned_driver_id')"));
      expect(taloes, contains(".select('assigned_driver_id')"));
      expect(taloes, contains('semLeitura = orders.isEmpty;'));
      expect(taloes, contains('? kTalaoFiltroEntregadorSemLeitura'));
      expect(taloes, contains('if (_pedidoSemLeitura) ...['));
      expect(taloes, contains('const Text(kTalaoEntregadorSemLeitura'));
    });

    test('Comércios: Reimportar pergunta com a explicação antes de importar', () {
      final reimport = _entre(comercios, 'Future<void> _reimport() async {',
          'Future<void> _setVisibility(');
      final pergunta = reimport.indexOf('showDialog<bool>(');
      final importa = reimport.indexOf(".invoke('import-guarda-businesses')");
      expect(pergunta, greaterThan(0));
      expect(importa, greaterThan(pergunta));
      expect(reimport, contains('const Text(kReimportarComerciosExplicacao)'));
    });

    test('Continente: aviso fixo no topo, antes do resto do ecrã', () {
      final corpo = _entre(continente, 'body: Column(', 'Widget _summaryPanel()');
      final aviso = corpo.indexOf("ValueKey('continente_pvpr_aviso')");
      final resto = corpo.indexOf('_summaryPanel()');
      expect(aviso, greaterThan(0));
      expect(resto, greaterThan(aviso));
      expect(corpo, contains('Text(kContinentePvprAviso'));
    });

    test('Despacho: a frase do topo diz o que a tela tem', () {
      final j = _juntarLiterais(despacho);
      expect(
          j,
          contains('Aqui só há tempos e a chamada de reforço; distâncias não '
              'se configuram nesta tela.'));
      expect(j, isNot(contains('Estes 5 parâmetros')));
    });

    test('nenhum "Erro: \$e" cru nos ecrãs tocados', () {
      for (final s in [fecho, tokens, acertos, orfaos, taloes, continente]) {
        expect(s, isNot(contains(r"'Erro: $e'")));
        expect(s, isNot(contains(r"'Erro: $_error'")));
      }
      for (final s in [fecho, tokens, acertos, orfaos, taloes, continente]) {
        expect(s, contains("import '_admin_rpc_errors.dart';"));
      }
    });
  });

  group('textos', () {
    test('as frases pedidas, tal e qual', () {
      expect(kMbwayBoraExplicacao,
          'Número que aparece nos recibos e lembretes de quem deve à Bora.');
      expect(
          kAvisoPedidosVermelho,
          'Pedidos em que a Bora perdeu dinheiro: o cliente pagou menos que a '
          'compra mais o entregador. Corrija o preço em Preços por talão.');
      expect(kSemLeituraAdmin,
          'Ainda mostra zero: falta permissão de leitura de admin no servidor (proposta enviada).');
      expect(
          kTokensListaLimitada,
          'A lista mostra só os tokens que o servidor deixa o painel ler; '
          'a leitura completa de admin está em proposta.');
      expect(kExcluirRascunhoIndisponivel,
          'Excluir ainda não funciona: falta uma função de admin no servidor (proposta enviada).');
      expect(
          kReimportarComerciosExplicacao,
          'Reimportar traz de novo os dados do mapa e desfaz correções de nome, '
          'categoria e endereço feitas à mão; os escondidos continuam escondidos.');
      expect(kContinentePvprAviso,
          'Ferramenta de junho/2026, já aplicada. Não use para atualizar os preços de hoje.');
      expect(kTalaoFiltroEntregadorSemLeitura, contains('filtro por entregador'));
      expect(kTalaoEntregadorSemLeitura, startsWith('Entregador: '));
    });
  });

  testWidgets('Tokens: pede só colunas que existem e diz porque a lista vem curta',
      (tester) async {
    await _abrir(tester, const AdminTokensScreen());
    final leitura = _chamadas.firstWhere((c) => c['tabela'] == 'bora_tokens');
    final colunas = '${leitura['select']}';
    expect(colunas, contains('is_used'));
    expect(colunas, contains('used_at'));
    expect(colunas, isNot(contains('is_active')));
    expect(colunas, isNot(contains('reason')));
    expect(find.text(kTokensListaLimitada), findsOneWidget);
    expect(find.text('Sem tokens neste filtro.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Acertos: textos novos e Reenviar recibos só manda depois do sim',
      (tester) async {
    await _abrir(tester, const AdminAcertosSemanaScreen());

    expect(find.text('Copiar MB Way e valor'), findsOneWidget);
    expect(find.text('Pagar'), findsNothing);
    expect(find.byTooltip('O pagamento você faz no app do banco'), findsOneWidget);
    expect(find.byTooltip('Voltar para pendente e recalcular com os dados de hoje'),
        findsOneWidget);
    expect(find.text(kMbwayBoraExplicacao), findsOneWidget);
    expect(find.text(kAvisoPedidosVermelho), findsOneWidget);
    expect(find.text(kSemLeituraAdmin), findsNWidgets(2));

    // Cancelar: nada sai.
    await tester.tap(find.text('Reenviar recibos'));
    await _animar(tester);
    expect(find.text('Reenviar o recibo desta semana por email para TODOS?'),
        findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await _animar(tester);
    await _servidorResponde(tester);
    expect(_chamadas.where((c) => c['rpc'] == 'admin_resend_weekly_digest'),
        isEmpty);

    // Sim: sai uma vez, para a semana aberta.
    await tester.tap(find.text('Reenviar recibos'));
    await _animar(tester);
    await tester.tap(find.text('Reenviar para todos'));
    await _animar(tester);
    await _servidorResponde(tester);
    final envios = _chamadas
        .where((c) => c['rpc'] == 'admin_resend_weekly_digest')
        .toList();
    expect(envios, hasLength(1));
    expect(envios.single['p_week_start'], '2026-11-09');

    // Deixa o aviso (SnackBar) acabar antes de fechar o teste.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
