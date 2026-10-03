import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/address_autocomplete_field.dart';

/// Painel admin (PT-BR) — MUDAR DESTINO de uma corrida TVDE (30/09/2026).
///
/// • Histórico: todas as mudanças da corrida (RPC `admin_tvde_dest_changes`):
///   de → para, km, preço antes/depois, o que o cliente pagou a mais, o que o
///   motorista ganhou a mais, forma de pagamento e estado.
/// • Corrida de BALCÃO (cliente sem app): só o admin muda o destino, com o
///   valor novo combinado À MÃO (RPC `admin_tvde_dest_change_counter`). A
///   `tvde_finish_ride` cobra o combinado — nada de tabela.
class AdminTvdeDestChangeDialog extends StatefulWidget {
  const AdminTvdeDestChangeDialog({super.key, required this.rideId});

  final String rideId;

  static Future<void> open(BuildContext context, String rideId) => showDialog(
        context: context,
        builder: (_) => AdminTvdeDestChangeDialog(rideId: rideId),
      );

  @override
  State<AdminTvdeDestChangeDialog> createState() =>
      _AdminTvdeDestChangeDialogState();
}

class _AdminTvdeDestChangeDialogState extends State<AdminTvdeDestChangeDialog> {
  static const _vivos = {
    'solicitada',
    'motorista_atribuido',
    'motorista_a_caminho',
    'motorista_chegou',
    'em_andamento',
  };

  bool _loading = true;
  String? _erro;
  Map<String, dynamic>? _ride;
  List<Map<String, dynamic>> _changes = const [];

  final _dest = TextEditingController();
  final _valor = TextEditingController();
  final _ganho = TextEditingController();
  final _km = TextEditingController();
  final _motivo = TextEditingController();
  double? _lat;
  double? _lng;
  bool _saving = false;

