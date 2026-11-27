// CHAMADAS (ATENDENTE DE VOZ) — missão atendente-voz-2026-11-25, bloco B5.
// Painel PT-BR. Quem liga para o telefone da Bora é atendido por um assistente
// virtual (central na VPS + cérebro na Edge voz-cerebro). Aqui o admin vê cada
// chamada (quem ligou, resumo, etiquetas, custo da IA), lê a transcrição, ouve o
// áudio (90 dias), marca resolvido, exporta CSV e muda as definições do
// atendente (ligar/desligar, saudação, voz, motor, tetos de gasto).
//
// Contratos do servidor (migração 20261125213000_atendente_voz_chamadas.sql):
//   admin_chamadas_voz(p_estado, p_limite, p_incluir_teste)  — lista (só admin)
//   admin_chamada_voz(p_id)                                  — chamada + falas
//   admin_chamada_voz_marcar(p_id, p_estado, p_nota)         — auditado
//   admin_voz_definir(p_key, p_value)                        — auditado
//   tabela voz_definicoes (leitura só admin), bucket privado chamadas-voz.
// 27/11/2026: cada chamada mostra a revisão automática (nota e falhas que o Opus encontrou) e o
// botão "Lições" abre o que a atendente já aprendeu (admin_voz_licoes_screen.dart).
// O aviso/push de cada chamada abre /admin/chamadas/<id>. Nada aqui mexe em dinheiro.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../utils/hora_lisboa.dart';
import 'admin_conversas_ao_vivo_screen.dart';
import 'admin_voz_licoes_screen.dart';

const String kRotaChamadasVoz = '/admin/chamadas';
const String kPrefixoChamadaVoz = '/admin/chamadas/';

/// "/admin/chamadas/<uuid>" → uuid (o link dos avisos e do push), ou null.
String? chamadaVozDoLink(String? nome) {
  if (nome == null || !nome.startsWith(kPrefixoChamadaVoz)) return null;
  final id = Uri.decodeComponent(
      nome.substring(kPrefixoChamadaVoz.length).split(RegExp(r'[?#/]')).first);
  return RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ? id : null;
}

/// Rótulos PT-BR do estado da chamada.
String rotuloEstadoChamada(String? e) => switch (e) {
      'resolvido' => 'Resolvida',
      'escalado' => 'Para a equipe',
      'a_decorrer' => 'Em andamento',
      'perdida' => 'Perdida',
      'ocupado' => 'Linha ocupada',
      'erro' => 'Erro',
      _ => e ?? '—',
    };

/// Rótulos PT-BR de quem ligou (reconhecido pelo número — não prova a identidade).
String rotuloPapelChamada(String? p) => switch (p) {
      'cliente' => 'Cliente',
      'estafeta' => 'Entregador',
      'parceiro' => 'Parceiro',
      _ => 'Número desconhecido',
    };

Color _corEstado(String? e) => switch (e) {
      'resolvido' => AppColors.primary,
      'escalado' => AppColors.accent,
      'a_decorrer' => Colors.blue,
      _ => Colors.grey,
    };

String _duracao(Object? s) {
  final n = (s is num ? s : num.tryParse('${s ?? ''}'))?.round();
  if (n == null) return '—';
  final m = n ~/ 60, r = n % 60;
  return m > 0 ? '${m}min ${r}s' : '${r}s';
}

String _usd(Object? v) {
  final n = (v is num ? v : num.tryParse('${v ?? 0}') ?? 0).toDouble();
  return 'US\$ ${n.toStringAsFixed(3).replaceAll('.', ',')}';
}

class AdminChamadasVozScreen extends StatefulWidget {
  const AdminChamadasVozScreen({super.key});

  @override
  State<AdminChamadasVozScreen> createState() => _AdminChamadasVozScreenState();
}

