import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../config/app_colors.dart';
import '../widgets/auto_address_hint.dart';
import '../config/app_spacing.dart';
import '../services/auto_address.dart';
import '../services/client_address_service.dart';
import '../widgets/address_autocomplete_field.dart';
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
  bool _autoLocating = false;
  ll.LatLng? _selectedCoords;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _preencherMoradaSozinho());
  }

  /// Primeira morada preenchida sozinha, logo a seguir ao registo.
  /// REGRA DE 24/08: nunca trava — este ecrã já é saltável, e falhar aqui
  /// deixa apenas o campo vazio e escrevível.
  Future<void> _preencherMoradaSozinho() async {
    if (!mounted || _addressController.text.trim().isNotEmpty) return;
    setState(() => _autoLocating = true);
    // Conta acabada de criar: não há morada guardada nem casa — vai ao GPS.
    final s = await AutoAddress.descobrir(preferirGps: true);
    if (!mounted) return;
    setState(() {
      _autoLocating = false;
      if (s != null && _addressController.text.trim().isEmpty) {
        _addressController.text = s.morada;
        _selectedCoords = s.coords;
      }
    });
  }

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
        lat: _selectedCoords?.latitude,
        lng: _selectedCoords?.longitude,
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
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text('Bem-vindo à Bora'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Spacing.xxl,
            Spacing.lg,
            Spacing.xxl,
            MediaQuery.of(context).viewInsets.bottom + Spacing.xxl,
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
              AddressAutocompleteField(
                controller: _addressController,
                labelText: 'Morada (opcional)',
                prefixIcon: const Icon(Icons.home_outlined),
                onSelected: (address, coords) {
                  _selectedCoords = coords;
                },
                onChanged: (_) {
                  // user re-edited the field — invalidate previously
                  // selected coords (must pick a suggestion again).
                  _selectedCoords = null;
                },
              ),
            AutoAddressHint(visible: _autoLocating),
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
