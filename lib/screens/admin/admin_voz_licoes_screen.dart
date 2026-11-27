// LIÇÕES DA ATENDENTE DE VOZ — 27/11/2026, pedido do Danilo depois da chamada de teste:
// "tem que aprender com os erros ... cada vez se aprimorar mais".
// Painel PT-BR. Depois de cada chamada, o Opus revê a conversa (voz-cerebro op "aprender") e escreve
// lições curtas. As ATIVAS entram no roteiro da atendente em todas as chamadas seguintes. As que tocam
// em dinheiro e as de informação em falta nascem PENDENTES: o admin aprova, edita ou desliga aqui.
//
// Contratos do servidor (migração 20261127110000_voz_licoes_aprender.sql):
//   admin_voz_licoes(p_estado)                     — lista (só admin)
//   admin_voz_licao_mudar(p_id, p_estado, p_regra) — ativar/desligar/editar (auditado)
//   admin_voz_licao_nova(p_regra)                  — lição escrita pela equipe (auditado)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';

String rotuloEstadoLicao(String? e) => switch (e) {
      'ativa' => 'Ativa',
      'pendente' => 'Pendente',
      'desligada' => 'Desligada',
      _ => e ?? '—',
    };

Color _corLicao(String? e) => switch (e) {
      'ativa' => AppColors.primary,
      'pendente' => AppColors.accent,
      _ => Colors.grey,
    };

class AdminVozLicoesScreen extends StatefulWidget {
  const AdminVozLicoesScreen({super.key});

  @override
  State<AdminVozLicoesScreen> createState() => _AdminVozLicoesScreenState();
}

class _AdminVozLicoesScreenState extends State<AdminVozLicoesScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _lista = const [];
  bool _carregando = true;
  String? _erro;
  String _filtro = ''; // '' = todas · 'pendente' · 'ativa' · 'desligada'

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await _sb.rpc('admin_voz_licoes', params: {'p_estado': _filtro.isEmpty ? null : _filtro});
      if (!mounted) return;
      setState(() {
        _lista = (res is List ? res : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar as lições: $e';
        _carregando = false;
      });
    }
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _mudar(Map<String, dynamic> l, {String? estado, String? regra}) async {
    try {
      await _sb.rpc('admin_voz_licao_mudar', params: {'p_id': l['id'], 'p_estado': estado, 'p_regra': regra});
      _aviso(estado == 'ativa'
          ? 'Lição ativada: entra nas próximas chamadas.'
          : estado == 'desligada'
              ? 'Lição desligada.'
              : 'Lição salva.');
      await _carregar();
    } catch (e) {
      _aviso('Não foi possível salvar: $e');
    }
  }

  /// Caixa de texto para editar ou criar uma lição. Devolve o texto ou null (cancelado).
  Future<String?> _pedirTexto({required String titulo, String inicial = ''}) {
    final ctl = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctl,
          maxLines: 5,
          maxLength: 400,
          decoration: const InputDecoration(
            hintText: 'Ex.: Quando a pessoa der um e-mail, repita devagar para confirmar.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
  }

  Future<void> _editar(Map<String, dynamic> l) async {
    final t = await _pedirTexto(titulo: 'Editar lição', inicial: '${l['regra'] ?? ''}');
    if (t == null || t.length < 10) return;
    await _mudar(l, regra: t);
  }

  Future<void> _nova() async {
    final t = await _pedirTexto(titulo: 'Nova lição para a atendente');
    if (t == null || t.length < 10) return;
    try {
      await _sb.rpc('admin_voz_licao_nova', params: {'p_regra': t});
      _aviso('Lição criada e ativa: entra nas próximas chamadas.');
      await _carregar();
    } catch (e) {
      _aviso('Não foi possível criar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ativas = _lista.where((l) => l['estado'] == 'ativa').length;
    final pendentes = _lista.where((l) => l['estado'] == 'pendente').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lições da atendente'),
        actions: [IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _carregar)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nova,
        icon: const Icon(Icons.add),
        label: const Text('Nova lição'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Depois de cada chamada, a IA (Opus) revê a conversa e escreve o que a atendente deve '
                  'fazer melhor. As lições ATIVAS entram em todas as chamadas seguintes (até 40, as mais '
                  'repetidas primeiro). As que falam de dinheiro e as de informação que faltou ficam '
                  'PENDENTES até alguém da equipe aprovar.',
                ),
              ),
            ),
            if (!_carregando && _erro == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('$ativas ativas · $pendentes pendentes · ${_lista.length} no total'),
              ),
            Wrap(
              spacing: 8,
              children: [
                for (final f in const [('', 'Todas'), ('pendente', 'Pendentes'), ('ativa', 'Ativas'), ('desligada', 'Desligadas')])
                  ChoiceChip(
                    label: Text(f.$2),
                    selected: _filtro == f.$1,
                    onSelected: (_) {
                      setState(() => _filtro = f.$1);
                      _carregar();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_carregando) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (!_carregando && _erro != null) Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)),
            if (!_carregando && _erro == null && _lista.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma lição ainda. Elas aparecem depois das primeiras chamadas.'),
              ),
            for (final l in _lista) _cartao(l),
          ],
        ),
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> l) {
    final estado = l['estado'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Chip(
                label: Text(rotuloEstadoLicao(estado), style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: _corLicao(estado),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Chip(
                label: Text(l['tipo'] == 'conhecimento' ? 'Informação em falta' : 'Comportamento',
                    style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Text('${l['vezes'] ?? 1}x', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
            const SizedBox(height: 4),
            Text('${l['regra'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((l['motivo'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Por quê: ${l['motivo']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            Text(
              '${l['origem'] == 'admin' ? 'Escrita pela equipe' : 'Aprendida numa chamada'} · '
              '${dataHoraLisboa(l['criado_em'])}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (estado != 'ativa')
                FilledButton.icon(
                  onPressed: () => _mudar(l, estado: 'ativa'),
                  icon: const Icon(Icons.check),
                  label: Text(estado == 'pendente' ? 'Aprovar' : 'Ativar'),
                ),
              if (estado != 'desligada')
                OutlinedButton.icon(
                  onPressed: () => _mudar(l, estado: 'desligada'),
                  icon: const Icon(Icons.block),
                  label: const Text('Desligar'),
                ),
              OutlinedButton.icon(
                onPressed: () => _editar(l),
                icon: const Icon(Icons.edit),
                label: const Text('Editar'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
