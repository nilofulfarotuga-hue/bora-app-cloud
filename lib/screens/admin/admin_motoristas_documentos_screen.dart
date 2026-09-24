import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../services/ficha_legal_service.dart';

/// Documentos dos motoristas (TVDE) — semáforo por motorista.
///
/// Certificado TVDE, carta, seguro, inspeção e dístico: válido / a expirar em
/// 30 dias / expirado / não preenchido. O estado é decidido no servidor
/// (`admin_motoristas_documentos`, hora de Lisboa); aqui só se desenha.
///
/// O Danilo pode: ver, editar a ficha de qualquer motorista (fica no
/// admin_audit_log), ligar/desligar o bloqueio de ficar online com documento
/// expirado, preencher NIF e licença da plataforma, e exportar CSV.
/// O aviso 30 dias antes corre sozinho todos os dias às 08:00 UTC
/// (cron `motorista-docs-alerta-diario`) — ao motorista e a este painel.
class AdminMotoristasDocumentosScreen extends StatefulWidget {
  const AdminMotoristasDocumentosScreen({super.key});

  @override
  State<AdminMotoristasDocumentosScreen> createState() =>
      _AdminMotoristasDocumentosScreenState();
}

class _AdminMotoristasDocumentosScreenState
    extends State<AdminMotoristasDocumentosScreen> {
  static const _chaves = [
    'motorista_bloqueio_doc_expirado',
    'plataforma_nif',
    'plataforma_licenca_imt',
  ];

  List<Map<String, dynamic>> _lista = const [];
  Map<String, dynamic> _cfg = const {};
  String _filtro = 'todos';
  bool _carregando = true;
  String? _erro;

  SupabaseClient get _c => Supabase.instance.client;

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
      final r = await _c.rpc('admin_motoristas_documentos');
      final s = await _c
          .from('platform_settings')
          .select('key,value')
          .inFilter('key', _chaves);
      if (!mounted) return;
      setState(() {
        _lista = ((r as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cfg = {for (final l in (s as List)) (l as Map)['key'] as String: l['value']};
        _carregando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Erro ao carregar: $e';
          _carregando = false;
        });
      }
    }
  }

  Future<void> _gravarSetting(String key, Object value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _c.rpc('admin_update_setting',
          params: {'p_key': key, 'p_value': value});
      messenger.showSnackBar(const SnackBar(content: Text('Configuração salva.')));
      _carregar();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  List<Map<String, dynamic>> get _visiveis => _filtro == 'todos'
      ? _lista
      : _lista.where((m) => (m['pior'] ?? '').toString().endsWith(_filtro)).toList();

  Future<void> _exportar() async {
    final headers = [
      'nome', 'telefone', 'matricula', 'pior',
      'certificado_tvde', 'carta', 'seguro', 'inspecao', 'distico',
    ];
    String doc(Map<String, dynamic> m, String k) {
      final d = ((m['documentos'] as List?) ?? const [])
          .cast<Map>()
          .firstWhere((e) => e['doc'] == k, orElse: () => const {});
      return '${d['estado'] ?? ''} ${d['validade'] ?? ''}'.trim();
    }

    final rows = _lista
        .map((m) => [
              m['nome'] ?? '', m['telefone'] ?? '', m['matricula'] ?? '',
              (m['pior'] ?? '').toString().substring(2),
              doc(m, 'certificado_tvde'), doc(m, 'carta'), doc(m, 'seguro'),
              doc(m, 'inspecao'), doc(m, 'distico'),
            ])
        .toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_documentos_motoristas_$stamp.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Documentos dos motoristas $stamp',
    );
  }

  Future<void> _editarTexto(String key, String titulo) async {
    final ctl = TextEditingController(text: (_cfg[key] ?? '').toString());
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
            controller: ctl,
            decoration: const InputDecoration(
                helperText: 'Vazio = aparece "em processo" para a autoridade')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (v != null) await _gravarSetting(key, v);
  }

  @override
  Widget build(BuildContext context) {
    final bloqueio = _cfg['motorista_bloqueio_doc_expirado'] != false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos dos motoristas'),
        actions: [
          IconButton(
              tooltip: 'Exportar CSV',
              onPressed: _lista.isEmpty ? null : _exportar,
              icon: const Icon(Icons.download)),
          IconButton(
              tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        child: Column(children: [
                          SwitchListTile(
                            title: const Text('Bloquear online com documento expirado'),
                            subtitle: const Text(
                                'Motorista TVDE com certificado, carta, seguro, inspeção ou dístico vencido não consegue ficar online (o servidor recusa).'),
                            value: bloqueio,
                            onChanged: (v) =>
                                _gravarSetting('motorista_bloqueio_doc_expirado', v),
                          ),
                          ListTile(
                            title: const Text('NIF da Bora (plataforma)'),
                            subtitle: Text(_textoCfg('plataforma_nif')),
                            trailing: const Icon(Icons.edit),
                            onTap: () => _editarTexto('plataforma_nif', 'NIF da Bora'),
                          ),
                          ListTile(
                            title: const Text('Licença IMT de operador de plataforma'),
                            subtitle: Text(_textoCfg('plataforma_licenca_imt')),
                            trailing: const Icon(Icons.edit),
                            onTap: () => _editarTexto('plataforma_licenca_imt',
                                'Licença IMT (operador de plataforma)'),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        for (final f in const [
                          ['todos', 'Todos'],
                          ['expirado', 'Expirado'],
                          ['a_expirar', 'A expirar (30 dias)'],
                          ['em_falta', 'Não preenchido'],
                          ['valido', 'Tudo válido'],
                        ])
                          ChoiceChip(
                            label: Text(
                                '${f[1]} (${f[0] == 'todos' ? _lista.length : _lista.where((m) => (m['pior'] ?? '').toString().endsWith(f[0])).length})'),
                            selected: _filtro == f[0],
                            onSelected: (_) => setState(() => _filtro = f[0]),
                          ),
                      ]),
                      const SizedBox(height: 8),
                      if (_visiveis.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Nenhum motorista neste filtro.')),
                        ),
                      for (final m in _visiveis)
                        _LinhaMotorista(m: m, onEditar: () => _editarFicha(m)),
                    ],
                  ),
                ),
    );
  }

  String _textoCfg(String k) {
    final v = (_cfg[k] ?? '').toString();
    return v.isEmpty ? 'Em processo (vazio)' : v;
  }

  Future<void> _editarFicha(Map<String, dynamic> m) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditarFichaSheet(motorista: m),
    );
    if (ok == true) _carregar();
  }
}

