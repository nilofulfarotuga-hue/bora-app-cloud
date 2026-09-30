import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/tvde_dest_change.dart';
import '../../../widgets/bora/bora.dart';

/// O que o cliente decidiu na folha "Mudar destino".
class TvdeDestChangeDecision {
  const TvdeDestChangeDecision({required this.phone});

  /// 9 dígitos, só preenchido quando se paga por MB Way.
  final String phone;
}

/// Folha "Mudar destino" (30/09/2026, regra do Danilo).
///
/// Mostra SEMPRE, antes de confirmar: o destino novo, os km, o preço novo e a
/// diferença, com a fórmula (Lei 45/2018 art. 15.º n.º 4). "Aceitar" devolve
/// um [TvdeDestChangeDecision]; "Cancelar" ou fechar devolve null — e sem
/// aceitar nada muda. Os números vêm todos do servidor ([TvdeDestChangeQuote]).
class TvdeDestChangeSheet extends StatefulWidget {
  const TvdeDestChangeSheet({
    super.key,
    required this.quote,
    required this.destLabel,
    required this.method,
    this.initialPhone = '',
  });

  final TvdeDestChangeQuote quote;
  final String destLabel;

  /// Forma de pagamento da corrida: 'cash' | 'card' | 'mbway'.
  final String method;
  final String initialPhone;

  @override
  State<TvdeDestChangeSheet> createState() => _TvdeDestChangeSheetState();
}

class _TvdeDestChangeSheetState extends State<TvdeDestChangeSheet> {
  late final TextEditingController _phone;
  String? _phoneError;

  TvdeDestChangeQuote get q => widget.quote;
  bool get _pagaAgora => !q.isFree && widget.method != 'cash';
  bool get _mbway => _pagaAgora && widget.method == 'mbway';

  @override
  void initState() {
    super.initState();
    final digits = widget.initialPhone.replaceAll(RegExp(r'\D'), '');
    _phone = TextEditingController(
        text: digits.length >= 9 ? digits.substring(digits.length - 9) : '');
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _aceitar() {
    if (_mbway) {
      final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 9) {
        setState(() => _phoneError = 'Indica um número com 9 dígitos.'.tr);
        return;
      }
      Navigator.pop(context, TvdeDestChangeDecision(phone: digits));
      return;
    }
    Navigator.pop(context, const TvdeDestChangeDecision(phone: ''));
  }

  String get _comoPagas {
    if (q.isFree) return 'Não há nada a pagar.'.tr;
    final v = TvdeDestChangeQuote.eur(q.clientDiffCents);
    switch (widget.method) {
      case 'card':
        return 'Cobramos {0} no cartão agora. O destino só muda depois de o pagamento passar.'
            .trArgs([v]);
      case 'mbway':
        return 'Cobramos {0} por MB Way agora. O destino só muda depois de confirmares no MB Way.'
            .trArgs([v]);
      default:
        return 'Pagas {0} a mais ao motorista, em dinheiro, no fim da viagem.'
            .trArgs([v]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    final safeBottom = media.padding.bottom;
    const secundario = TextStyle(color: AppColors.textSecondary, fontSize: 13);
    const eur = TvdeDestChangeQuote.eur;
    const km = TvdeDestChangeQuote.km;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: Spacing.lg + inset + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_location_alt_outlined,
                  color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text('Mudar destino'.tr,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                tooltip: 'Fechar'.tr,
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text('Destino novo'.tr, style: secundario),
          Text(widget.destLabel,
              key: const Key('tvde_dest_change_label'),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.md),
          Text(
            q.longer
                ? '{0} km já feitos + {1} km até ao destino novo = {2} km'
                    .trArgs([km(q.kmDone), km(q.kmRemaining), km(q.kmNewTotal)])
                : 'O destino novo fica mais perto ({0} km no total, combinados {1} km).'
                    .trArgs([km(q.kmNewTotal), km(q.kmBefore)]),
            key: const Key('tvde_dest_change_km'),
            style: secundario,
          ),
          const SizedBox(height: Spacing.sm),
          _linha('Preço combinado'.tr, eur(q.priceBeforeCents)),
          _linha('Preço novo'.tr, eur(q.priceAfterCents), forte: true),
          const SizedBox(height: Spacing.sm),
          Text(
            q.isFree
                ? 'Não pagas mais nada'.tr
                : 'Pagas mais {0}'.trArgs([eur(q.clientDiffCents)]),
            key: const Key('tvde_dest_change_diff'),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          if (q.minApplied && !q.isFree)
            Text(
              'Pela tabela a diferença seria {0}; cada mudança para mais longe tem o mínimo de {1}.'
                  .trArgs([eur(q.priceNewCents - q.priceBeforeCents < 0 ? 0 : q.priceNewCents - q.priceBeforeCents), eur(q.minCents)]),
              style: secundario,
            ),
          if (!q.longer)
            Text('O preço fica igual e não há devolução.'.tr, style: secundario),
          const SizedBox(height: Spacing.sm),
          Text(_comoPagas, style: secundario),
          if (q.hasFormula) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Como se calcula: {0} até {1} km + {2} por km a mais. As paragens pagam-se à parte.'
                  .trArgs([eur(q.baseFareCents!), q.baseKm, eur(q.perKmCents!)]),
              key: const Key('tvde_dest_change_formula'),
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 11.5),
            ),
          ],
          if (_mbway) ...[
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('tvde_dest_change_mbway_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Número MBWay'.tr,
                hintText: '9XXXXXXXX'.tr,
                prefixText: '+351 ',
                errorText: _phoneError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          BoraAccentButton(
            key: const Key('tvde_dest_change_accept'),
            label: 'Aceitar'.tr,
            onPressed: _aceitar,
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            key: const Key('tvde_dest_change_cancel'),
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'.tr),
          ),
        ],
      ),
    );
  }

  Widget _linha(String k, String v, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13.5))),
            Text(v,
                style: TextStyle(
                    fontWeight: forte ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary,
                    fontSize: 13.5)),
          ],
        ),
      );
}
