// lib/screens/client/loja_online/minhas_encomendas_loja_online_screen.dart
//
// Loja Online — as encomendas do próprio cliente (checkup-geral-15-11, B3.7): o que comprou, o
// estado (paga, enviada, entregue...), o prazo do correio e o código de seguimento quando houver.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/loja_online_produto.dart';
import '../../../services/loja_online_pagamento_service.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

class MinhasEncomendasLojaOnlineScreen extends StatefulWidget {
  const MinhasEncomendasLojaOnlineScreen({super.key, this.ler, this.servico});

  /// Injetáveis para os testes.
  final Future<List<Map<String, dynamic>>> Function()? ler;
  final LojaOnlinePagamentoService? servico;

  @override
  State<MinhasEncomendasLojaOnlineScreen> createState() =>
      _MinhasEncomendasLojaOnlineScreenState();
}

class _MinhasEncomendasLojaOnlineScreenState
    extends State<MinhasEncomendasLojaOnlineScreen> {
  late Future<List<Map<String, dynamic>>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _carregar();
  }

  /// Lê as encomendas; as que ficaram "à espera do pagamento" (ex.: cartão pelo site, que sai
  /// do separador) perguntam ao servidor se já pagaram e a lista lê-se outra vez.
  Future<List<Map<String, dynamic>>> _carregar() async {
    final ler = widget.ler ?? lojaOnlineMinhasEncomendas;
    final lista = await ler();
    final pendentes = lista
        .where((e) => e['estado'] == 'aguarda_pagamento')
        .take(3)
        .toList();
    if (pendentes.isEmpty) return lista;
    final servico = widget.servico ?? LojaOnlinePagamentoService();
    var mudou = false;
    for (final e in pendentes) {
      try {
        if (await servico.confirmar('${e['id']}') != 'aguarda_pagamento') {
          mudou = true;
        }
      } catch (err) {
        debugPrint('[LojaOnline] confirmar pendente: $err');
      }
    }
    return mudou ? await ler() : lista;
  }

  int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'As minhas encomendas'.tr),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() =>
                    _futuro = _carregar()),
                child: Text('Tentar outra vez'.tr),
              ),
            );
          }
          final lista = snap.data ?? const [];
          if (lista.isEmpty) {
            return Center(
              child: Text('Ainda não fizeste nenhuma encomenda.'.tr,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Spacing.lg),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const SizedBox(height: Spacing.md),
            itemBuilder: (context, i) {
              final e = lista[i];
              final estado = '${e['estado'] ?? ''}';
              final prazo =
                  textoPrazoCorreio(_int(e['prazo_min_dias']), _int(e['prazo_max_dias']));
              final tracking = '${e['tracking'] ?? ''}'.trim();
              return Container(
                padding: const EdgeInsets.all(Spacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e['titulo'] ?? ''} × ${_int(e['quantidade'])}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: Spacing.xs),
                    Text(formatarEurosCents(_int(e['total_cents'])),
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textSecondary)),
                    const SizedBox(height: Spacing.xs),
                    Text(lojaOnlineEstadoCliente(estado).tr,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                    if (prazo.isNotEmpty &&
                        estado != 'entregue' &&
                        estado != 'cancelada' &&
                        estado != 'falhou_pagamento')
                      Text(prazo,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    if (tracking.isNotEmpty)
                      InkWell(
                        onTap: () =>
                            Clipboard.setData(ClipboardData(text: tracking)),
                        child: Padding(
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Text(
                              'Código de seguimento: {0}'.trArgs([tracking]),
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