Color corEstadoDocumento(String e) => switch (e) {
      'valido' => AppColors.success,
      'a_expirar' => AppColors.warning,
      'expirado' => AppColors.error,
      _ => const Color(0xFF9CA3AF),
    };

class _LinhaMotorista extends StatelessWidget {
  const _LinhaMotorista({required this.m, required this.onEditar});
  final Map<String, dynamic> m;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final docs = ((m['documentos'] as List?) ?? const [])
        .map((e) => DocumentoEstado.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return Card(
      child: InkWell(
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('${m['nome'] ?? '—'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                if (m['online'] == true)
                  const Chip(label: Text('online'), visualDensity: VisualDensity.compact),
                const Icon(Icons.edit_outlined, size: 18),
              ]),
              Text('${m['matricula'] ?? 'sem matrícula'} · ${m['telefone'] ?? ''}',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 6, children: [
                for (final d in docs)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, size: 12, color: corEstadoDocumento(d.estado)),
                    const SizedBox(width: 4),
                    Text(
                        '${d.rotulo.split(' (').first}: ${d.validade == null ? 'não preenchido' : FichaTexto.data(d.validade)}',
                        style: const TextStyle(fontSize: 12)),
                  ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edição pelo admin — mesma RPC para todos os campos, auditada no servidor.
class _EditarFichaSheet extends StatefulWidget {
  const _EditarFichaSheet({required this.motorista});
  final Map<String, dynamic> motorista;

  @override
  State<_EditarFichaSheet> createState() => _EditarFichaSheetState();
}

class _EditarFichaSheetState extends State<_EditarFichaSheet> {
  static const _campos = <String, String>{
    'tvde_cert_numero': 'N.º certificado TVDE (IMT)',
    'tvde_cert_validade': 'Certificado válido até (AAAA-MM-DD)',
    'carta_numero': 'N.º carta de condução',
    'carta_validade': 'Carta válida até (AAAA-MM-DD)',
    'distico_numero': 'N.º dístico TVDE',
    'distico_validade': 'Dístico válido até (AAAA-MM-DD)',
    'inspecao_validade': 'Inspeção válida até (AAAA-MM-DD)',
    'seguro_seguradora': 'Seguradora',
    'seguro_apolice': 'Apólice',
    'seguro_validade': 'Seguro válido até (AAAA-MM-DD)',
    'veiculo_ano': 'Ano do veículo',
    'operador_nome': 'Operador (frota)',
    'operador_nif': 'NIF do operador',
    'operador_licenca': 'Licença IMT do operador',
  };
  late final Map<String, TextEditingController> _ctl;
  late final Map<String, String> _orig;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final f = widget.motorista['ficha'] is Map
        ? Map<String, dynamic>.from(widget.motorista['ficha'] as Map)
        : <String, dynamic>{};
    _orig = {for (final k in _campos.keys) k: (f[k] ?? '').toString()};
    _ctl = {for (final k in _campos.keys) k: TextEditingController(text: _orig[k])};
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    final p = <String, dynamic>{
      for (final k in _campos.keys)
        if (_ctl[k]!.text.trim() != _orig[k]) k: _ctl[k]!.text.trim(),
    };
    if (p.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _salvando = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await Supabase.instance.client.rpc('admin_guardar_ficha_legal',
          params: {'p_user': widget.motorista['user_id'], 'p': p});
      messenger.showSnackBar(const SnackBar(content: Text('Ficha salva e auditada.')));
      nav.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Ficha legal — ${widget.motorista['nome'] ?? ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final e in _campos.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _ctl[e.key],
                  decoration: InputDecoration(
                      labelText: e.value, border: const OutlineInputBorder()),
                ),
              ),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: Text(_salvando ? 'Salvando…' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
