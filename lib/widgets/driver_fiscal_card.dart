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
    final r = await confirmarNifEAtividade(context,
        nifAtual: (_fiscal?['nif'] ?? '').toString());
    if (r != null && mounted) setState(() => _fiscal = r);
  }

  Future<void> _marcarRecibo() async {
    if (await marcarReciboPassado(context, ano: _anoRef, mes: _mesRef)) {
      await _carregar();
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
          DriverReciboCard(recibo: r, onMarcar: _marcarRecibo),
      ],
    );
  }
}

/// Missão m2 (08/11/2026): o diálogo "NIF e atividade nas Finanças", para o
/// cartão acima e para o ecrã "A minha conta". Devolve o estado fiscal novo
/// do servidor, ou null se a pessoa cancelou / não gravou.
Future<Map<String, dynamic>?> confirmarNifEAtividade(BuildContext context,
    {String? nifAtual}) async {
  final sb = Supabase.instance.client;
  final ctrl = TextEditingController(text: nifAtual ?? '');
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
  // Sem dispose: o diálogo ainda anima a sair com o campo montado.
  if (ok != true) return null;
  final nif = ctrl.text;
  try {
    final r = await sb.rpc('driver_confirm_fiscal_activity',
        params: {'p_nif': nif});
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados fiscais confirmados. Obrigado!')));
    return r is Map ? Map<String, dynamic>.from(r) : null;
  } catch (e) {
    if (!context.mounted) return null;
    final msg = e.toString().contains('nif_invalido')
        ? 'Esse NIF não é válido. Confirme os 9 dígitos.'
        : 'Não foi possível gravar. Tente outra vez.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return null;
  }
}

/// Missão m2 (08/11/2026): "Já passei o recibo" — para o cartão acima e para
/// "A minha conta". true = gravado no servidor.
Future<bool> marcarReciboPassado(BuildContext context,
    {required int ano, required int mes}) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Já passei o recibo'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(
            labelText: 'N.º do recibo verde (ex.: FR ATSIRE01FR/12)'),
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
  final numero = ctrl.text.trim();
  if (ok != true || numero.isEmpty) return false;
  try {
    await Supabase.instance.client.rpc('driver_mark_invoice_issued', params: {
      'p_year': ano,
      'p_month': mes,
      'p_numero': numero,
    });
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível gravar. Tente outra vez.')));
    }
    return false;
  }
}

/// Missão m2 (08/11/2026): o recibo verde do mês passado dentro de
/// "A minha conta" (antes vivia no ecrã dos pedidos, a aparecer com a oferta).
/// Lê `driver_monthly_invoice_summary`; sem recibo por passar não mostra nada.
class DriverReciboSecao extends StatefulWidget {
  const DriverReciboSecao({super.key, this.aoMarcar});

  /// Chamado depois de gravar "Já passei o recibo".
  final VoidCallback? aoMarcar;

  @override
  State<DriverReciboSecao> createState() => _DriverReciboSecaoState();
}

class _DriverReciboSecaoState extends State<DriverReciboSecao> {
  Map<String, dynamic>? _recibo;
  late final int _ano;
  late final int _mes;

  @override
  void initState() {
    super.initState();
    final ant = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    _ano = ant.year;
    _mes = ant.month;
    _carregar();
  }

  Future<void> _carregar() async {
    if (DateTime(_ano, _mes).isBefore(DateTime(2026, 10))) return;
    try {
      final s = await Supabase.instance.client.rpc(
          'driver_monthly_invoice_summary',
          params: {'p_year': _ano, 'p_month': _mes});
      final lista = s is Map ? s['estafetas'] : null;
      if (!mounted) return;
      setState(() => _recibo = (lista is List &&
              lista.isNotEmpty &&
              lista.first is Map)
          ? Map<String, dynamic>.from(lista.first as Map)
          : null);
    } catch (e) {
      debugPrint('[DriverReciboSecao] $e');
    }
  }

  Future<void> _marcar() async {
    if (await marcarReciboPassado(context, ano: _ano, mes: _mes)) {
      await _carregar();
      widget.aoMarcar?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _recibo;
    if (r == null || r['recibo_passado'] == true) return const SizedBox.shrink();
    return DriverReciboCard(recibo: r, onMarcar: _marcar);
  }
}

/// Cartão do recibo verde do mês passado.
///
/// O cliente do recibo vem do servidor (`cliente` / `cliente_nif` do
/// `driver_monthly_invoice_summary`): "Consumidor final" até outubro; a partir
/// do recibo de novembro, a Bora — e então mostra-se "Passa o recibo à Bora,
/// NIF …" com copiar. O NIF nunca está escrito na app, e o estafeta nunca vê o
/// NIF de nenhum cliente: este é o da própria Bora.
class DriverReciboCard extends StatelessWidget {
  const DriverReciboCard({
    super.key,
    required this.recibo,
    required this.onMarcar,
  });

  final Map<String, dynamic> recibo;
  final VoidCallback onMarcar;

  static String _eur(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    return '${n.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  @override
  Widget build(BuildContext context) {
    final r = recibo;
    final cliente = (r['cliente'] ?? 'Consumidor final').toString();
    final clienteNif = (r['cliente_nif'] ?? '').toString().trim();
    return Card(
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
            Text('${r['entregas']} entregas · cliente: $cliente · ${r['iva']}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (clienteNif.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('recibo_nif_bora'),
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Passa o recibo à Bora, NIF $clienteNif',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      key: const Key('recibo_copiar_nif'),
                      tooltip: 'Copiar NIF',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: clienteNif));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('NIF copiado.')));
                      },
                    ),
                  ],
                ),
              ),
            ],
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
                  onPressed: onMarcar,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Já passei o recibo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
