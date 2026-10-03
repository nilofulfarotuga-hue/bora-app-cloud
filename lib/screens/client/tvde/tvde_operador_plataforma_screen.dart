import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../services/tvde_conformidade_service.dart';
import '../../../widgets/bora/bora.dart';

/// "Sobre o operador da plataforma" — identificação do operador de plataforma
/// eletrónica TVDE (Lei 45/2018 na versão da Lei 59/2026). Lê
/// `tvde_operador_plataforma()`; o que ainda não existe aparece como
/// "Em constituição" — nunca se inventa um NIF ou uma licença.
class TvdeOperadorPlataformaScreen extends StatefulWidget {
  const TvdeOperadorPlataformaScreen({super.key});

  @override
  State<TvdeOperadorPlataformaScreen> createState() =>
      _TvdeOperadorPlataformaScreenState();
}

class _TvdeOperadorPlataformaScreenState
    extends State<TvdeOperadorPlataformaScreen> {
  Map<String, dynamic>? _dados;
  bool _erro = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = false);
    try {
      final d = await TvdeConformidadeService.instance.operadorPlataforma();
      if (!mounted) return;
      setState(() => _dados = d);
    } catch (e) {
      debugPrint('[TvdeOperador] falhou: $e');
      if (!mounted) return;
      setState(() => _erro = true);
    }
  }

  static String _valor(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? 'Em constituição' : s;
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Operador da plataforma'),
      body: _erro
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Não foi possível carregar esta informação.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: Spacing.sm),
                    TextButton(
                        onPressed: _carregar,
                        child: const Text('Tentar outra vez')),
                  ],
                ),
              ),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  children: [
                    const Text(
                      'Quem gere a plataforma eletrónica de transporte (TVDE) '
                      'que estás a usar.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: Spacing.md),
                    Container(
                      padding: const EdgeInsets.all(Spacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Campo('Marca', _valor(d['marca'])),
                          _Campo('Denominação', _valor(d['denominacao'])),
                          _Campo('NIF', _valor(d['nif'])),
                          _Campo('Sede', _valor(d['sede'])),
                          _Campo('Licença IMT', _valor(d['licenca_imt'])),
                          _Campo('Email', _valor(d['email'])),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSubtle)),
          SelectableText(valor,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
