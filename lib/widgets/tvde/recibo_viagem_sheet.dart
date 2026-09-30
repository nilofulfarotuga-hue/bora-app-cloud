import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../screens/client/tvde/tvde_queixas_screen.dart';
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

  /// 10 → "10", 12.5 → "12,5".
  static String _pct(num v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');

  /// Demonstração do cálculo (art. 15.º n.º 8) — só com `calculo` do servidor
  /// (não vem em pacote, assinatura nem preço combinado).
  List<Widget> _calculo(Map<String, dynamic> c) {
    int? n(String k) => c[k] is num ? (c[k] as num).toInt() : null;
    final kmExtra = n('km_extra') ?? 0;
    final precoKm = n('preco_km_extra_cents') ?? 0;
    final fator = (c['fator_dinamico'] as num?) ?? 1;
    const st = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    Widget l(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(a, style: st)),
            Text(b, style: st),
          ]),
        );
    return [
      const Padding(
        padding: EdgeInsets.only(top: 10, bottom: 2),
        child: Text('Como foi calculado',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      l(
          n('km_incluidos') != null
              ? 'Tarifa base (até ${n('km_incluidos')} km)'
              : 'Tarifa base',
          FichaTexto.euro(n('tarifa_base_cents'))),
      l('Km extra: $kmExtra × ${FichaTexto.euro(precoKm)}/km',
          FichaTexto.euro(kmExtra * precoKm)),
      l('Preço por tempo (o preço não depende do tempo)',
          FichaTexto.euro(n('preco_por_minuto_cents') ?? 0)),
      l('Tarifa dinâmica',
          fator == 1 ? 'sem tarifa dinâmica' : '× $fator'),
    ];
  }

  Future<void> _abrirFatura(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

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
                    // Conformidade (art. 15.º n.º 8): é um RESUMO da viagem,
                    // nunca se apresenta como fatura.
                    Text(
                        (r['titulo'] as String?)?.trim().isNotEmpty == true
                            ? (r['titulo'] as String).trim()
                            : 'Resumo da viagem',
                        key: const Key('tvde_resumo_titulo'),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                    Text(
                        '${'N.º'.tr} ${r['numero']} · ${FichaTexto.dataHora(r['data']?.toString())}',
                        style: const TextStyle(color: AppColors.textSubtle)),
                    if (r['codigo_viagem'] != null)
                      SelectableText(
                          'Código da viagem: ${r['codigo_viagem']}',
                          key: const Key('tvde_resumo_codigo'),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSubtle)),
                    if (_c('duracao_min') != null)
                      Text('Duração: ${_c('duracao_min')} min',
                          key: const Key('tvde_resumo_duracao'),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSubtle)),
                    const SizedBox(height: 10),
                    Text('${r['origem'] ?? ''} → ${r['destino'] ?? ''}'),
                    if (r['motorista'] != null)
                      Text('${'Motorista'.tr}: ${r['motorista']}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                    const Divider(height: 24),
                    if (r['discriminado'] == true) ...[
                      _linha('Serviço de transporte (motorista)'.tr,
                          FichaTexto.euro(_c('transporte_cents'))),
                      _linha(
                          r['taxa_intermediacao_pct'] is num
                              ? '${'Taxa de intermediação Bora'.tr} (${_pct(r['taxa_intermediacao_pct'] as num)} %)'
                              : 'Taxa de intermediação Bora'.tr,
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
                    // IVA só quando o servidor o discrimina.
                    if (r['iva_pct'] is num)
                      _linha(
                          'IVA incluído (${_pct(r['iva_pct'] as num)} %)',
                          FichaTexto.euro(_c('iva_cents'))),
                    _linha('Pagamento'.tr,
                        FichaTexto.meio(r['pagamento']?.toString()).tr),
                    if (r['razao'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(r['razao'].toString().tr,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSubtle)),
                      ),
                    if (r['calculo'] is Map)
                      ..._calculo(
                          Map<String, dynamic>.from(r['calculo'] as Map)),
                    // Documento fiscal próprio, quando já foi emitido.
                    if (r['fatura'] is Map) ...[
                      const SizedBox(height: 10),
                      Builder(builder: (_) {
                        final f = Map<String, dynamic>.from(r['fatura'] as Map);
                        final atcud = f['atcud']?.toString();
                        final url = f['url']?.toString();
                        final texto = 'Fatura n.º ${f['numero'] ?? ''}'
                            '${atcud != null && atcud.isNotEmpty ? ' (ATCUD $atcud)' : ''}';
                        return url != null && url.isNotEmpty
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: const Key('tvde_resumo_fatura'),
                                  onPressed: () => _abrirFatura(url),
                                  icon: const Icon(Icons.description_outlined,
                                      size: 18),
                                  label: Text(texto),
                                ),
                              )
                            : Text(texto,
                                key: const Key('tvde_resumo_fatura'),
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary));
                      }),
                    ],
                    const SizedBox(height: 10),
                    Text(
                        (r['aviso_legal'] as String?)?.trim().isNotEmpty == true
                            ? (r['aviso_legal'] as String).trim()
                            : 'Recibo de viagem. Não substitui fatura: a fatura é emitida por software certificado.'
                                .tr,
                        key: const Key('tvde_resumo_aviso_legal'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSubtle)),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _aEnviar ? null : _enviar,
                      icon: const Icon(Icons.email_outlined),
                      label: Text('Enviar por e-mail'.tr),
                    ),
                    // Conformidade (art. 19.º n.º 3): queixa sobre ESTA viagem.
                    TextButton.icon(
                      key: const Key('tvde_resumo_queixa'),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  TvdeQueixasScreen(rideId: widget.rideId))),
                      icon: const Icon(Icons.feedback_outlined, size: 18),
                      label: const Text('Fazer uma queixa sobre esta viagem'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