class _AdminChamadasVozScreenState extends State<AdminChamadasVozScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _lista = const [];
  Map<String, dynamic> _defs = const {};
  bool _carregando = true;
  String? _erro;
  String _filtro = ''; // '' = todas · 'escalado' · 'resolvido'
  bool _comTestes = false;
  RealtimeChannel? _canal;
  Timer? _atraso;

  @override
  void initState() {
    super.initState();
    _carregar();
    // Tempo real: chamada nova ou fechada → recarrega (com um pequeno atraso
    // para juntar vários eventos da mesma chamada).
    _canal = _sb
        .channel('admin_chamadas_voz')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chamadas_voz',
          callback: (_) {
            _atraso?.cancel();
            _atraso = Timer(const Duration(seconds: 2), _carregar);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _atraso?.cancel();
    final c = _canal;
    if (c != null) _sb.removeChannel(c);
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await _sb.rpc('admin_chamadas_voz', params: {
        'p_estado': _filtro.isEmpty ? null : _filtro,
        'p_limite': 300,
        'p_incluir_teste': _comTestes,
      });
      final defs = await _sb.from('voz_definicoes').select('key,value');
      if (!mounted) return;
      setState(() {
        _lista = (res is List ? res : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _defs = {
          for (final r in (defs as List).whereType<Map>()) '${r['key']}': r['value'],
        };
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar as chamadas: $e';
        _carregando = false;
      });
    }
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _exportarCsv() async {
    String c(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final linhas = <String>[
      'id;inicio_lisboa;duracao_s;telefone;quem;nome;estado;etiquetas;resumo;custo_usd;motor;teste',
      for (final i in _lista)
        [
          i['id'], dataHoraLisboa(i['inicio']), i['duracao_s'], i['telefone'],
          rotuloPapelChamada(i['papel'] as String?), i['nome_identificado'],
          rotuloEstadoChamada(i['estado'] as String?),
          (i['etiquetas'] is List ? (i['etiquetas'] as List).join(',') : ''),
          i['resumo'], i['custo_usd'], i['motor'], i['teste'],
        ].map(c).join(';'),
    ];
    await AdminExportService.instance.exportCsvText(
      filename: 'chamadas_voz_${DateTime.now().millisecondsSinceEpoch}.csv',
      csv: linhas.join('\n'),
    );
    _aviso('CSV com ${_lista.length} chamadas baixado.');
  }

  Future<void> _abrirDefinicoes() async {
    final mudou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DefinicoesVozSheet(defs: _defs),
    );
    if (mudou == true) {
      _aviso('Definições do atendente salvas.');
      _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ativo = _defs['voz_atendente_ativo'] == true;
    final gastoHoje = _lista
        .where((c) {
          final d = DateTime.tryParse('${c['inicio'] ?? ''}');
          if (d == null) return false;
          final h = horaLisboa(d), agora = horaLisboa(DateTime.now().toUtc());
          return h.year == agora.year && h.month == agora.month && h.day == agora.day;
        })
        .fold<double>(0, (s, c) => s + ((c['custo_usd'] as num?)?.toDouble() ?? 0));
    final escaladas = _lista.where((c) => c['estado'] == 'escalado' && c['revisto_em'] == null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chamadas (atendente de voz)'),
        actions: [
          IconButton(
              tooltip: 'Conversas ao vivo (robôs)',
              icon: const Icon(Icons.forum),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AdminConversasAoVivoScreen()))),
          IconButton(
              tooltip: 'Lições que a atendente aprendeu',
              icon: const Icon(Icons.school),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AdminVozLicoesScreen()))),
          IconButton(
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download),
              onPressed: _lista.isEmpty ? null : _exportarCsv),
          IconButton(
              tooltip: 'Definições do atendente',
              icon: const Icon(Icons.tune),
              onPressed: _defs.isEmpty ? null : _abrirDefinicoes),
          IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                leading: Icon(ativo ? Icons.phone_in_talk : Icons.phone_disabled,
                    color: ativo ? AppColors.primary : Colors.grey),
                title: Text(ativo ? 'Atendente LIGADO' : 'Atendente DESLIGADO'),
                subtitle: Text(
                  'Gasto de IA hoje (custo da API Claude): ${_usd(gastoHoje)} · '
                  'Para a equipe sem revisão: $escaladas\n'
                  'Desligado = quem liga ouve uma mensagem curta pedindo para escrever para '
                  '${_defs['voz_email_suporte'] ?? 'suporte@boraguarda.com'}.',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: _defs.isEmpty ? null : _abrirDefinicoes,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final f in const [('', 'Todas'), ('escalado', 'Para a equipe'), ('resolvido', 'Resolvidas')])
                  ChoiceChip(
                    label: Text(f.$2),
                    selected: _filtro == f.$1,
                    onSelected: (_) {
                      setState(() => _filtro = f.$1);
                      _carregar();
                    },
                  ),
                FilterChip(
                  label: const Text('Mostrar testes'),
                  selected: _comTestes,
                  onSelected: (v) {
                    setState(() => _comTestes = v);
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
                child: Text('Nenhuma chamada ainda. Quando alguém ligar para a Bora, ela aparece aqui '
                    '(e chega uma notificação no celular).'),
              ),
            for (final c in _lista) _cartao(c),
          ],
        ),
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> c) {
    final etiquetas = (c['etiquetas'] is List) ? (c['etiquetas'] as List).cast<Object?>() : const [];
    final estado = c['estado'] as String?;
    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AdminChamadaVozScreen(chamadaId: '${c['id']}')));
          _carregar();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${rotuloPapelChamada(c['papel'] as String?)}'
                      '${c['nome_identificado'] != null ? ' · ${c['nome_identificado']}' : ''}'
                      '${c['teste'] == true ? '  [TESTE]' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Chip(
                    label: Text(rotuloEstadoChamada(estado),
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: _corEstado(estado),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Text('${dataHoraLisboa(c['inicio'])} · ${_duracao(c['duracao_s'])} · '
                  '${c['telefone'] ?? 'sem número'} · ${_usd(c['custo_usd'])}'
                  '${c['tem_audio'] == true ? ' · áudio' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              if ((c['resumo'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('${c['resumo']}', maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              if (etiquetas.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (final e in etiquetas)
                    Chip(label: Text('$e', style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                ]),
              ],
              if (c['revisto_em'] != null)
                Text('Revisada em ${dataHoraLisboa(c['revisto_em'])}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma chamada: resumo, dados, áudio, transcrição e marcação (só admin).
class AdminChamadaVozScreen extends StatefulWidget {
  const AdminChamadaVozScreen({super.key, required this.chamadaId});
  final String chamadaId;

  @override
  State<AdminChamadaVozScreen> createState() => _AdminChamadaVozScreenState();
}

class _AdminChamadaVozScreenState extends State<AdminChamadaVozScreen> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _c;
  String? _erro;
  bool _gravando = false;
  final _nota = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final res = await _sb.rpc('admin_chamada_voz', params: {'p_id': widget.chamadaId});
      if (!mounted) return;
      setState(() {
        _c = res is Map ? Map<String, dynamic>.from(res) : null;
        _erro = _c == null ? 'Chamada não encontrada.' : null;
        _nota.text = '${_c?['nota_admin'] ?? ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = 'Não foi possível abrir a chamada: $e');
    }
  }

  Future<void> _ouvir() async {
    final caminho = _c?['audio_path'] as String?;
    if (caminho == null) return;
    try {
      // Link assinado de 10 minutos (o bucket é privado; só admin lê).
      final url = await _sb.storage.from('chamadas-voz').createSignedUrl(caminho, 600);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o áudio: $e')));
    }
  }

  Future<void> _marcar(String estado) async {
    setState(() => _gravando = true);
    try {
      await _sb.rpc('admin_chamada_voz_marcar', params: {
        'p_id': widget.chamadaId,
        'p_estado': estado,
        'p_nota': _nota.text.trim().isEmpty ? null : _nota.text.trim(),
      });
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(estado == 'resolvido' ? 'Marcada como resolvida.' : 'Marcada para a equipe.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Chamada')),
      body: c == null
          ? Center(child: _erro != null ? Text(_erro!) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rotuloPapelChamada(c['papel'] as String?)}'
                          '${c['nome_identificado'] != null ? ' · ${c['nome_identificado']}' : ''}'
                          '${c['teste'] == true ? '  [TESTE]' : ''}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('Telefone: ${c['telefone'] ?? '—'} (o número não prova quem é)'),
                        Text('Início: ${dataHoraLisboa(c['inicio'])} · Duração: ${_duracao(c['duracao_s'])}'),
                        Text('Situação: ${rotuloEstadoChamada(c['estado'] as String?)}'),
                        Text('Custo de IA: ${_usd(c['custo_usd'])} · Motor (modelo de IA): ${c['motor'] ?? '—'}'),
                        if (c['primeira_palavra_ms'] != null)
                          Text('Tempo até a primeira palavra: ${c['primeira_palavra_ms']} ms'),
                        if (c['gravacao_consentida'] == false)
                          const Text('A pessoa pediu para não gravar: o áudio não foi guardado.'),
                        const SizedBox(height: 8),
                        Text('Resumo', style: Theme.of(context).textTheme.titleSmall),
                        Text('${c['resumo'] ?? 'sem resumo'}'),
                        if (c['etiquetas'] is List && (c['etiquetas'] as List).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, children: [
                            for (final e in c['etiquetas'] as List) Chip(label: Text('$e')),
                          ]),
                        ],
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(
                            onPressed: c['audio_path'] == null ? null : _ouvir,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(c['audio_path'] == null ? 'Sem áudio' : 'Ouvir áudio'),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
                if (c['revisao_ia'] is Map) _revisao(Map<String, dynamic>.from(c['revisao_ia'] as Map)),
                Text('Transcrição (fala a fala)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final f in (c['falas'] is List ? c['falas'] as List : const []))
                  if (f is Map) _bolha(Map<String, dynamic>.from(f)),
                const SizedBox(height: 12),
                TextField(
                  controller: _nota,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nota da equipe (fica na auditoria)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _gravando ? null : () => _marcar('resolvido'),
                      child: const Text('Marcar resolvida'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _gravando ? null : () => _marcar('escalado'),
                      child: const Text('Deixar para a equipe'),
                    ),
                  ),
                ]),
              ],
            ),
    );
  }

  /// Revisão automática da chamada (voz-cerebro op "aprender"): nota, o que correu bem e as falhas.
  Widget _revisao(Map<String, dynamic> r) {
    final falhas = r['falhas'] is List ? (r['falhas'] as List) : const [];
    final novas = (r['licoes_novas'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Revisão automática da IA${r['nota'] != null ? ' · nota ${r['nota']}/10' : ''}',
                style: Theme.of(context).textTheme.titleSmall),
            if ((r['correu_bem'] ?? '').toString().isNotEmpty) Text('Correu bem: ${r['correu_bem']}'),
            for (final f in falhas) Text('• $f'),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(novas > 0 ? '$novas lição(ões) nova(s) aprendida(s) nesta chamada.' : 'Nenhuma lição nova.',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const AdminVozLicoesScreen())),
                child: const Text('Ver lições'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _bolha(Map<String, dynamic> f) {
    final quem = f['quem'] as String?;
    final cliente = quem == 'cliente';
    final rotulo = switch (quem) {
      'cliente' => 'Quem ligou',
      'atendente' => 'Atendente',
      'ferramenta' => 'Consulta',
      _ => 'Sistema',
    };
    return Align(
      alignment: cliente ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: cliente ? Colors.grey.shade200 : AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rotulo, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Text('${f['texto'] ?? ''}'),
          ],
        ),
      ),
    );
  }
}

