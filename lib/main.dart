import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// BUG #12 (2026-05-13) — delegates Material/Widgets/Cupertino + Locale PT-PT
// para o showDatePicker e outros widgets localizados funcionarem fora EN.
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/floating_bubble_service.dart';
import 'services/foreground_service.dart';
import 'services/notification_service.dart';
import 'services/offer_presentation_gate.dart';
// Sessão 2026-05-21 — overlay system_alert_window. O import garante que o
// `@pragma('vm:entry-point') void overlayMain()` ali declarado fica vivo no
// build e o flutter_overlay_window consegue arrancar o isolate da overlay
// quando NotificationService dispara showOverlay() em background.
// ignore: unused_import
import 'widgets/driver_order_overlay.dart';
import 'auth/auth_store.dart';
import 'dispatch/dispatch_engine.dart';
import 'screens/admin/admin_crosstalk_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_ratings_screen.dart';
import 'screens/admin/admin_skill_suggestions_metrics_screen.dart';
import 'screens/admin/admin_weekly_settlements_screen.dart';
import 'screens/restaurant_ratings_list_screen.dart';
import 'screens/client_login_screen.dart';
import 'screens/client_main_screen.dart';
import 'screens/driver_home_screen.dart';
import 'screens/driver/tvde/tvde_driver_home_screen.dart';
import 'screens/driver_login_screen.dart';
import 'screens/driver_signup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/partner_entry_screen.dart';
import 'screens/role_screen.dart';
import 'stores/cart_store.dart';
import 'stores/chat_store.dart';
import 'stores/driver_store.dart';
import 'stores/order_store.dart';
import 'stores/partner_product_store.dart';
import 'stores/partner_appointments_store.dart';
import 'stores/partner_reservas_store.dart';
import 'stores/reservation_store.dart';
import 'stores/restaurant_store.dart';
import 'stores/services_store.dart';
import 'stores/cleaner_store.dart';
import 'stores/cleaning_chat_store.dart';
import 'stores/cleaning_store.dart';
import 'stores/tvde_store.dart';
import 'stores/tvde_driver_store.dart';
import 'stores/tvde_chat_store.dart';
import 'models/driver_model.dart' show VehicleType;
import 'stores/favorite_store.dart';
import 'config/app_theme.dart';
import 'providers/support_settings_provider.dart';
import 'stores/consent_store.dart';
import 'stores/session_store.dart';
import 'widgets/consent_banner.dart';

// Injected at build time via --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
// or --dart-define-from-file=.dart_defines
// Never hardcode these values here.
const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// 5G — RouteObserver global para detectar regresso ao dashboard admin
// (refresh do badge contador propostas pendentes).
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

// [F] 2026-06-30 — observer leve que regista o nome da rota actual para o
// logger de crash (debug_crash_logs.route). Complementa o `screen` vindo do
// FlutterError context. Rotas push sem `settings.name` ficam null (melhor do
// que o null fixo de antes).
String? _currentRouteName;
final NavigatorObserver crashRouteObserver = _CrashRouteObserver();

class _CrashRouteObserver extends NavigatorObserver {
  void _set(Route<dynamic>? route) {
    final n = route?.settings.name;
    if (n != null && n.isNotEmpty) _currentRouteName = n;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);
}

