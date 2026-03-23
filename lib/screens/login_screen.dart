import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';
import 'register_client_screen.dart';
import 'register_driver_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _clientEmailController = TextEditingController(text: 'cliente@bora.app');
  final _clientPasswordController = TextEditingController(text: '123456');
  final _driverPhoneController = TextEditingController(text: '910000000');
  final _driverPasswordController = TextEditingController(text: '123456');

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
        appBar: AppBar(
          title: const Text('BORA APP'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Cliente'),
              Tab(text: 'Estafeta'),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Entre como cliente', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          TextField(
            controller: _clientEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _clientPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Palavra-passe',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : () => _handleClientLogin(context),
              child: _isProcessing
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Entrar'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Ainda não tem conta?'),
              TextButton(
                onPressed: () async {
                  final created = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterClientScreen()),
                  );
                  if (created == true && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Conta criada com sucesso. Faça login.')),
                    );
                  }
                },
                child: const Text('Registar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverLogin(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Painel do estafeta', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          TextField(
            controller: _driverPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telemóvel',
              prefixIcon: Icon(Icons.phone_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _driverPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Palavra-passe',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : () => _handleDriverLogin(context),
              child: _isProcessing
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Entrar'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Primeira vez como estafeta?'),
              TextButton(
                onPressed: () async {
                  final registered = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterDriverScreen()),
                  );
                  if (registered == true && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Registo concluído. Faça login.')),
                    );
                  }
                },
                child: const Text('Registar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleClientLogin(BuildContext context) async {
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    final email = _clientEmailController.text.trim();
    final password = _clientPasswordController.text;

    final success = await authStore.loginClientAsync(email, password);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credenciais inválidas.')),
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
    final phone = _driverPhoneController.text.trim();
    final password = _driverPasswordController.text;

    final success = await authStore.loginDriverAsync(phone, password);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credenciais inválidas.')),
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