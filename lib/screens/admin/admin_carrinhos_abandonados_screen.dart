import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin (PT-BR) — Carrinho abandonado (ronda 04/10/2026).
///
/// Como a Uber Eats e a Glovo: quem deixa produtos no carrinho e não faz o
/// pedido recebe UM push ("Ficou alguma coisa no teu carrinho 🛒") depois de
/// X minutos — no máximo 1 por carrinho e 1 por dia. Aqui o Danilo liga/desliga,
/// muda os minutos e o texto, e vê os números. Nasce DESLIGADO.
///
/// Servidor: tabela `carrinhos_abandonados`, cron `carrinhos-abandonados-15min`
/// (função `carrinhos_abandonados_avisar`), RPCs
/// `admin_carrinhos_abandonados_resumo` / `admin_carrinho_abandonado_config`.
class AdminCarrinhosAbandonadosScreen extends StatefulWidget {
  const AdminCarrinhosAbandonadosScreen({super.key});

  @override
  State<AdminCarrinhosAbandonadosScreen> createState() =>
      _AdminCarrinhosAbandonadosScreenState();
}

class _AdminCarrinhosAbandonadosScreenState
    extends State<AdminCarrinhosAbandonadosScreen> {
  final _sb = Supabase.instance.client;
  final _minutosCtrl = TextEditingController();
  final _tituloCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();

  bool _carregando = true;
  bool _aGravar = false;
  String? _erro;
  Map<String, dynamic> _r = const {};

  /// 03/11/2026: emails excluídos e avisos "loja ficou mais barata"
  /// (RPCs admin_carrinho_extras / _excluir_emails_definir / admin_loja_mais_barata_*).
  Map<String, dynamic> _extras = const {};
  final _novoEmailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _minutosCtrl.dispose();
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    _novoEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarExtras() async {
    try {
      final res = await _sb.rpc('admin_carrinho_extras');
      if (!mounted) return;
      setState(() => _extras = Map<String, dynamic>.from(res as Map));
    } catch (_) {
      // sem extras: o resto do ecrã continua a funcionar
    }
  }

  List<String> get _emailsExcluidos => [
        for (final e in (_extras['excluir_emails'] as List?) ?? const []) '$e'
      ];

  Future<void> _gravarEmails(List<String> emails) async {
    try {
      final res = await _sb.rpc('admin_carrinho_excluir_emails_definir',
          params: {'p_emails': emails});
      if (!mounted) return;
      setState(() => _extras = Map<String, dynamic>.from(res as Map));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Lista salva.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para salvar: $e')));
    }
  }

  Future<void> _terminarAviso(int id) async {
    try {
      final res = await _sb
          .rpc('admin_loja_mais_barata_terminar', params: {'p_id': id});
      if (!mounted) return;
      setState(() => _extras = Map<String, dynamic>.from(res as Map));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para encerrar: $e')));
    }
  }

  Future<void> _novoAviso() async {
    List<Map<String, dynamic>> lojas = const [];
    try {
      final rows = await _sb
          .from('restaurants')
          .select('id, name')
          .order('name', ascending: true)
          .limit(500);
      lojas = [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
    } catch (_) {}
    if (!mounted) return;
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoLojaMaisBarata(lojas: lojas),
    );
    if (res == null) return;
    try {
      final out = await _sb.rpc('admin_loja_mais_barata_guardar', params: {
        'p_id': null,
        'p_loja_id': res['loja_id'],
        'p_titulo': res['titulo'],
        'p_texto': res['texto'],
        'p_valido_ate': (res['valido_ate'] as DateTime).toUtc().toIso8601String(),
      });
      if (!mounted) return;
      setState(() => _extras = Map<String, dynamic>.from(out as Map));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Aviso criado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para criar: $e')));
    }
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await _sb.rpc('admin_carrinhos_abandonados_resumo');
      if (!mounted) return;
      _aplicar(Map<String, dynamic>.from(res as Map));
      await _carregarExtras();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não deu para carregar: $e';
        _carregando = false;
      });
    }
  }

  void _aplicar(Map<String, dynamic> r) {
    setState(() {
      _r = r;
      _minutosCtrl.text = '${r['minutos'] ?? 60}';
      _tituloCtrl.text = '${r['titulo'] ?? ''}';
      _textoCtrl.text = '${r['texto'] ?? ''}';
      _carregando = false;
    });
  }

  Future<void> _gravar({bool? ligado}) async {
    if (_aGravar) return;
    final minutos = int.tryParse(_minutosCtrl.text.trim());
    if (minutos == null || minutos < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Minutos inválidos (mínimo 5).')));
      return;
    }
    setState(() => _aGravar = true);
    try {
      final res = await _sb.rpc('admin_carrinho_abandonado_config', params: {
        'p_ligado': ligado ?? (_r['ligado'] == true),
        'p_minutos': minutos,
        'p_titulo': _tituloCtrl.text.trim(),
        'p_texto': _textoCtrl.text.trim(),
      });
      if (!mounted) return;
      _aplicar(Map<String, dynamic>.from(res as Map));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gravado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para gravar: $e')));
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  Widget _secaoEmailsExcluidos() {
    final emails = _emailsExcluidos;
    return Card(
      key: const Key('carrinho_emails_excluidos'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Emails que nunca recebem o aviso',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
                'Contas de teste. Use % como curinga (ex.: %@bora.app). '
                'Contas demo do servidor já ficam de fora sozinhas.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in emails)
                  InputChip(
                    label: Text(e),
                    onDeleted: () =>
                        _gravarEmails([...emails]..remove(e)),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('carrinho_novo_email'),
                    controller: _novoEmailCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Adicionar email'),
                  ),
                ),
                IconButton(
                  tooltip: 'Adicionar',
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final v = _novoEmailCtrl.text.trim();
                    if (v.isEmpty) return;
                    _novoEmailCtrl.clear();
                    _gravarEmails([...emails, v]);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoLojasMaisBaratas() {
    final avisos = (_extras['avisos'] as List?) ?? const [];
    return Column(
      key: const Key('carrinho_lojas_mais_baratas'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Avisos "a loja ficou mais barata"',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              key: const Key('carrinho_novo_aviso_barato'),
              onPressed: _novoAviso,
              icon: const Icon(Icons.add),
              label: const Text('Novo aviso'),
            ),
          ],
        ),
        const Text(
            'Quem largou o carrinho ANTES da mudança recebe este texto no lugar '
            'do aviso normal (mesmas regras: 3 dias, 1 por dia, nunca a quem já pediu).',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        if (avisos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nenhum aviso criado.'),
          ),
        for (final raw in avisos)
          Builder(builder: (_) {
            final a = Map<String, dynamic>.from(raw as Map);
            final ativo = a['ativo'] == true;
            return Card(
              child: ListTile(
                title: Text('${a['loja']} · ${a['titulo']}'),
                subtitle: Text(
                    '${a['texto']}\n'
                    '${ativo ? 'Ativo' : 'Encerrado'} · desde ${dataHoraLisboa(a['mudou_em'])}'
                    ' · até ${a['valido_ate'] == null ? 'sem fim' : dataHoraLisboa(a['valido_ate'])}\n'
                    'Avisados: ${a['avisados'] ?? 0} · voltaram a pedir: ${a['voltaram_a_pedir'] ?? 0}'),
                isThreeLine: true,
                trailing: ativo
                    ? TextButton(
                        onPressed: () => _terminarAviso((a['id'] as num).toInt()),
                        child: const Text('Encerrar'),
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }

  String _eur(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return '€${n.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final ligado = _r['ligado'] == true;
    final lista = (_r['lista'] as List?) ?? const [];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Carrinho abandonado'),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_erro!),
                ))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: SwitchListTile(
                          value: ligado,
                          onChanged:
                              _aGravar ? null : (v) => _gravar(ligado: v),
                          activeColor: AppColors.primary,
                          title: const Text('Aviso de carrinho abandonado',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(ligado
                              ? 'LIGADO — o cliente recebe 1 push quando larga o carrinho.'
                              : 'DESLIGADO — ninguém recebe aviso.'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Numero('Carrinhos abertos',
                              '${_r['carrinhos_abertos'] ?? 0}'),
                          _Numero('Valor parado', _eur(_r['valor_aberto'])),
                          _Numero('Avisados (7 dias)',
                              '${_r['avisados_7d'] ?? 0}'),
                          _Numero('Pediram depois do aviso (7 dias)',
                              '${_r['convertidos_apos_aviso_7d'] ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Configuração',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _minutosCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutos até o aviso',
                          helperText:
                              'Depois da última mexida no carrinho. Máx. 1 aviso por carrinho e 1 por dia.',
                        ),
                      ),
                      TextField(
                        controller: _tituloCtrl,
                        maxLength: 80,
                        decoration:
                            const InputDecoration(labelText: 'Título do push'),
                      ),
                      TextField(
                        controller: _textoCtrl,
                        maxLength: 200,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Texto do push',
                          helperText: '{loja} vira o nome da loja.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _aGravar ? null : () => _gravar(),
                        icon: _aGravar
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save),
                        label: const Text('Salvar'),
                      ),
                      const SizedBox(height: 20),
                      _secaoEmailsExcluidos(),
                      const SizedBox(height: 20),
                      _secaoLojasMaisBaratas(),
                      const SizedBox(height: 20),
                      const Text('Últimos carrinhos',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      if (lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Nenhum carrinho registrado ainda.'),
                        ),
                      for (final raw in lista)
                        _LinhaCarrinho(
                          l: Map<String, dynamic>.from(raw as Map),
                          eur: _eur,
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Criar um aviso "a loja ficou mais barata" (PT-BR). Devolve
/// {loja_id, titulo, texto, valido_ate} ou null.
class _DialogoLojaMaisBarata extends StatefulWidget {
  const _DialogoLojaMaisBarata({required this.lojas});

  final List<Map<String, dynamic>> lojas;

  @override
  State<_DialogoLojaMaisBarata> createState() => _DialogoLojaMaisBarataState();
}

class _DialogoLojaMaisBarataState extends State<_DialogoLojaMaisBarata> {
  String? _loja;
  int _dias = 3;
  final _titulo =
      TextEditingController(text: 'O teu carrinho do {loja} ficou mais barato');
  final _texto = TextEditingController();

  @override
  void dispose() {
    _titulo.dispose();
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _loja != null &&
        _titulo.text.trim().isNotEmpty &&
        _texto.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Novo aviso "loja ficou mais barata"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _loja,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Loja'),
              items: [
                for (final l in widget.lojas)
                  DropdownMenuItem(
                      value: '${l['id']}',
                      child: Text('${l['name'] ?? l['id']}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _loja = v),
            ),
            TextField(
              controller: _titulo,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Título', helperText: '{loja} vira o nome da loja.'),
            ),
            TextField(
              controller: _texto,
              maxLength: 240,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Texto (PT-PT, só o que é verdade)'),
            ),
            DropdownButtonFormField<int>(
              initialValue: _dias,
              decoration: const InputDecoration(labelText: 'Válido por'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 dia')),
                DropdownMenuItem(value: 3, child: Text('3 dias')),
                DropdownMenuItem(value: 7, child: Text('7 dias')),
              ],
              onChanged: (v) => setState(() => _dias = v ?? 3),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: ok
              ? () => Navigator.pop(context, {
                    'loja_id': _loja,
                    'titulo': _titulo.text.trim(),
                    'texto': _texto.text.trim(),
                    'valido_ate': DateTime.now().add(Duration(days: _dias)),
                  })
              : null,
          child: const Text('Criar'),
        ),
      ],
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.titulo, this.valor);

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(titulo,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _LinhaCarrinho extends StatelessWidget {
  const _LinhaCarrinho({required this.l, required this.eur});

  final Map<String, dynamic> l;
  final String Function(Object?) eur;

  @override
  Widget build(BuildContext context) {
    final String estado;
    if (l['convertido_em'] != null) {
      estado = 'Fechado/pedido feito ${dataHoraLisboa(l['convertido_em'])}';
    } else if (l['avisado_em'] != null) {
      estado = 'Avisado ${dataHoraLisboa(l['avisado_em'])}';
    } else {
      estado = 'Aberto';
    }
    final cliente = '${l['cliente'] ?? ''}'.trim();
    return Card(
      child: ListTile(
        title: Text(
            '${cliente.isEmpty ? 'Cliente' : cliente} · ${l['loja'] ?? '—'}'),
        subtitle: Text(
            '${l['resumo'] ?? ''}\nMexido ${dataHoraLisboa(l['atualizado_em'])} · $estado'),
        isThreeLine: true,
        trailing: Text(eur(l['total']),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
