// Painel admin (PT-BR) — Caixa de guardados + Quadro Sim/Não
// (missão sistema-conteudo-14-11, blocos 5.3 e 5.5).
//
// Separador "Esperando você" (Quadro Sim/Não): num só lugar, tudo o que espera pelo Danilo —
//   (a) linhas da public.caixa_guardados por decidir (guardado, analisado, precisa-danilo):
//       Sim → estado 'aprovado' + decisao 'sim (painel)'; Não → estado 'rejeitado';
//   (b) opções do radar sem resposta (public.radar_videos, veredito 'pendente', nota 8 ou mais —
//       os lotes enviados ao Telegram vivem num ficheiro da VPS, não na base):
//       Sim → tarefa no despacho para o Emerson + veredito 'despachado'; Não → 'rejeitado-danilo'
//       (as duas pela função admin_quadro_radar_decidir);
//   (c) propostas do Córtex por rever (public.cortex_red_proposals, status 'nova', pelas RPCs que a
//       Central já usa): Sim → cortex_proposal_approve (com confirmação, é zona vermelha);
//       Não → cortex_proposal_mark_status 'decidida_fora'.
// Separador "Caixa toda": a lista inteira com filtro por estado e tipo, mais recentes primeiro;
// abrir um item mostra o conteúdo completo e deixa editar estado/decisão/resultado/prioridade,
// marcar feito ou rejeitar. Por cima dos dois: o agente de segunda e o botão "Correr agora"
// (linha em public.despacho, para = 'agente-segunda').
//
// Leitura e escrita da caixa e do despacho vão direto pelo PostgREST (policies com is_admin()).
// NUNCA se apaga uma linha daqui. Datas em hora de Lisboa (dataHoraLisboa).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_bottom_action_bar.dart';

/// Estados da caixa. 'aprovado' só passa na base depois da migração
/// supabase/migrations/PROPOSTA_20261114_quadro_sim_nao_painel_admin.sql (Sim do Quadro).
const Map<String, String> kCaixaEstados = {
  'guardado': 'Guardado',
  'analisado': 'Analisado',
  'precisa-danilo': 'Precisa de você',
  'aprovado': 'Aprovado',
  'em-curso': 'Em curso',
  'feito': 'Feito',
  'rejeitado': 'Rejeitado',
};

/// Estados que ainda esperam uma decisão do Danilo (entram no Quadro Sim/Não).
const List<String> kCaixaPorDecidir = ['guardado', 'analisado', 'precisa-danilo'];

/// Tipos aceites pela base (check caixa_guardados_tipo_check).
const Map<String, String> kCaixaTipos = {
  'missao': 'Missão',
  'tarefa': 'Tarefa',
  'video': 'Vídeo',
  'ideia': 'Ideia',
  'link': 'Link',
};

/// Estados de public.despacho (check despacho_estado_check), em PT-BR.
const Map<String, String> kDespachoEstados = {
  'aberta': 'Na fila (ainda não começou)',
  'executando': 'Executando agora',
  'feita': 'Feita',
  'falhou': 'Falhou',
  'a-espera-do-danilo': 'Esperando você',
  'a-espera-do-pc': 'Esperando o PC',
  'cancelada': 'Cancelada',
};

/// Origem gravada no despacho quando o pedido vem deste ecrã. O check despacho_origem_check só
/// aceita danilo-telegram, claude-ai, relogio, evento e agente: um clique no painel é um 'evento',
/// e o título e a tarefa acabam em "(painel admin)" para se saber de onde veio.
const String kCaixaOrigemDespacho = 'evento';
const String kCaixaMarcaPainel = '(painel admin)';
const String kCaixaAgente = 'agente-segunda';
const String kCaixaMigracao = 'PROPOSTA_20261114_quadro_sim_nao_painel_admin.sql';

/// Nota mínima para uma opção do radar aparecer no Quadro.
const int kRadarNotaMinima = 8;

