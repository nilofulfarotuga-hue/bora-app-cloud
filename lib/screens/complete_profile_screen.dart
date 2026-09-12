import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../utils/contact_validators.dart';
import '../widgets/bora/bora_primary_button.dart';

/// Ecrã de completar contacto do cliente — nome e telemóvel.
///
/// Sessão `tudo-04-09-noite` (2026-09-04). Motivo real: 60 de 74 clientes sem
/// nome e 69 sem telemóvel. O registo antigo aceitava um espaço, e quem entrou
/// por convite/QR nunca chegou a dar contacto nenhum. Quando um pedido corria
/// mal, não havia a quem ligar.
///
/// O ecrã de perfil que já existe (`profile_screen.dart`) só MOSTRA o
/// telemóvel — não o deixa editar. Por isso este ecrã existe: é o único sítio
/// da app onde um cliente já registado consegue corrigir o seu contacto.
///
/// Dois modos, de propósito:
/// * `bloqueante: false` — aviso à entrada da app, com "Agora não". Pedir uma
///   vez é lembrar; prender a app à entrada é perder o cliente.
/// * `bloqueante: true` — antes de fechar pedido/reserva/limpeza/corrida. Aí
///   não há saída, porque é aí que o contacto faz falta a sério.
///
/// Textos em PT-PT (app de cliente).
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key, this.bloqueante = false});

  /// Quando `true`, não há como sair sem preencher.
  final bool bloqueante;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _aGuardar = false;

  @override
  void initState() {
    super.initState();
    final client = context.read<AuthStore>().currentClient;
    _nameController = TextEditingController(text: client?.name ?? '');
    _phoneController = TextEditingController(text: client?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _aGuardar = true);

    final authStore = context.read<AuthStore>();
    final erro = await authStore.updateClientContact(
      name: _nameController.text.trim(),
      // Grava os 9 dígitos nacionais — mesma forma que o registo usa.
      phone: normalizarTelemovelPt(_phoneController.text) ??
          _phoneController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _aGuardar = false);

    if (erro != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(erro.tr)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Em modo bloqueante o botão "voltar" do telemóvel também não sai.
      canPop: !widget.bloqueante,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: !widget.bloqueante,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.headerGradient),
          ),
          title: Text('Os seus contactos'.tr),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
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
                  Text(
                    widget.bloqueante
                        ? 'Falta o seu contacto para concluir'.tr
                        : 'Falta o seu contacto'.tr,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Precisamos do seu nome e telemóvel para lhe ligarmos se algo correr mal com o seu pedido. Não é usado para mais nada.'
                        .tr,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSubtle),
                  ),
                  const SizedBox(height: Spacing.xl),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nome completo'.tr,
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (v) => validarNomeCliente(v)?.tr,
                  ),
                  const SizedBox(height: Spacing.md),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telemóvel'.tr,
                      hintText: '912345678',
                      prefixIcon: const Icon(Icons.phone_rounded),
                    ),
                    validator: (v) => validarTelemovelPt(v)?.tr,
                  ),
                  const SizedBox(height: Spacing.xl),
                  BoraPrimaryButton(
                    label: 'Guardar'.tr,
                    loading: _aGuardar,
                    color: AppColors.primary,
                    onPressed: _aGuardar ? null : _guardar,
                  ),
                  if (!widget.bloqueante) ...[
                    const SizedBox(height: Spacing.sm),
                    TextButton(
                      onPressed: _aGuardar
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text('Agora não'.tr),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Garante que o cliente tem contacto utilizável antes de continuar.
///
/// Abre o ecrã bloqueante quando faltar nome ou telemóvel e devolve `true` se
/// no fim o contacto está completo. É este o teste único que o checkout, as
/// reservas, a limpeza e as corridas chamam — uma porta só, para não haver
/// quatro regras diferentes a divergir.
Future<bool> garantirContactoDoCliente(BuildContext context) async {
  final client = context.read<AuthStore>().currentClient;
  if (client == null) return false;
  if (contactoDoClienteCompleto(nome: client.name, telemovel: client.phone)) {
    return true;
  }
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const CompleteProfileScreen(bloqueante: true),
    ),
  );
  return ok ?? false;
}
