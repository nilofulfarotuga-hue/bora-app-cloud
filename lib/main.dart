import 'package:connectycube_flutter_call_kit/connectycube_flutter_call_kit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'screens/restaurant_ratings_list_screen.dart';
import 'screens/client_login_screen.dart';
import 'screens/client_main_screen.dart';
import 'screens/driver_home_screen.dart';
import 'screens/driver_login_screen.dart';
import 'screens/login_screen.dart';
import 'screens/partner_entry_screen.dart';
import 'screens/role_screen.dart';
import 'stores/cart_store.dart';
import 'stores/chat_store.dart';
import 'stores/driver_store.dart';
import 'stores/order_store.dart';
import 'stores/partner_product_store.dart';
import 'stores/partner_reservas_store.dart';
import 'stores/reservation_store.dart';
import 'stores/restaurant_store.dart';
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

/// Sessão 2026-05-21 — Lockscreen CallKit handlers (top-level functions
/// para sobreviver ao isolate de background).
///
/// onCallAccepted: estafeta tocou ✅ no ecrã de chamada do lockscreen — o
/// sistema acorda a app e o realtime channel encarrega-se do aceitar real
/// (driver_home_screen escuta `current_driver_offer_id`).
///
/// onCallRejected: dispara `driver_reject_offer` RPC para libertar a oferta
/// imediatamente — sem esperar pelo timeout de 40s no dispatch-engine.
@pragma('vm:entry-point')
Future<void> _onBoraCallAccepted(CallEvent callEvent) async {
  debugPrint('[CallKit] accepted session=${callEvent.sessionId}');
  // No-op: a UI/realtime trata do aceitar quando o app sobe ao foreground.
}

@pragma('vm:entry-point')
Future<void> _onBoraCallRejected(CallEvent callEvent) async {
  final orderId = callEvent.userInfo?['order_id']?.toString();
  debugPrint('[CallKit] rejected session=${callEvent.sessionId} order=$orderId');
  if (orderId == null || orderId.isEmpty) return;
  try {
    // Supabase pode não estar inicializado neste isolate em background.
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: const String.fromEnvironment('SUPABASE_URL'),
        anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      );
    }
    await Supabase.instance.client.rpc(
      'driver_reject_offer',
      params: <String, dynamic>{'p_order_id': orderId},
    );
  } catch (e) {
    debugPrint('[CallKit] reject RPC error: $e');
  }
}

/// Sessão 2026-05-17 — Foreground service: regista os canais Android de alta
/// prioridade para que FCM consiga acordar a app com som + vibração mesmo
/// quando minimizada/fechada. Também inicializa o flutter_foreground_task.
Future<void> _setupForegroundAndUrgentChannel() async {
  if (kIsWeb) return;
  try {
    // 1) Canal de alta prioridade para pedidos novos (Importance.max).
    //    Sem isto registado no Android Oreo+, FCM com priority=high é
    //    silenciado. notify-driver/notify-partner usam channel_id
    //    'bora_orders_urgent'.
    // Sessão 2026-05-18 — sound bora_alert + RawResource para o canal urgente.
    // O FCM data-only message dispara o background handler que usa este canal
    // para mostrar a notificação com fullScreenIntent + som personalizado.
    const urgentChannel = AndroidNotificationChannel(
      'bora_orders_urgent',
      'Bora — Pedidos urgentes',
      description: 'Notificações de novos pedidos (alta prioridade + som).',
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

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

    // Sessão 2026-05-21 — Lockscreen CallKit (connectycube_flutter_call_kit).
    // Tem de correr DEPOIS de Firebase.initializeApp() para o background
    // isolate ter acesso ao Supabase quando driver_reject_offer for chamado.
    try {
      ConnectycubeFlutterCallKit.instance.init(
        onCallAccepted: _onBoraCallAccepted,
        onCallRejected: _onBoraCallRejected,
      );
      // Android 14+ pediu permissão explícita para fullScreenIntent (já
      // declarada no manifest, mas precisa de consent runtime).
      final canFullScreen =
          await ConnectycubeFlutterCallKit.canUseFullScreenIntent();
      if (!canFullScreen) {
        ConnectycubeFlutterCallKit.provideFullScreenIntentAccess();
      }
    } catch (e) {
      debugPrint('[main] CallKit init error: $e');
    }
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
    }
    // Sessão 2026-05-19 — floating bubble: mostra/esconde consoante app
    // está em background/foreground. Sem-op em iOS.
    BoraBubbleService.onAppLifecycleChange(state);
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
        ChangeNotifierProvider<PartnerReservasStore>(
          create: (_) => PartnerReservasStore(),
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
        navigatorObservers: [routeObserver],
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
        home: const ConsentBanner(child: _RootNavigator()),
      ),
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
        if (driver != null) return const DriverHomeScreen();
        return const DriverLoginScreen();

      case UserRole.partner:
        return const PartnerEntryScreen();
    }
  }
}
