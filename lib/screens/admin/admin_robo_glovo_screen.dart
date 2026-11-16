import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/auth_admin_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Robô Glovo das farmácias (PT-BR) — missão noite-farmacia-17-11, 1.1.
///
/// Às 07:30 e às 14:00 (Lisboa) o servidor lê as lojas da Glovo da Farmácia da Sé e da
/// Farmácia Teixeira e copia para o Bora o PREÇO e o ESGOTADO. Não pisa o que a farmácia
/// mudou à mão no painel, nunca troca fotos já existentes e, se ler menos de 80% dos
/// produtos, não muda nada e avisa no Telegram.
///
/// Fonte: RPCs `admin_robo_glovo_estado`, `admin_robo_glovo_ligar` e `admin_robo_glovo_agora`.
class AdminRoboGlovoScreen extends StatefulWidget {
  const AdminRoboGlovoScreen({super.key, this.carregar});

  /// Para testes: substitui a leitura do servidor.
  final Future<Map<String, dynamic>> Function()? carregar;

  @override
  State<AdminRoboGlovoScreen> createState() => _AdminRoboGlovoScreenState();
}

class _AdminRoboGlovoScreenState extends State<AdminRoboGlovoScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _ocupado = false;

  Future<Map<String, dynamic>> _load() async {
    if (widget.carregar != null) return widget.carregar!();
    final res = await Supabase.instance.client.rpc('admin_robo_glovo_estado');
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _ligar(bool v) async {
    setState(() => _ocupado = true);
    try {
      await Supabase.instance.client.rpc('admin_robo_glovo_ligar', params: {'p_ligado': v});
      _aviso(v ? 'Robô ligado.' : 'Robô desligado: não lê mais a Glovo até ligar de novo.');
    } catch (e) {
      _aviso('Erro: $e');
    }
    if (mounted) setState(() => _ocupado = false);
    await _refresh();
  }

  Future<void> _agora() async {
    setState(() => _ocupado = true);
    try {
      final n = await Supabase.instance.client.rpc('admin_robo_glovo_agora');
      _aviso((n is int && n > 0)
          ? 'Leitura começou ($n farmácia${n == 1 ? '' : 's'}). Leva uns 5 minutos por farmácia.'
          : 'Já havia uma leitura a correr.');
    } catch (e) {
      _aviso('Erro: $e');
    }
    if (mounted) setState(() => _ocupado = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.carregar == null && !AuthAdminService.isAdmin()) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: 'Robô Glovo das farmácias'),
        body: Center(child: Text('Acesso negado.')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Robô Glovo das farmácias',
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(12), children: [
                Text('Erro a carregar (admin_robo_glovo_estado): ${snap.error}'),
              ]);
            }
            final d = snap.data ?? const {};
            final ligado = d['ligado'] == true;
            final corridas = (d['corridas'] is List)
                ? [for (final c in d['corridas'] as List) Map<String, dynamic>.from(c as Map)]
                : const <Map<String, dynamic>>[];
            final aCorrer = corridas.any((c) => c['estado'] == 'a_correr');
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Às 07:30 e às 14:00 (hora de Lisboa) o servidor lê as lojas da Glovo da '
                  'Farmácia da Sé e da Farmácia Teixeira e copia para o Bora o preço e o esgotado. '
                  'O que a farmácia mudar à mão no painel dela fica como ela pôs. '
                  'Fotos já existentes nunca são trocadas. Se a leitura trouxer menos de 80% '
                  'dos produtos, nada é mudado e chega um aviso no Telegram.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
                  child: SwitchListTile(
                    key: const Key('robo_glovo_ligado'),
                    title: Text(ligado ? 'Robô ligado' : 'Robô desligado'),
                    subtitle: Text(ligado
                        ? 'Lê a Glovo 2 vezes por dia.'
                        : 'Não lê a Glovo. Os preços ficam como estão.'),
                    value: ligado,
                    onChanged: _ocupado ? null : _ligar,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('robo_glovo_agora'),
                  onPressed: (_ocupado || !ligado || aCorrer) ? null : _agora,
                  icon: const Icon(Icons.sync),
                  label: Text(aCorrer ? 'A ler a Glovo…' : 'Atualizar agora'),
                ),
                const SizedBox(height: 16),
                Text(
                  corridas.isEmpty ? 'Ainda não houve leituras.' : 'Últimas leituras',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final c in corridas) RoboGlovoCorridaCard(corrida: c),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Uma leitura do robô: estado, contagens e exemplos do que mudou.
