// Painel admin (PT-BR) — Recibos por viagem TVDE (fecho-manha-2026-09-24, bloco 6).
//
// Correspondência no painel para o recibo automático criado a 23/09 (missão
// motorista-ficha-legal): o passageiro recebe por email um recibo (documento simples com
// o valor pago e a taxa de intermediação da Bora; não substitui fatura) no fim de cada
// viagem. Aqui o Danilo:
//   • liga/desliga o envio automático (platform_settings.tvde_recibo_email_auto);
//   • vê os recibos já enviados (email, hora, se chegou) e o conteúdo de cada um;
//   • pede o reenvio ao passageiro (RPC admin_tvde_recibo_reenviar, auditada).
// Só leitura de viagens já finalizadas: nada aqui mexe em preços nem cobra nada.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminTvdeRecibosScreen extends StatefulWidget {
  const AdminTvdeRecibosScreen({super.key});

  @override
  State<AdminTvdeRecibosScreen> createState() => _AdminTvdeRecibosScreenState();
}

class _AdminTvdeRecibosScreenState extends State<AdminTvdeRecibosScreen> {
  final _c = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;
  bool _autoLigado = true;
  List<ReciboLinha> _linhas = const [];
  String _filtro = 'todos'; // todos | ok | falhou

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final setting = await _c
          .from('platform_settings')
          .select('value')
          .eq('key', 'tvde_recibo_email_auto')
          .maybeSingle();
      final lista = await _c.rpc('admin_tvde_recibos_listar', params: {'p_limite': 300});
      if (!mounted) return;
      setState(() {
        _autoLigado = lerBool(setting?['value'], porDefeito: true);
        _linhas = (lista as List).map((e) => ReciboLinha.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  Future<void> _gravarAuto(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _c.rpc('admin_update_setting', params: {'p_key': 'tvde_recibo_email_auto', 'p_value': v});
      messenger.showSnackBar(SnackBar(
          content: Text(v ? 'Recibo automático ligado.' : 'Recibo automático desligado: ninguém recebe até voltar a ligar.')));
      _carregar();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _reenviar(ReciboLinha r) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reenviar recibo ao passageiro?'),
        content: Text('Viagem ${r.rideId.substring(0, 8)}… · ${r.email ?? 'sem email'}\n'
            'O email volta a sair pelo mesmo caminho automático. Fica registado quem pediu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reenviar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _c.rpc('admin_tvde_recibo_reenviar', params: {'p_ride': r.rideId});
      messenger.showSnackBar(const SnackBar(content: Text('Reenvio pedido. A linha atualiza em alguns segundos.')));
      await Future<void>.delayed(const Duration(seconds: 4));
      _carregar();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao reenviar: $e')));
    }
  }

  Future<void> _ver(ReciboLinha r) async {
    try {
      final data = await _c.rpc('tvde_recibo_viagem', params: {'p_ride': r.rideId});
      if (!mounted) return;
      final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recibo da viagem'),
          content: SingleChildScrollView(
            child: SelectableText(
              m.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = filtrarRecibos(_linhas, _filtro);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recibos por viagem (TVDE)'),
        actions: [IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar')],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: SwitchListTile(
                        key: const Key('sw_recibo_auto'),
                        title: const Text('Enviar recibo por email ao passageiro no fim de cada viagem'),
                        subtitle: const Text(
                            'Chave tvde_recibo_email_auto. Desligado, nenhum recibo sai sozinho (só pelo botão Reenviar).'),
                        value: _autoLigado,
                        onChanged: _gravarAuto,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recibos enviados: ${_linhas.length} · com falha: ${_linhas.where((l) => !l.ok).length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final f in const ['todos', 'ok', 'falhou'])
                          ChoiceChip(
                            label: Text(f == 'todos' ? 'todos' : f == 'ok' ? 'enviados' : 'com falha'),
                            selected: _filtro == f,
                            onSelected: (_) => setState(() => _filtro = f),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (lista.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Nenhum recibo com este filtro.')),
                      ),
                    for (final r in lista) _linha(r),
                  ],
                ),
    );
  }

  Widget _linha(ReciboLinha r) {
    final quando = r.enviadoEm == null
        ? '—'
        : '${r.enviadoEm!.day.toString().padLeft(2, '0')}/${r.enviadoEm!.month.toString().padLeft(2, '0')} '
            '${r.enviadoEm!.hour.toString().padLeft(2, '0')}:${r.enviadoEm!.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        leading: Icon(r.ok ? Icons.mark_email_read_outlined : Icons.error_outline,
            color: r.ok ? AppColors.success : AppColors.error),
        title: Text('${r.email ?? 'sem email'} · € ${r.precoEur.toStringAsFixed(2)}'),
        subtitle: Text(
          '$quando · ${r.motorista.isEmpty ? 'motorista ?' : r.motorista}\n'
          '${r.origem} → ${r.destino}\n'
          '${r.ok ? 'enviado' : 'FALHOU'}${r.detalhe != null && r.detalhe!.isNotEmpty ? ' · ${r.detalhe}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(tooltip: 'Ver recibo', icon: const Icon(Icons.receipt_long), onPressed: () => _ver(r)),
            IconButton(tooltip: 'Reenviar ao passageiro', icon: const Icon(Icons.send), onPressed: () => _reenviar(r)),
          ],
        ),
      ),
    );
  }
}

/// Uma linha da lista admin_tvde_recibos_listar.
class ReciboLinha {
  final String rideId;
  final String? email;
  final DateTime? enviadoEm;
  final bool ok;
  final String? detalhe;
  final double precoEur;
  final String motorista;
  final String origem;
  final String destino;

  const ReciboLinha({
    required this.rideId,
    this.email,
    this.enviadoEm,
    required this.ok,
    this.detalhe,
    this.precoEur = 0,
    this.motorista = '',
    this.origem = '',
    this.destino = '',
  });

  factory ReciboLinha.fromMap(Map<String, dynamic> m) => ReciboLinha(
        rideId: (m['ride_id'] ?? '').toString(),
        email: m['email']?.toString(),
        enviadoEm: m['enviado_em'] == null ? null : DateTime.tryParse(m['enviado_em'].toString())?.toLocal(),
        ok: m['ok'] == true,
        detalhe: m['detalhe']?.toString(),
        precoEur: double.tryParse((m['preco_eur'] ?? 0).toString()) ?? 0,
        motorista: (m['motorista'] ?? '').toString(),
        origem: (m['origem'] ?? '').toString(),
        destino: (m['destino'] ?? '').toString(),
      );
}

/// Filtro da lista: todos | ok | falhou.
List<ReciboLinha> filtrarRecibos(List<ReciboLinha> todas, String filtro) {
  if (filtro == 'ok') return todas.where((r) => r.ok).toList();
  if (filtro == 'falhou') return todas.where((r) => !r.ok).toList();
  return todas;
}

/// platform_settings.value chega como jsonb: true, "true", 1 … tudo isso é "ligado".
bool lerBool(Object? v, {required bool porDefeito}) {
  if (v == null) return porDefeito;
  if (v is bool) return v;
  final s = v.toString().trim().toLowerCase().replaceAll('"', '');
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return porDefeito;
}
