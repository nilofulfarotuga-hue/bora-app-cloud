import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/client_address_service.dart';
import '../widgets/bora/bora_primary_button.dart';

/// Welcome step apresentado APÓS signup cliente bem-sucedido.
/// Alinhado com Glovo: pede morada como parte do onboarding (não no signup).
/// Skippable — _RootNavigator já vê currentClient != null e renderiza
/// ClientMainScreen quando este ecrã faz pop.
class WelcomeAddressScreen extends StatefulWidget {
  const WelcomeAddressScreen({super.key});

  @override
  State<WelcomeAddressScreen> createState() => _WelcomeAddressScreenState();
}

class _WelcomeAddressScreenState extends State<WelcomeAddressScreen> {
  final _addressController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _goHome();
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ClientAddressService.instance.create(
        label: 'Casa',
        address: address,
        isDefault: true,
      );
    } catch (e) {
      debugPrint('[WelcomeAddressScreen] save address failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Não foi possível guardar a morada agora — podes adicionar depois.'),
          ),
        );
      }
    }
    if (mounted) _goHome();
  }

  void _goHome() {
    // popUntil first removes WelcomeAddressScreen + RegisterClientScreen
    // from the stack. _RootNavigator then renders ClientMainScreen because
    // session.role == client && auth.currentClient != null.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text('Bem-vindo à Bora'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.xxl,
            Spacing.lg,
            Spacing.xxl,
            Spacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.celebration_rounded,
                size: 72,
                color: AppColors.accent,
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                'Conta criada!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Adiciona a tua morada para vermos restaurantes e lojas perto de ti.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: Spacing.xxl),
              TextField(
                controller: _addressController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Morada (opcional)',
                  hintText: 'Rua, número, código postal',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                maxLines: 2,
                minLines: 1,
              ),
              const SizedBox(height: Spacing.xl),
              BoraPrimaryButton(
                label: 'Continuar',
                loading: _isSaving,
                color: AppColors.primary,
                onPressed: _saveAndContinue,
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: _isSaving ? null : _goHome,
                child: Text(
                  'Saltar por agora',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
