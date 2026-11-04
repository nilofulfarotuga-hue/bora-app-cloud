// Painel admin (PT-BR) — "Diferenças de Favor" (04/11/2026, missão
// favor-diferenca-mbway-2026-11-03, bloco E). Favores pagos por MB Way em que a
// compra passou o orçado: quanto falta, estado do pedido MB Way (pedido /
// pago / expirou / falhou), quantas tentativas e o botão "Reenviar pedido MB
// Way" (RPC admin_favor_diferenca_reenviar, fica no log de auditoria).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';

/// Texto PT-BR do estado do pedido MB Way.
String estadoDiferencaTexto(String? estado) => switch (estado) {
      'pedido' => 'Pedido MB Way enviado (aguardando o cliente aprovar no app MB Way)',
      'pago' => 'Pago',
      'expirou' => 'Expirou (o cliente não aprovou a tempo)',
      'falhou' => 'Falhou (recusado ou erro do MB Way)',
      _ => 'Sem pedido MB Way (diferença em disputa)',
    };

class AdminFavorDiferencasScreen extends StatefulWidget {
  const AdminFavorDiferencasScreen({super.key, this.listar, this.reenviar});

  /// Só para testes.
  final Future<List<Map<String, dynamic>>> Function()? listar;
  final Future<Map<String, dynamic>> Function(String pedidoId)? reenviar;

  static Future<List<Map<String, dynamic>>> listarDoServidor() async {
    final r = await Supabase.instance.client.rpc('admin_favor_diferencas_listar');
    if (r is List) {
      return r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  static Future<Map<String, dynamic>> reenviarNoServidor(String pedidoId) async {
    final r = await Supabase.instance.client
        .rpc('admin_favor_diferenca_reenviar', params: {'p_pedido': pedidoId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  @override
  State<AdminFavorDiferencasScreen> createState() => _AdminFavorDiferencasScreenState();
}

class _AdminFavorDiferencasScreenState extends State<AdminFavorDiferencasScreen> {
  List<Map<String, dynamic>>? _linhas;
  String? _erro;
  final Set<String> _aEnviar = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final l = await (widget.listar ?? AdminFavorDiferencasScreen.listarDoServidor)();
      if (mounted) setState(() { _linhas = l; _erro = null; });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    }
  }

  Future<void> _reenviar(String pedidoId) async {
    setState(() => _aEnviar.add(pedidoId));
    final messenger = ScaffoldMessenger.of(context);
    String msg;
    try {
      final r = await (widget.reenviar ?? AdminFavorDiferencasScreen.reenviarNoServidor)(pedidoId);
      msg = r['ok'] == true
          ? 'Novo pedido MB Way enviado (tentativa ${r['tentativa']}).'
          : 'Não enviado: ${r['error'] ?? 'erro desconhecido'}';
    } catch (e) {
      msg = 'Erro ao reenviar: $e';
    }
    if (!mounted) return;
    setState(() => _aEnviar.remove(pedidoId));
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    await _carregar();
  }

  static String _eur(Object? cents) =>
      '€${(((cents as num?) ?? 0) / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diferenças de Favor'),
        actions: [IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh))],
      ),
      body: _erro != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Não foi possível carregar: $_erro',
                  style: const TextStyle(color: AppColors.error)),
            )
          : linhas == null
              ? const Center(child: CircularProgressIndicator())
              : linhas.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nenhuma diferença de Favor por cobrar.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: linhas.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return const Text(
                            'Favores pagos por MB Way em que a compra passou o orçado. O servidor pede a diferença '
                            'por MB Way (o cliente tem poucos minutos para aprovar). "Reenviar" manda um pedido novo.',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          );
                        }
                        final l = linhas[i - 1];
                        final id = '${l['pedido_id']}';
                        final acertado = l['acertado_em'] != null;
                        return Card(
                          key: Key('favor_dif_$id'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Pedido ${id.substring(0, id.length < 8 ? id.length : 8)} · ${l['cliente'] ?? '—'}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('Criado em ${dataHoraLisboa(l['criado_em'])} · status ${l['status']}',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                const SizedBox(height: 6),
                                Text(acertado
                                    ? 'Acertado (${l['acertado_via']})'
                                    : 'Falta cobrar: ${_eur(l['devido_cents'])}'),
                                Text('MB Way: ${estadoDiferencaTexto(l['estado'] as String?)} · tentativas: ${l['tentativas'] ?? 0}'),
                                if (!acertado && l['payment_method'] == 'mbway' && l['estado'] != 'pago')
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      key: Key('reenviar_$id'),
                                      onPressed: _aEnviar.contains(id) ? null : () => _reenviar(id),
                                      icon: const Icon(Icons.send_to_mobile),
                                      label: Text(_aEnviar.contains(id) ? 'Enviando…' : 'Reenviar pedido MB Way'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
