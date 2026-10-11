import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/driver/tvde/tvde_ride_active_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fabrica_de_fotos.dart';

/// [Cartão por fases · 11/10/2026] Fotos do cartão da corrida do MOTORISTA
/// nas três fases, com a gaveta recolhida e aberta, em telemóvel médio e
/// pequeno (um estouro de texto falha o teste sozinho). O mapa é um fundo
/// cinzento e o detalhe é um exemplo — o cabeçalho, a gaveta e o botão fixo
/// são os widgets verdadeiros do ecrã. A prova do ecrã inteiro é a do
/// emulador (`integration_test/tvde_corrida_fases_prova_test.dart`).
TvdeRide _corrida(String status, {int paragens = 0}) => TvdeRide.fromMap({
      'id': 'r1',
      'client_id': 'c1',
      'status': status,
      'origin_lat': 40.5285,
      'origin_lng': -7.2516,
      'dest_lat': 40.5407,
      'dest_lng': -7.2677,
      'est_distance_km': 4.5,
      'est_fare_cents': 700,
      'driver_earn_cents': 520,
      'payment_method': 'cash',
      'origin_label': 'Rua Marquês de Pombal 12',
      'dest_label': 'Estação da Guarda',
      'extra_stops_count': paragens,
    });

final _paragem = TvdeRideStop(
  id: 's1',
  seq: 1,
  label: 'Farmácia Central',
  lat: 40.535,
  lng: -7.26,
  feeCents: 200,
  driverCents: 150,
);

/// Detalhe de EXEMPLO (o verdadeiro precisa do estado do ecrã).
Widget _detalhe(TvdeRide r) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 12),
          const Row(children: [
            CircleAvatar(radius: 18, child: Icon(Icons.person, size: 18)),
            SizedBox(width: 8),
            Expanded(
                child: Text('Maria',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            Icon(Icons.chat_bubble_outline, color: AppColors.primary),
            SizedBox(width: 16),
            Icon(Icons.call, color: AppColors.primary),
          ]),
          const SizedBox(height: 10),
          const Text('Dinheiro · cobrar ao passageiro €7.00',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('Viagem: ${r.originLabel} → ${r.destLabel}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5)),
        ],
      ),
    );

Widget _ecra(
  DraggableScrollableController ctrl,
  TvdeRide r, {
  int? eta,
  int? espera,
  TvdeRideStop? paragem,
}) {
  return Scaffold(
    appBar: AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      title: const Text('Corrida'),
    ),
    bottomNavigationBar: TvdeCorridaBotaoPrincipal(
      ride: r,
      busy: false,
      onCheguei: () {},
      onIniciar: () {},
      onFinalizar: () {},
    ),
    body: Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: const Color(0xFFE8EAED),
            alignment: const Alignment(0, -0.7),
            child: const Text('(mapa)',
                style: TextStyle(color: AppColors.textSubtle)),
          ),
        ),
        Positioned.fill(
          child: TvdeCorridaGaveta(
            controller: ctrl,
            fase: '${r.id}|${r.status}',
            cabecalho: TvdeCorridaCabecalho(
              ride: r,
              passengerName: 'Maria',
              etaMin: eta,
              esperaSegundos: espera,
              proximaParagem: paragem,
              onNavegar: () {},
            ),
            detalhe: _detalhe(r),
          ),
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  final fases = <(String, TvdeRide, int?, int?, TvdeRideStop?)>[
    ('a_caminho', _corrida('motorista_a_caminho'), 4, null, null),
    ('chegou', _corrida('motorista_chegou'), null, 95, null),
    ('em_viagem', _corrida('em_andamento'), 7, null, null),
    ('em_viagem_paragem', _corrida('em_andamento', paragens: 1), 9, null,
        _paragem),
  ];
  const tamanhos = [('telemovel', Size(390, 844)), ('pequeno', Size(320, 640))];

  for (final (nome, r, eta, espera, paragem) in fases) {
    for (final tamanho in tamanhos) {
      testWidgets('$nome · recolhida · ${tamanho.$1}', (tester) async {
        final ctrl = DraggableScrollableController();
        addTearDown(ctrl.dispose);
        await fotografaTela(
          tester,
          nome: 'tvde_corrida_motorista_${nome}_recolhida',
          tamanho: tamanho,
          tela: _ecra(ctrl, r, eta: eta, espera: espera, paragem: paragem),
          interagir: (t) => t.pumpAndSettle(),
        );
        expect(ctrl.size, lessThan(0.6));
      });

      testWidgets('$nome · aberta · ${tamanho.$1}', (tester) async {
        final ctrl = DraggableScrollableController();
        addTearDown(ctrl.dispose);
        await fotografaTela(
          tester,
          nome: 'tvde_corrida_motorista_${nome}_aberta',
          tamanho: tamanho,
          tela: _ecra(ctrl, r, eta: eta, espera: espera, paragem: paragem),
          interagir: (t) async {
            await t.pumpAndSettle();
            await t.tap(find.byKey(const ValueKey('tvde_corrida_pega')));
            await t.pumpAndSettle();
          },
        );
        // Aberta à altura do conteúdo: o fim do detalhe à vista, por cima do
        // botão fixo.
        final fim = tester.getRect(find.textContaining('Viagem:'));
        final botao = tester.getRect(find.byType(ElevatedButton));
        expect(fim.bottom, lessThanOrEqualTo(botao.top));
      });
    }
  }
}