/// Definições do atendente (todas pelo admin_voz_definir, que valida e audita).
class _DefinicoesVozSheet extends StatefulWidget {
  const _DefinicoesVozSheet({required this.defs});
  final Map<String, dynamic> defs;

  @override
  State<_DefinicoesVozSheet> createState() => _DefinicoesVozSheetState();
}

class _DefinicoesVozSheetState extends State<_DefinicoesVozSheet> {
  final _sb = Supabase.instance.client;
  late bool _ativo = widget.defs['voz_atendente_ativo'] == true;
  late String _voz = '${widget.defs['voz_voz'] ?? 'pt-PT-RaquelNeural'}';
  late final _saudacao = TextEditingController(text: '${widget.defs['voz_saudacao'] ?? ''}');
  late final _motor = TextEditingController(text: '${widget.defs['voz_motor'] ?? ''}');
  late final _reserva = TextEditingController(text: '${widget.defs['voz_motor_reserva'] ?? ''}');
  late final _email = TextEditingController(text: '${widget.defs['voz_email_suporte'] ?? ''}');
  late final _tetoChamada = TextEditingController(text: '${widget.defs['voz_opus_teto_chamada_eur'] ?? ''}');
  late final _tetoDia = TextEditingController(text: '${widget.defs['voz_opus_teto_dia_eur'] ?? ''}');
  late final _duracao = TextEditingController(text: '${widget.defs['voz_duracao_max_min'] ?? ''}');
  late final _linhas = TextEditingController(text: '${widget.defs['voz_linhas_simultaneas'] ?? ''}');
  bool _gravando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_saudacao, _motor, _reserva, _email, _tetoChamada, _tetoDia, _duracao, _linhas]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _gravar() async {
    num? n(TextEditingController c) => num.tryParse(c.text.trim().replaceAll(',', '.'));
    final novos = <String, Object>{
      'voz_atendente_ativo': _ativo,
      'voz_voz': _voz,
      'voz_saudacao': _saudacao.text.trim(),
      'voz_motor': _motor.text.trim(),
      'voz_motor_reserva': _reserva.text.trim(),
      'voz_email_suporte': _email.text.trim(),
      if (n(_tetoChamada) != null) 'voz_opus_teto_chamada_eur': n(_tetoChamada)!,
      if (n(_tetoDia) != null) 'voz_opus_teto_dia_eur': n(_tetoDia)!,
      if (n(_duracao) != null) 'voz_duracao_max_min': n(_duracao)!,
      if (n(_linhas) != null) 'voz_linhas_simultaneas': n(_linhas)!,
    };
    setState(() {
      _gravando = true;
      _erro = null;
    });
    try {
      for (final e in novos.entries) {
        if ('${widget.defs[e.key]}' == '${e.value}') continue; // só o que mudou
        await _sb.rpc('admin_voz_definir', params: {'p_key': e.key, 'p_value': e.value});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível salvar: $e');
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration d(String t, [String? ajuda]) =>
        InputDecoration(labelText: t, helperText: ajuda, helperMaxLines: 3, border: const OutlineInputBorder());
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Definições do atendente de voz', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
              title: const Text('Atendente ligado'),
              subtitle: const Text('Desligado: quem liga ouve uma mensagem curta e o e-mail de suporte.'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _saudacao,
              maxLines: 3,
              decoration: d('Saudação (primeira frase)',
                  'Obrigatório dizer "assistente virtual" e que a chamada é gravada (lei europeia de IA e RGPD).'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _voz,
              decoration: d('Voz (sempre português de Portugal)'),
              items: const [
                DropdownMenuItem(value: 'pt-PT-RaquelNeural', child: Text('Raquel — feminina')),
                DropdownMenuItem(value: 'pt-PT-DuarteNeural', child: Text('Duarte — masculina')),
              ],
              onChanged: (v) => setState(() => _voz = v ?? _voz),
            ),
            const SizedBox(height: 8),
            TextField(controller: _motor, decoration: d('Motor principal (modelo de IA)', 'Ex.: claude-opus-5-5')),
            const SizedBox(height: 8),
            TextField(controller: _reserva, decoration: d('Motor de reserva', 'Usado quando passa o teto do dia. Ex.: claude-sonnet-5-5')),
            const SizedBox(height: 8),
            TextField(controller: _email, decoration: d('E-mail de suporte dito ao cliente')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _tetoChamada, keyboardType: TextInputType.number, decoration: d('Teto por chamada (€)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _tetoDia, keyboardType: TextInputType.number, decoration: d('Teto por dia (€)'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _duracao, keyboardType: TextInputType.number, decoration: d('Duração máx. (min)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _linhas, keyboardType: TextInputType.number, decoration: d('Chamadas ao mesmo tempo'))),
            ]),
            if (_erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 12),
            FilledButton(onPressed: _gravando ? null : _gravar, child: Text(_gravando ? 'Salvando…' : 'Salvar')),
          ],
        ),
      ),
    );
  }
}
