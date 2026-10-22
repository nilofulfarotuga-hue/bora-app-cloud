// lib/widgets/checkin/premio_carrinho_banner.dart
//
// No carrinho da loja certa, o prémio do check-in aparece para aplicar
// ("Tens um prémio para esta loja — Aplicar"), como os vales da Uber Eats e da
// Glovo. Com o prémio já no carrinho, diz o que se paga. Sem marcos ligados, sem
// prémio para esta loja ou sem rede: não aparece nada.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';
import '../../stores/cart_store.dart';
import '../../utils/premio_checkin_fluxo.dart';

class PremioCarrinhoBanner extends StatefulWidget {
  const PremioCarrinhoBanner({super.key, this.carregar, this.aplicar});

  /// Por omissão, `CheckinPremiosService.instance.estado`.
  final Future<CheckinPremiosEstado?> Function()? carregar;

  /// Por omissão, [aplicarPremioNoCarrinho].
  final Future<bool> Function(BuildContext context, CheckinVale vale)? aplicar;

  @override
  State<PremioCarrinhoBanner> createState() => _PremioCarrinhoBannerState();
}

class _PremioCarrinhoBannerState extends State<PremioCarrinhoBanner> {
  CheckinPremiosEstado? _estado;
  bool _aAplicar = false;

  @override
  void initState() {
    super.initState();
    _estado = CheckinPremiosService.instance.ultimo.value;
    _ler();
  }

  Future<void> _ler() async {
    final e = await (widget.carregar ?? CheckinPremiosService.instance.estado)();
    if (!mounted) return;
    setState(() => _estado = e);
  }

  Future<void> _aplicar(CheckinVale v) async {
    if (_aAplicar) return;
    setState(() => _aAplicar = true);
    try {
      await (widget.aplicar ?? aplicarPremioNoCarrinho)(context, v);
    } finally {
      if (mounted) setState(() => _aAplicar = false);
      await _ler();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final e = _estado;
    if (cart.temArtigoPremio) {
      return _caixa(
        key: const Key('premio_no_carrinho'),
        texto: 'Prémio do check-in no carrinho: pagas só a entrega e as taxas.'.tr,
      );
    }
    if (e == null) return const SizedBox.shrink();
    final v = e.valeParaLoja(cart.vendorRestaurantId);
    if (v == null) return const SizedBox.shrink();
    return _caixa(
      key: const Key('premio_para_aplicar'),
      texto: 'Tens um prémio para esta loja: {0}.'.trArgs([v.titulo.tr]),
      acao: TextButton(
        key: const Key('btn_aplicar_premio'),
        onPressed: _aAplicar ? null : () => _aplicar(v),
        child: Text(_aAplicar ? 'A aplicar…'.tr : 'Aplicar'.tr),
      ),
    );
  }

  Widget _caixa({required Key key, required String texto, Widget? acao}) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13, height: 1.3, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
            ),
          ),
          if (acao != null) acao,
        ],
      ),
    );
  }
}