class RoboGlovoCorridaCard extends StatelessWidget {
  const RoboGlovoCorridaCard({super.key, required this.corrida});
  final Map<String, dynamic> corrida;

  static const _lojas = {
    'farmacia-se-guarda': 'Farmácia da Sé',
    'farmacia-teixeira-guarda': 'Farmácia Teixeira',
  };

  @override
  Widget build(BuildContext context) {
    final c = corrida;
    final estado = '${c['estado']}';
    final (rotulo, cor, icone) = switch (estado) {
      'ok' => ('Concluída', AppColors.success, Icons.check_circle_outline),
      'a_correr' => ('A correr', Colors.blue, Icons.sync),
      'abortada' => ('Não aplicada (leitura incompleta)', Colors.orange, Icons.warning_amber),
      _ => ('Erro', AppColors.error, Icons.error_outline),
    };
    final ex = (c['exemplos'] is Map) ? Map<String, dynamic>.from(c['exemplos'] as Map) : const <String, dynamic>{};
    List<Map<String, dynamic>> lista(String k) =>
        (ex[k] is List) ? [for (final e in ex[k] as List) Map<String, dynamic>.from(e as Map)] : const [];
    String n(Object? v) => v == null ? '—' : '$v';
    final linhas = <String>[
      if (estado == 'a_correr' && c['categorias'] != null)
        'Categoria ${n(c['categoria_atual'])} de ${n(c['categorias'])} · ${n(c['lidos'])} produtos lidos',
      if (estado != 'a_correr')
        'Lidos ${n(c['lidos'])} de ${n(c['conhecidos'])} conhecidos (${n(c['cobertura'])}%) · '
            '${n(c['pedidos_glovo'])} pedidos à Glovo',
      if (estado == 'ok')
        'Preço mudou: ${n(c['mudou_preco'])} · esgotou: ${n(c['esgotou'])} · voltou: ${n(c['voltou'])} · '
            'novos: ${n(c['novos'])} · mudados à mão (não mexi): ${n(c['mao'])} · '
            'saltos suspeitos (não apliquei): ${n(c['suspeitos'])}',
      if (c['erro'] != null) 'Nota: ${c['erro']}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: cor),
      ),
      child: ExpansionTile(
        leading: Icon(icone, color: cor),
        title: Text('${_lojas[c['loja']] ?? c['loja']} · ${dataHoraLisboa(c['iniciada_em'])}'),
        subtitle: Text(
          '$rotulo · ${c['origem'] == 'manual' ? 'pedida no painel' : 'agendada'}\n${linhas.join('\n')}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in lista('precos'))
                  Text('Preço: ${p['nome']} — € ${p['de']} → € ${p['para']}', style: const TextStyle(fontSize: 12)),
                for (final p in lista('esgotados'))
                  Text('Esgotado: ${p['nome']} (${p['porque']})', style: const TextStyle(fontSize: 12)),
                for (final p in lista('voltaram'))
                  Text('Voltou à venda: ${p['nome']}', style: const TextStyle(fontSize: 12)),
                for (final p in lista('novos'))
                  Text('Novo: ${p['nome']} — € ${p['preco']} (${p['categoria']})', style: const TextStyle(fontSize: 12)),
                for (final p in lista('suspeitos'))
                  Text('Suspeito (não aplicado): ${p['nome']} — € ${p['base']} na Bora, € ${p['glovo']} na Glovo',
                      style: const TextStyle(fontSize: 12, color: Colors.orange)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
