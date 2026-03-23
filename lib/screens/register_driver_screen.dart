import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../auth/auth_store.dart';
import '../models/driver_model.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';
import 'driver_login_screen.dart';

class RegisterDriverScreen extends StatefulWidget {
  const RegisterDriverScreen({super.key});

  @override
  State<RegisterDriverScreen> createState() => _RegisterDriverScreenState();
}

class _RegisterDriverScreenState extends State<RegisterDriverScreen> {
  final _formKey = GlobalKey<FormState>();

  // Personal
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _nifController = TextEditingController();

  // Vehicle
  VehicleType _vehicleType = VehicleType.motorcycle;
  final _licensePlateController = TextEditingController();

  // Account
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Photo placeholders (URL or empty — actual upload requires storage integration)
  final _profilePhotoController = TextEditingController();
  final _idDocumentController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nifController.dispose();
    _licensePlateController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _profilePhotoController.dispose();
    _idDocumentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Registar como estafeta')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crie o seu perfil profissional para começar a receber pedidos.',
                style: theme.textTheme.titleMedium,
              ),

              // ── Dados pessoais ──────────────────────────────────────────
              const SizedBox(height: 28),
              const _SectionHeader(title: 'Dados pessoais'),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome completo *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o seu nome.' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o email.';
                  if (!v.contains('@')) return 'Email inválido.';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telemóvel *',
                  prefixIcon: Icon(Icons.phone_android),
                  helperText: 'Usado como identificador de login',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o telemóvel.';
                  if (v.trim().length < 9) return 'Número inválido.';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Morada *',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a sua morada.' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nifController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'NIF *',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: 'Número de Identificação Fiscal (9 dígitos)',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o NIF.';
                  if (v.trim().length != 9) return 'NIF deve ter 9 dígitos.';
                  return null;
                },
              ),

              // ── Veículo ────────────────────────────────────────────────
              const SizedBox(height: 28),
              const _SectionHeader(title: 'Informação do veículo'),
              const SizedBox(height: 16),

              DropdownButtonFormField<VehicleType>(
                initialValue: _vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de veículo *',
                  prefixIcon: Icon(Icons.two_wheeler_outlined),
                ),
                items: VehicleType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _vehicleType = v);
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _licensePlateController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Matrícula *',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a matrícula.' : null,
              ),

              // ── Documentos (placeholder) ───────────────────────────────
              const SizedBox(height: 28),
              const _SectionHeader(title: 'Documentos'),
              const SizedBox(height: 8),
              Text(
                'Em breve poderá carregar fotos directamente. Por agora, deixe em branco ou insira um URL.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _profilePhotoController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Foto de perfil (URL opcional)',
                  prefixIcon: Icon(Icons.photo_camera_outlined),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _idDocumentController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Documento de identidade (URL opcional)',
                  prefixIcon: Icon(Icons.credit_card_outlined),
                ),
              ),

              // ── Acesso ─────────────────────────────────────────────────
              const SizedBox(height: 28),
              const _SectionHeader(title: 'Acesso à conta'),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe *',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres.' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmar palavra-passe *',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
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

              // ── Botões ─────────────────────────────────────────────────
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Concluir registo'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Já tem uma conta?'),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const DriverLoginScreen()),
                    ),
                    child: const Text('Iniciar sessão'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

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
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final driver = authStore.currentDriver;
    if (driver != null) {
      final authUserId = Supabase.instance.client.auth.currentUser?.id;
      driverStore.configurePrimaryDriver(
        name: driver.name,
        phone: driver.phone,
        vehicleType: driver.vehicleType,
        licensePlate: driver.licensePlate,
        driverId: authUserId,
      );
    }

    await sessionStore.setRole(UserRole.driver);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registo concluído com sucesso!')),
    );

    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Divider(height: 12),
      ],
    );
  }
}