import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';

/// Quanto tempo a janela espera pelo MB WAY de um pedido.
///
/// noite-farmacia-17-11 (3.1): eram 120 s e o MB WAY leva ~4 min a chegar a
/// alguns clientes. A 16/11 (pedido 1006af87; antes 25/10 4c462849 e 28/10
/// 6361fa99) a janela fechou antes, o pedido foi cancelado e o cliente pagou
/// depois. Agora espera 4 minutos.
const int mbwayEsperaPedidoSegundos = 240;

/// Janela "Aguarda a confirmação no MB WAY" do pedido.
///
/// Fecha com `true` quando o pedido fica pago e com `false` quando o tempo
/// acaba ou o cliente CONFIRMA que quer cancelar. O botão voltar do Android já
/// não a fecha (antes fechava sem perguntar e o pedido era cancelado com o MB
/// WAY ainda vivo no telemóvel): pergunta o mesmo que o "Cancelar".
class MbwayEsperaPedidoDialog extends StatefulWidget {
  const MbwayEsperaPedidoDialog({
    super.key,
    required this.orderId,
    required this.amount,
    this.segundos = mbwayEsperaPedidoSegundos,
    this.lerEstadoPagamento,
    this.intervaloLeitura = const Duration(seconds: 3),
  });

  final String orderId;
  final double amount;
  final int segundos;

  /// Para testes: lê `orders.payment_status` (por defeito, do Supabase).
  final Future<String?> Function(String orderId)? lerEstadoPagamento;
  final Duration intervaloLeitura;

  @override
  State<MbwayEsperaPedidoDialog> createState() => _MbwayEsperaPedidoDialogState();
}

class _MbwayEsperaPedidoDialogState extends State<MbwayEsperaPedidoDialog> {
  late int _secondsLeft = widget.segundos;
  bool _done = false;
  bool _aPerguntar = false;

  @override
  void initState() {
    super.initState();
    _countdown();
    _poll();
  }

  void _fechar(bool pago) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(pago);
  }

  void _countdown() async {
    while (_secondsLeft > 0 && mounted && !_done) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && !_done) setState(() => _secondsLeft--);
    }
    // Tempo esgotado: se a pergunta "cancelar?" estiver aberta, fecha-a primeiro.
    if (mounted && !_done && _aPerguntar) Navigator.of(context).pop();
    _fechar(false);
  }

  Future<String?> _ler(String id) async {
    if (widget.lerEstadoPagamento != null) return widget.lerEstadoPagamento!(id);
    final row = await Supabase.instance.client
        .from('orders')
        .select('payment_status')
        .eq('id', id)
        .maybeSingle();
    return row?['payment_status']?.toString();
  }

  void _poll() async {
    while (mounted && !_done) {
      await Future.delayed(widget.intervaloLeitura);
      if (!mounted || _done) break;
      try {
        if (await _ler(widget.orderId) == 'paid' && mounted && !_done) {
          if (_aPerguntar) Navigator.of(context).pop();
          _fechar(true);
        }
      } catch (_) {}
    }
  }

  /// "Cancelar" e o botão voltar: só fecha se o cliente confirmar.
  Future<void> _pedirCancelar() async {
    if (_done || _aPerguntar) return;
    _aPerguntar = true;
    final sim = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('mbway_cancelar_confirmar'),
        title: Text('Cancelar o pagamento?'.tr),
        content: Text('Se já aprovaste na app MB WAY, espera mais um pouco: o pedido confirma sozinho. Se cancelares, o pedido é cancelado e o pagamento no MB WAY deixa de valer.'.tr),
        actions: [
          TextButton(
            key: const Key('mbway_continuar_espera'),
            onPressed: () => Navigator.pop(c, false),
            child: Text('Continuar à espera'.tr),
          ),
          TextButton(
            key: const Key('mbway_cancelar_sim'),
            onPressed: () => Navigator.pop(c, true),
            child: Text('Cancelar pagamento'.tr),
          ),
        ],
      ),
    );
    _aPerguntar = false;
    if (sim == true) _fechar(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pedirCancelar();
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.phone_iphone, color: Colors.red.shade700),
            const SizedBox(width: 8),
            // Revisão 15/11 (nota 17): "MB WAY", como nas outras frases.
            Flexible(child: Text('Aguarda a confirmação no MB WAY'.tr)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              'Enviámos um pedido de {0} € para o teu telemóvel.\nAbre a app MB WAY e confirma.'
                  .trArgs([widget.amount.toStringAsFixed(2).replaceAll('.', ',')]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'A aguardar confirmação... {0} s'.trArgs([_secondsLeft]),
              key: const Key('mbway_segundos'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('mbway_cancelar'),
            onPressed: _pedirCancelar,
            child: Text('Cancelar'.tr),
          ),
        ],
      ),
    );
  }
}
