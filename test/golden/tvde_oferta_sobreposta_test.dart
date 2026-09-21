import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/widgets/tvde/tvde_offer_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fabrica_de_fotos.dart';

/// [Oferta sobreposta 20/09/2026] Fotos do cartão de oferta POR CIMA de um
/// ecrã qualquer (aqui, um ecrã de corrida activa a fingir), nos três estados
/// que interessam: oferta imediata com o motorista ocupado, oferta de reserva
/// (o caso que falhou a 20/09) e oferta expirada nas mãos dele (a frase
/// honesta, nunca um ecrã vazio). No emulador a heads-up do Android tapava a
/// frase de expirada; estas fotos são a prova de como o cartão se desenha.
TvdeRide _ride({
  String id = 'r1',
  String status = 'solicitada',
  DateTime? expira,
  DateTime? reservaExpira,
  DateTime? marcada,
  String? origem,
  String? destino,
}) {
  return TvdeRide(
    id: id,
    clientId: 'c1',
    status: status,
    originLat: 40.5285,
    originLng: -7.2516,
    destLat: 40.5407,
    destLng: -7.2677,
    estDistanceKm: 4.5,
    estFareCents: 500,
    driverEarnCents: 400,
    originLabel: origem ?? 'Intermarché Guarda',
    destLabel: destino ?? 'Rua Francisco de Passos 75',
    offerExpiresAt: expira,
    reservationOfferExpiresAt: reservaExpira,
    scheduledAt: marcada,
    reservationStatus: marcada == null ? null : 'a_procurar',
  );
}

/// Um ecrã de corrida activa a fingir — só para se ver que o cartão fica
/// POR CIMA (AppBar incluída), como no `MaterialApp.builder`.
Widget _ecraDeCorrida(Widget cartao) {
  return Stack(
    fit: StackFit.expand,
    children: [
      Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('Corrida'),
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFFE8EAED),
                alignment: Alignment.center,
                child: const Text('(mapa)',
                    style: TextStyle(color: AppColors.textSubtle)),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Motorista a caminho · Recolha em ~4 min',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  SizedBox(height: 6),
                  Text('Campo de Ténis do IPG → Garden Shopping',
                      style: TextStyle(color: AppColors.textSecondary)),
                  SizedBox(height: 60),
                ],
              ),
            ),
          ],
        ),
      ),
      Positioned(
        top: 8,
        left: 12,
        right: 12,
        child: Material(type: MaterialType.transparency, child: cartao),
      ),
    ],
  );
}

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  final agora = DateTime(2026, 9, 20, 23, 33, 0);
  const telemovel = ('telemovel', Size(390, 844));

  testWidgets('oferta imediata por cima da corrida activa (motorista ocupado)',
      (tester) async {
    await fotografaTela(
      tester,
      nome: 'tvde_oferta_sobreposta_ocupado',
      tamanho: telemovel,
      tela: _ecraDeCorrida(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.add(const Duration(seconds: 27))),
        current: _ride(
            id: 'activa',
            status: 'motorista_a_caminho',
            origem: 'Campo de Ténis do IPG',
            destino: 'Garden Shopping'),
        agora: () => agora,
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () {},
      )),
    );
    expect(find.text('Nova corrida — depois desta corrida'), findsOneWidget);
    expect(find.text('Aceitar'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
    expect(find.text('27s'), findsOneWidget);
  });

  testWidgets('oferta de RESERVA por cima da corrida activa (o caso de 20/09)',
      (tester) async {
    await fotografaTela(
      tester,
      nome: 'tvde_oferta_sobreposta_reserva',
      tamanho: telemovel,
      tela: _ecraDeCorrida(TvdeReservationOverlayCard(
        ride: _ride(
          id: 'res',
          status: 'agendada',
          marcada: DateTime(2026, 9, 21, 0, 0),
          reservaExpira: agora.add(const Duration(minutes: 4, seconds: 56)),
          origem: 'Santa Casa da Misericórdia',
          destino: 'Pingo Doce novo (Av. S. Salvador)',
        ),
        agora: () => agora,
        onAccept: () {},
        onReject: () {},
        onExpiredDismiss: () {},
      )),
    );
    expect(find.text('Reserva para aceitar'), findsOneWidget);
    expect(find.text('Aceitar reserva'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
  });

  testWidgets('oferta expirada nas mãos dele: a frase honesta',
      (tester) async {
    await fotografaTela(
      tester,
      nome: 'tvde_oferta_sobreposta_expirada',
      tamanho: telemovel,
      tela: _ecraDeCorrida(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.subtract(const Duration(seconds: 2))),
        current: _ride(id: 'activa', status: 'motorista_a_caminho'),
        agora: () => agora,
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () {},
      )),
    );
    expect(find.text('Esta corrida já foi para outro motorista.'),
        findsOneWidget);
    expect(find.text('Aceitar'), findsNothing);
  });
}
