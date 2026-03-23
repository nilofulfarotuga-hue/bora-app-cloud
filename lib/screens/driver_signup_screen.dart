import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../models/driver_model.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';

class DriverSignupScreen extends StatefulWidget {
  const DriverSignupScreen({super.key});

  @override
  State<DriverSignupScreen> createState() => _DriverSignupScreenState();
}

class _DriverSignupScreenState extends State<DriverSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  VehicleType _vehicleType = VehicleType.motorcycle;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isProcessing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _licensePlateController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta de estafeta')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preencha os dados para criar a sua conta.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),

              // Nome
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o nome.' : null,
              ),
              const SizedBox(height: 16),

              // Email
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o email.';
                  if (!v.contains('@')) return 'Email inválido.';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Telefone
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telemóvel',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe o telemóvel.'
                    : null,
              ),
              const SizedBox(height: 16),

              // Tipo de veículo
              DropdownButtonFormField<VehicleType>(
                value: _vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de veículo',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: VehicleType.motorcycle,
                    child: Text('Mota'),
                  ),
                  DropdownMenuItem(
                    value: VehicleType.car,
                    child: Text('Carro'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _vehicleType = v);
                },
              ),
              const SizedBox(height: 16),

              // Matrícula
              TextFormField(
                controller: _licensePlateController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Matrícula',
                  prefixIcon: Icon(Icons.credit_card_outlined),
                  hintText: 'AA-00-BB',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe a matrícula.'
                    : null,
              ),
              const SizedBox(height: 16),

              // Senha
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Informe a palavra-passe.';
                  }
                  if (v.length < 6) {
                    return 'A palavra-passe deve ter pelo menos 6 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Confirmar senha
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmar palavra-passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'As palavras-passe não coincidem.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _submit,
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Criar conta'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _isProcessing
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Já tenho conta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();
    final driverStore = context.read<DriverStore>();
    final sessionStore = context.read<SessionStore>();

    final error = await authStore.registerDriverAsync(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      vehicleType: _vehicleType,
      licensePlate: _licensePlateController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final account = authStore.currentDriver;
    if (account != null) {
      final authUserId = Supabase.instance.client.auth.currentUser?.id;
      driverStore.configurePrimaryDriver(
        name: account.name,
        phone: account.phone,
        vehicleType: account.vehicleType,
        licensePlate: account.licensePlate,
        driverId: authUserId,
      );
    }

    await sessionStore.setRole(UserRole.driver);

    if (!mounted) return;
    setState(() => _isProcessing = false);
    // RootNavigator reacts automatically to SessionStore change.
  }
}
