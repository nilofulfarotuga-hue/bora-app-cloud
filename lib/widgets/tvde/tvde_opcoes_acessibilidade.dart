import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/tvde_conformidade_service.dart';

/// Opções do passageiro TVDE — Lei 45/2018 na versão da Lei 59/2026:
/// "Motorista que fala português" e "Mobilidade reduzida" (cão-guia, cadeira
/// de rodas, carrinho de bebé), sempre ao mesmo preço.
///
/// Só aparece quando o pai o decide (interruptor `tvde_client_options_enabled`
/// → `config().opcoesCliente`). Cada toque grava logo no servidor
/// (`tvde_prefs_guardar`) — é o servidor que copia as preferências para a
/// corrida quando ela nasce, por isso ficam guardadas ANTES de pedir.
/// Sem sessão ou sem rede, o bloco simplesmente não aparece.
class TvdeOpcoesAcessibilidade extends StatefulWidget {
  const TvdeOpcoesAcessibilidade({super.key});

  @override
  State<TvdeOpcoesAcessibilidade> createState() =>
      _TvdeOpcoesAcessibilidadeState();
}

class _TvdeOpcoesAcessibilidadeState extends State<TvdeOpcoesAcessibilidade> {
  final _svc = TvdeConformidadeService.instance;

  Map<String, bool>? _prefs;

  /// `tvde_mobilidade_disponivel` — só lido com mobilidade reduzida ativa.
  Map<String, dynamic>? _mobilidade;

  static const _chaves = [
    'fala_portugues',
    'mobilidade_reduzida',
    'cao_guia',
    'cadeira_rodas',
    'carrinho_bebe',
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final res = await _svc.preferencias();
      if (!mounted) return;
      setState(() => _prefs = {for (final k in _chaves) k: res[k] == true});
      if (_prefs!['mobilidade_reduzida'] == true) _verMobilidade();
    } catch (e) {
      debugPrint('[TvdeOpcoes] preferências indisponíveis: $e');
    }
  }

  Future<void> _verMobilidade() async {
    try {
      final res = await _svc.mobilidadeDisponivel();
      if (!mounted) return;
      setState(() => _mobilidade = res);
    } catch (e) {
      debugPrint('[TvdeOpcoes] mobilidade indisponível: $e');
    }
  }

  /// Muda uma opção: mostra logo (otimista) e grava. Se o servidor recusar,
  /// volta atrás e diz porquê. Cada toque é independente — nenhum botão fica
  /// preso a um estado de "ocupado" partilhado (PADRAO_BORA 3.13).
  Future<void> _mudar(String chave, bool valor) async {
    final antes = _prefs?[chave] ?? false;
    setState(() => _prefs = {...?_prefs, chave: valor});
    if (chave == 'mobilidade_reduzida') {
      if (valor) {
        _verMobilidade();
      } else {
        setState(() => _mobilidade = null);
      }
    }
    try {
      await _svc.guardarPreferencias({chave: valor});
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = {...?_prefs, chave: antes});
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagemErroConformidade(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    if (p == null) return const SizedBox.shrink();
    final mobilidade = p['mobilidade_reduzida'] == true;
    final semAdaptado = mobilidade &&
        _mobilidade != null &&
        ((_mobilidade!['adaptados_online'] as num?) ?? 0) == 0;
    final esperaMin = (_mobilidade?['espera_min'] as num?)?.toInt() ?? 15;

    return Container(
      key: const Key('tvde_opcoes_acessibilidade'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, 0),
            child: Text('Preferências da viagem',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          SwitchListTile(
            key: const Key('tvde_pref_fala_portugues'),
            dense: true,
            title: const Text('Motorista que fala português'),
            subtitle: const Text('Mesmo preço.'),
            value: p['fala_portugues'] == true,
            onChanged: (v) => _mudar('fala_portugues', v),
          ),
          SwitchListTile(
            key: const Key('tvde_pref_mobilidade'),
            dense: true,
            title: const Text('Mobilidade reduzida'),
            subtitle: const Text('Carro adaptado, mesmo preço.'),
            value: mobilidade,
            onChanged: (v) => _mudar('mobilidade_reduzida', v),
          ),
          if (mobilidade) ...[
            _sub('cao_guia', 'Cão-guia', p),
            _sub('cadeira_rodas', 'Cadeira de rodas', p),
            _sub('carrinho_bebe', 'Carrinho de bebé', p),
          ],
          if (semAdaptado)
            Container(
              key: const Key('tvde_aviso_sem_adaptado'),
              margin: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.xs, Spacing.md, Spacing.md),
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                'Neste momento não há carro adaptado disponível. Se não '
                'houver em $esperaMin minutos, podes usar: táxi adaptado, '
                'transporte público acessível ou pedir apoio pelo 112 em '
                'emergência.',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textPrimary),
              ),
            )
          else
            const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }

  Widget _sub(String chave, String rotulo, Map<String, bool> p) {
    return CheckboxListTile(
      key: Key('tvde_pref_$chave'),
      dense: true,
      contentPadding: const EdgeInsets.only(left: Spacing.xxxl, right: Spacing.lg),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(rotulo),
      value: p[chave] == true,
      onChanged: (v) => _mudar(chave, v ?? false),
    );
  }
}
