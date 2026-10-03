import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

/// Modelo a partir de 01/10/2026 (missão fecho-mensal-2026-09, B6A): o
/// estafeta fatura a parte dele com recibo verde; a Bora cobra por conta dele.
///
/// Dois cartões no topo do ecrã do estafeta, ambos só com o que o servidor diz:
///  1. NIF + "tenho atividade aberta nas Finanças" (`driver_fiscal_status_get`
///     / `driver_confirm_fiscal_activity`). Aviso durante 14 dias; depois do
///     prazo o estafeta não fica online até confirmar ([DriverFiscalGate]).
///  2. Recibo verde do mês anterior (`driver_monthly_invoice_summary`): total a
///     faturar, n.º de entregas, texto pronto a copiar e "Já passei o recibo"
///     (`driver_mark_invoice_issued`). Só a partir do mês de outubro de 2026.
///
/// Textos em PT-PT. Falha aberta: sem rede os cartões não aparecem e nada bloqueia.
class DriverFiscalGate {
  DriverFiscalGate._();

  /// true só quando o servidor diz que o prazo passou e falta NIF/atividade.
  static Future<bool> bloqueado() async {
    try {
      final r = await Supabase.instance.client.rpc('driver_fiscal_status_get');
      return r is Map && r['bloqueado'] == true;
    } catch (_) {
      return false;
    }
  }
}

class DriverFiscalCard extends StatefulWidget {
  const DriverFiscalCard({super.key});

  @override
  State<DriverFiscalCard> createState() => _DriverFiscalCardState();
}

class _DriverFiscalCardState extends State<DriverFiscalCard> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _fiscal;
  Map<String, dynamic>? _recibo;
  late final int _anoRef;
  late final int _mesRef;

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    final ant = DateTime(agora.year, agora.month - 1, 1);
    _anoRef = ant.year;
    _mesRef = ant.month;
    _carregar();
  }

  static double _n(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static String _eur(dynamic v) =>
      '${_n(v).toStringAsFixed(2).replaceAll('.', ',')} €';

  Future<void> _carregar() async {
    if (_sb.auth.currentUser == null) return;
    try {
      final f = await _sb.rpc('driver_fiscal_status_get');
      Map<String, dynamic>? rec;
      // O recibo verde começa com o mês de outubro de 2026.
      if (!DateTime(_anoRef, _mesRef).isBefore(DateTime(2026, 10))) {
        final s = await _sb.rpc('driver_monthly_invoice_summary',
            params: {'p_year': _anoRef, 'p_month': _mesRef});
        final lista = s is Map ? s['estafetas'] : null;
        if (lista is List && lista.isNotEmpty && lista.first is Map) {
          rec = Map<String, dynamic>.from(lista.first as Map);
        }
      }
      if (!mounted) return;
      setState(() {
        _fiscal = f is Map ? Map<String, dynamic>.from(f) : null;
        _recibo = rec;
      });
    } catch (e) {
      debugPrint('[DriverFiscalCard] $e');
    }
  }

  Future<void> _confirmarFiscal() async {
    final ctrl = TextEditingController(text: (_fiscal?['nif'] ?? '').toString());
    bool atividade = false;
    String? erro;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('NIF e atividade nas Finanças'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 9,
                decoration: InputDecoration(labelText: 'NIF', errorText: erro),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: atividade,
                onChanged: (v) => setD(() => atividade = v ?? false),
                title: const Text(
                    'Tenho atividade aberta nas Finanças (trabalhador independente)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.length != 9) {
                  setD(() => erro = 'O NIF tem 9 dígitos');
                  return;
                }
                if (!atividade) {
                  setD(() => erro = 'Confirme que tem atividade aberta');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await _sb.rpc('driver_confirm_fiscal_activity',
          params: {'p_nif': ctrl.text});
      if (!mounted) return;
      setState(() => _fiscal = r is Map ? Map<String, dynamic>.from(r) : _fiscal);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados fiscais confirmados. Obrigado!')));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('nif_invalido')
          ? 'Esse NIF não é válido. Confirme os 9 dígitos.'
          : 'Não foi possível gravar. Tente outra vez.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _marcarRecibo() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Já passei o recibo'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(labelText: 'N.º do recibo verde (ex.: FR ATSIRE01FR/12)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await _sb.rpc('driver_mark_invoice_issued', params: {
        'p_year': _anoRef,
        'p_month': _mesRef,
        'p_numero': ctrl.text.trim(),
      });
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível gravar. Tente outra vez.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _fiscal;
    final r = _recibo;
    final mostrarFiscal = f != null && f['mostrar_aviso'] == true;
    final mostrarRecibo = r != null && r['recibo_passado'] != true;
    if (!mostrarFiscal && !mostrarRecibo) return const SizedBox.shrink();
    return Column(
      children: [
        if (mostrarFiscal)
          Card(
            color: f['bloqueado'] == true ? Colors.red.shade50 : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f['bloqueado'] == true
                        ? 'Falta o seu NIF e a atividade nas Finanças'
                        : 'A partir de 1 de outubro passa a faturar a sua parte',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    f['bloqueado'] == true
                        ? 'Enquanto não confirmar, não pode aceitar entregas.'
                        : 'Confirme o seu NIF e que tem atividade aberta nas Finanças. '
                            'Tem ${f['dias_restantes']} dia(s) (até ${f['prazo']}); depois disso não poderá aceitar entregas.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _confirmarFiscal,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Confirmar NIF e atividade'),
                  ),
                ],
              ),
            ),
          ),
        if (mostrarRecibo)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recibo verde do mês passado',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(_eur(r['total_a_faturar']),
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary)),
                  Text('${r['entregas']} entregas · cliente: consumidor final · ${r['iva']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 8),
                  SelectableText('${r['texto_recibo']}',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: '${r['texto_recibo']}'));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Texto copiado.')));
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar texto'),
                      ),
                      FilledButton(
                        onPressed: _marcarRecibo,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        child: const Text('Já passei o recibo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