// [F] Diagnóstico de aparelho (app_version, modelo, versão Android) via a
// bridge nativa já existente (pt.boraapp.bora/native) — sem dependências novas
// (package_info_plus/device_info_plus arriscariam o build de release no CI).
// Preenchido uma vez no arranque; usado pelo logger de crash.
const MethodChannel _diagBridge = MethodChannel('pt.boraapp.bora/native');
Map<String, String> _deviceDiag = const <String, String>{};
Future<void> _loadDeviceDiagnostics() async {
  if (kIsWeb) return;
  try {
    final res = await _diagBridge
        .invokeMethod<Map<dynamic, dynamic>>('getDeviceDiagnostics');
    if (res != null) {
      _deviceDiag =
          res.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
  } catch (e) {
    debugPrint('[main] getDeviceDiagnostics indisponível: $e');
  }
}

/// Sessão 2026-05-17 — Foreground service: regista os canais Android de alta
/// prioridade para que FCM consiga acordar a app com som + vibração mesmo
/// quando minimizada/fechada. Também inicializa o flutter_foreground_task.
Future<void> _setupForegroundAndUrgentChannel() async {
  if (kIsWeb) return;
  try {
    // 1) Canal de alta prioridade para pedidos novos (Importance.max).
    //    Sessão 2026-05-25 (exec6.16) — alinhado com canal v3 que MainActivity
    //    cria nativamente (com setSound bora_alert + bypass DND). Edge Fn
    //    notify-driver usa 'bora_orders_urgent_v3'. Re-registar do Dart é
    //    idempotente — não sobrescreve setSound nativo.
    const urgentChannel = AndroidNotificationChannel(
      'bora_orders_urgent_v3',
      'Bora — Novos pedidos',
      description: 'Som contínuo + vibração para novos pedidos urgentes.',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('bora_alert'),
      enableVibration: true,
      showBadge: true,
    );
    final localPlugin = FlutterLocalNotificationsPlugin();
    await localPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(urgentChannel);

    // 2) Init flutter_foreground_task — regista também o canal LOW
    //    'bora_service' para a notificação persistente.
    await BoraForegroundService.init();
  } catch (e) {
    debugPrint('[main] _setupForegroundAndUrgentChannel error: $e');
  }
}

// TODO: remover após diagnóstico — grava crash na tabela debug_crash_logs.
void _logCrashToSupabase(Object error, StackTrace stack, {String? screen}) {
  try {
    final supabase = Supabase.instance.client;
    String? uid;
    try {
      uid = supabase.auth.currentUser?.id;
    } catch (_) {/* sessão indisponível */}
    supabase.rpc('log_client_crash', params: {
      'p_screen': screen,
      'p_route': _currentRouteName,
      'p_error_message': error.toString(),
      'p_stack_trace': stack.toString(),
      'p_platform': Platform.isAndroid ? 'android' : 'ios',
      // [F] contexto real (antes: tudo null em debug_crash_logs).
      'p_app_version': _deviceDiag['app_version'],
      'p_device_model': _deviceDiag['device_model'],
      'p_android_version': _deviceDiag['android_version'],
      'p_gms_status': NotificationService.fcmHealth,
      'p_user_id': uid,
    }).then((_) {}, onError: (_) {});
  } catch (_) {}
}

/// [C/adenda 2026-06-30] Breadcrumb leve (NÃO-crash) para diagnosticar telas
/// brancas no device: regista entrada/build de um ecrã + estado relevante em
/// debug_crash_logs, reutilizando o RPC enriquecido do [F] (device/versão/rota/
/// gms/user). Permite ver o que está null/loading quando o body fica branco.
void logScreenBreadcrumb(String screen, String info) =>
    _logCrashToSupabase('BREADCRUMB: $info', StackTrace.empty, screen: screen);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // TODO: remover após diagnóstico — handlers globais de crash.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    originalOnError?.call(details);
    _logCrashToSupabase(
      details.exception,
      details.stack ?? StackTrace.empty,
      screen: details.context?.toDescription(),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _logCrashToSupabase(error, stack);
    return false;
  };

  // TODO: remover após diagnóstico — mostra aviso em vez de tela branca.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // [C/adenda 2026-06-30] Em DEBUG mostra o erro REAL no ecrã (em vez de
    // branco) para apanhar excepções de build silenciosas que pintam o body em
    // branco. Em release mantém a mensagem amigável.
    if (kDebugMode) {
      return Material(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'ERRO DE BUILD NESTA TELA\n\n'
            '${details.exceptionAsString()}\n\n'
            '${details.stack ?? ''}',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      );
    }
    return Material(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Text(
            'Ocorreu um erro nesta tela',
            style: TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  // [F] Carrega o diagnóstico de aparelho para o logger de crash. Não bloqueia
  // o arranque (fire-and-forget); se a bridge falhar, os campos ficam null.
  _loadDeviceDiagnostics();

  if (!kIsWeb) {
    // BUG 13 — Stripe mode toggle. Default = live (safety).
    // For QA com cartões 4242…: pass --dart-define=BORA_STRIPE_MODE=test
    //   AND --dart-define=STRIPE_TEST_PUBLISHABLE_KEY=pk_test_...
    // Edge Fn create-payment-intent + create-mbway-payment-intent leem o
    // BORA_STRIPE_MODE da Edge Fn env (configurada no Supabase Secrets) e
    // escolhem STRIPE_TEST_SECRET_KEY ou STRIPE_SECRET_KEY em conformidade.
    const stripeMode =
        String.fromEnvironment('BORA_STRIPE_MODE', defaultValue: 'live');
    const stripeLivePublishableKey =
        String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
    const stripeTestPublishableKey =
        String.fromEnvironment('STRIPE_TEST_PUBLISHABLE_KEY');
    const stripePublishableKey = stripeMode == 'test'
        ? stripeTestPublishableKey
        : stripeLivePublishableKey;
    if (stripePublishableKey.isEmpty) {
      throw StateError(
        'Stripe publishable key missing (mode=$stripeMode). '
        'Run with: flutter run --dart-define-from-file=.dart_defines '
        '${stripeMode == "test" ? "--dart-define=BORA_STRIPE_MODE=test --dart-define=STRIPE_TEST_PUBLISHABLE_KEY=..." : ""}',
      );
    }
    Stripe.publishableKey = stripePublishableKey;
    Stripe.merchantIdentifier = 'merchant.com.boraapp.app';
    // 2026-05-14 perf: Stripe.applySettings + Firebase chain correm em paralelo
    // (eram em serie). NotificationService depende do Firebase, por isso fica
    // encadeado dentro da mesma future.
    // NOTE: Requires google-services.json (Android) and GoogleService-Info.plist (iOS).
    await Future.wait([
      Stripe.instance.applySettings(),
      Firebase.initializeApp().then((_) => NotificationService.instance.init()),
      // Sessão 2026-05-17 — foreground service config + canal urgente Android.
      _setupForegroundAndUrgentChannel(),
    ]);

    // Exec6.16 (2026-05-25) — CAMADA 3 support: main isolate alive heartbeat
    // (escreve bora_main_alive_ts a cada 3s). FGS task isolate lê para saber
    // se main está vivo. Stale > 5s → FGS dispara postWakeActivityNotification.
    OfferPresentationGate.bootstrapMainAlive();
  }

  // 2026-05-14 perf: SessionStore.load + ConsentStore.load em paralelo.
  final sessionStore = SessionStore();
  final consentStore = ConsentStore();
  await Future.wait([sessionStore.load(), consentStore.load()]);

  Provider.debugCheckInvalidValueType = null;

  runApp(MyApp(
    sessionStore: sessionStore,
    consentStore: consentStore,
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.sessionStore,
    required this.consentStore,
  });

  final SessionStore sessionStore;
  final ConsentStore consentStore;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final SupportSettingsProvider _supportSettings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supportSettings = SupportSettingsProvider()..load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _supportSettings.load();
      // Exec6.16 CAMADA 4 — força re-subscribe do WebSocket Supabase
      // (Samsung pode tê-lo morto em BG).
      DriverStore.instance?.forceResubscribeIfStale();
    }
    BoraBubbleService.onAppLifecycleChange(state);
    // Exec6 GATE — alimenta o gate com lifecycle (FG heartbeat).
    OfferPresentationGate.updateLifecycle(state);
  }

  SessionStore get sessionStore => widget.sessionStore;
  ConsentStore get consentStore => widget.consentStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionStore>.value(value: sessionStore),
        ChangeNotifierProvider<ConsentStore>.value(value: consentStore),
        ChangeNotifierProvider<SupportSettingsProvider>.value(
          value: _supportSettings,
        ),
        ChangeNotifierProvider<AuthStore>(
          create: (_) => AuthStore(),
        ),
        ChangeNotifierProvider<CartStore>(
          create: (_) => CartStore(),
        ),
        ChangeNotifierProvider<FavoriteStore>(
          create: (_) => FavoriteStore(),
        ),
        ChangeNotifierProvider<ChatStore>(
          create: (_) => ChatStore(),
        ),
        ChangeNotifierProvider<DriverStore>(
          create: (_) => DriverStore(),
        ),
        ChangeNotifierProvider<RestaurantStore>(
          create: (_) => RestaurantStore(),
        ),
        ChangeNotifierProvider<ReservationStore>(
          create: (_) => ReservationStore(),
        ),
        ChangeNotifierProvider<ServicesStore>(
          create: (_) => ServicesStore(),
        ),
        ChangeNotifierProvider<TvdeStore>(
          create: (_) => TvdeStore(),
        ),
        ChangeNotifierProvider<TvdeDriverStore>(
          create: (_) => TvdeDriverStore(),
        ),
        ChangeNotifierProvider<TvdeChatStore>(
          create: (_) => TvdeChatStore(),
        ),
        ChangeNotifierProvider<CleaningStore>(
          create: (_) => CleaningStore(),
        ),
        ChangeNotifierProvider<CleanerStore>(
          create: (_) => CleanerStore(),
        ),
        ChangeNotifierProvider<CleaningChatStore>(
          create: (_) => CleaningChatStore(),
        ),
        ChangeNotifierProvider<PartnerReservasStore>(
          create: (_) => PartnerReservasStore(),
        ),
        ChangeNotifierProvider<PartnerAppointmentsStore>(
          create: (_) => PartnerAppointmentsStore(),
        ),
        ChangeNotifierProxyProvider<RestaurantStore, PartnerProductStore>(
          create: (_) => PartnerProductStore(),
          update: (_, RestaurantStore restaurantStore,
              PartnerProductStore? partnerProductStore) {
            partnerProductStore ??= PartnerProductStore();
            partnerProductStore.updateRestaurantStore(restaurantStore);
            return partnerProductStore;
          },
        ),
        ChangeNotifierProxyProvider3<AuthStore, DriverStore, RestaurantStore,
            OrderStore>(
          create: (context) => OrderStore(
            driverStore: context.read<DriverStore>(),
          ),
          update: (_, AuthStore authStore, DriverStore driverStore,
              RestaurantStore restaurantStore, OrderStore? orderStore) {
            orderStore!.updateAuthStore(authStore);
            orderStore.updateDriverStore(driverStore);
            orderStore.updateRestaurantStore(restaurantStore);
            return orderStore;
          },
        ),
        ProxyProvider2<DriverStore, OrderStore, DispatchEngine>(
          create: (_) => DispatchEngine(),
          update: (_, DriverStore driverStore, OrderStore orderStore,
              DispatchEngine? engine) {
            engine ??= DispatchEngine();
            engine.attach(
              orderStore: orderStore,
              driverStore: driverStore,
            );
            orderStore.updateDispatchEngine(engine);
            return engine;
          },
          dispose: (_, DispatchEngine engine) => engine.dispose(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'BORA APP',
        theme: AppTheme.lightTheme,
        // BUG #12 (2026-05-13) — localizations PT-PT/BR/EN. Sem delegates,
        // showDatePicker crashava silencioso em Android (calendario em
        // branco). Default locale PT-PT.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('pt', 'PT'),
          Locale('pt', 'BR'),
          Locale('en'),
        ],
        locale: const Locale('pt', 'PT'),
        navigatorObservers: [routeObserver, crashRouteObserver],
        routes: {
          '/role': (_) => const RoleScreen(),
          '/login': (_) => const LoginScreen(),
          '/admin': (_) => const AdminDashboardScreen(),
          // 5F-β — deep link de notificação push crosstalk_critical
          '/admin/crosstalk': (_) => const AdminCrosstalkScreen(),
          // 5G — métricas detalhadas das propostas IA
          '/admin/suggestions/metrics': (_) =>
              const AdminSkillSuggestionsMetricsScreen(),
          // Sessão 6 §44 — Avaliações
          '/admin/ratings': (_) => const AdminRatingsScreen(),
          // Fechos Semanais (2026-06-12) — deep link do push de 2ª-feira
          // (run_weekly_closeout → notify-admin-urgent route '/admin/settlements').
          '/admin/settlements': (_) => const AdminWeeklySettlementsScreen(),
        },
        onGenerateRoute: (settings) {
          // §44 — deep link da push low_rating: /partner/ratings precisa
          // restaurant_id + restaurant_name nos arguments.
          if (settings.name == '/partner/ratings' ||
              settings.name == '/restaurant/ratings') {
            final args = settings.arguments;
            if (args is Map) {
              final id = args['restaurant_id']?.toString();
              final name = args['restaurant_name']?.toString() ?? 'Restaurante';
              if (id != null) {
                return MaterialPageRoute<void>(
                  builder: (_) => RestaurantRatingsListScreen(
                    restaurantId: id,
                    restaurantName: name,
                  ),
                );
              }
            }
          }
          if (settings.name == '/driver/ratings') {
            final args = settings.arguments;
            if (args is Map) {
              final id = args['driver_id']?.toString();
              final name = args['driver_name']?.toString() ?? 'Estafeta';
              if (id != null) {
                return MaterialPageRoute<void>(
                  builder: (_) => DriverRatingsListScreen(
                    driverId: id,
                    driverName: name,
                  ),
                );
              }
            }
          }
          return null;
        },
        home: const ConsentBanner(child: _BackToBackgroundWrapper(child: _RootNavigator())),
      ),
    );
  }
}

