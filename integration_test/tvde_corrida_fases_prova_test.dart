// PROVA VISUAL do cartão da corrida do MOTORISTA por fases (11/10/2026), no
// emulador Android. Monta o ecrã VERDADEIRO (`TvdeRideActiveScreen`: mapa,
// GPS, gaveta, botão fixo) com uma corrida de exemplo num store falso — a
// caminho, chegou, em viagem e em viagem com paragem —, com a gaveta
// recolhida e aberta, e pára em cada uma para o PC tirar a captura por adb
// (`.claude/.ai/provas/cartao-corrida-motorista-2026-10-11/capturar.ps1`).
//
// Sem login e sem escrever no banco: criar uma corrida em `tvde_rides` à mão
// é proibido pelas regras de operação e uma corrida de teste em produção é
// oferecida a motoristas reais. As duas chamadas que o ecrã faz sozinho
// (`driver_update_location`, `tvde_ride_passenger_card`) estão fechadas a
// quem não tem sessão — sem sessão falham e não gravam nada; por isso o
// título sai "sem nome" ("o passageiro").
//
// Cada paragem anuncia-se no log: "[prova] PRONTO <nome>".
//   flutter build apk --debug --dart-define-from-file=.dart_defines
//     --target=integration_test/tvde_corrida_fases_prova_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/driver/tvde/tvde_ride_active_screen.dart';
import 'package:bora_app/stores/driver_store.dart';
import 'package:bora_app/stores/tvde_chat_store.dart';
import 'package:bora_app/stores/tvde_driver_store.dart';
import 'package:bora_app/stores/tvde_store.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _anon = String.fromEnvironment('SUPABASE_ANON_KEY');
const _segundosPorCaptura = 6;

class _Motorista extends TvdeDriverStore {
  TvdeRide? corrida;
  @override
  TvdeRide? get activeRide => corrida;
  @override
  TvdeRide? get queuedRide => null;
  @override
  int get noshowWaitMinutes => 5;
  @override
  Future<void> loadCurrent() async {}
  void mudar(TvdeRide r) {
    corrida = r;
    notifyListeners();
  }
}

class _Tvde extends TvdeStore {
  @override
  Future<int> getSettingInt(String key, int fallback) async => fallback;
  @override
  Future<List<TvdeRideStop>> fetchRideStops(String rideId) async =>
      rideId == 'prova-paragem'
          ? [
              TvdeRideStop(
                id: 's1',
                seq: 1,
                label: 'Farmácia Central, Rua do Comércio',
                lat: 40.5372,
                lng: -7.2655,
                feeCents: 200,
                driverCents: 150,
              ),
            ]
          : const <TvdeRideStop>[];
}

class _Chat extends TvdeChatStore {
  @override
  void listen(String rideId) {}
  @override
  void unlisten(String rideId) {}
  @override
  int unreadFor(String rideId, String myRole) => 0;
}

TvdeRide _corrida(String status,
        {String id = 'prova-corrida', int paragens = 0, DateTime? chegou}) =>
    TvdeRide.fromMap({
      'id': id,
      'client_id': 'cliente-de-teste',
      'status': status,
      'origin_lat': 40.5373,
      'origin_lng': -7.2676,
      'dest_lat': 40.5458,
      'dest_lng': -7.2417,
      'est_distance_km': 3.2,
      'est_fare_cents': 700,
      'driver_earn_cents': 520,
      'payment_method': 'cash',
      'origin_label': 'Praça Luís de Camões, Guarda',
      'dest_label': 'Estação da Guarda',
      'extra_stops_count': paragens,
      if (chegou != null) 'arrived_at': chegou.toUtc().toIso8601String(),
    });

Future<void> _assentar(WidgetTester t, {int segundos = 3}) async {
  for (var i = 0; i < segundos * 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
}

Future<void> _parar(WidgetTester t, String nome) async {
  await _assentar(t, segundos: 2);
  debugPrint('[prova] PRONTO $nome');
  await _assentar(t, segundos: _segundosPorCaptura);
}

double _tamanho(WidgetTester t) => t
    .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
    .controller!
    .size;

Future<void> _fase(WidgetTester t, _Motorista m, TvdeRide r, String nome) async {
  m.mudar(r);
  await _assentar(t, segundos: 4);
  final recolhida = _tamanho(t);
  await _parar(t, '${nome}_recolhida');
  // [Juiz 11/10] Abre-se com o DEDO, devagar, com frames pelo meio — como na
  // rua, com o ecrã a redesenhar-se (mira, SOS, cronómetro). Fecha-se com um
  // toque na pega. As duas maneiras ficam provadas.
  final dedo = await t.startGesture(
      t.getCenter(find.byKey(const ValueKey('tvde_corrida_pega'))));
  for (var i = 0; i < 24; i++) {
    await dedo.moveBy(const Offset(0, -25));
    await t.pump(const Duration(milliseconds: 16));
  }
  final comODedo = _tamanho(t);
  await dedo.up();
  await _assentar(t, segundos: 1);
  debugPrint('[prova] TAMANHO $nome recolhida=${recolhida.toStringAsFixed(3)} '
      'com_o_dedo=${comODedo.toStringAsFixed(3)} '
      'aberta=${_tamanho(t).toStringAsFixed(3)}');
  await _parar(t, '${nome}_aberta');
  // Volta a recolher (toque na pega) para a fase seguinte começar como na rua.
  await t.tap(find.byKey(const ValueKey('tvde_corrida_pega')));
  await _assentar(t, segundos: 1);
  debugPrint('[prova] TAMANHO $nome depois_do_toque='
      '${_tamanho(t).toStringAsFixed(3)}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('prova visual do cartão da corrida por fases', (t) async {
    // ignore: deprecated_member_use
    await Supabase.initialize(url: _url, anonKey: _anon);
    final motorista = _Motorista()..corrida = _corrida('motorista_a_caminho');

    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DriverStore>(create: (_) => DriverStore()),
        ChangeNotifierProvider<TvdeStore>(create: (_) => _Tvde()),
        ChangeNotifierProvider<TvdeChatStore>(create: (_) => _Chat()),
        ChangeNotifierProvider<TvdeDriverStore>.value(value: motorista),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const TvdeRideActiveScreen(),
      ),
    ));
    // Mapa, GPS e rota a chegar.
    await _assentar(t, segundos: 8);

    await _fase(t, motorista, _corrida('motorista_a_caminho'), 'a_caminho');
    await _fase(
        t,
        motorista,
        _corrida('motorista_chegou',
            chegou: DateTime.now().subtract(const Duration(seconds: 95))),
        'chegou');
    await _fase(t, motorista, _corrida('em_andamento'), 'em_viagem');
    await _fase(
        t,
        motorista,
        _corrida('em_andamento', id: 'prova-paragem', paragens: 1),
        'em_viagem_paragem');
    debugPrint('[prova] FIM');
  });
}
