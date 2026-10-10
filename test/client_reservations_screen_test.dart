// Separador "Reservas" do cliente (10/10/2026): os quatro tipos no mesmo
// sítio, e um store que falha não apaga os outros três da lista.
import 'package:bora_app/models/appointment_model.dart';
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/models/reservation_model.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/client/services/booking_success_screen.dart';
import 'package:bora_app/screens/client_reservations_screen.dart';
import 'package:bora_app/stores/cleaning_store.dart';
import 'package:bora_app/stores/reservation_store.dart';
import 'package:bora_app/stores/services_store.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:bora_app/widgets/ver_nas_minhas_reservas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'golden/fabrica_de_fotos.dart';

// Sem renovação automática do token: senão fica um temporizador de 10 s vivo
// depois do teste.
SupabaseClient _semRede() => SupabaseClient('http://localhost:9', 'teste',
    authOptions: const AuthClientOptions(autoRefreshToken: false));

class _Mesas extends ReservationStore {
  _Mesas(this._l) : super(supabase: _semRede());
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
  _Corridas(this._l);
  final List<TvdeRide> _l;
  @override
  List<TvdeRide> get reservations => _l;
  @override
  List<TvdeRide> get history => const [];
  @override
  TvdeRide? get activeRide => null;
  @override
  bool get historyFailed => false;
  @override
  Future<void> loadMyReservations() async {}
  @override
  Future<void> loadHistory() async {}
}

/// A limpeza falha ao carregar (ou não, conforme [falha]) — e tem as que já
/// estavam na memória. Como o store real: não lança, diz pela bandeira.
class _Limpezas extends CleaningStore {
  _Limpezas(this._l, {this.falha = false});
  final List<CleaningBooking> _l;
  final bool falha;
  @override
  List<CleaningBooking> get bookings => _l;
  @override
  bool get myBookingsFailed => falha;
  @override
  Future<void> loadMyBookings() async {}
}

/// Avisa os ouvintes logo à entrada, antes do primeiro await — como o
/// `ReservationStore.fetchMyReservations` real.
class _MesasQueAvisam extends _Mesas {
  _MesasQueAvisam() : super(const []);
  @override
  Future<void> fetchMyReservations() async {
    notifyListeners();
  }
}

/// Pai que liga o separador ao tocar, como o `ClientMainScreen`.
class _Pai extends StatefulWidget {
  const _Pai();
  @override
  State<_Pai> createState() => _PaiState();
}

class _PaiState extends State<_Pai> {
  bool ativo = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: ClientReservationsScreen(ativo: ativo),
        floatingActionButton: TextButton(
          onPressed: () => setState(() => ativo = true),
          child: const Text('abrir'),
        ),
      );
}

class _Marcacoes extends ServicesStore {
  _Marcacoes(this._l) : super(supabase: _semRede());
  final List<AppointmentModel> _l;
  @override
  List<AppointmentModel> get myAppointments => _l;
  @override
  String? get appointmentsError => null;
  @override
  Future<void> fetchMyAppointments() async {}
}

/// O ecrã com uma reserva de cada tipo, à volta de agora.
Widget _ecraComUmaDeCada({bool limpezaFalha = false}) {
  final daqui = DateTime.now().toUtc();
  final mesa = ReservationModel(
    id: 'm1',
    restaurantId: 'r1',
    clientUserId: 'c',
    clientName: 'C',
    clientPhone: '9',
    people: 2,
    reservedFor: daqui.add(const Duration(days: 3)),
    status: ReservationStatus.approved,
    prepaymentCents: 300,
    restaurantName: 'Tasca do Teste',
  );
  final corrida = TvdeRide.fromMap({
    'id': 'c1',
    'client_id': 'c',
    'status': 'agendada',
    'reservation_status': 'atribuida',
    'payment_method': 'mbway',
    'payment_status': 'succeeded',
    'scheduled_at': daqui.add(const Duration(hours: 2)).toIso8601String(),
    'dest_label': 'Hospital Sousa Martins, Avenida Rainha Dona Amélia, Guarda',
    'origin_label': 'Praça Luís de Camões, Guarda, Portugal',
  });
  final limpeza = CleaningBooking.fromSupabase({
    'id': 'l1',
    'client_user_id': 'c',
    'scheduled_at': daqui.add(const Duration(days: 1)).toIso8601String(),
    'status': 'accepted',
    'payment_method': 'mbway',
    'payment_status': 'held',
    'address_street': 'Rua do Teste 12',
  });
  final marcacao = AppointmentModel(
    id: 'a1',
    providerId: 'p1',
    scheduledAt: daqui.add(const Duration(days: 2)),
    status: AppointmentStatus.confirmed,
    depositStatus: 'paid',
    providerName: 'Barbearia do Teste',
    serviceName: 'Corte',
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ReservationStore>(create: (_) => _Mesas([mesa])),
      ChangeNotifierProvider<TvdeStore>(create: (_) => _Corridas([corrida])),
      ChangeNotifierProvider<CleaningStore>(
          create: (_) => _Limpezas([limpeza], falha: limpezaFalha)),
      ChangeNotifierProvider<ServicesStore>(
          create: (_) => _Marcacoes([marcacao])),
    ],
    child: const ClientReservationsScreen(),
  );
}