  static String _eur(dynamic c) =>
      c is num ? '€${(c / 100).toStringAsFixed(2)}' : '—';
  static String _km1(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return n == null ? '—' : n.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dest.dispose();
    _valor.dispose();
    _ganho.dispose();
    _km.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final sb = Supabase.instance.client;
      final ride = await sb
          .from('tvde_rides')
          .select('id, status, source, dest_label, est_distance_km, est_fare_cents, '
              'driver_earn_cents, agreed_fare_cents, agreed_driver_earn_cents, '
              'payment_method, dest_change_count, dest_change_fee_cents, '
              'dest_change_driver_cents, dest_change_cash_cents')
          .eq('id', widget.rideId)
          .maybeSingle();
      final res = await sb
          .rpc('admin_tvde_dest_changes', params: {'p_ride_id': widget.rideId});
      final list = ((res as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _ride = ride;
        _changes = list;
        final agreed = (ride?['agreed_fare_cents'] as num?)?.toInt();
        final ganho = ((ride?['agreed_driver_earn_cents'] ??
                ride?['driver_earn_cents']) as num?)
            ?.toInt();
        if (agreed != null && _valor.text.isEmpty) {
          _valor.text = (agreed / 100).toStringAsFixed(2);
        }
        if (ganho != null && _ganho.text.isEmpty) {
          _ganho.text = (ganho / 100).toStringAsFixed(2);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _podeBalcao {
    final r = _ride;
    if (r == null) return false;
    return r['agreed_fare_cents'] != null && _vivos.contains(r['status']);
  }

  int? _cents(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  Future<void> _salvarBalcao() async {
    final valor = _cents(_valor);
    final ganho = _cents(_ganho);
    if (_lat == null || _lng == null) {
      _snack('Escolha o destino novo na lista de endereços.');
      return;
    }
    if (valor == null || valor < 0) {
      _snack('Valor combinado inválido.');
      return;
    }
    if (_motivo.text.trim().length < 3) {
      _snack('Escreva o motivo (obrigatório).');
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('admin_tvde_dest_change_counter', params: {
        'p_ride_id': widget.rideId,
        'p_dest_lat': _lat,
        'p_dest_lng': _lng,
        'p_dest_label': _dest.text.trim(),
        'p_new_agreed_fare_cents': valor,
        'p_new_agreed_driver_earn_cents': ganho,
        'p_est_distance_km': double.tryParse(_km.text.trim().replaceAll(',', '.')),
        'p_reason': _motivo.text.trim(),
      });
      _snack('Destino alterado. O motorista foi avisado.');
      _dest.clear();
      _motivo.clear();
      _lat = null;
      _lng = null;
      await _load();
    } catch (e) {
      _snack('Não foi possível alterar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _estado(String? e) => switch (e) {
        'aplicada' => 'aplicada',
        'proposta' => 'aguardando pagamento',
        'paga' => 'paga',
        'recusada' => 'recusada',
        'falhada' => 'falhou',
        _ => e ?? '—',
      };

  String _metodo(String? m) => switch (m) {
        'cash' => 'dinheiro',
        'card' => 'cartão',
        'mbway' => 'MB Way',
        'nenhum' => 'sem cobrança',
        'balcao' => 'balcão (valor combinado)',
        _ => m ?? '—',
      };

  @override
  Widget build(BuildContext context) {
    final r = _ride;
    return AlertDialog(
      title: const Text('Destino da corrida'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : _erro != null
                ? Text('Erro: $_erro',
                    style: const TextStyle(color: AppColors.error))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Destino atual: ${r?['dest_label'] ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            'Km combinados: ${_km1(r?['est_distance_km'])} · '
                            'cliente paga ${_eur(r?['agreed_fare_cents'] ?? r?['est_fare_cents'])} · '
                            'motorista ganha ${_eur(r?['agreed_driver_earn_cents'] ?? r?['driver_earn_cents'])}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        if (((r?['dest_change_fee_cents'] as num?) ?? 0) > 0)
                          Text(
                              'Mudanças: cliente +${_eur(r?['dest_change_fee_cents'])} '
                              '(dinheiro ${_eur(r?['dest_change_cash_cents'])}) · '
                              'motorista +${_eur(r?['dest_change_driver_cents'])}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        const Divider(height: 20),
                        Text('Histórico (${_changes.length})',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (_changes.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text('Nenhuma mudança de destino.',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        for (final c in _changes)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${c['old_dest_label'] ?? '—'} → ${c['new_dest_label'] ?? '—'}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(
                                    'km ${_km1(c['km_before'])} → ${_km1(c['km_new_total'])} '
                                    '(feitos ${_km1(c['km_done'])} + resto ${_km1(c['km_remaining'])}) · '
                                    'preço ${_eur(c['price_before_cents'])} → tabela ${_eur(c['price_new_cents'])}',
                                    style: const TextStyle(fontSize: 12)),
                                Text(
                                    'cliente +${_eur(c['client_diff_cents'])}'
                                    '${c['min_applied'] == true ? ' (mínimo)' : ''} · '
                                    'motorista +${_eur(c['driver_diff_cents'])} · '
                                    '${_metodo(c['method']?.toString())} · '
                                    '${_estado(c['estado']?.toString())}'
                                    '${c['motivo'] != null ? ' · ${c['motivo']}' : ''}'
                                    '${c['refunded_at'] != null ? ' · devolvido ${_eur(c['refund_cents'])} (${c['refund_motivo'] ?? ''})' : ''}',
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.textSecondary)),
                                Text('${c['created_at'] ?? ''} · por ${c['created_by_role'] ?? '—'}',
                                    style: const TextStyle(
                                        fontSize: 11, color: AppColors.textSubtle)),
                              ],
                            ),
                          ),
                        if (_podeBalcao) ...[
                          const Divider(height: 24),
                          const Text('Mudar destino (corrida de balcão)',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const Text(
                              'O cliente não tem app: combine o valor novo por telefone e escreva-o aqui.',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          AddressAutocompleteField(
                            controller: _dest,
                            labelText: 'Destino novo',
                            onSelected: (address, coords) {
                              if (coords == null) return;
                              setState(() {
                                _lat = coords.latitude;
                                _lng = coords.longitude;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _valor,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Valor combinado (€)',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _ganho,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Ganho do motorista (€)',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _km,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Km totais (opcional)',
                                border: OutlineInputBorder(),
                                isDense: true),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _motivo,
                            decoration: const InputDecoration(
                                labelText: 'Motivo (obrigatório)',
                                border: OutlineInputBorder(),
                                isDense: true),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '⚠️ ISTO MEXE EM DINHEIRO: o valor combinado é o que o cliente paga no fim. Fica registrado com o seu nome e o motivo.',
                            style: TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        if (_podeBalcao)
          FilledButton(
            onPressed: _saving ? null : _salvarBalcao,
            child: Text(_saving ? 'Salvando…' : 'Mudar destino'),
          ),
      ],
    );
  }
}
