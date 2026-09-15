import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora.dart';

/// PAINEL ADMIN — Papéis e candidaturas (PT-BR, só o Danilo).
///
/// Não existia para categoria nenhuma. Havia painel de estafetas, de
/// faxineiros e de lavadores, mas nenhum lugar onde se visse UMA pessoa com os
/// papéis todos dela, nem onde se acrescentasse ou tirasse um papel na mão.
///
/// Duas abas: as pessoas e as candidaturas. Aprovar e recusar chamam as
/// funções que já existiam por papel — não há decisão duplicada aqui.
class AdminPapeisScreen extends StatefulWidget {
  const AdminPapeisScreen({super.key, this.buscaInicial});

  /// Abre já filtrado por esta pessoa — é assim que se chega aqui a partir da
  /// ficha dela nas outras telas, em vez de ter de a procurar de novo.
  final String? buscaInicial;

  @override
  State<AdminPapeisScreen> createState() => _AdminPapeisScreenState();
}

class _AdminPapeisScreenState extends State<AdminPapeisScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  bool _busy = false;
  String? _erro;
  List<Map<String, dynamic>> _pessoas = const [];
  List<String> _papeisPossiveis = const [];
  List<Map<String, dynamic>> _candidaturas = const [];
  String _estadoFiltro = 'pending';
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if ((widget.buscaInicial ?? '').isNotEmpty) {
      _buscaCtrl.text = widget.buscaInicial!;
    }
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final pessoas = await _sb.rpc('admin_papeis_listar', params: {
        'p_busca': _buscaCtrl.text.trim().isEmpty ? null : _buscaCtrl.text.trim(),
        'p_limite': 200,
      });
      final cands = await _sb.rpc('admin_candidaturas_listar', params: {
        'p_estado': _estadoFiltro,
      });
      if (!mounted) return;
      final mp = (pessoas as Map).cast<String, dynamic>();
      final mc = (cands as Map).cast<String, dynamic>();
      setState(() {
        _pessoas = ((mp['itens'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _papeisPossiveis = ((mp['papeis_possiveis'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        _candidaturas = ((mc['itens'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _chamar(String rpc, Map<String, dynamic> params,
      String sucesso) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _sb.rpc(rpc, params: params);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(sucesso)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg.contains('tem_trabalho_em_curso')
            ? 'Essa pessoa tem trabalho em andamento. Feche ou reatribua antes.'
            : 'Falhou: $msg'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _darPapel(Map<String, dynamic> p) async {
    final atuais = ((p['papeis'] as List?) ?? []).map((e) => e.toString()).toSet();
    final disponiveis =
        _papeisPossiveis.where((r) => !atuais.contains(r)).toList();
    if (disponiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Essa pessoa já tem todos os papéis.')));
      return;
    }
    final escolhido = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Adicionar papel a ${p['nome']}'),
        children: [
          for (final r in disponiveis)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Text(_rotulo(r)),
            ),
        ],
      ),
    );
    if (escolhido == null) return;
    await _chamar('admin_papel_dar',
        {'p_user_id': p['user_id'], 'p_papel': escolhido},
        'Papel "${_rotulo(escolhido)}" adicionado.');
  }

  Future<void> _tirarPapel(Map<String, dynamic> p, String papel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirar papel'),
        content: Text(
          'Tirar "${_rotulo(papel)}" de ${p['nome']}?\n\n'
          'A candidatura e o histórico ficam. Só deixa de poder trabalhar '
          'nisso.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tirar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _chamar('admin_papel_tirar',
        {'p_user_id': p['user_id'], 'p_papel': papel},
        'Papel "${_rotulo(papel)}" removido.');
  }

  Future<void> _decidir(Map<String, dynamic> c, bool aprovar) async {
    final tipo = (c['tipo'] ?? '').toString();
    String motivo = '';
    if (!aprovar) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recusar candidatura'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Motivo (vai para a pessoa)',
                border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Recusar'),
            ),
          ],
        ),
      );
      motivo = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true) return;
    }

    // Cada papel decide-se pela sua própria função, que já existia e já avisa
    // o candidato. Aqui só se escolhe qual.
    switch (tipo) {
      case 'driver':
        await _chamar(
            aprovar ? 'admin_approve_driver' : 'admin_reject_driver',
            aprovar
                ? {'p_driver_id': c['id']}
                : {'p_driver_id': c['id'], 'p_reason': motivo},
            aprovar ? 'Estafeta aprovado.' : 'Estafeta recusado.');
      case 'cleaner':
        await _chamar('admin_review_cleaner', {
          'p_cleaner_id': c['id'],
          'p_action': aprovar ? 'approve' : 'reject',
          'p_reason': motivo,
        }, aprovar ? 'Faxineiro aprovado.' : 'Faxineiro recusado.');
      case 'washer':
        await _chamar('admin_rever_lavador', {
          'p_washer_id': c['id'],
          'p_accao': aprovar ? 'approve' : 'reject',
          'p_motivo': motivo,
        }, aprovar ? 'Lavador aprovado.' : 'Lavador recusado.');
      default:
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tipo desconhecido: $tipo')));
    }
  }

  static String _rotulo(String papel) => switch (papel) {
        'client' => 'Cliente',
        'driver' => 'Corridas de passageiros',
        'delivery' => 'Entregas',
        'partner' => 'Parceiro',
        'cleaner' => 'Limpeza',
        'washer' => 'Lavagem de carros',
        'admin' => 'Admin',
        _ => papel,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Papéis e candidaturas',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Pessoas'),
            Tab(text: 'Candidaturas'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Text('Erro: $_erro',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [_abaPessoas(), _abaCandidaturas()],
                ),
    );
  }

  Widget _abaPessoas() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: TextField(
              controller: _buscaCtrl,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou e-mail',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward), onPressed: _load),
              ),
            ),
          ),
          Expanded(
            child: _pessoas.isEmpty
                ? const Center(
                    child: Text('Ninguém encontrado.',
                        style: TextStyle(color: AppColors.textSubtle)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md, vertical: Spacing.sm),
                    itemCount: _pessoas.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (_, i) {
                      final p = _pessoas[i];
                      final papeis = ((p['papeis'] as List?) ?? [])
                          .map((e) => e.toString())
                          .toList();
                      return Container(
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text((p['nome'] ?? '').toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                      Text(
                                        [
                                          (p['email'] ?? '').toString(),
                                          (p['telefone'] ?? '').toString(),
                                        ]
                                            .where((s) => s.isNotEmpty)
                                            .join('  ·  '),
                                        style: const TextStyle(
                                            color: AppColors.textSubtle,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Adicionar papel',
                                  icon: const Icon(Icons.add_circle_outline,
                                      color: AppColors.primary),
                                  onPressed:
                                      _busy ? null : () => _darPapel(p),
                                ),
                              ],
                            ),
                            const SizedBox(height: Spacing.xs),
                            Wrap(
                              spacing: Spacing.xs,
                              runSpacing: 4,
                              children: [
                                for (final r in papeis)
                                  InputChip(
                                    label: Text(_rotulo(r),
                                        style: const TextStyle(fontSize: 11)),
                                    onDeleted:
                                        _busy ? null : () => _tirarPapel(p, r),
                                    deleteIcon: const Icon(Icons.close, size: 14),
                                    backgroundColor: AppColors.primaryWash,
                                  ),
                                for (final e in {
                                  'driver': p['estado_driver'],
                                  'cleaner': p['estado_cleaner'],
                                  'washer': p['estado_washer'],
                                }.entries)
                                  if (e.value != null && e.value != 'approved')
                                    Chip(
                                      label: Text(
                                        '${_rotulo(e.key)}: ${e.value}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      backgroundColor:
                                          AppColors.warning.withValues(alpha: .15),
                                    ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );

  Widget _abaCandidaturas() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                const Text('Estado:  '),
                DropdownButton<String>(
                  value: _estadoFiltro,
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pendentes')),
                    DropdownMenuItem(value: 'approved', child: Text('Aprovadas')),
                    DropdownMenuItem(value: 'rejected', child: Text('Recusadas')),
                    DropdownMenuItem(
                        value: 'suspended', child: Text('Suspensas')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _estadoFiltro = v);
                    _load();
                  },
                ),
                const Spacer(),
                Text('${_candidaturas.length}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _candidaturas.isEmpty
                ? const Center(
                    child: Text('Nenhuma candidatura nesse estado.',
                        style: TextStyle(color: AppColors.textSubtle)))
                : ListView.separated(
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: _candidaturas.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (_, i) {
                      final c = _candidaturas[i];
                      final pendente = c['estado'] == 'pending';
                      return Container(
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text((c['nome'] ?? '').toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary)),
                                ),
                                Chip(
                                  label: Text(_rotulo((c['tipo'] ?? '').toString()),
                                      style: const TextStyle(fontSize: 11)),
                                  backgroundColor: AppColors.primaryWash,
                                ),
                              ],
                            ),
                            Text(
                              [
                                (c['email'] ?? '').toString(),
                                (c['telefone'] ?? '').toString(),
                              ].where((s) => s.isNotEmpty).join('  ·  '),
                              style: const TextStyle(
                                  color: AppColors.textSubtle, fontSize: 12),
                            ),
                            if ((c['motivo'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Motivo: ${c['motivo']}',
                                    style: const TextStyle(
                                        color: AppColors.error, fontSize: 12)),
                              ),
                            if (pendente) ...[
                              const SizedBox(height: Spacing.sm),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed:
                                        _busy ? null : () => _decidir(c, false),
                                    child: const Text('Recusar',
                                        style:
                                            TextStyle(color: AppColors.error)),
                                  ),
                                  const SizedBox(width: Spacing.sm),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.primary),
                                    onPressed:
                                        _busy ? null : () => _decidir(c, true),
                                    child: const Text('Aprovar'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
}