Widget _ecraVazio() => MultiProvider(
      providers: [
        ChangeNotifierProvider<ReservationStore>(create: (_) => _Mesas([])),
        ChangeNotifierProvider<TvdeStore>(create: (_) => _Corridas([])),
        ChangeNotifierProvider<CleaningStore>(create: (_) => _Limpezas([])),
        ChangeNotifierProvider<ServicesStore>(create: (_) => _Marcacoes([])),
      ],
      child: const ClientReservationsScreen(),
    );

void main() {
  testWidgets(
      'mostra mesa, corrida, limpeza e marcação; a limpeza falhada não apaga '
      'as outras', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        MaterialApp(home: _ecraComUmaDeCada(limpezaFalha: true)));
    await tester.pumpAndSettle();

    // Os quatro tipos, cada um com o seu nome.
    expect(find.text('Corrida marcada'), findsOneWidget);
    expect(find.text('Limpeza'), findsOneWidget);
    expect(find.text('Marcação'), findsOneWidget);
    expect(find.text('Mesa'), findsOneWidget);
    expect(find.textContaining('Para Hospital Sousa Martins'), findsOneWidget);
    expect(find.text('Rua do Teste 12'), findsOneWidget);
    expect(find.text('Barbearia do Teste'), findsOneWidget);
    expect(find.text('Tasca do Teste'), findsOneWidget);
    expect(find.text('Motorista confirmado'), findsOneWidget);
    expect(find.text('Pago'), findsNWidgets(4));

    // A limpeza falhou ao carregar: avisa-se, e as outras continuam lá.
    expect(find.textContaining('Não conseguimos carregar: limpezas'),
        findsOneWidget);

    // Ordem: corrida (2 h) → limpeza (amanhã) → marcação (2 dias) → mesa.
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Corrida marcada') < y('Limpeza'), isTrue);
    expect(y('Limpeza') < y('Marcação'), isTrue);
    expect(y('Marcação') < y('Mesa'), isTrue);
  });

  testWidgets('sem nada marcado: texto genérico e atalhos', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: _ecraVazio()));
    await tester.pumpAndSettle();

    expect(find.text('Ainda não tens nada marcado'), findsOneWidget);
    expect(find.text('Restaurantes'), findsOneWidget);
    expect(find.text('Motorista'), findsOneWidget);
    expect(find.text('Limpeza'), findsOneWidget);
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.textContaining('Não conseguimos carregar'), findsNothing);
  });

  testWidgets(
      'abrir o separador não avisa os stores a meio do build '
      '(revisão de contexto limpo, 10/10)', (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ReservationStore>(
            create: (_) => _MesasQueAvisam()),
        ChangeNotifierProvider<TvdeStore>(create: (_) => _Corridas([])),
        ChangeNotifierProvider<CleaningStore>(create: (_) => _Limpezas([])),
        ChangeNotifierProvider<ServicesStore>(create: (_) => _Marcacoes([])),
      ],
      child: const MaterialApp(home: _Pai()),
    ));
    // Ainda fechado: nada carregado, o indicador roda (não assenta).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Ainda não tens nada marcado'), findsOneWidget);
  });

  group('fotografias (falham se alguma coisa estourar)', () {
    setUpAll(() async {
      await carregaFonteInter();
      await carregaFontesSdk();
    });

    for (final tamanho in kTamanhos) {
      testWidgets('reservas num só sítio — ${tamanho.$1}', (tester) async {
        await fotografaTela(tester,
            nome: 'reservas_num_so_sitio',
            tela: _ecraComUmaDeCada(),
            tamanho: tamanho);
      });
      testWidgets('reservas vazio — ${tamanho.$1}', (tester) async {
        await fotografaTela(tester,
            nome: 'reservas_vazio', tela: _ecraVazio(), tamanho: tamanho);
      });
      // Bloco B: o fim de marcar leva ao separador Reservas.
      testWidgets('marcação confirmada — ${tamanho.$1}', (tester) async {
        await fotografaTela(tester,
            nome: 'marcacao_confirmada_ver_reservas',
            tela: BookingSuccessScreen(
              providerName: 'Barbearia do Teste',
              serviceName: 'Corte e barba',
              scheduledAt: DateTime.utc(2026, 10, 14, 15, 30),
              paidCents: 1500,
            ),
            tamanho: tamanho);
        expect(find.text('Ver nas minhas reservas'), findsOneWidget);
      });
      testWidgets('faixa corrida marcada — ${tamanho.$1}', (tester) async {
        await fotografaTela(tester,
            nome: 'faixa_corrida_marcada',
            // Como no ecrã real: no topo de uma coluna.
            tela: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  ReservaMarcadaFaixa(titulo: 'Corrida marcada!'),
                ]),
              ),
            ),
            tamanho: tamanho);
        expect(find.text('Ver nas minhas reservas'), findsOneWidget);
      });
    }
  });
}
