import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/notification_service.dart';
import 'auth/auth_store.dart';
import 'dispatch/dispatch_engine.dart';
import 'screens/admin/admin_dashboard_screen.dart';
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
import 'stores/restaurant_store.dart';
import 'stores/favorite_store.dart';
import 'config/app_theme.dart';
import 'stores/consent_store.dart';
import 'stores/session_store.dart';
import 'widgets/consent_banner.dart';

const String _supabaseUrl = 'https://ojykpzwqrtusfeakzrna.supabase.co';
const String _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  if (!kIsWeb) {
    Stripe.publishableKey =
        'pk_test_51T8MG0GmiUUEIr722bf8w8H8LWZgAlMMuPgEP4XOxzfYr9VsiIhxQixvj7uqkdtbfXatRHrvOcgX3C3dv257rjs600mn6d5mVv';
    Stripe.merchantIdentifier = 'merchant.com.boraapp.app';
    await Stripe.instance.applySettings();
    // NOTE: Requires google-services.json (Android) and GoogleService-Info.plist (iOS).
    // See README_FIREBASE_SETUP.md for setup instructions.
    await Firebase.initializeApp();
    await NotificationService.instance.init();
  }

  final sessionStore = SessionStore();
  await sessionStore.load();

  final consentStore = ConsentStore();
  await consentStore.load();

  Provider.debugCheckInvalidValueType = null;

  runApp(MyApp(
    sessionStore: sessionStore,
    consentStore: consentStore,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.sessionStore,
    required this.consentStore,
  });

  final SessionStore sessionStore;
  final ConsentStore consentStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionStore>.value(value: sessionStore),
        ChangeNotifierProvider<ConsentStore>.value(value: consentStore),
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
        debugShowCheckedModeBanner: false,
        title: 'BORA APP',
        theme: AppTheme.lightTheme,
        routes: {
          '/role': (_) => const RoleScreen(),
          '/login': (_) => const LoginScreen(),
          '/admin': (_) => const AdminDashboardScreen(),
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
