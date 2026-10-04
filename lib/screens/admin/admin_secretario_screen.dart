import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin (PT-BR) — Secretário Virtual (missão 03/10 · bloco 5).
///
/// Venda do assistente de WhatsApp a negócios de Portugal: os prospects que o
/// caçador encontrou (com WhatsApp no site e email verificado), o estado do
/// email, quem já testou a demo (código "TESTE 1234", 7 dias) e as conversas da
/// demo. Interruptor do envio (`secretario_envio_ligado`): desligar também
/// pausa os emails que estavam prontos para sair.
class AdminSecretarioScreen extends StatefulWidget {
  const AdminSecretarioScreen({super.key});

  @override
  State<AdminSecretarioScreen> createState() => _AdminSecretarioScreenState();
}

class _AdminSecretarioScreenState extends State<AdminSecretarioScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  bool _aMudar = false;
  String? _erro;
  Map<String, dynamic> _r = const {};

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
      final r = await _sb.rpc('admin_secretario_resumo');
      if (!mounted) return;
      setState(() {
        _r = Map<String, dynamic>.from(r as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _mudarEnvio(bool v) async {
    if (_aMudar) return;
    setState(() => _aMudar = true);
    try {
      final r = await _sb.rpc('admin_secretario_envio', params: {'p_ligado': v});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(v
              ? 'Envio ligado (${(r as Map)['propostas_mexidas']} emails voltaram à fila).'
              : 'Envio desligado (${(r as Map)['propostas_mexidas']} emails pausados).')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _aMudar = false);
    }
  }

  String _data(dynamic iso) {
    final t = iso == null ? null : DateTime.tryParse(iso.toString())?.toLocal();
    if (t == null) return '—';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final prospects =
        List<Map<String, dynamic>>.from((_r['prospects'] as List?) ?? const []);
    final testaram = prospects.where((p) => p['testou_em'] != null).toList();
    final conversas = List<Map<String, dynamic>>.from(
        (_r['conversas_demo'] as List?) ?? const []);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: BoraScreenAppBar(
          title: 'Secretário Virtual',
          actions: [
            IconButton(
                tooltip: 'Atualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _carregar),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Erro ao carregar: $_erro')))
                : Column(
                    children: [
                      SwitchListTile(
                        value: _r['envio_ligado'] == true,
                        onChanged: _aMudar ? null : _mudarEnvio,
                        title: const Text('Enviar emails do Secretário'),
                        subtitle: Text(
                            'Mesma fila do caça-clientes: até 5 novos por dia útil, 09h30–11h30, conta Bora. '
                            'Número de teste: ${_r['numero_teste'] ?? '—'}'),
                      ),
                      const TabBar(
                        labelColor: AppColors.primary,
                        tabs: [
                          Tab(text: 'Prospects'),
                          Tab(text: 'Testaram'),
                          Tab(text: 'Conversas demo'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _lista(prospects),
                            _lista(testaram),
                            ListView(
                              padding: const EdgeInsets.all(12),
                              children: [
                                if (conversas.isEmpty)
                                  const Text('Ainda ninguém falou com a demo.'),
                                for (final m in conversas)
                                  ListTile(
                                    dense: true,
                                    leading: Icon(
                                        m['direcao'] == 'entrada'
                                            ? Icons.call_received
                                            : Icons.call_made,
                                        size: 18),
                                    title: Text(m['texto']?.toString() ?? ''),
                                    subtitle: Text(
                                        '${m['numero']} · ${_data(m['em'])}'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _lista(List<Map<String, dynamic>> linhas) {
    if (linhas.isEmpty) {
      return const Center(child: Text('Nada por aqui ainda.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: linhas.length,
      itemBuilder: (_, i) {
        final p = linhas[i];
        return Card(
          child: ListTile(
            title: Text('${p['nome']} · ${p['categoria'] ?? ''}'),
            subtitle: Text([
              '${p['concelho'] ?? ''} · ${p['email'] ?? ''}',
              'Email: ${p['email_estado'] ?? 'por escrever'}'
                  '${p['enviado_em'] != null ? ' em ${_data(p['enviado_em'])}' : ''}'
                  '${p['codigo'] != null ? ' · código ${p['codigo']}' : ''}',
              if (p['testou_em'] != null)
                'Testou em ${_data(p['testou_em'])} (${p['numero']}) · acaba ${_data(p['expira_em'])}',
              if ((p['resposta'] ?? '').toString().isNotEmpty) 'Resposta: ${p['resposta']}',
            ].join('\n')),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
