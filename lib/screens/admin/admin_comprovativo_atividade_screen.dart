/// Painel admin (PT-BR) — Comprovativo de atividade dos prestadores (Bloco C · 20/10/2026).
///
/// Lista de quem trabalha no Bora (estafeta, motorista TVDE, limpeza, lavagem,
/// serviços) com o estado do comprovativo de atividade nas Finanças; filtro
/// "Sem atividade"; ver o documento (URL assinada de 2 minutos, nunca pública);
/// aprovar; recusar com motivo; pedir de novo; marcar em análise; lembrete a
/// uma pessoa ou a todos (com contagem e confirmação); histórico; exportar CSV
/// (só metadados, nunca o ficheiro); interruptor `provider_atividade_obrigatoria`.
///
/// Tudo passa pelas RPC `admin_provider_atividade_*` (validam is_admin() e
/// auditam em admin_audit_log). O interruptor usa `admin_update_setting`.
library;

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../services/robo_documentos.dart';
import '../../services/robo_documentos_service.dart';
import '../../widgets/admin_robo_documentos.dart';
import 'admin_robo_documentos_screen.dart';
import '../../utils/hora_lisboa_ext.dart';
import '_admin_rpc_errors.dart';

/// Rótulo PT-BR do papel (nunca o nome técnico cru — PADRAO §1.16).
String rotuloPapelAtividade(String p) => switch (p) {
      'estafeta' => 'Entregas',
      'motorista_tvde' => 'Corridas (TVDE)',
      'limpeza' => 'Limpeza',
      'lavagem' => 'Lavagem de carros',
      'servicos' => 'Serviços',
      _ => 'Outro trabalho',
    };

/// Rótulo PT-BR do estado.
String rotuloEstadoAtividade(String estado, {required bool temDocumento}) =>
    switch (estado) {
      'em_analise' =>
        temDocumento ? 'Em análise' : 'Disse que tem (sem documento)',
      'aprovada' => 'Aprovada',
      'recusada' => 'Recusada',
      _ => 'Por enviar',
    };

const List<String> kCabecalhoCsvAtividade = [
  'nome',
  'email',
  'telefone',
  'papeis',
  'estado',
  'tem_documento',
  'tipo_documento',
  'nif',
  'enviado_em',
  'decidido_em',
  'decidido_por',
  'motivo',
  'obrigatoria',
  'lembretes_enviados',
  'ultimo_lembrete',
];

/// CSV só com metadados (nunca o caminho nem o ficheiro). Função pura, testada.
String construirCsvAtividade(List<Map<String, dynamic>> linhas) {
  String t(Object? v) => v?.toString() ?? '';
  final rows = <List<String>>[
    kCabecalhoCsvAtividade,
    for (final l in linhas)
      [
        t(l['nome']),
        t(l['email']),
        t(l['telefone']),
        ((l['papeis'] as List?) ?? const [])
            .map((e) => rotuloPapelAtividade('$e'))
            .join(' + '),
        rotuloEstadoAtividade(t(l['atividade_status']),
            temDocumento: l['tem_documento'] == true),
        l['tem_documento'] == true ? 'sim' : 'não',
        t(l['documento_tipo']),
        t(l['nif']),
        t(l['enviado_em']),
        t(l['decidido_em']),
        t(l['decidido_por_email']),
        t(l['motivo']),
        l['obrigatoria'] == true ? 'sim' : 'não',
        t(l['lembretes_enviados']),
        t(l['lembrete_enviado_em']),
      ],
  ];
  return const ListToCsvConverter(fieldDelimiter: ';', eol: '\n').convert(rows);
}

class AdminComprovativoAtividadeScreen extends StatefulWidget {
  const AdminComprovativoAtividadeScreen({super.key});

  @override
  State<AdminComprovativoAtividadeScreen> createState() =>
      _AdminComprovativoAtividadeScreenState();
}

