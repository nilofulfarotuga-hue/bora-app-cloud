// PROVA VISUAL do separador "Reserva" com os 4 tipos (10/10/2026), no
// emulador Android. Sem login e sem dados reais: monta o ecrã verdadeiro
// (ClientReservationsScreen) com stores de exemplo — mesa, corrida marcada,
// limpeza e marcação inventadas — e pára em cada ecrã para o PC tirar a
// captura por adb (`.claude/.ai/provas/reservas-num-so-sitio-2026-10-10/capturar.ps1`).
//
// Porque não se criam reservas de teste no banco: inserir à mão em
// `tvde_rides`/`appointments` é proibido pelas regras de operação, e uma
// corrida ou limpeza marcada em produção é oferecida a motoristas e
// faxineiras reais (cicatriz das corridas sintéticas que fugiram para gente
// real).
//
// Cada paragem anuncia-se no log: "[prova] PRONTO <nome>".
//   flutter build apk --debug --target=integration_test/reservas_prova_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bora_app/models/appointment_model.dart';
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/models/reservation_model.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/client/cleaning/cleaning_tracking_screen.dart';
import 'package:bora_app/screens/client/services/booking_success_screen.dart';
import 'package:bora_app/screens/client/tvde/tvde_my_reservations_screen.dart';
import 'package:bora_app/screens/client_reservations_screen.dart';
import 'package:bora_app/stores/cleaning_store.dart';
import 'package:bora_app/stores/reservation_store.dart';
import 'package:bora_app/stores/services_store.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:bora_app/widgets/bora/bora_bottom_nav_v2.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _anon = String.fromEnvironment('SUPABASE_ANON_KEY');
const _segundosPorCaptura = 6;

class _Mesas extends ReservationStore {
  _Mesas(this._l);
  final List<ReservationModel> _l;
  @override
  List<ReservationModel> get myReservations => _l;
  @override
  String? get error => null;
  @override
  Future<void> fetchMyReservations() async {}
  @override
  void subscribeMyReservations() {}
}

class _Corridas extends TvdeStore {
  _Corridas(this._agendadas, this._historico);
  final List<TvdeRide> _agendadas;
  final List<TvdeRide> _historico;
  @override
  List<TvdeRide> get reservations => _agendadas;
  @override
  List<TvdeRide> get history => _historico;
  @override
  TvdeRide? get activeRide => null;
  @override
  bool get historyFailed => false;
  @override
  Future<void> loadMyReservations() async {}
  @override
  Future<void> loadHistory() async {}
  @override
  Future<Map<String, int>> loadReservationLimits() async =>
      {'freeCancelHours': 2};
}

class _Limpezas extends CleaningStore {
  _Limpezas(this._l);
  final List<CleaningBooking> _l;
  @override
  List<CleaningBooking> get bookings => _l;
  @override
  Future<void> loadMyBookings() async {}
  @override
  CleaningBooking? get tracked => null;
  @override
  void trackBooking(CleaningBooking booking) {}
  @override
  Future<int> getSettingInt(String key, int fallback) async => fallback;
}

class _Marcacoes extends ServicesStore {
  _Marcacoes(this._l);
  final List<AppointmentModel> _l;
  @override
  List<AppointmentModel> get myAppointments => _l;
  @override
  String? get appointmentsError => null;
  @override
  Future<void> fetchMyAppointments() async {}
}

TvdeRide _corrida(String id, Duration daqui,
        {String status = 'agendada',
        String? reserva,
        String metodo = 'mbway',
        String? pagamento = 'succeeded',
        required String para,
        required String de}) =>
    TvdeRide.fromMap({
      'id': id,
      'client_id': 'cliente-de-teste',
      'status': status,
      'reservation_status': reserva,
      'payment_method': metodo,
      'payment_status': pagamento,
      'scheduled_at': DateTime.now().toUtc().add(daqui).toIso8601String(),
      'dest_label': para,
      'origin_label': de,
    });

CleaningBooking _limpeza(String id, Duration daqui, String status,
        {String metodo = 'mbway', String pagamento = 'held'}) =>
    CleaningBooking.fromSupabase({
      'id': id,
      'client_user_id': 'cliente-de-teste',
      'scheduled_at': DateTime.now().toUtc().add(daqui).toIso8601String(),
      'status': status,
      'payment_method': metodo,
      'payment_status': pagamento,
      'address_street': 'Rua do Teste 12, Guarda',
      'cleaning_type': 'standard',
    });