/// De onde o ecrã lê e para onde escreve. Em produção é o Supabase; nos testes, uma
/// fonte falsa (o ecrã renderiza sem Supabase inicializado).
abstract class CaixaGuardadosFonte {
  Future<List<Map<String, dynamic>>> listar({String? estado, String? tipo});
  Future<List<Map<String, dynamic>>> caixaPorDecidir();
  Future<List<Map<String, dynamic>>> radarPendentes();

  /// Propostas do Córtex por rever; null = não deu para ler (o ecrã manda ver no Córtex).
  Future<List<Map<String, dynamic>>?> cortexPendentes();
  Future<Map<String, dynamic>?> ultimoPedidoAgente();

  /// Atualiza uma linha da caixa e devolve quantas mudaram (0 = não gravou).
  Future<int> atualizar(int id, Map<String, dynamic> campos, {required String acao});
  Future<void> correrAgora();
  Future<void> radarDecidir(String youtubeId, {required bool sim});
  Future<void> cortexDecidir(String pid, {required bool sim});
}

class CaixaGuardadosFonteSupabase implements CaixaGuardadosFonte {
  SupabaseClient get _c => Supabase.instance.client;

  static const _colunas =
      'id,criado_em,origem,tipo,titulo,conteudo,prioridade,estado,decisao,resultado,ref,analisado_em,feito_em';