class _AdminComprovativoAtividadeScreenState
    extends State<AdminComprovativoAtividadeScreen> {
  final _sb = Supabase.instance.client;
  String _filtro = 'sem_atividade';
  bool _carregando = true;
  String? _erro;
  bool? _interruptor;
  DateTime? _corte;
  List<Map<String, dynamic>> _linhas = const [];
  bool _ocupado = false;

  static const _filtros = <(String, String)>[
    ('sem_atividade', 'Sem atividade'),
    ('em_analise', 'Em análise'),
    ('por_enviar', 'Por enviar'),
    ('recusada', 'Recusada'),
    ('aprovada', 'Aprovada'),
    ('todos', 'Todos'),
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _data(Object? v) {
    final d = v == null ? null : DateTime.tryParse(v.toString());
    if (d == null) return '—';
    final l = d.toLisboa();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await _sb.rpc('admin_provider_atividade_listar',
          params: {'p_filtro': _filtro}).timeout(const Duration(seconds: 15));
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      final linhasCarregadas = ((m['linhas'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      // Adendo 3: o veredito do robô junto a cada pessoa (`_robo`).
      await juntarVereditosRobo(_sb, linhasCarregadas);
      if (!mounted) return;
      setState(() {
        _interruptor = m['interruptor'] == true;
        _corte = m['corte'] == null
            ? null
            : DateTime.tryParse(m['corte'].toString());
        _linhas = linhasCarregadas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _carregando = false;
      });
    }
  }

  Future<void> _mudarInterruptor(bool ligado) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ligado
            ? 'Ligar a obrigatoriedade?'
            : 'Desligar a obrigatoriedade?'),
        content: Text(ligado
            ? 'Cadastros NOVOS de prestador só poderão ser aprovados com o comprovativo '
                'de atividade aprovado. Quem já trabalhava antes da data de corte não é '
                'bloqueado.'
            : 'As aprovações deixam de esperar pelo comprovativo. O aviso continua a '
                'aparecer para quem não enviou, mas não bloqueia nada.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.rpc('admin_update_setting', params: {
        'p_key': 'provider_atividade_obrigatoria',
        'p_value': ligado,
      });
      _msg(ligado ? 'Obrigatoriedade ligada.' : 'Obrigatoriedade desligada.');
      await _carregar();
    } catch (e) {
      _msg(humanizeAdminRpcError(e));
    }
  }

  Future<void> _lembrarTodos() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final c = await _sb.rpc('admin_provider_atividade_lembrar_todos',
          params: {'p_confirmar': false});
      final n = (c is Map ? c['alvos'] : null) as int? ?? 0;
      if (!mounted) return;
      if (n == 0) {
        _msg(
            'Ninguém para lembrar agora (sem pendentes ou já lembrados nas últimas 20 h).');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lembrar todos sem atividade'),
          content: Text(
              'Vai enviar o aviso "Falta o comprovativo de atividade" (push + '
              'caixa da app) a $n pessoa${n == 1 ? '' : 's'}. Contas de demonstração ficam '
              'de fora e ninguém recebe duas vezes em 20 horas.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Enviar a $n')),
          ],
        ),
      );
      if (ok != true) return;
      final r = await _sb.rpc('admin_provider_atividade_lembrar_todos',
          params: {'p_confirmar': true});
      final enviados = (r is Map ? r['enviados'] : null) ?? 0;
      _msg('Lembrete enviado a $enviados pessoa(s).');
      await _carregar();
    } catch (e) {
      _msg(humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _exportar() async {
    try {
      final r = await _sb.rpc('admin_provider_atividade_listar',
          params: {'p_filtro': 'todos'});
      final linhas = ((r is Map ? r['linhas'] : null) as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final hoje = DateTime.now().toLisboa();
      final nome =
          'comprovativo_atividade_${hoje.year}${hoje.month.toString().padLeft(2, '0')}${hoje.day.toString().padLeft(2, '0')}.csv';
      await AdminExportService.instance.exportCsvText(
          filename: nome,
          csv: construirCsvAtividade(linhas),
          subject: 'Bora — comprovativo de atividade');
      _msg('CSV exportado (${linhas.length} linhas, sem os ficheiros).');
    } catch (e) {
      _msg(humanizeAdminRpcError(e));
    }
  }

  Future<String?> _pedirMotivo(String titulo,
      {bool obrigatorio = true, String? sugestao}) {
    final ctrl = TextEditingController(text: sugestao ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText:
                obrigatorio ? 'Motivo (a pessoa vai ler)' : 'Nota (opcional)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (obrigatorio && t.length < 3) return;
              Navigator.pop(ctx, t);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _decidir(Map<String, dynamic> l, String acao) async {
    String? motivo;
    if (acao == 'recusar') {
      motivo = await _pedirMotivo('Recusar comprovativo');
      if (motivo == null) return;
    } else if (acao == 'pedir_de_novo') {
      motivo = await _pedirMotivo('Pedir de novo',
          sugestao: 'Precisamos de um comprovativo legível com o teu NIF');
      if (motivo == null) return;
    } else if (acao == 'em_analise') {
      motivo = await _pedirMotivo('Marcar em análise', obrigatorio: false);
      if (motivo == null) return;
    } else if (acao == 'aprovar') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aprovar comprovativo?'),
          content: Text(
              'Confirmas que viste o documento de ${l['nome']} e que a atividade '
              'está aberta com o NIF ${l['nif'] ?? '—'}?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Aprovar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _sb.rpc('admin_provider_atividade_decidir', params: {
        'p_user_id': l['user_id'],
        'p_acao': acao,
        'p_motivo': motivo,
        'p_avisar': true,
      });
      _msg(switch (acao) {
        'aprovar' => 'Comprovativo aprovado (a pessoa foi avisada).',
        'recusar' => 'Comprovativo recusado (a pessoa foi avisada).',
        'pedir_de_novo' => 'Pedido de novo envio feito (a pessoa foi avisada).',
        _ => 'Marcado em análise.',
      });
      if (mounted) Navigator.of(context).maybePop();
      await _carregar();
    } catch (e) {
      final s = e.toString();
      _msg(s.contains('sem_documento')
          ? 'Ainda não há documento para aprovar. Use "Pedir de novo" ou "Enviar lembrete".'
          : humanizeAdminRpcError(e));
    }
  }

  Future<void> _lembrar(Map<String, dynamic> l) async {
    try {
      final r = await _sb.rpc('admin_provider_atividade_lembrar',
          params: {'p_user_id': l['user_id']});
      final ok = r is Map && r['ok'] == true;
      _msg(ok
          ? 'Lembrete enviado a ${l['nome']}.'
          : 'Nada a pedir: o comprovativo já foi enviado ou aprovado.');
      await _carregar();
    } catch (e) {
      _msg(humanizeAdminRpcError(e));
    }
  }

  Future<void> _verDocumento(Map<String, dynamic> l) async {
    try {
      final r = await _sb.rpc('admin_provider_atividade_documento',
          params: {'p_user_id': l['user_id']});
      final path = r is Map ? r['path']?.toString() : null;
      if (path == null) throw Exception('sem_documento');
      // URL assinada de curta duração (2 min) — o bucket é privado.
      final url = await _sb.storage
          .from('provider-atividade')
          .createSignedUrl(path, 120);
      final aberto =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!aberto) _msg('Não foi possível abrir o documento neste aparelho.');
    } catch (e) {
      _msg(e.toString().contains('sem_documento')
          ? 'Esta pessoa ainda não enviou o documento.'
          : humanizeAdminRpcError(e));
    }
  }

  Future<void> _historico(Map<String, dynamic> l) async {
    List<Map<String, dynamic>> ev = const [];
    try {
      final r = await _sb.rpc('admin_provider_atividade_historico',
          params: {'p_user_id': l['user_id']});
      ev = ((r as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      _msg(humanizeAdminRpcError(e));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Histórico — ${l['nome']}'),
        content: SizedBox(
          width: 420,
          child: ev.isEmpty
              ? const Text('Sem registos.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in ev)
                      ListTile(
                        dense: true,
                        title: Text(
                            '${e['evento']} · ${e['antes'] ?? '—'} → ${e['depois'] ?? '—'}'),
                        subtitle: Text([
                          _data(e['quando']),
                          if (e['autor_email'] != null)
                            '${e['autor_email']}'
                          else
                            '${e['autor_tipo']}',
                          if (e['motivo'] != null) 'motivo: ${e['motivo']}',
                        ].join(' · ')),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))
        ],
      ),
    );
  }

  void _abrirPessoa(Map<String, dynamic> l) {
    final temDoc = l['tem_documento'] == true;
    final estado = l['atividade_status']?.toString() ?? 'por_enviar';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l['nome']}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text([
                ((l['papeis'] as List?) ?? const [])
                    .map((e) => rotuloPapelAtividade('$e'))
                    .join(' + '),
                if (l['email'] != null) '${l['email']}',
                if (l['telefone'] != null) '${l['telefone']}',
              ].join(' · ')),
              const SizedBox(height: 8),
              Text(
                  'Estado: ${rotuloEstadoAtividade(estado, temDocumento: temDoc)}'
                  '${l['obrigatoria'] == true ? ' · obrigatório (cadastro novo)' : ''}'),
              Text(
                  'NIF: ${l['nif'] ?? '—'} · documento: ${temDoc ? (l['documento_tipo'] ?? 'sim') : 'não'}'),
              Text(
                  'Enviado: ${_data(l['enviado_em'])} · decidido: ${_data(l['decidido_em'])}'
                  '${l['decidido_por_email'] == null ? '' : ' por ${l['decidido_por_email']}'}'),
              if (l['motivo'] != null) Text('Motivo/nota: ${l['motivo']}'),
              Text(
                  'Lembretes: ${l['lembretes_enviados'] ?? 0} · último: ${_data(l['lembrete_enviado_em'])}'),
              if (vereditoDe(l, 'provider_atividade.documento_path') != null)
                RoboVereditoChip(
                  veredito: vereditoDe(l, 'provider_atividade.documento_path')!,
                  onDesfazer: (v) async {
                    final fez = await desfazerDecisaoDoRobo(ctx, v);
                    if (fez && mounted) _carregar();
                  },
                ),
              if (vereditoDe(l, 'provider_atividade.documento_path')?.errado == true)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Atenção: o robô diz que este ficheiro NÃO é o comprovativo. Confere antes de aprovar.',
                    key: Key('robo-aviso-botao-aprovar'),
                    style: TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: temDoc ? () => _verDocumento(l) : null,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Ver documento'),
                  ),
                  FilledButton.icon(
                    key: const Key('aprovar-comprovativo-lista'),
                    style: vereditoDe(l, 'provider_atividade.documento_path')?.errado == true
                        ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                        : null,
                    onPressed: temDoc && estado != 'aprovada'
                        ? () => _decidir(l, 'aprovar')
                        : null,
                    icon: const Icon(Icons.check),
                    label: Text(vereditoDe(l, 'provider_atividade.documento_path')?.errado == true
                        ? 'Aprovar (o robô diz errado)'
                        : 'Aprovar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: temDoc && estado != 'recusada'
                        ? () => _decidir(l, 'recusar')
                        : null,
                    icon: const Icon(Icons.close),
                    label: const Text('Recusar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decidir(l, 'pedir_de_novo'),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Pedir de novo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: estado == 'em_analise'
                        ? null
                        : () => _decidir(l, 'em_analise'),
                    icon: const Icon(Icons.hourglass_top),
                    label: const Text('Marcar em análise'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _lembrar(l),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Enviar lembrete'),
                  ),
                  TextButton.icon(
                    onPressed: () => _historico(l),
                    icon: const Icon(Icons.history),
                    label: const Text('Histórico (auditoria)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _corEstado(String estado, bool temDoc) => switch (estado) {
        'aprovada' => AppColors.success,
        'recusada' => AppColors.error,
        'em_analise' when temDoc => AppColors.info,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comprovativo de atividade'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV (só metadados)',
            onPressed: _exportar,
            icon: const Icon(Icons.download),
          ),
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: SwitchListTile(
                key: const Key('admin-atividade-interruptor'),
                title: const Text(
                    'Obrigatório para cadastros novos (provider_atividade_obrigatoria)'),
                subtitle: Text(
                    'Ligado: cadastro novo só é aprovado com o comprovativo aprovado. '
                    'Quem já trabalhava antes de ${_corte == null ? '—' : _data(_corte!.toIso8601String())} '
                    'não é bloqueado.'),
                value: _interruptor ?? false,
                onChanged: _interruptor == null ? null : _mudarInterruptor,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('admin-atividade-abrir-robo'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdminRoboDocumentosScreen())),
                icon: const Icon(Icons.smart_toy_outlined),
                label: const Text('Robô de documentos (ligar, ver e desfazer)'),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (k, rot) in _filtros)
                  ChoiceChip(
                    label: Text(rot),
                    selected: _filtro == k,
                    onSelected: (_) {
                      setState(() => _filtro = k);
                      _carregar();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('admin-atividade-lembrar-todos'),
                onPressed: _ocupado ? null : _lembrarTodos,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Lembrar todos sem atividade'),
              ),
            ),
            const SizedBox(height: 8),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_erro!,
                    style: const TextStyle(color: AppColors.error)),
              )
            else if (_linhas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Ninguém neste filtro.'),
              )
            else
              for (final l in _linhas)
                Card(
                  child: ListTile(
                    onTap: () => _abrirPessoa(l),
                    title: Text('${l['nome']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text([
                          ((l['papeis'] as List?) ?? const [])
                              .map((e) => rotuloPapelAtividade('$e'))
                              .join(' + '),
                          'NIF ${l['nif'] ?? '—'}',
                          if (l['enviado_em'] != null)
                            'enviado ${_data(l['enviado_em'])}',
                        ].join(' · ')),
                        RoboResumoLinha(linha: l),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(
                        rotuloEstadoAtividade('${l['atividade_status']}',
                            temDocumento: l['tem_documento'] == true),
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: _corEstado('${l['atividade_status']}',
                              l['tem_documento'] == true)
                          .withValues(alpha: 0.15),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
