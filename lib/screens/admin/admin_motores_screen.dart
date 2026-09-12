// Missão 02/09/2026 (noite) — MOTORES: o roteador "Motor Bora" no painel admin (PT-BR).
// Lê `motor_estado` (uma linha por fornecedor, escrita pelo roteador de 20 em 20 s: quota gasta hoje,
// latência mediana, castigado, último erro) e `motor_chamadas` (o log). O botão "Pausar" escreve
// `motor_estado.pausado` — o roteador lê a coluna no próximo ciclo e deixa de usar o fornecedor.
// Chaves NUNCA aparecem aqui (só "tem chave: sim/não").

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminMotoresScreen extends StatefulWidget {
  const AdminMotoresScreen({super.key});

  @override
  State<AdminMotoresScreen> createState() => _AdminMotoresScreenState();
}

class _AdminMotoresScreenState extends State<AdminMotoresScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _motores = [];
  List<Map<String, dynamic>> _chamadas = [];
  bool _loading = false;
  String? _erro;

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
      final m = await _supabase
          .from('motor_estado')
          .select('fornecedor, dados, pausado, updated_at')
          .order('fornecedor');
      final c = await _supabase
          .from('motor_chamadas')
          .select('maquina, perfil, fornecedor, modelo, ok, latencia_ms, tokens, erro, created_at')
          .order('created_at', ascending: false)
          .limit(120);
      setState(() {
        _motores = List<Map<String, dynamic>>.from(m);
        _chamadas = List<Map<String, dynamic>>.from(c);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pausar(Map<String, dynamic> m, bool pausar) async {
    try {
      await _supabase
          .from('motor_estado')
          .update({'pausado': pausar})
          .eq('fornecedor', m['fornecedor']);
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pausar
            ? '${m['fornecedor']} pausado — o roteador deixa de o usar no próximo ciclo (20 s).'
            : '${m['fornecedor']} retomado.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  String _quando(dynamic v) => (v ?? '—').toString().replaceFirst('T', ' ').split('.').first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Motores (roteador grátis)',
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _resumo(),
                    const SizedBox(height: 8),
                    ..._motores.map(_cartao),
                    const SizedBox(height: 16),
                    const Text('Últimas chamadas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 6),
                    ..._chamadas.take(60).map(_linhaChamada),
                  ],
                ),
    );
  }

  Widget _resumo() {
    final comChave = _motores.where((m) => (m['dados'] as Map?)?['chave'] == true).length;
    final castigados = _motores.where((m) => (m['dados'] as Map?)?['castigado_ate'] != null).length;
    final pausados = _motores.where((m) => m['pausado'] == true).length;
    final ok = _chamadas.where((c) => c['ok'] == true).length;
    final lat = _chamadas.where((c) => c['ok'] == true && c['latencia_ms'] != null).map((c) => (c['latencia_ms'] as num).toInt()).toList()..sort();
    final mediana = lat.isEmpty ? '—' : '${lat[lat.length ~/ 2]} ms';
    final p95 = lat.isEmpty ? '—' : '${lat[((lat.length * 0.95).ceil() - 1).clamp(0, lat.length - 1)]} ms';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            _kv('Fornecedores com chave', '$comChave / ${_motores.length}'),
            _kv('Castigados agora', '$castigados'),
            _kv('Pausados por você', '$pausados'),
            _kv('Últimas chamadas OK', '$ok / ${_chamadas.length}'),
            _kv('Latência mediana', mediana),
            _kv('p95', p95),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      );

  Widget _cartao(Map<String, dynamic> m) {
    final d = Map<String, dynamic>.from((m['dados'] as Map?) ?? {});
    final hoje = Map<String, dynamic>.from((d['hoje'] as Map?) ?? {});
    final temChave = d['chave'] == true;
    final pausado = m['pausado'] == true;
    final castigado = d['castigado_ate'] != null;
    final cor = pausado
        ? AppColors.textSubtle
        : (!temChave ? AppColors.textSubtle : (castigado ? AppColors.accent : AppColors.primary));
    final estado = pausado
        ? 'PAUSADO por você'
        : (!temChave ? 'sem chave' : (castigado ? 'castigado até ${_quando(d['castigado_ate'])}' : 'disponível'));
    final lat = d['latencia_mediana_ms'];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cor.withValues(alpha: 0.15),
          child: Icon(pausado ? Icons.pause : (castigado ? Icons.hourglass_bottom : Icons.bolt), color: cor, size: 20),
        ),
        title: Text('${m['fornecedor']} · $estado', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'hoje: ${hoje['pedidos'] ?? 0} pedidos (${hoje['ok'] ?? 0} ok, ${hoje['falhas'] ?? 0} falhas) · ${hoje['tokens'] ?? 0} tokens'
          ' · último minuto: ${d['ultimo_minuto'] ?? 0} · latência: ${lat == null ? '—' : '$lat ms'}'
          '${d['castigo_motivo'] != null ? '\ncastigo: ${d['castigo_motivo']}' : ''}'
          '${d['ultimo_erro'] != null ? '\núltimo erro: ${d['ultimo_erro']}' : ''}'
          '${d['nota'] != null ? '\n${d['nota']}' : ''}',
        ),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: () => _pausar(m, !pausado),
          child: Text(pausado ? 'Retomar' : 'Pausar'),
        ),
      ),
    );
  }

  Widget _linhaChamada(Map<String, dynamic> c) {
    final ok = c['ok'] == true;
    return ListTile(
      dense: true,
      leading: Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: ok ? AppColors.primary : AppColors.error),
      title: Text('${c['fornecedor']}:${c['modelo']} · ${c['perfil'] ?? '—'} · ${c['latencia_ms'] ?? 0} ms · ${c['maquina'] ?? ''}'),
      subtitle: Text('${_quando(c['created_at'])}${c['erro'] != null ? ' · ${c['erro']}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
