import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Saúde da Web (PT-BR) — missão endereco-web-2026-08-31.
///
/// Mostra os eventos de falha registrados pela app web em `web_health_events`
/// (autocomplete de endereço que morreu, geocode manual sem coordenadas,
/// script do Google bloqueado…). Antes disso, esses problemas só se
/// descobriam por telefonema de cliente perdido.
class AdminWebHealthScreen extends StatefulWidget {
  const AdminWebHealthScreen({super.key});

  @override
  State<AdminWebHealthScreen> createState() => _AdminWebHealthScreenState();
}

class _AdminWebHealthScreenState extends State<AdminWebHealthScreen> {
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _eventos = const [];

  /// Filtro por período, em dias (1 = hoje, 7, 30).
  int _dias = 7;

  static const Map<String, String> _motivoLabel = {
    'script_bloqueado': 'Script do Google bloqueado',
    'timeout_sdk': 'Google demorou demais (timeout)',
    'sem_resultados': 'Busca sem resultados',
    'geocode_manual_falhou': 'Endereço manual sem coordenadas',
    'proxy_falhou': 'Plano B (servidor) falhou',
  };

  static const Map<String, IconData> _motivoIcone = {
    'script_bloqueado': Icons.block,
    'timeout_sdk': Icons.hourglass_bottom,
    'sem_resultados': Icons.search_off,
    'geocode_manual_falhou': Icons.location_off,
    'proxy_falhou': Icons.cloud_off,
  };

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final desde =
          DateTime.now().subtract(Duration(days: _dias)).toUtc().toIso8601String();
      final rows = await Supabase.instance.client
          .from('web_health_events')
          .select()
          .gte('criado_em', desde)
          .order('criado_em', ascending: false)
          .limit(300);
      if (!mounted) return;
      setState(() {
        _eventos = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não consegui carregar os eventos: $e';
        _loading = false;
      });
    }
  }

  Map<String, int> get _contagemPorMotivo {
    final out = <String, int>{};
    for (final e in _eventos) {
      final m = e['motivo']?.toString() ?? '?';
      out[m] = (out[m] ?? 0) + 1;
    }
    return out;
  }

  String _formatarData(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    String dois(int v) => v.toString().padLeft(2, '0');
    return '${dois(dt.day)}/${dois(dt.month)} ${dois(dt.hour)}:${dois(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saúde da Web')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Falhas do campo de endereço e do carregamento do Google na '
              'web, registradas direto do navegador dos clientes.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final opcao in const [(1, 'Hoje'), (7, '7 dias'), (30, '30 dias')])
                  ChoiceChip(
                    label: Text(opcao.$2),
                    selected: _dias == opcao.$1,
                    onSelected: (_) {
                      setState(() => _dias = opcao.$1);
                      _carregar();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ))
            else if (_erro != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_erro!, style: const TextStyle(color: Colors.red)),
                ),
              )
            else if (_eventos.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nenhuma falha registrada neste período. 🎉'),
                ),
              )
            else ...[
              // Resumo por motivo
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_eventos.length} eventos no período',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      for (final entrada in _contagemPorMotivo.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(_motivoIcone[entrada.key] ?? Icons.error_outline,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(
                                      _motivoLabel[entrada.key] ?? entrada.key)),
                              Text('${entrada.value}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final e in _eventos)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      _motivoIcone[e['motivo']] ?? Icons.error_outline,
                      color: Colors.orange,
                    ),
                    title: Text(
                        _motivoLabel[e['motivo']] ?? e['motivo'].toString()),
                    subtitle: Text([
                      if (e['ecra'] != null) 'Campo: ${e['ecra']}',
                      if (e['plataforma'] != null) e['plataforma'].toString(),
                      if (e['user_id'] != null)
                        'user ${e['user_id'].toString().substring(0, 8)}…'
                      else
                        'sem login',
                      if (e['detalhe'] != null) e['detalhe'].toString(),
                    ].join(' · ')),
                    trailing: Text(_formatarData(e['criado_em']?.toString()),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
