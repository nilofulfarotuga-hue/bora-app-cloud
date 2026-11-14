import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../utils/contact_validators.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// Perfil › "Editar perfil" do cliente (missão editar-perfil-2026-11-11).
///
/// Porquê: uma cliente perguntou no Suporte como mudar o nome e o robô
/// mandou-a para um botão que não existia. Como na Uber e na Glovo, o cliente
/// muda aqui o nome e o telemóvel. O email não se muda: é o acesso à conta.
///
/// Grava por `AuthStore.editClientProfile` (RPC `client_update_my_profile`,
/// que valida no servidor e só mexe na própria conta). O botão "Guardar" fica
/// desligado sem mudanças, mostra a rodinha enquanto grava e não aceita dois
/// toques. Se a rede cair, o que a pessoa escreveu fica nos campos.
///
/// Textos em PT-PT (app de cliente).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final String _nomeInicial;
  late final String _telInicial;
  late final String _email;
  bool _aGuardar = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final client = context.read<AuthStore>().currentClient;
    _nomeInicial = client?.name ?? '';
    _telInicial = client?.phone ?? '';
    _email = client?.email ?? '';
    _nameController = TextEditingController(text: _nomeInicial)
      ..addListener(_mudou);
    _phoneController = TextEditingController(text: _telInicial)
      ..addListener(_mudou);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _mudou() {
    if (!mounted) return;
    setState(() => _erro = null);
  }

  /// O telemóvel compara-se já normalizado: "+351 912 345 678" e
  /// "912345678" são o mesmo número, não uma mudança.
  String _telComparavel(String v) => normalizarTelemovelPt(v) ?? v.trim();

  bool get _haMudancas =>
      limparNome(_nameController.text) != limparNome(_nomeInicial) ||
      _telComparavel(_phoneController.text) != _telComparavel(_telInicial);

  String? _validarTelemovel(String? v) {
    // Conta antiga sem telemóvel: pode guardar só o nome.
    if ((v ?? '').trim().isEmpty && _telInicial.trim().isEmpty) return null;
    return validarTelemovelPt(v);
  }

  Future<void> _guardar() async {
    if (_aGuardar || !_haMudancas) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _aGuardar = true;
      _erro = null;
    });

    final authStore = context.read<AuthStore>();
    final telEscrito = _phoneController.text.trim();
    final erro = await authStore.editClientProfile(
      name: limparNome(_nameController.text),
      phone: telEscrito.isEmpty
          ? null
          : (normalizarTelemovelPt(telEscrito) ?? telEscrito),
    );

    if (!mounted) return;
    if (erro != null) {
      // Os campos ficam como a pessoa os deixou: nada se perde.
      setState(() {
        _aGuardar = false;
        _erro = erro.tr;
      });
      return;
    }
    setState(() => _aGuardar = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podeGuardar = _haMudancas && !_aGuardar;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: BoraScreenAppBar(title: 'Editar perfil'.tr),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.xxl,
              Spacing.xl,
              Spacing.xxl,
              Spacing.xxxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('editar_perfil_nome'),
                  controller: _nameController,
                  enabled: !_aGuardar,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: 'Nome'.tr,
                    prefixIcon: const Icon(Icons.person_outline),
                    counterText: '',
                  ),
                  validator: (v) => validarNomePerfil(v)?.tr,
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  key: const Key('editar_perfil_telemovel'),
                  controller: _phoneController,
                  enabled: !_aGuardar,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _guardar(),
                  decoration: InputDecoration(
                    labelText: 'Telemóvel'.tr,
                    hintText: '912345678',
                    prefixIcon: const Icon(Icons.phone_rounded),
                  ),
                  validator: (v) => _validarTelemovel(v)?.tr,
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  key: const Key('editar_perfil_email'),
                  initialValue: _email,
                  readOnly: true,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Email'.tr,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'O email é o teu acesso e não se altera.'.tr,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSubtle),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: Spacing.lg),
                  Container(
                    key: const Key('editar_perfil_erro'),
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            _erro!,
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.xl),
                BoraPrimaryButton(
                  key: const Key('editar_perfil_guardar'),
                  label: 'Guardar'.tr,
                  loading: _aGuardar,
                  color: AppColors.primary,
                  onPressed: podeGuardar ? _guardar : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