  @override
  Future<List<Map<String, dynamic>>> listar({String? estado, String? tipo}) async {
    var q = _c.from('caixa_guardados').select(_colunas);
    if (estado != null) q = q.eq('estado', estado);
    if (tipo != null) q = q.eq('tipo', tipo);
    final r = await q.order('criado_em', ascending: false).limit(300);
    return r.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> caixaPorDecidir() async {
    final r = await _c
        .from('caixa_guardados')
        .select(_colunas)
        .inFilter('estado', kCaixaPorDecidir)
        .order('criado_em', ascending: false)
        .limit(100);
    return r.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> radarPendentes() async {
    final r = await _c
        .from('radar_videos')
        .select('youtube_id,titulo,canal,link,tema,nota_utilidade,transcricao_resumida,ideias,recolhido_em,veredito')
        .eq('veredito', 'pendente')
        .gte('nota_utilidade', kRadarNotaMinima)
        .order('nota_utilidade', ascending: false)
        .order('recolhido_em', ascending: false)
        .limit(40);
    return r.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>?> cortexPendentes() async {
    try {
      final r = await _c.rpc('cortex_list_red_proposals',
          params: {'p_status': 'nova', 'p_limit': 100, 'p_offset': 0});
      return ((r as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('[AdminCaixaGuardados] Córtex indisponível: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> ultimoPedidoAgente() async {
    final r = await _c
        .from('despacho')
        .select('id,origem,estado,resultado,created_at,iniciada_em,terminada_em')
        .eq('para', kCaixaAgente)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  @override
  Future<int> atualizar(int id, Map<String, dynamic> campos, {required String acao}) async {
    final r = await _c.from('caixa_guardados').update(campos).eq('id', id).select('id');
    final n = r.length;
    if (n > 0) await _auditar(acao, 'caixa_guardados', '$id', campos);
    return n;
  }

  @override
  Future<void> correrAgora() async {
    final r = await _c
        .from('despacho')
        .insert({
          'origem': kCaixaOrigemDespacho,
          'para': kCaixaAgente,
          'tipo': 'tarefa',
          'titulo': 'agente-segunda: correr agora $kCaixaMarcaPainel',
          'tarefa': 'Correr o agente de segunda-feira agora $kCaixaMarcaPainel',
          'prioridade': 90,
          'estado': 'aberta',
        })
        .select('id')
        .single();
    await _auditar('caixa_correr_agora', 'despacho', '${r['id']}', {'para': kCaixaAgente});
  }

  // A função audita sozinha (log_admin_action dentro dela).
  @override
  Future<void> radarDecidir(String youtubeId, {required bool sim}) async {
    await _c.rpc('admin_quadro_radar_decidir', params: {'p_youtube_id': youtubeId, 'p_sim': sim});
  }

  // As mesmas RPCs da Central (admin_robot_suggestions_screen), que já auditam.
  @override
  Future<void> cortexDecidir(String pid, {required bool sim}) async {
    if (sim) {
      await _c.rpc('cortex_proposal_approve', params: {'p_pid': pid});
    } else {
      await _c.rpc('cortex_proposal_mark_status', params: {
        'p_pid': pid,
        'p_status': 'decidida_fora',
        'p_nota': 'não (painel, Quadro Sim/Não)',
      });
    }
  }

  // Auditoria: sobrecarga log_admin_action(p_action_type text, ..., p_entity_id text, ...)
  // que escreve em admin_audit_log.entity_id_text. Falha da auditoria não desfaz a ação.
  Future<void> _auditar(String acao, String tipo, String id, Map<String, dynamic> detalhe) async {
    try {
      await _c.rpc('log_admin_action', params: {
        'p_action_type': acao,
        'p_entity_type': tipo,
        'p_entity_id': id,
        'p_details': detalhe,
      });
    } catch (e) {
      debugPrint('[AdminCaixaGuardados] auditoria falhou: $e');
    }
  }
}

class AdminCaixaGuardadosScreen extends StatefulWidget {
  const AdminCaixaGuardadosScreen({super.key, this.fonte});

  /// Só para testes; em produção fica nulo e usa o Supabase.
  final CaixaGuardadosFonte? fonte;

  @override
  State<AdminCaixaGuardadosScreen> createState() => _AdminCaixaGuardadosScreenState();
}

class _AdminCaixaGuardadosScreenState extends State<AdminCaixaGuardadosScreen> {
  late final CaixaGuardadosFonte _fonte = widget.fonte ?? CaixaGuardadosFonteSupabase();
  bool _carregando = true;
  bool _aPedir = false;
  String? _erro;
  String? _erroRadar;
  List<Map<String, dynamic>> _lista = const [];
  List<Map<String, dynamic>> _caixaDecidir = const [];
  List<Map<String, dynamic>> _radar = const [];
  List<Map<String, dynamic>>? _cortex = const [];
  Map<String, dynamic>? _ultimo;
  String? _estado;
  String? _tipo;
  final Set<String> _aDecidir = {};

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
      final l = await _fonte.listar(estado: _estado, tipo: _tipo);
      final d = await _fonte.caixaPorDecidir();
      final u = await _fonte.ultimoPedidoAgente();
      List<Map<String, dynamic>> radar = const [];
      String? erroRadar;
      try {
        radar = await _fonte.radarPendentes();
      } catch (e) {
        erroRadar = e.toString();
      }
      final cortex = await _fonte.cortexPendentes();
      if (!mounted) return;
      setState(() {
        _lista = l;
        _caixaDecidir = d;
        _ultimo = u;
        _radar = radar;
        _erroRadar = erroRadar;
        _cortex = cortex;
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

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? AppColors.error : null));
  }

  String _erroSimples(Object e) {
    final t = e.toString();
    if (t.contains('caixa_guardados_estado_check') ||
        t.contains('admin_quadro_radar_decidir') ||
        t.contains('PGRST202')) {
      return 'O servidor ainda não aceita isto vindo do painel: falta aplicar a migração $kCaixaMigracao.';
    }
    if (t.contains('so_admin') || t.contains('row-level security') || t.contains('42501')) {
      return 'Só o administrador pode fazer isso.';
    }
    if (t.contains('ja_decidido')) return 'Essa opção já foi decidida. Atualize a lista.';
    if (t.contains('_check')) return 'A base recusou o valor (fora da lista permitida).';
    return 'Não deu certo: $t';
  }

  bool get _agenteOcupado {
    final e = _ultimo?['estado'];
    return e == 'aberta' || e == 'executando';
  }

  int get _totalEsperando => _caixaDecidir.length + _radar.length + (_cortex?.length ?? 0);

  // ── Correr agora ────────────────────────────────────────────────────────────
  Future<void> _correrAgora() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Correr o agente de segunda agora?'),
        content: const Text(
            'Vai um pedido para a fila do agente (despacho). Ele analisa a caixa de guardados '
            'como faria na segunda-feira. Acompanhe o estado aqui no topo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Correr agora')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _aPedir = true);
    try {
      await _fonte.correrAgora();
      _aviso('Pedido na fila do agente de segunda.');
      await _carregar();
    } catch (e) {
      _aviso(_erroSimples(e), erro: true);
    } finally {
      if (mounted) setState(() => _aPedir = false);
    }
  }

  // ── Caixa: gravar, feito, rejeitar ──────────────────────────────────────────
  Future<bool> _gravar(Map<String, dynamic> item, Map<String, dynamic> campos,
      {required String acao, required String feito}) async {
    try {
      final n = await _fonte.atualizar((item['id'] as num).toInt(), campos, acao: acao);
      if (n == 0) {
        _aviso('Nada foi gravado (0 linhas). Atualize e tente de novo.', erro: true);
        return false;
      }
      _aviso(feito);
      await _carregar();
      return true;
    } catch (e) {
      _aviso(_erroSimples(e), erro: true);
      return false;
    }
  }

  // feito_em vai com a hora do aparelho em UTC (o PostgREST não deixa usar now() num update).
  String _agoraUtc() => DateTime.now().toUtc().toIso8601String();

  Future<bool> _marcarFeito(Map<String, dynamic> item) => _gravar(
        item,
        {'estado': 'feito', 'feito_em': _agoraUtc()},
        acao: 'caixa_marcar_feito',
        feito: 'Marcado como feito.',
      );

  Future<bool> _rejeitar(Map<String, dynamic> item) async {
    final motivo = TextEditingController(text: '${item['decisao'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar este guardado?'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: motivo,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Motivo (fica na decisão)', alignLabelWithHint: true),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    final texto = motivo.text.trim();
    if (texto.isEmpty) {
      _aviso('Escreva o motivo para rejeitar.', erro: true);
      return false;
    }
    return _gravar(item, {'estado': 'rejeitado', 'decisao': texto},
        acao: 'caixa_rejeitar', feito: 'Rejeitado.');
  }

  // ── Quadro Sim/Não ──────────────────────────────────────────────────────────
  Future<void> _decidir(String chave, Future<void> Function() acao) async {
    setState(() => _aDecidir.add(chave));
    try {
      await acao();
    } finally {
      if (mounted) setState(() => _aDecidir.remove(chave));
    }
  }

  Future<void> _caixaSim(Map<String, dynamic> i) async {
    await _gravar(i, {'estado': 'aprovado', 'decisao': 'sim (painel)'},
        acao: 'quadro_caixa_sim', feito: 'Aprovado.');
  }

  Future<void> _caixaNao(Map<String, dynamic> i) async {
    await _gravar(i, {'estado': 'rejeitado'}, acao: 'quadro_caixa_nao', feito: 'Rejeitado.');
  }

  Future<void> _radarDecidir(Map<String, dynamic> v, {required bool sim}) async {
    try {
      await _fonte.radarDecidir('${v['youtube_id']}', sim: sim);
      _aviso(sim ? 'Tarefa criada para o Emerson.' : 'Opção do radar rejeitada.');
      await _carregar();
    } catch (e) {
      _aviso(_erroSimples(e), erro: true);
    }
  }

  Future<void> _cortexDecidir(Map<String, dynamic> p, {required bool sim}) async {
    if (sim) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aprovar esta proposta do Córtex?'),
          content: const Text(
              'É uma proposta de zona vermelha. Fica marcada como aprovada por você e entra na fila '
              'normal (próxima sincronização, até 10 min). Se o texto tocar em dinheiro, o carteiro '
              'volta a pedir a sua confirmação no Telegram.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprovar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _fonte.cortexDecidir('${p['pid']}', sim: sim);
      _aviso(sim ? 'Proposta aprovada.' : 'Proposta marcada como "não".');
      await _carregar();
    } catch (e) {
      _aviso(_erroSimples(e), erro: true);
    }
  }

  Future<void> _verTexto(String titulo, String texto) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(texto, style: const TextStyle(height: 1.4))),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );

  String _ideias(Object? ideias) {
    if (ideias == null) return '';
    if (ideias is List) return ideias.map((e) => '• $e').join('\n');
    return '$ideias';
  }

  Future<void> _exportarCsv() async {
    String c(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final linhas = <String>[
      'id;criado_em_lisboa;origem;tipo;titulo;prioridade;estado;decisao;resultado;ref;analisado_em_lisboa;feito_em_lisboa;conteudo',
      for (final i in _lista)
        [
          i['id'], dataHoraLisboa(i['criado_em']), i['origem'], i['tipo'], i['titulo'], i['prioridade'],
          i['estado'], i['decisao'], i['resultado'], i['ref'], dataHoraLisboa(i['analisado_em']),
          dataHoraLisboa(i['feito_em']), i['conteudo'],
        ].map(c).join(';'),
    ];
    await AdminExportService.instance.exportCsvText(
      filename: 'caixa_guardados_${DateTime.now().millisecondsSinceEpoch}.csv',
      csv: linhas.join('\n'),
    );
    _aviso('CSV com ${_lista.length} guardados descarregado.');
  }

  Color _corEstado(String? e) {
    switch (e) {
      case 'feito':
      case 'aprovado':
        return AppColors.success;
      case 'rejeitado':
        return AppColors.error;
      case 'em-curso':
        return AppColors.info;
      case 'precisa-danilo':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  // ── Detalhe de um guardado ──────────────────────────────────────────────────
  Future<void> _abrirDetalhe(Map<String, dynamic> item) async {
    final decisao = TextEditingController(text: '${item['decisao'] ?? ''}');
    final resultado = TextEditingController(text: '${item['resultado'] ?? ''}');
    String estado = kCaixaEstados.containsKey(item['estado']) ? '${item['estado']}' : 'guardado';
    int prioridade = ((item['prioridade'] as num?)?.toInt() ?? 3).clamp(1, 5);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (_, controle) => ListView(
            controller: controle,
            padding: EdgeInsets.fromLTRB(20, 20, 20, BoraBottomActionBar.folgaInferior(ctx, base: 20)),
            children: [
              SelectableText('${item['titulo'] ?? '—'}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${kCaixaTipos[item['tipo']] ?? item['tipo']} · de ${item['origem'] ?? '—'} · '
                'guardado em ${dataHoraLisboa(item['criado_em'])} (Lisboa)',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              if ((item['ref'] ?? '').toString().isNotEmpty) _linha('Referência', item['ref']),
              _linha('Analisado em', dataHoraLisboa(item['analisado_em'])),
              _linha('Feito em', dataHoraLisboa(item['feito_em'])),
              const SizedBox(height: 12),
              const Text('Conteúdo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
                child: SelectableText(
                  (item['conteudo'] ?? '').toString().isEmpty ? '(sem conteúdo)' : '${item['conteudo']}',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Editar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                DropdownButton<String>(
                  value: estado,
                  items: [
                    for (final e in kCaixaEstados.entries)
                      DropdownMenuItem(value: e.key, child: Text('Estado: ${e.value}')),
                  ],
                  onChanged: (v) => setSheet(() => estado = v ?? estado),
                ),
                DropdownButton<int>(
                  value: prioridade,
                  items: [
                    for (var p = 1; p <= 5; p++) DropdownMenuItem(value: p, child: Text('Prioridade $p')),
                  ],
                  onChanged: (v) => setSheet(() => prioridade = v ?? prioridade),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: decisao,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Decisão', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: resultado,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Resultado', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () async {
                    final campos = <String, dynamic>{
                      'estado': estado,
                      'prioridade': prioridade,
                      'decisao': decisao.text.trim().isEmpty ? null : decisao.text.trim(),
                      'resultado': resultado.text.trim().isEmpty ? null : resultado.text.trim(),
                      if (estado == 'feito' && item['feito_em'] == null) 'feito_em': _agoraUtc(),
                    };
                    if (await _gravar(item, campos, acao: 'caixa_editar', feito: 'Guardado.') &&
                        ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
                OutlinedButton.icon(
                  onPressed: item['estado'] == 'feito'
                      ? null
                      : () async {
                          if (await _marcarFeito(item) && ctx.mounted) Navigator.pop(ctx);
                        },
                  icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
                  label: const Text('Marcar feito'),
                ),
                OutlinedButton.icon(
                  onPressed: item['estado'] == 'rejeitado'
                      ? null
                      : () async {
                          if (await _rejeitar(item) && ctx.mounted) Navigator.pop(ctx);
                        },
                  icon: const Icon(Icons.block, color: AppColors.error),
                  label: const Text('Rejeitar'),
                ),
              ]),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
    decisao.dispose();
    resultado.dispose();
  }

  Widget _linha(String rotulo, Object? valor) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SelectableText('$rotulo: ${(valor ?? '').toString().isEmpty ? '—' : valor}',
            style: const TextStyle(fontSize: 13)),
      );

  // ── Pedaços do ecrã ─────────────────────────────────────────────────────────
  Widget _cartaoAgente() {
    final u = _ultimo;
    final estado = u?['estado']?.toString();
    final resultado = (u?['resultado'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Agente de segunda-feira',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            FilledButton.icon(
              onPressed: _aPedir || _agenteOcupado ? null : _correrAgora,
              icon: _aPedir
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Correr agora'),
            ),
          ]),
          const SizedBox(height: 4),
          if (u == null)
            const Text('Ainda não houve nenhum pedido ao agente de segunda.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
          else ...[
            Text(
              'Último pedido: ${kDespachoEstados[estado] ?? estado ?? '—'} · '
              'pedido em ${dataHoraLisboa(u['created_at'])}'
              '${u['terminada_em'] != null ? ' · terminou ${dataHoraLisboa(u['terminada_em'])}' : ''}'
              ' (Lisboa) · de ${u['origem'] ?? '—'}',
              style: const TextStyle(fontSize: 12),
            ),
            if (resultado.isNotEmpty)
              SelectableText('Resultado: $resultado',
                  maxLines: 3, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (_agenteOcupado)
              const Text('Já há um pedido em andamento: o botão volta quando ele terminar.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ]),
      ),
    );
  }

  Widget _cabecalho(String titulo, String? contagem) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(contagem == null ? titulo : '$titulo ($contagem)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _vazio(String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(texto, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      );

  Widget _itemSimNao({
    required String chave,
    required String titulo,
    required String detalhe,
    required VoidCallback onAbrir,
    required Future<void> Function() onSim,
    required Future<void> Function() onNao,
  }) {
    final ocupado = _aDecidir.contains(chave);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: onAbrir,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(detalhe, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Text('Toque para ler tudo', style: TextStyle(fontSize: 11, color: AppColors.textSubtle)),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: ocupado ? null : () => _decidir(chave, onSim),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Sim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  onPressed: ocupado ? null : () => _decidir(chave, onNao),
                  icon: const Icon(Icons.close_rounded, color: AppColors.error),
                  label: const Text('Não', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _quadro() {
    final cortex = _cortex;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Text(
            'Tudo o que espera por você, num só lugar. "Sim" avança, "Não" arquiva.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          // (a) caixa de guardados
          _cabecalho('Caixa de guardados', '${_caixaDecidir.length}'),
          if (_caixaDecidir.isEmpty) _vazio('Nada por decidir na caixa.'),
          for (final i in _caixaDecidir)
            _itemSimNao(
              chave: 'c:${i['id']}',
              titulo: '${i['titulo'] ?? '—'}',
              detalhe: '${kCaixaTipos[i['tipo']] ?? i['tipo']} · ${kCaixaEstados[i['estado']] ?? i['estado']} · '
                  'prioridade ${i['prioridade'] ?? '—'} · ${dataHoraLisboa(i['criado_em'])} · de ${i['origem'] ?? '—'}',
              onAbrir: () => _abrirDetalhe(i),
              onSim: () => _caixaSim(i),
              onNao: () => _caixaNao(i),
            ),
          // (b) opções do radar
          _cabecalho('Opções do radar (nota $kRadarNotaMinima ou mais)', '${_radar.length}'),
          if (_erroRadar != null)
            _vazio('Não consegui ler o radar: $_erroRadar')
          else if (_radar.isEmpty)
            _vazio('Nenhuma opção do radar à espera.')
          else if (_radar.length >= 40)
            _vazio('Mostrando as 40 de nota mais alta; o resto está no ecrã "Radar de vídeos".'),
          for (final v in _radar)
            _itemSimNao(
              chave: 'r:${v['youtube_id']}',
              titulo: '${(v['tema'] ?? '').toString().isNotEmpty ? v['tema'] : v['titulo'] ?? '—'}',
              detalhe: 'nota ${v['nota_utilidade'] ?? '—'} · ${v['canal'] ?? '—'} · '
                  'recolhido ${dataHoraLisboa(v['recolhido_em'])} · Sim cria tarefa para o Emerson',
              onAbrir: () => _verTexto(
                '${v['titulo'] ?? 'Vídeo'}',
                [
                  'Link: ${v['link'] ?? '—'}',
                  'Tema: ${v['tema'] ?? '—'}',
                  '',
                  'Resumo:\n${v['transcricao_resumida'] ?? '—'}',
                  '',
                  'Ideias:\n${_ideias(v['ideias'])}',
                ].join('\n'),
              ),
              onSim: () => _radarDecidir(v, sim: true),
              onNao: () => _radarDecidir(v, sim: false),
            ),
          // (c) propostas do Córtex
          _cabecalho('Propostas do Córtex', cortex == null ? null : '${cortex.length}'),
          if (cortex == null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.hub_outlined),
                title: Text('Propostas do Córtex: ver no Córtex'),
                subtitle: Text('Não deu para ler as propostas a partir daqui.'),
              ),
            )
          else if (cortex.isEmpty)
            _vazio('Nenhuma proposta do Córtex à espera.')
          else
            for (final p in cortex)
              _itemSimNao(
                chave: 'x:${p['pid']}',
                titulo: '${p['tarefa'] ?? p['pid']}',
                detalhe: 'zona ${p['zona'] ?? '—'} · ${p['tipo'] ?? '—'} · de ${p['who'] ?? '—'} · '
                    '${dataHoraLisboa(p['criada_em'])}',
                onAbrir: () => _verTexto('Proposta ${p['pid']}', '${p['tarefa'] ?? ''}'),
                onSim: () => _cortexDecidir(p, sim: true),
                onNao: () => _cortexDecidir(p, sim: false),
              ),
        ],
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> i) {
    final estado = '${i['estado']}';
    final cor = _corEstado(estado);
    return Card(
      child: ListTile(
        onTap: () => _abrirDetalhe(i),
        title: Text('${i['titulo'] ?? '—'}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${kCaixaTipos[i['tipo']] ?? i['tipo']} · prioridade ${i['prioridade'] ?? '—'} · '
          '${dataHoraLisboa(i['criado_em'])} · de ${i['origem'] ?? '—'}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(kCaixaEstados[estado] ?? estado,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
        ),
      ),
    );
  }

  Widget _caixaToda() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: _estado == null,
              onSelected: (_) {
                setState(() => _estado = null);
                _carregar();
              },
            ),
            for (final e in kCaixaEstados.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _estado == e.key,
                onSelected: (_) {
                  setState(() => _estado = e.key);
                  _carregar();
                },
              ),
          ]),
          const SizedBox(height: 8),
          DropdownButton<String?>(
            value: _tipo,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos os tipos')),
              for (final e in kCaixaTipos.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              setState(() => _tipo = v);
              _carregar();
            },
          ),
          const SizedBox(height: 8),
          Text('${_lista.length} na lista (mais recentes primeiro)',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (_lista.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Nada guardado com estes filtros.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          for (final i in _lista) _cartao(i),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Caixa de guardados'),
          actions: [
            IconButton(
                onPressed: _lista.isEmpty ? null : _exportarCsv,
                icon: const Icon(Icons.download),
                tooltip: 'Exportar CSV'),
            IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
          ],
          bottom: TabBar(tabs: [
            Tab(text: _carregando ? 'Esperando você' : 'Esperando você ($_totalEsperando)'),
            const Tab(text: 'Caixa toda'),
          ]),
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
                : Column(children: [
                    _cartaoAgente(),
                    Expanded(child: TabBarView(children: [_quadro(), _caixaToda()])),
                  ]),
      ),
    );
  }
}