/// CAMADA 2 (Stuart pattern, exec6.16 2026-05-25) — back button intercept.
/// Em vez de destruir MainActivity (default), chama moveTaskToBack(true) via
/// MethodChannel nativo. Resultado: app vai a background (igual ao HOME)
/// MAS Activity sobrevive → main isolate + WebSocket Supabase continuam vivos.
/// Sem isto, BACK no driver_home → MaterialApp pop → Activity finish → main
/// isolate morre → realtime morre → ofertas perdidas.
class _BackToBackgroundWrapper extends StatelessWidget {
  const _BackToBackgroundWrapper({required this.child});
  final Widget child;

  static const _native = MethodChannel('pt.boraapp.bora/native');

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        try {
          await _native.invokeMethod<bool>('moveTaskToBack');
        } catch (e) {
          debugPrint('[BackToBackground] moveTaskToBack error: $e');
        }
      },
      child: child,
    );
  }
}

class _RootNavigator extends StatelessWidget {
  const _RootNavigator();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final auth = context.watch<AuthStore>();

    final role = session.role;
    final client = auth.currentClient;
    final driver = auth.currentDriver;

    if (!session.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (role == null) {
      return const RoleScreen();
    }

    switch (role) {
      case UserRole.client:
        if (client != null) return const ClientMainScreen();
        return const ClientLoginScreen();

      case UserRole.driver:
        if (driver != null) {
          if (session.hasDriverSignupDraft) return const DriverSignupScreen();
          // TVDE — motorista de passageiros entra no modo passageiros (Plano §4).
          // O próprio ecrã gateia pending/rejected, igual ao DriverHomeScreen.
          if (driver.vehicleType == VehicleType.carPassengers) {
            return const TvdeDriverHomeScreen();
          }
          return const DriverHomeScreen();
        }
        return const DriverLoginScreen();

      case UserRole.partner:
        return const PartnerEntryScreen();
    }
  }
}
