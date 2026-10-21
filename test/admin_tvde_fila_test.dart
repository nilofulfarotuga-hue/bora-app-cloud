// [A2 · 21/10/2026] Painel admin (PT-BR) da fila inteligente do TVDE.
// Lê exactamente o formato que a RPC admin_tvde_fila_ao_vivo devolveu na prova em
// transacção desfeita (a2/prova_fila_rollback_RESULT_1.json), mostra quem tem a
// oferta e quanto falta, o histórico com os motivos, exporta CSV, e o
// interruptor grava pela RPC de sempre (admin_update_setting).
import 'package:bora_app/screens/admin/admin_tvde_fila_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _aoVivo() => {
      'agora': '2026-10-21T12:25:00Z',
      'ligada': true,
      'oferta_s': 40,
      'max_motoristas': 5,
      'peso_nota_min': 2,
      'peso_aceitacao_min': 5,
      'historico_dias': 30,
      'corridas': [
        {
          'ride_id': 'a2a20000-0000-4000-8000-0000000000b1',
          'status': 'solicitada',
          'ride_kind': 'passageiros',
          'origem': 'Sé da Guarda (prova A2)',
          'destino': 'Bairro da Luz (prova A2)',
          'criada_em': '2026-10-21T12:24:20Z',
          'reserva': false,
          'balcao': false,
          'oferta_motorista': 'DEMO A2 D3',
          'oferta_expira_em': '2026-10-21T12:25:30Z',
          'segundos_restantes': 30,
          'ronda': 1,
          'ronda_estado': 'ativa',
          'entradas': [
            {'pos': 1, 'motorista': 'Estafeta Demo', 'eta_min': 1.93, 'dist_km': 0.9, 'nota': 4.8, 'taxa_aceitacao': 0.8, 'pontos': 3.33, 'estado': 'expirou'},
            {'pos': 2, 'motorista': 'DEMO A2 D3', 'eta_min': 3.22, 'dist_km': 1.5, 'nota': 4.8, 'taxa_aceitacao': 0.8, 'pontos': 4.62, 'estado': 'oferta'},
            {'pos': 3, 'motorista': 'DEMO A2 D2', 'eta_min': 1.07, 'dist_km': 0.5, 'nota': 4.8, 'taxa_aceitacao': 0.267, 'pontos': 5.135, 'estado': 'espera'},
          ],
        },
      ],
    };

List<dynamic> _historico() => [
      {
        'ride_id': 'a2a20000-0000-4000-8000-0000000000b1',
        'ronda': 1,
        'pos': 1,
        'motorista': 'Estafeta Demo',
        'estado': 'expirou',
        'quando': '2026-10-21T12:25:00Z',
        'origem': 'Sé da Guarda',
      },
      {
        'ride_id': 'a2a20000-0000-4000-8000-0000000000b1',
        'ronda': 1,
        'pos': 4,
        'motorista': 'Outro; com ponto e vírgula',
        'estado': 'saltado',
        'motivo': 'sem_aviso_no_telemovel',
        'quando': '2026-10-21T12:25:10Z',
      },
    ];

void main() {
  test('lê a fila ao vivo no formato da RPC', () {
    final v = FilaAoVivoView.fromMap(_aoVivo());
    expect(v.ligada, isTrue);
    expect(v.ofertaS, 40);
    expect(v.corridas.single.entradas.map((e) => e.pos), [1, 2, 3]);
    expect(v.corridas.single.entradas[2].taxaAceitacao, closeTo(0.267, 1e-9));
    expect(v.corridas.single.ofertaMotorista, 'DEMO A2 D3');
    expect(v.corridas.single.rondaEstado, 'ativa');
  });

  test('aguenta nulos e JSON mínimo (fila desligada, sem corridas)', () {
    final v = FilaAoVivoView.fromMap({'ligada': 'false'});
    expect(v.ligada, isFalse);
    expect(v.corridas, isEmpty);
    final e = FilaEntradaView.fromMap({'pos': '2', 'motorista_id': 'abcdef1234'});
    expect(e.pos, 2);
    expect(e.motorista, 'Motorista abcdef12');
    expect(e.estado, 'espera');
  });

  test('rótulos em PT-BR', () {
    expect(rotuloEstadoFila('espera'), 'Na fila');
    expect(rotuloEstadoFila('oferta'), 'Com a oferta');
    expect(rotuloEstadoFila('expirou'), 'Deixou expirar');
    expect(rotuloEstadoFila('saltado'), 'Pulado');
    expect(rotuloRondaFila('esgotada'), contains('despacho normal'));
    expect(rotuloRondaFila(null), contains('Sem fila'));
    expect(rotuloMotivoFila('sem_aviso_no_telemovel'),
        'sem notificação no telemóvel (sem_aviso_no_telemovel)');
  });

  test('contagem decrescente da oferta a partir da leitura do servidor', () {
    final lido = DateTime.utc(2026, 10, 21, 12, 25, 0);
    expect(segundosQueFaltam(30, lido, lido), 30);
    expect(segundosQueFaltam(30, lido, lido.add(const Duration(seconds: 12))), 18);
    expect(segundosQueFaltam(30, lido, lido.add(const Duration(minutes: 2))), 0);
    expect(segundosQueFaltam(null, lido, lido), 0);
  });

  test('exportar CSV: cabeçalho, uma linha por evento, campos com ";" entre aspas', () {
    final linhas = _historico()
        .map((e) => FilaHistoricoLinha.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final csv = csvHistoricoFila(linhas).trim().split('\n');
    expect(csv.first, startsWith('quando_lisboa;corrida;rodada;posicao;motorista;estado'));
    expect(csv.length, 3);
    expect(csv[1], contains('Deixou expirar'));
    expect(csv[2], contains('"Outro; com ponto e vírgula"'));
    expect(csv[2], contains('Pulado'));
    expect(csv[1], startsWith('2026-10-21T13:25:00'), reason: 'hora de Lisboa (UTC+1 em outubro)');
  });

  testWidgets('ecrã: mostra a corrida, quem tem a oferta e o interruptor grava', (tester) async {
    final gravados = <String, Object>{};
    await tester.pumpWidget(MaterialApp(
      home: AdminTvdeFilaScreen(
        autoAtualizar: false,
        carregarAoVivo: () async => _aoVivo(),
        carregarHistorico: () async => _historico(),
        carregarAjustes: () async => {
          'tvde_fila_inteligente_enabled': false,
          'tvde_offer_ttl_seconds': 40,
          'tvde_pos_ao_vivo_enabled': true,
        },
        gravarAjuste: (k, v) async => gravados[k] = v,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fila inteligente LIGADA'), findsOneWidget);
    expect(find.text('Sé da Guarda (prova A2) → Bairro da Luz (prova A2)'), findsOneWidget);
    expect(find.byKey(const Key('fila_oferta_a2a20000-0000-4000-8000-0000000000b1')), findsOneWidget);
    expect(find.textContaining('Oferta agora: DEMO A2 D3'), findsOneWidget);
    expect(find.text('Com a oferta'), findsOneWidget);
    expect(find.text('Deixou expirar'), findsOneWidget);
    expect(find.text('Na fila'), findsOneWidget);

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estafeta Demo — Deixou expirar'), findsOneWidget);
    expect(find.textContaining('sem notificação no telemóvel'), findsOneWidget);

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    final sw = find.byKey(const Key('sw_fila_inteligente'));
    expect(sw, findsOneWidget);
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(gravados['tvde_fila_inteligente_enabled'], true);
  });
}
