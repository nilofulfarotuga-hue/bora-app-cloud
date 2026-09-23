import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/ficha_legal_service.dart';

/// Recibo da viagem TVDE (Lei 45/2018 rev. Lei 59/2026): valor da viagem com
/// a taxa de intermediação da Bora numa linha própria. Não é fatura.
///
/// Os números vêm todos de `tvde_recibo_viagem` (servidor). A app não soma
/// nem divide nada — quando o servidor não sabe discriminar (pacote
/// ida-e-volta), mostra o total e a razão.
Future<void> abrirReciboViagem(BuildContext context, String rideId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReciboViagemSheet(rideId: rideId),
  );
}

class _ReciboViagemSheet extends StatefulWidget {
  const _ReciboViagemSheet({required this.rideId});
  final String rideId;

  @override
  State<_ReciboViagemSheet> createState() => _ReciboViagemSheetState();
}

class _ReciboViagemSheetState extends State<_ReciboViagemSheet> {
  Map<String, dynamic>? _r;
  String? _erro;
  bool _aEnviar = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await Supabase.instance.client
          .rpc('tvde_recibo_viagem', params: {'p_ride': widget.rideId})
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() => r == null
          ? _erro = 'O recibo fica disponível quando a viagem terminar.'.tr
          : _r = Map<String, dynamic>.from(r as Map));
    } catch (_) {
      if (mounted) {
        setState(() => _erro = 'Não foi possível abrir o recibo. Tenta de novo.'.tr);
      }
    }
  }

  Future<void> _enviar() async {
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await Supabase.instance.client.functions
          .invoke('tvde-recibo-viagem', body: {'rideId': widget.rideId})
          .timeout(const Duration(seconds: 20));
      final ok = res.data is Map && (res.data as Map)['ok'] == true;
      messenger.showSnackBar(SnackBar(
          content: Text(ok
              ? 'Recibo enviado para o teu e-mail.'.tr
              : 'Não foi possível enviar o recibo.'.tr)));
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível enviar o recibo.'.tr)));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  Widget _linha(String rotulo, String valor, {bool forte = false}) {
    final st = TextStyle(
        fontSize: 15,
        fontWeight: forte ? FontWeight.w800 : FontWeight.w500,
        color: AppColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(rotulo, style: st)),
        Text(valor, style: st),
      ]),
    );
  }

  int? _c(String k) => _r?[k] is num ? (_r![k] as num).toInt() : null;

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: r == null
            ? SizedBox(
                height: 160,
                child: Center(
                    child: _erro == null
                        ? const CircularProgressIndicator()
                        : Text(_erro!, textAlign: TextAlign.center)))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Recibo da viagem'.tr,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                    Text(
                        '${'N.º'.tr} ${r['numero']} · ${FichaTexto.dataHora(r['data']?.toString())}',
                        style: const TextStyle(color: AppColors.textSubtle)),
                    const SizedBox(height: 10),
                    Text('${r['origem'] ?? ''} → ${r['destino'] ?? ''}'),
                    if (r['motorista'] != null)
                      Text('${'Motorista'.tr}: ${r['motorista']}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                    const Divider(height: 24),
                    if (r['discriminado'] == true) ...[
                      _linha('Serviço de transporte (motorista)'.tr,
                          FichaTexto.euro(_c('transporte_cents'))),
                      _linha('Taxa de intermediação Bora'.tr,
                          FichaTexto.euro(_c('taxa_intermediacao_cents'))),
                    ],
                    _linha('Valor da viagem'.tr,
                        FichaTexto.euro(_c('valor_viagem_cents')),
                        forte: _c('descontos_cents') == null),
                    if (_c('descontos_cents') != null) ...[
                      _linha('Descontos (tokens / crédito)'.tr,
                          '− ${FichaTexto.euro(_c('descontos_cents'))}'),
                      _linha('Total pago'.tr,
                          FichaTexto.euro(_c('total_pago_cents')),
                          forte: true),
                    ],
                    _linha('Pagamento'.tr,
                        FichaTexto.meio(r['pagamento']?.toString()).tr),
                    if (r['razao'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(r['razao'].toString().tr,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSubtle)),
                      ),
                    const SizedBox(height: 10),
                    Text(
                        'Recibo de viagem. Não substitui fatura: a fatura é emitida por software certificado.'
                            .tr,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSubtle)),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _aEnviar ? null : _enviar,
                      icon: const Icon(Icons.email_outlined),
                      label: Text('Enviar por e-mail'.tr),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
