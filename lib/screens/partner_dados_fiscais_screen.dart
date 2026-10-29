import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/dados_fiscais_parceiro.dart';
import '../services/dados_fiscais_parceiro_service.dart';
import '../services/legal_fields_service.dart';
import '../utils/conformidade_mensagem.dart';
import '../widgets/legal_fields_section.dart';

/// Lê os dados fiscais da loja (por defeito `parceiro_dados_fiscais`).
typedef CarregarDadosFiscais = Future<DadosFiscaisParceiro> Function();

/// Grava os dados do formulário (por defeito `provider_update_legal_fields`
/// com o papel 'partner', a mesma gravação do registo).
typedef GravarDadosFiscais = Future<void> Function(
    LegalFieldsController controller);

/// Painel do parceiro (PT-PT) → "Dados fiscais" (DAC7, Lei n.º 36/2023).
///
/// Missão boom-burger-2026-10-27, F3. No topo diz o que falta para a loja
/// poder abrir ao público (a lista do portão do servidor); por baixo, o mesmo
/// formulário do registo ([LegalFieldsSection]), já preenchido com o que o
/// servidor tem.
class PartnerDadosFiscaisScreen extends StatefulWidget {
  const PartnerDadosFiscaisScreen({
    super.key,
    required this.restaurantId,
    this.carregar,
    this.gravar,
  });

  final String restaurantId;

  /// Só para testes: substitui a leitura da base.
  @visibleForTesting
  final CarregarDadosFiscais? carregar;

  /// Só para testes: substitui a gravação.
  @visibleForTesting
  final GravarDadosFiscais? gravar;

  @override
  State<PartnerDadosFiscaisScreen> createState() =>
      _PartnerDadosFiscaisScreenState();
}

class _PartnerDadosFiscaisScreenState extends State<PartnerDadosFiscaisScreen> {
  final LegalFieldsController _legal = LegalFieldsController();
  DadosFiscaisParceiro? _dados;
  bool _carregando = true;
  bool _aGravar = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _legal.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    // Ao reler depois de gravar o formulário fica à vista (sem roda).
    setState(() {
      _carregando = _dados == null;
      _erro = null;
    });
    try {
      final d = await (widget.carregar?.call() ??
          DadosFiscaisParceiroService.ler(widget.restaurantId));
      if (!mounted) return;
      _legal.legalName.text = d.legalName ?? '';
      _legal.nif.text = d.nif ?? '';
      _legal.address.text = d.address ?? '';
      _legal.iban.text = d.iban ?? '';
      _legal.birthDate.value = d.birthDate;
      setState(() {
        _dados = d;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('[PartnerDadosFiscais] leitura falhou: $e');
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível ler os dados fiscais. Verifica a ligação '
            'e tenta de novo.';
        _carregando = false;
      });
    }
  }

  void _msg(String texto, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: ok ? AppColors.success : null,
      duration: Duration(seconds: ok ? 3 : 6),
    ));
  }

  Future<void> _gravar() async {
    if (_aGravar) return;
    final falta = await _legal.validateAndReveal();
    if (!mounted) return;
    if (falta != null) {
      _msg('Falta: $falta');
      return;
    }
    setState(() => _aGravar = true);
    try {
      final gravar = widget.gravar;
      if (gravar != null) {
        await gravar(_legal);
      } else {
        await _legal.save('partner');
      }
      _msg('Dados fiscais guardados.', ok: true);
      await _carregar();
    } catch (e) {
      _msg(LegalFieldsService.messageFor(e));
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dados fiscais')),
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = _dados;
    if (_erro != null || d == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erro ?? 'Sem dados.', textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    // A morada fiscal da loja é a morada da loja (restaurants.address). Só se
    // pede aqui quando falta — mudar a morada da loja é noutro sítio.
    final pedirMorada = d.emFalta.contains('morada') ||
        (d.address ?? '').trim().length < 5;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DadosFiscaisEstadoCard(emFalta: d.emFalta),
          const SizedBox(height: Spacing.lg),
          LegalFieldsSection(
            controller: _legal,
            legalNameLabel: 'Nome completo do responsável (como no documento)',
            showAddress: pedirMorada,
            enabled: !_aGravar,
          ),
          if (!pedirMorada) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Morada fiscal (a da loja): ${d.address}',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: Spacing.xl),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _aGravar ? null : _gravar,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              icon: _aGravar
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar dados fiscais'),
            ),
          ),
        ],
      ),
    );
  }
}

/// O cartão do topo: o que falta para a loja poder abrir ao público, ou
/// "Dados fiscais completos". Só desenha — recebe os códigos de `em_falta`.
class DadosFiscaisEstadoCard extends StatelessWidget {
  const DadosFiscaisEstadoCard({super.key, required this.emFalta});

  /// Códigos do servidor ('nome', 'nif', 'morada', 'iban',
  /// 'data_nascimento', 'autocertificacao').
  final List<String> emFalta;

  @override
  Widget build(BuildContext context) {
    final completo = emFalta.isEmpty;
    final cor = completo ? AppColors.primary : AppColors.accent;
    final rotulos = emFalta.map(rotuloEmFalta).toList();
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(completo ? Icons.check_circle : Icons.error_outline,
              color: cor),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  completo
                      ? 'Dados fiscais completos'
                      : 'Para a loja poder abrir ao público, falta:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: Spacing.xs),
                if (completo)
                  const Text(
                    'A loja pode abrir ao público.',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  )
                else ...[
                  for (final r in rotulos)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.xxs),
                      child: Text('• $r',
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary)),
                    ),
                  const SizedBox(height: Spacing.sm),
                  const Text(
                    'Preenche os dados abaixo e toca em "Guardar dados '
                    'fiscais". A lei (DAC7) obriga a Bora a tê-los.',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
