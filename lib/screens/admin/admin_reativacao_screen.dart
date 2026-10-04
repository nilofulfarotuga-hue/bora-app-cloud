// Clientes parados — reativação (ronda 04/10/2026, agente admin-geral).
// Como a Uber/Glovo: todos os dias, UM push a quem não pede há N dias, no
// máximo 1 a cada 30 dias por pessoa (cron reativacao-clientes-parados →
// reativacao_processar → Edge push-clientes-alvo). Nasce DESLIGADO.
// Aqui o Danilo liga/desliga, muda os dias e o texto e vê quantos receberam e
// quantos voltaram a pedir (até 14 dias depois do push).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminReativacaoScreen extends StatefulWidget {
  const AdminReativacaoScreen({super.key});

  @override
  State<AdminReativacaoScreen> createState() => _AdminReativacaoScreenState();
}

class _AdminReativacaoScreenState extends State<AdminReativacaoScreen> {
  Map<String, dynamic>? _d;
  bool _loading = true;
  bool _salvando = false;
  String? _error;
  bool _ligada = false;
  bool _soOptIn = true;
  final _dias = TextEditingController();
  final _titulo = TextEditingController();
  final _texto = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dias.dispose();
    _titulo.dispose();
    _texto.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await Supabase.instance.client.rpc('admin_reativacao_resumo');
      if (!mounted) return;
      final d = Map<String, dynamic>.from(res as Map);
      setState(() {
        _d = d;
        _ligada = d['ligada'] == true;
        _soOptIn = d['so_opt_in'] != false;
        _dias.text = '${d['dias'] ?? 14}';
        _titulo.text = '${d['titulo'] ?? ''}';
        _texto.text = '${d['texto'] ?? ''}';
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminReativacao] $e');
      if (!mounted) return;
      setState(() {
        _error = 'Não consegui carregar a reativação.';
        _loading = false;
      });
    }
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    final dias = int.tryParse(_dias.text.trim());
    final messenger = ScaffoldMessenger.of(context);
    if (dias == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Dias tem de ser um número.')));
      return;
    }
    if (_ligada && (_d?['ligada'] != true)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ligar a reativação?'),
          content: Text(
              'A partir de hoje (às ~18h de Lisboa), quem não pede há $dias dias '
              'recebe um push. Agora seriam ${_d?['candidatos_agora'] ?? '?'} pessoa(s)'
              '${_soOptIn ? ' (só quem aceitou promoções)' : ''}.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ligar')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _salvando = true);
    try {
      final res = await Supabase.instance.client
          .rpc('admin_reativacao_configurar', params: {
        'p_ligada': _ligada,
        'p_dias': dias,
        'p_titulo': _titulo.text.trim(),
        'p_texto': _texto.text.trim(),
        'p_so_opt_in': _soOptIn,
      });
      if (!mounted) return;
      final m = (res is Map) ? res : const {};
      messenger.showSnackBar(SnackBar(
          content: Text(m['ok'] == true
              ? 'Gravado.'
              : (m['erro']?.toString() ?? 'Não consegui gravar.'))));
      if (m['ok'] == true) await _load();
    } catch (e) {
      debugPrint('[AdminReativacao] salvar: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui gravar.')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _numero(String rotulo, Object? v) => Expanded(
        child: Card(
          color: AppColors.card,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text('${v ?? 0}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(rotulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final ultimos = ((d?['ultimos'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Clientes parados (reativação)',
        actions: [
          AdminCsvButton(
            nome: 'reativacao_envios',
            colunas: const [
              ('enviado_em', 'enviado (Lisboa)'),
              ('cliente', 'cliente'),
              ('dias_parado', 'dias parado'),
              ('voltou_em', 'voltou (Lisboa)'),
              ('voltou_order_id', 'pedido'),
            ],
            linhas: () => ultimos,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(children: [
                      _numero('parados agora\n(receberiam hoje)',
                          d?['candidatos_agora']),
                      _numero('enviados\n(30 dias)', d?['enviados_30d']),
                      _numero('voltaram a pedir\n(30 dias)', d?['voltaram_30d']),
                    ]),
                    Text(
                      'Total desde o início: ${d?['enviados_total'] ?? 0} enviados, '
                      '${d?['voltaram_total'] ?? 0} voltaram a pedir.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Reativação ligada'),
                      subtitle: const Text(
                          'Um push por dia (~18h de Lisboa) a quem está parado.'),
                      value: _ligada,
                      onChanged: (v) => setState(() => _ligada = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Só quem aceitou promoções'),
                      subtitle: const Text(
                          'Regra de 23/09: comunicação comercial só com consentimento.'),
                      value: _soOptIn,
                      onChanged: (v) => setState(() => _soOptIn = v),
                    ),
                    TextField(
                      controller: _dias,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Dias sem pedir',
                        helperText:
                            'A mesma pessoa só recebe outro passados ${d?['intervalo_dias'] ?? 30} dias.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titulo,
                      maxLength: 100,
                      decoration: const InputDecoration(
                          labelText: 'Título do push (PT-PT)'),
                    ),
                    TextField(
                      controller: _texto,
                      maxLength: 300,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Texto do push (PT-PT)'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: const Text('Salvar'),
                    ),
                    const Divider(height: 32),
                    const Text('Últimos envios',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    if (ultimos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Ainda não saiu nenhum.'),
                      ),
                    for (final u in ultimos)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          u['voltou_em'] != null
                              ? Icons.check_circle
                              : Icons.notifications_none,
                          color: u['voltou_em'] != null
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        title: Text('${u['cliente'] ?? '—'}'),
                        subtitle: Text(
                            '${dataHoraLisboa(u['enviado_em'])} · parado há ${u['dias_parado'] ?? '?'} dias'
                            '${u['voltou_em'] != null ? ' · voltou ${dataHoraLisboa(u['voltou_em'])}' : ''}'),
                      ),
                  ],
                ),
    );
  }
}
