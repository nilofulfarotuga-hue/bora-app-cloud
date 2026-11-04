// Favor pago por MB Way com a compra acima do orçado (04/11/2026, missão
// favor-diferenca-mbway-2026-11-03, adendo 1). O servidor pede a diferença por
// MB Way; o pedido dura poucos minutos. Este cartão mostra ao cliente o que
// falta e porquê e, quando o pedido expirou ou falhou, o botão "Pagar a
// diferença" manda um MB Way novo (RPC cliente_favor_pagar_diferenca).
//
// Lê a tabela favor_diferencas (só as linhas do próprio cliente, por RLS).
// Sem linhas, sem a tabela no servidor ou sem rede: não mostra nada.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';

/// Último pedido MB Way da diferença de um Favor.
class FavorDiferenca {
  const FavorDiferenca({
    required this.estado,
    required this.valorCents,
    required this.criadoEm,
  });

  /// 'pedido' | 'pago' | 'expirou' | 'falhou'.
  final String estado;
  final int valorCents;
  final DateTime criadoEm;

  factory FavorDiferenca.fromJson(Map<String, dynamic> m) => FavorDiferenca(
        estado: '${m['estado'] ?? ''}',
        valorCents: (m['valor_cents'] as num?)?.toInt() ?? 0,
        criadoEm: DateTime.tryParse('${m['criado_em']}') ?? DateTime.now(),
      );

  /// O MB Way dá poucos minutos: um pedido sem resposta há 5 min já expirou
  /// (o servidor marca-o assim no próximo pedido).
  bool podeReenviar(DateTime agora) =>
      estado == 'expirou' ||
      estado == 'falhou' ||
      (estado == 'pedido' && agora.difference(criadoEm).inMinutes >= 5);

  String get valorTexto =>
      (valorCents / 100).toStringAsFixed(2).replaceAll('.', ',');
}

class FavorDiferencaBanner extends StatefulWidget {
  const FavorDiferencaBanner({
    super.key,
    required this.order,
    this.ler,
    this.pagar,
    this.agora,
  });

  final OrderModel order;

  /// Só para testes.
  final Future<FavorDiferenca?> Function(String pedidoId)? ler;
  final Future<Map<String, dynamic>> Function(String pedidoId)? pagar;
  final DateTime Function()? agora;

  static Future<FavorDiferenca?> lerDoServidor(String pedidoId) async {
    final linha = await Supabase.instance.client
        .from('favor_diferencas')
        .select('estado, valor_cents, criado_em')
        .eq('pedido_id', pedidoId)
        .order('criado_em', ascending: false)
        .limit(1)
        .maybeSingle();
    return linha == null ? null : FavorDiferenca.fromJson(linha);
  }

  static Future<Map<String, dynamic>> pagarNoServidor(String pedidoId) async {
    final r = await Supabase.instance.client
        .rpc('cliente_favor_pagar_diferenca', params: {'p_pedido': pedidoId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  @override
  State<FavorDiferencaBanner> createState() => _FavorDiferencaBannerState();
}

class _FavorDiferencaBannerState extends State<FavorDiferencaBanner> {
  FavorDiferenca? _d;
  bool _aEnviar = false;

  bool get _aplica {
    final o = widget.order;
    return o.serviceType == OrderServiceType.errand &&
        o.paymentMethod == PaymentMethod.mbway &&
        o.status != OrderStatus.delivered;
  }

  @override
  void initState() {
    super.initState();
    if (_aplica) _ler();
  }

  Future<void> _ler() async {
    try {
      final d = await (widget.ler ?? FavorDiferencaBanner.lerDoServidor)(widget.order.id);
      if (mounted) setState(() => _d = d);
    } catch (_) {
      // sem a tabela ou sem rede: não mostra nada
    }
  }

  Future<void> _pagar() async {
    if (_aEnviar) return;
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    String msg;
    try {
      final r = await (widget.pagar ?? FavorDiferencaBanner.pagarNoServidor)(widget.order.id);
      msg = switch (r['error']) {
        null when r['ok'] == true =>
          'Enviámos um novo pedido MB Way. Tens poucos minutos para o aprovar na app MB Way.'.tr,
        'pedido_em_curso' =>
          'Já tens um pedido MB Way à espera. Aprova-o na app MB Way.'.tr,
        'ja_pago' || 'ja_acertado' || 'nada_a_pagar' => 'A diferença já está paga.'.tr,
        _ => 'Não foi possível enviar o pedido MB Way. Tenta outra vez daqui a pouco.'.tr,
      };
    } catch (_) {
      msg = 'Não foi possível enviar o pedido MB Way. Tenta outra vez daqui a pouco.'.tr;
    }
    if (!mounted) return;
    setState(() => _aEnviar = false);
    messenger.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
    await _ler();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (!_aplica || d == null || d.estado == 'pago') return const SizedBox.shrink();
    final agora = (widget.agora ?? DateTime.now)();
    final reenviar = d.podeReenviar(agora);
    final texto = reenviar
        ? 'Falta pagar {0} € da compra do teu Favor: o estafeta comprou acima do orçado. O pedido MB Way expirou.'
            .trArgs([d.valorTexto])
        : 'Falta pagar {0} € da compra do teu Favor. Enviámos um pedido MB Way: aprova-o na app MB Way, tens poucos minutos.'
            .trArgs([d.valorTexto]);
    return Container(
      key: const Key('favor_diferenca_banner'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.phone_iphone, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(texto,
                    style: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (reenviar) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('btn_pagar_diferenca'),
                onPressed: _aEnviar ? null : _pagar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: Text(_aEnviar ? 'A enviar…'.tr : 'Pagar a diferença'.tr),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