Widget _comStores(Widget filho) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ReservationStore>(
          create: (_) => _Mesas([
            ReservationModel(
              id: 'mesa-1',
              restaurantId: 'r1',
              clientUserId: 'cliente-de-teste',
              clientName: 'Cliente de Teste',
              clientPhone: '910000000',
              people: 4,
              reservedFor:
                  DateTime.now().toUtc().add(const Duration(days: 3, hours: 6)),
              status: ReservationStatus.approved,
              prepaymentCents: 300,
              restaurantName: 'Restaurante de Teste',
            ),
            ReservationModel(
              id: 'mesa-2',
              restaurantId: 'r1',
              clientUserId: 'cliente-de-teste',
              clientName: 'Cliente de Teste',
              clientPhone: '910000000',
              people: 2,
              reservedFor:
                  DateTime.now().toUtc().subtract(const Duration(days: 9)),
              status: ReservationStatus.cancelledByClient,
              prepaymentCents: 300,
              restaurantName: 'Restaurante de Teste',
            ),
          ]),
        ),
        ChangeNotifierProvider<TvdeStore>(
          create: (_) => _Corridas([
            // Ainda agendada (vem das "reservas" do TvdeStore).
            _corrida('corrida-2', const Duration(days: 1, hours: 2),
                metodo: 'cash',
                pagamento: null,
                reserva: 'atribuida',
                para: 'Estação da Guarda',
                de: 'Rua do Teste 12, Guarda'),
          ], [
            // Aos 20 min já passou a motorista a caminho (só está no
            // histórico): continua em Próximas até acabar.
            _corrida('corrida-1', const Duration(minutes: 15),
                status: 'motorista_a_caminho',
                reserva: 'ativada',
                para: 'Hospital Sousa Martins, Guarda',
                de: 'Praça Luís de Camões, Guarda'),
            _corrida('corrida-3', const Duration(days: -4),
                status: 'finalizada',
                reserva: 'ativada',
                para: 'IPG, Avenida Dr. Francisco Sá Carneiro',
                de: 'Praça Luís de Camões, Guarda'),
            _corrida('corrida-4', const Duration(days: -6),
                status: 'cancelada_cliente',
                reserva: 'cancelada',
                metodo: 'cash',
                pagamento: null,
                para: 'Estação da Guarda',
                de: 'Rua do Teste 12, Guarda'),
          ]),
        ),
        ChangeNotifierProvider<CleaningStore>(
          create: (_) => _Limpezas([
            _limpeza('limpeza-1', const Duration(hours: 8), 'accepted'),
            _limpeza('limpeza-2', const Duration(days: -12), 'completed',
                metodo: 'cash', pagamento: 'cash_settled'),
          ]),
        ),
        ChangeNotifierProvider<ServicesStore>(
          create: (_) => _Marcacoes([
            AppointmentModel(
              id: 'marcacao-1',
              providerId: 'p1',
              scheduledAt:
                  DateTime.now().toUtc().add(const Duration(days: 2, hours: 3)),
              status: AppointmentStatus.confirmed,
              depositStatus: 'paid',
              providerName: 'Barbearia de Teste',
              serviceName: 'Corte e barba',
            ),
            AppointmentModel(
              id: 'marcacao-2',
              providerId: 'p1',
              scheduledAt:
                  DateTime.now().toUtc().subtract(const Duration(days: 2)),
              status: AppointmentStatus.completed,
              depositStatus: 'paid',
              providerName: 'Barbearia de Teste',
              serviceName: 'Corte',
            ),
          ]),
        ),
      ],
      child: filho,
    );

Widget _vazio(Widget filho) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ReservationStore>(create: (_) => _Mesas([])),
        ChangeNotifierProvider<TvdeStore>(create: (_) => _Corridas([], [])),
        ChangeNotifierProvider<CleaningStore>(create: (_) => _Limpezas([])),
        ChangeNotifierProvider<ServicesStore>(create: (_) => _Marcacoes([])),
      ],
      child: filho,
    );

/// O separador como aparece na app: o ecrã e a barra de baixo em "Reserva".
Widget _separador() => Scaffold(
      body: const ClientReservationsScreen(),
      bottomNavigationBar: BoraBottomNavV2(
        current: BoraNavTab.reservation,
        onTabChanged: (_) {},
      ),
    );

Future<void> _parar(WidgetTester t, String nome) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  debugPrint('[prova] PRONTO $nome');
  for (var i = 0; i < _segundosPorCaptura * 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('prova visual do separador Reserva com os 4 tipos', (t) async {
    // ignore: deprecated_member_use
    await Supabase.initialize(url: _url, anonKey: _anon);
    final pagina = ValueNotifier<Widget>(const SizedBox());
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ValueListenableBuilder<Widget>(
        valueListenable: pagina,
        builder: (_, w, __) => w,
      ),
    ));

    pagina.value = _comStores(_separador());
    await _parar(t, '01_proximas_4_tipos');
    await t.tap(find.text('Passadas'));
    await t.pumpAndSettle();
    await _parar(t, '02_passadas');
    await t.tap(find.text('Canceladas'));
    await t.pumpAndSettle();
    await _parar(t, '03_canceladas');

    // Chave própria: senão o Flutter reaproveita os stores da página de cima
    // (mesma estrutura) e o ecrã vazio sai com as reservas de antes.
    pagina.value = KeyedSubtree(
        key: const ValueKey('vazio'), child: _vazio(_separador()));
    await _parar(t, '04_vazio_com_atalhos');

    pagina.value = BookingSuccessScreen(
      providerName: 'Barbearia de Teste',
      serviceName: 'Corte e barba',
      scheduledAt:
          DateTime.now().toUtc().add(const Duration(days: 2, hours: 3)),
      paidCents: 1500,
    );
    await _parar(t, '05_marcacao_confirmada');

    pagina.value =
        _comStores(const TvdeMyReservationsScreen(acabadaDeMarcar: true));
    await _parar(t, '06_corrida_marcada');

    pagina.value = _comStores(CleaningTrackingScreen(
      booking: _limpeza('limpeza-1', const Duration(hours: 8), 'scheduled'),
      acabadaDeMarcar: true,
    ));
    await _parar(t, '07_limpeza_marcada');

    debugPrint('[prova] FIM');
  });
}
