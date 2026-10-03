import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'driver_signup_screen.dart';
import 'trabalhar_no_bora_screen.dart';
import 'register_client_screen.dart';

import '../l10n/tr.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 2026-05-21 — prefill demo credentials só em debug; release vê campos vazios.
  final _clientEmailController =
      TextEditingController();
  final _clientPasswordController =
      TextEditingController();
  final _driverPhoneController =
      TextEditingController();
  final _driverPasswordController =
      TextEditingController();

  bool _isProcessing = false;

  @override
  void dispose() {
    _clientEmailController.dispose();
    _clientPasswordController.dispose();
    _driverPhoneController.dispose();
    _driverPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.headerGradient),
          ),
          title: Text(
            'BORA APP'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Cliente'.tr),
              Tab(text: 'Estafeta'.tr),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildClientLogin(context),
            _buildDriverLogin(context),
          ],
        ),
      ),
    );
  }

  Widget _buildClientLogin(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entre como cliente'.tr,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Spacing.xxl),
          TextField(
            controller: _clientEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email'.tr,
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          TextField(
            controller: _clientPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Palavra-passe'.tr,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: Spacing.xxl),
          BoraPrimaryButton(
            label: 'Entrar'.tr,
            loading: _isProcessing,
            onPressed: () => _handleClientLogin(context),
          ),
          const SizedBox(height: Spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Ainda não tem conta?'.tr,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final created = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RegisterClientScreen(),
                    ),
                  );
                  if (created == true && mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content:
                            Text('Conta criada com sucesso. Faça login.'.tr),
                      ),
                    );
                  }
                },
                child: Text('Registar'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverLogin(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Painel do estafeta'.tr,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Spacing.xxl),
          TextField(
            controller: _driverPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Telemóvel'.tr,
              prefixIcon: const Icon(Icons.phone_rounded),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          TextField(
            controller: _driverPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Palavra-passe'.tr,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: Spacing.xxl),
          BoraPrimaryButton(
            label: 'Entrar'.tr,
            loading: _isProcessing,
            onPressed: () => _handleDriverLogin(context),
          ),
          const SizedBox(height: Spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Primeira vez como estafeta?'.tr,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverSignupScreen(),
                    ),
                  );
                },
                child: Text('Candidata-te'.tr),
              ),
            ],
          ),
          // A PORTA (2026-08-29): daqui via-se so a candidatura de estafeta.
          // Quem queria limpar casas ou lavar carros nao tinha por onde entrar.
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const TrabalharNoBoraScreen()),
            ),
            icon: const Icon(Icons.badge_outlined, size: 18),
            label: Text('Ver tudo o que se pode fazer no Bora'.tr),
          ),
        ],
      ),
    );
  }

  Future<void> _handleClientLogin(BuildContext context) async {
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    final messenger = ScaffoldMessenger.of(context);
    final email = _clientEmailController.text.trim();
    final password = _clientPasswordController.text;

    final success = await authStore.loginClientAsync(email, password);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (!success) {
      messenger.showSnackBar(
        SnackBar(content: Text('Credenciais inválidas.'.tr)),
      );
      return;
    }

    await sessionStore.setRole(UserRole.client);
    // No Navigator call — RootNavigator reacts automatically.
  }

  Future<void> _handleDriverLogin(BuildContext context) async {
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();
    final driverStore = context.read<DriverStore>();
    final sessionStore = context.read<SessionStore>();
    final messenger = ScaffoldMessenger.of(context);
    final phone = _driverPhoneController.text.trim();
    final password = _driverPasswordController.text;

    final success = await authStore.loginDriverAsync(phone, password);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (!success) {
      messenger.showSnackBar(
        SnackBar(content: Text('Credenciais inválidas.'.tr)),
      );
      return;
    }

    final driver = authStore.currentDriver;
    if (driver != null) {
      driverStore.configurePrimaryDriver(
        name: driver.name,
        phone: driver.phone,
        vehicleType: driver.vehicleType,
        licensePlate: driver.licensePlate,
      );
    }

    await sessionStore.setRole(UserRole.driver);
    // No Navigator call — RootNavigator reacts automatically.
  }
}
