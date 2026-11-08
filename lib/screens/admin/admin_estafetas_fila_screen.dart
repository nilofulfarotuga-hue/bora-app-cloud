import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/minha_conta.dart';
import '../../services/minha_conta_service.dart';
import 'admin_driver_approval_screen.dart';

/// PAINEL · ESTAFETAS — FILA E DOCUMENTOS (missão m2-estafeta-conta-fila-2026-11-08).
///
/// Paridade com o ecrã "A minha conta" da app: o MESMO semáforo por item
/// (`driver_minha_conta_estado`), a fase de cada candidato (documentos
/// pendentes → em verificação → fila de espera → aprovado) e os botões:
///  · Aprovar — abre a aprovação de sempre; aprovar é SÓ do Danilo;
///  · Reenviar mensagem do que falta — o robô dos documentos
///    (`admin_robo_documentos_lembrar`);
///  · Marcar atividade confirmada — `admin_provider_atividade_decidir`, com
///    motivo.
/// Enquanto a função `admin_estafetas_fila` não está no servidor (proposta
/// 03 da missão), lê a tabela `drivers` e monta o semáforo pela regra da app.
/// PT-BR (painel).
class AdminEstafetasFilaScreen extends StatefulWidget {
  const AdminEstafetasFilaScreen({super.key, this.carregar});

  /// Só para testes: troca o servidor.
  final Future<List<LinhaEstafetaFila>> Function(String filtro)? carregar;

  @override
  State<AdminEstafetasFilaScreen> createState() =>
      _AdminEstafetasFilaScreenState();
}

/// Uma linha do painel.
class LinhaEstafetaFila {
  const LinhaEstafetaFila({
    required this.userId,
    required this.nome,
    required this.approvalStatus,
    required this.fase,
    required this.conta,
    this.vehicleType,
  });

  final String userId;
  final String nome;
  final String? approvalStatus;
  final String? vehicleType;
  final FaseCandidato fase;
  final EstadoMinhaConta conta;

  factory LinhaEstafetaFila.fromJson(Map<String, dynamic> j) =>
      LinhaEstafetaFila(
        userId: (j['user_id'] ?? '').toString(),
        nome: (j['nome'] ?? '—').toString(),
        approvalStatus: j['approval_status']?.toString(),
        vehicleType: j['vehicle_type']?.toString(),
        fase: faseCandidatoDeTexto(j['fase']?.toString()),
        conta: EstadoMinhaConta.fromJson(j['conta']),
      );
}

String rotuloFase(FaseCandidato f) => switch (f) {
      FaseCandidato.documentosPendentes => 'Documentos pendentes',
      FaseCandidato.emVerificacao => 'Em verificação',
      FaseCandidato.filaDeEspera => 'Na fila de espera',
      FaseCandidato.aprovado => 'Aprovado',
      FaseCandidato.recusado => 'Recusado',
    };

Color corFase(FaseCandidato f) => switch (f) {
      FaseCandidato.documentosPendentes => AppColors.error,
      FaseCandidato.emVerificacao => Colors.amber.shade800,
      FaseCandidato.filaDeEspera => Colors.blue.shade700,
      FaseCandidato.aprovado => AppColors.success,
      FaseCandidato.recusado => Colors.grey.shade700,
    };

class _AdminEstafetasFilaScreenState extends State<AdminEstafetasFilaScreen> {
  static const _filtros = <(String, String)>[
    ('todos', 'Todos'),
    ('na_fila', 'Na fila'),
    ('incompletos', 'Incompletos'),
    ('aprovados', 'Aprovados'),
  ];

