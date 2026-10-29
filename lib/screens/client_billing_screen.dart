import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../services/fatura_nif_service.dart';
import '../utils/nif_pt.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// Perfil › "Dados de faturação" (28/10/2026): ver, mudar e apagar o NIF e o
/// nome que vêm preenchidos quando o cliente pede fatura com NIF.
///
/// O NIF é SEMPRE opcional. Apagar é apagar mesmo (`client_billing_save` com
/// NIF vazio). Os pedidos já feitos não mudam.
class ClientBillingScreen extends StatefulWidget {
  const ClientBillingScreen({super.key, this.servico});

  /// Para testes; por defeito é a instância da app.
  final FaturaNifService? servico;

  @override
  State<ClientBillingScreen> createState() => _ClientBillingScreenState();
}

class _ClientBillingScreenState extends State<ClientBillingScreen> {
  final TextEditingController _nif = TextEditingController();
  final TextEditingController _nome = TextEditingController();

  bool _aCarregar = true;
  bool _aGravar = false;
  bool _falhouLer = false;
  DadosFatura? _guardado;
  String? _erroNif;

  FaturaNifService get _servico => widget.servico ?? FaturaNifService.instance;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nif.dispose();
    _nome.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _falhouLer = false;
    });
    try {
      final d = await _servico.lerPerfil();
      if (!mounted) return;
      setState(() {
        _guardado = d;
        _nif.text = d == null ? '' : soDigitosNif(d.nif);
        _nome.text = d?.nome ?? '';
        _aCarregar = false;
      });
    } catch (e) {
      debugPrint('[ClientBilling] perfil não lido: $e');
      if (!mounted) return;
      setState(() {
        _aCarregar = false;
        _falhouLer = true;
      });
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _guardar() async {
    if (_aGravar) return;
    final nif = soDigitosNif(_nif.text);
    if (!nifPtValido(nif)) {
      setState(() => _erroNif = 'NIF inválido. Confere os 9 dígitos.'.tr);
      return;
    }
    setState(() {
      _erroNif = null;
      _aGravar = true;
    });
    final nome = _nome.text.trim();
    try {
      await _servico.guardarPerfil(nif, nome.isEmpty ? null : nome);
      if (!mounted) return;
      setState(() {
        _guardado = DadosFatura(nif: nif, nome: nome.isEmpty ? null : nome);
        _aGravar = false;
      });
      _aviso('Dados de faturação guardados.'.tr);
    } catch (e) {
      debugPrint('[ClientBilling] guardar falhou: $e');
      if (!mounted) return;
      setState(() => _aGravar = false);
      _aviso(e.toString().contains('NIF_INVALIDO')
          ? 'NIF inválido. Confere os 9 dígitos.'.tr
          : 'Não foi possível guardar. Tenta de novo.'.tr);
    }
  }

  Future<void> _apagar() async {
    if (_aGravar) return;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar os dados de faturação?'.tr),
        content: Text(
            'O NIF e o nome deixam de estar guardados. Os pedidos já feitos não mudam.'
                .tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'.tr),
          ),
          TextButton(
            key: const Key('billing_confirmar_apagar'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Apagar'.tr),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    setState(() => _aGravar = true);
    try {
      await _servico.apagarPerfil();
      if (!mounted) return;
      setState(() {
        _guardado = null;
        _nif.clear();
        _nome.clear();
        _erroNif = null;
        _aGravar = false;
      });
      _aviso('Dados de faturação apagados.'.tr);
    } catch (e) {
      debugPrint('[ClientBilling] apagar falhou: $e');
      if (!mounted) return;
      setState(() => _aGravar = false);
      _aviso('Não foi possível apagar. Tenta de novo.'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Dados de faturação'.tr),
      body: _aCarregar
          ? const Center(child: CircularProgressIndicator())
          : _falhouLer
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Não foi possível ler os teus dados. Tenta de novo.'
                              .tr,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: Spacing.md),
                        OutlinedButton(
                          key: const Key('billing_tentar_de_novo'),
                          onPressed: _carregar,
                          child: Text('Tentar de novo'.tr),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  children: [
                    Text(
                      'O NIF é opcional. Guardado aqui, vem já preenchido quando pedires fatura com NIF.'
                          .tr,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: Spacing.lg),
                    if (_guardado != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        child: Text(
                          'NIF guardado: {0}'
                              .trArgs([formatarNif(_guardado!.nif)]),
                          key: const Key('billing_guardado'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        child: Text(
                          'Ainda não tens NIF guardado.'.tr,
                          key: const Key('billing_sem_nif'),
                        ),
                      ),
                    TextField(
                      key: const Key('billing_nif'),
                      controller: _nif,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      decoration: InputDecoration(
                        labelText: 'NIF'.tr,
                        errorText: _erroNif,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    TextField(
                      key: const Key('billing_nome'),
                      controller: _nome,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: 'Nome na fatura (opcional)'.tr,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    FilledButton(
                      key: const Key('billing_guardar'),
                      onPressed: _aGravar ? null : _guardar,
                      child: Text('Guardar'.tr),
                    ),
                    if (_guardado != null) ...[
                      const SizedBox(height: Spacing.sm),
                      TextButton(
                        key: const Key('billing_apagar'),
                        onPressed: _aGravar ? null : _apagar,
                        child: Text('Apagar'.tr),
                      ),
                    ],
                  ],
                ),
    );
  }
}