  String _filtro = 'todos';
  List<LinhaEstafetaFila>? _linhas;
  String? _erro;
  bool _doServidor = true;
  String? _aAgir;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _linhas = null;
      _erro = null;
    });
    try {
      final l = await (widget.carregar?.call(_filtro) ?? _doBanco(_filtro));
      if (!mounted) return;
      setState(() => _linhas = l);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = 'Não foi possível carregar: $e');
    }
  }

  Future<List<LinhaEstafetaFila>> _doBanco(String filtro) async {
    try {
      final r = await _sb
          .rpc('admin_estafetas_fila', params: {'p_filtro': filtro});
      if (r is Map && r['ok'] == true && r['estafetas'] is List) {
        _doServidor = true;
        return [
          for (final e in r['estafetas'] as List)
            if (e is Map) LinhaEstafetaFila.fromJson(Map<String, dynamic>.from(e)),
        ];
      }
    } catch (e) {
      debugPrint('[AdminEstafetasFila] admin_estafetas_fila: $e');
    }
    // Sem a função no servidor: monta pela regra da app, só com a linha.
    _doServidor = false;
    final rows = await _sb
        .from('drivers')
        .select('${MinhaContaService.colunas}, deleted_at, submitted_at')
        .inFilter('approval_status', ['pending', 'approved'])
        .isFilter('deleted_at', null)
        .order('submitted_at', ascending: true);
    final out = <LinhaEstafetaFila>[];
    for (final row in rows) {
      final d = Map<String, dynamic>.from(row);
      final conta = montarMinhaConta(driver: d);
      final docs = conta.emFalta
          .where((i) => const {'selfie', 'document', 'document_number', 'vehicle', 'license_plate'}
              .contains(i.chave))
          .length;
      final fase = faseDoCandidato(
        approvalStatus: d['approval_status']?.toString(),
        emFalta: docs,
        roboAgir: false,
        roboTudoOk: false,
      );
      final passa = switch (filtro) {
        'na_fila' => fase == FaseCandidato.filaDeEspera,
        'incompletos' => fase == FaseCandidato.documentosPendentes,
        'aprovados' => fase == FaseCandidato.aprovado,
        _ => true,
      };
      if (!passa) continue;
      out.add(LinhaEstafetaFila(
        userId: (d['user_id'] ?? '').toString(),
        nome: (d['name'] ?? '—').toString(),
        approvalStatus: d['approval_status']?.toString(),
        vehicleType: d['vehicle_type']?.toString(),
        fase: fase,
        conta: conta,
      ));
    }
    return out;
  }

  void _msg(String t, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t), backgroundColor: ok ? AppColors.success : null));
  }

  Future<void> _reenviar(LinhaEstafetaFila l) async {
    setState(() => _aAgir = l.userId);
    try {
      final r = await _sb.rpc('admin_robo_documentos_lembrar',
          params: {'p_user_id': l.userId});
      final enviado = r is Map && r['enviado'] == true;
      _msg(
          enviado
              ? 'Mensagem do que falta enviada para ${l.nome}.'
              : 'Não enviado: ${r is Map ? (r['porque'] ?? r['error'] ?? 'sem motivo') : r}',
          ok: enviado);
    } catch (e) {
      _msg('Erro ao reenviar: $e');
    } finally {
      if (mounted) setState(() => _aAgir = null);
    }
  }

  Future<void> _confirmarAtividade(LinhaEstafetaFila l) async {
    final ctrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Marcar atividade confirmada — ${l.nome}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Motivo (obrigatório)',
            hintText: 'Ex.: conferi no Portal das Finanças',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (motivo == null || motivo.isEmpty) return;
    setState(() => _aAgir = l.userId);
    try {
      await _sb.rpc('admin_provider_atividade_decidir', params: {
        'p_user_id': l.userId,
        'p_acao': 'aprovar',
        'p_motivo': motivo,
        'p_avisar': true,
      });
      _msg('Atividade de ${l.nome} marcada como confirmada.', ok: true);
      await _carregar();
    } catch (e) {
      _msg('Erro: $e');
    } finally {
      if (mounted) setState(() => _aAgir = null);
    }
  }

  Future<void> _aprovar() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AdminDriverApprovalScreen()));
    await _carregar();
  }

  Widget _semaforo(EstadoMinhaConta c) {
    if (c.itens.isEmpty) {
      return const Text('Sem dados da conta.',
          style: TextStyle(color: Colors.grey));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final i in c.itens)
          Chip(
            key: Key('admin_fila_item_${i.chave}'),
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              switch (i.estado) {
                EstadoItemConta.ok => Icons.check_circle,
                EstadoItemConta.emAnalise => Icons.hourglass_top,
                EstadoItemConta.falta => Icons.error,
              },
              size: 16,
              color: switch (i.estado) {
                EstadoItemConta.ok => AppColors.success,
                EstadoItemConta.emAnalise => Colors.amber.shade800,
                EstadoItemConta.falta =>
                  i.opcional ? Colors.grey : AppColors.error,
              },
            ),
            label: Text(i.rotuloCurto, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _linha(LinhaEstafetaFila l) {
    final falta = l.conta.emFalta;
    final ocupado = _aAgir != null;
    return Card(
      key: Key('admin_fila_${l.userId}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 8,
          backgroundColor: corFase(l.fase),
        ),
        title: Text(l.nome, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${rotuloFase(l.fase)}'
          '${falta.isEmpty ? '' : ' · falta: ${juntarComVirgulas(falta.map((i) => i.rotuloCurto).toList())}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _semaforo(l.conta),
          const SizedBox(height: 10),
          if (_aAgir == l.userId)
            const LinearProgressIndicator()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (l.approvalStatus == 'pending')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    onPressed: ocupado ? null : _aprovar,
                    icon: const Icon(Icons.verified_user, size: 18),
                    label: const Text('Aprovar (só o Danilo)'),
                  ),
                OutlinedButton.icon(
                  onPressed: ocupado || falta.isEmpty ? null : () => _reenviar(l),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Reenviar mensagem do que falta'),
                ),
                OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _confirmarAtividade(l),
                  icon: const Icon(Icons.assignment_turned_in, size: 18),
                  label: const Text('Marcar atividade confirmada'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estafetas — fila e documentos'),
        actions: [
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                for (final (k, rotulo) in _filtros)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('admin_fila_filtro_$k'),
                      label: Text(rotulo),
                      selected: _filtro == k,
                      onSelected: (_) {
                        setState(() => _filtro = k);
                        _carregar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (!_doServidor)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Modo simplificado: a função admin_estafetas_fila ainda não está no '
                'servidor — mostrando só os documentos da ficha (sem NIF, '
                'comprovativo, recibo e dívida).',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
          Expanded(
            child: _erro != null
                ? Center(child: Text(_erro!))
                : linhas == null
                    ? const Center(child: CircularProgressIndicator())
                    : linhas.isEmpty
                        ? const Center(child: Text('Ninguém neste filtro.'))
                        : RefreshIndicator(
                            onRefresh: _carregar,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [for (final l in linhas) _linha(l)],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
