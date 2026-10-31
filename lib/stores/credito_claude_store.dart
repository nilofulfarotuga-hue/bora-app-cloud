// Missão motor-claude-2026-10-31 (Bloco 5) — Store do cartão "Crédito Claude" de /admin/motores.
// Lê platform_settings (claude_*), ia_gastos e licoes_robos; grava as chaves pelo mesmo caminho
// dos outros ecrãs admin (RPC admin_update_setting, que audita em admin_audit_log) e as lições
// direto na tabela (RLS is_admin), com registo em admin_audit_log pelo AdminAuditService.
// Enquanto a migração 20261031_motor_claude_porteiro.sql não estiver aplicada, nada rebenta:
// o estado diz "ainda não ativado".

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/credito_claude_model.dart';
import '../services/admin_audit_service.dart';
import '../utils/hora_lisboa.dart';
import '../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;

class CreditoClaudeStore extends ChangeNotifier {
  CreditoClaudeStore({SupabaseClient? client}) : _sb = client ?? Supabase.instance.client;

  final SupabaseClient _sb;

  EstadoCreditoClaude? estado;
  bool carregando = false;
  bool gravando = false;
  String? erro;

  List<LicaoRobo> licoes = [];

  /// `false` enquanto a tabela licoes_robos não existir no servidor.
  bool licoesAtivas = true;
  bool verArquivadas = false;
  String? erroLicoes;

  // O PostgREST devolve no máximo 1000 linhas por pedido: lê-se às páginas.
  static const int _pagina = 1000;
  static const int _maxLinhas = 200000;

  // O ecrã pode fechar a meio de uma leitura: depois disso não se avisa ninguém.
  bool _fechado = false;

  @override
  void dispose() {
    _fechado = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_fechado) super.notifyListeners();
  }

  Future<void> carregar() async {
    carregando = true;
    erro = null;
    notifyListeners();
    try {
      estado = await _lerEstado();
    } catch (e) {
      erro = '$e';
    }
    await _lerLicoes();
    carregando = false;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _todas(
      Future<List<Map<String, dynamic>>> Function(int de, int ate) pagina) async {
    final todas = <Map<String, dynamic>>[];
    for (var de = 0; de < _maxLinhas; de += _pagina) {
      final p = await pagina(de, de + _pagina - 1);
      todas.addAll(p);
      if (p.length < _pagina) break;
    }
    return todas;
  }

  Future<EstadoCreditoClaude> _lerEstado() async {
    final rows = await _sb
        .from('platform_settings')
        .select('key, value')
        .inFilter('key', kChavesCreditoClaude);
    final s = <String, dynamic>{
      for (final r in List<Map<String, dynamic>>.from(rows)) '${r['key']}': r['value'],
    };
    final settingsAtivos = s.containsKey('claude_robos') && s.containsKey('claude_credito_atual_usd');
    final robosMapa = s['claude_robos'] is Map
        ? Map<String, dynamic>.from(s['claude_robos'] as Map)
        : <String, dynamic>{};
    final lidoEm = EstadoCreditoClaude.data(s['claude_credito_lido_em'])?.toUtc();
    final proximo = EstadoCreditoClaude.data(s['claude_proximo_credito']);

    final agora = DateTime.now().toUtc();
    final hojeLx = paredeLisboa(agora);
    final inicioHoje = inicioDiaLisboaUtc(agora);
    final inicioMes = instanteDeLisboa(DateTime.utc(hojeLx.year, hojeLx.month, 1));
    final desde = (lidoEm != null && lidoEm.isBefore(inicioMes)) ? lidoEm : inicioMes;

    var livroAtivo = true;
    var gastoLeitura = 0.0;
    var gastoHoje = 0.0;
    var gastoMes = 0.0;
    var chamadasHoje = 0;
    final porRobo = <String, GastoRoboClaude>{};
    try {
      final linhas = await _todas((de, ate) => _sb
          .from('ia_gastos')
          .select('id, quando, robo, perfil, custo_usd')
          .gte('quando', desde.toIso8601String())
          .order('id', ascending: true)
          .range(de, ate));
      for (final l in linhas) {
        final q = EstadoCreditoClaude.data(l['quando'])?.toUtc();
        if (q == null) continue;
        final custo = EstadoCreditoClaude.numero(l['custo_usd']) ?? 0;
        // Igual ao porteiro: sem data de leitura, o gasto desde a leitura é zero.
        if (lidoEm != null && !q.isBefore(lidoEm)) gastoLeitura += custo;
        final doMes = !q.isBefore(inicioMes);
        final deHoje = !q.isBefore(inicioHoje);
        if (!doMes) continue;
        gastoMes += custo;
        final nome = '${l['robo'] ?? l['perfil'] ?? '—'}';
        final g = porRobo.putIfAbsent(nome, () => GastoRoboClaude(nome));
        g.mesUsd += custo;
        g.chamadasMes++;
        if (deHoje) {
          gastoHoje += custo;
          chamadasHoje++;
          g.hojeUsd += custo;
          g.chamadasHoje++;
        }
      }
    } catch (e) {
      if (!servidorAindaSemIsto(e)) rethrow;
      livroAtivo = false;
    }

    final gastos = porRobo.values.toList()..sort((a, b) => b.mesUsd.compareTo(a.mesUsd));
    return EstadoCreditoClaude(
      settingsAtivos: settingsAtivos,
      livroAtivo: livroAtivo,
      creditoLidoUsd: EstadoCreditoClaude.numero(s['claude_credito_atual_usd']),
      lidoEm: lidoEm,
      lotes: LoteCreditoClaude.daLista(s['claude_credito_validade']),
      proximoCredito: proximo,
      mensalUsd: EstadoCreditoClaude.numero(s['claude_credito_mensal_usd']),
      ligado: robosMapa['ligado'] != false && robosMapa['ligado'] != 'false',
      robos: RoboClaude.doMapa(robosMapa),
      gastoDesdeLeituraUsd: gastoLeitura,
      gastoHojeUsd: gastoHoje,
      gastoMesUsd: gastoMes,
      chamadasHoje: chamadasHoje,
      gastoPorRobo: gastos,
      diasAteProximo: RitmoCreditoClaude.diasEntre(hojeLx, proximo),
    );
  }

  // ── Interruptores (claude_robos) ─────────────────────────────────────────

  Future<void> gravarLigado(bool ligado) => _mexerRobos((m) => m['ligado'] = ligado);

  Future<void> gravarRobo(String chave, {bool? usar, String? modelo}) {
    if (modelo != null && !kModelosClaude.containsKey(modelo)) {
      throw ArgumentError('Só Haiku 5.5 ou Sonnet 5.5 (Opus nunca automático).');
    }
    return _mexerRobos((m) {
      final r = Map<String, dynamic>.from((m[chave] as Map?) ?? const {});
      if (usar != null) r['usar'] = usar;
      if (modelo != null) r['modelo'] = modelo;
      m[chave] = r;
    });
  }

  /// Lê o valor FRESCO do banco, muda só o que foi tocado e grava pela RPC
  /// admin_update_setting (a mesma dos outros ecrãs; audita sozinha).
  Future<void> _mexerRobos(void Function(Map<String, dynamic> m) mexer) async {
    gravando = true;
    notifyListeners();
    try {
      final atual = await _sb
          .from('platform_settings')
          .select('value')
          .eq('key', 'claude_robos')
          .maybeSingle();
      if (atual == null || atual['value'] is! Map) {
        throw StateError('A chave claude_robos ainda não existe (migração do porteiro por aplicar).');
      }
      final m = Map<String, dynamic>.from(atual['value'] as Map);
      mexer(m);
      await _sb.rpc('admin_update_setting', params: {'p_key': 'claude_robos', 'p_value': m});
      estado = await _lerEstado();
    } finally {
      gravando = false;
      notifyListeners();
    }
  }

  /// Depois de ler o crédito na Console (Billing): grava o valor, a hora da leitura (agora) e a
  /// data do próximo crédito. O gasto passa a contar a partir desta leitura.
  Future<void> atualizarCredito({required double usd, required DateTime proximoCredito}) async {
    gravando = true;
    notifyListeners();
    try {
      String dd(int n) => n.toString().padLeft(2, '0');
      final p = '${proximoCredito.year}-${dd(proximoCredito.month)}-${dd(proximoCredito.day)}';
      await _sb.rpc('admin_update_setting', params: {'p_key': 'claude_credito_atual_usd', 'p_value': usd});
      await _sb.rpc('admin_update_setting',
          params: {'p_key': 'claude_credito_lido_em', 'p_value': DateTime.now().toUtc().toIso8601String()});
      await _sb.rpc('admin_update_setting', params: {'p_key': 'claude_proximo_credito', 'p_value': p});
      estado = await _lerEstado();
    } finally {
      gravando = false;
      notifyListeners();
    }
  }

  // ── Exportar o livro de gastos ───────────────────────────────────────────

  static const List<String> colunasLivro = [
    'quando (Lisboa)',
    'robo',
    'modelo',
    'prioridade',
    'tokens',
    'custo_usd',
    'tokens_entrada',
    'tokens_saida',
    'tokens_cache_escrita',
    'tokens_cache_leitura',
    'perfil',
    'maquina',
    'ok',
    'lote',
  ];

  /// O livro inteiro (mais antigo primeiro), pronto para o AdminExportService.
  Future<List<List<Object?>>> linhasDoLivro() async {
    final linhas = await _todas((de, ate) => _sb
        .from('ia_gastos')
        .select('id, quando, maquina, robo, perfil, prioridade, modelo, tokens_entrada, tokens_saida, '
            'tokens_cache_escrita, tokens_cache_leitura, custo_usd, ok, lote')
        .order('id', ascending: true)
        .range(de, ate));
    String dd(int n) => n.toString().padLeft(2, '0');
    String quando(Object? v) {
      final d = EstadoCreditoClaude.data(v);
      if (d == null) return '';
      final l = paredeLisboa(d.toUtc());
      return '${l.year}-${dd(l.month)}-${dd(l.day)} ${dd(l.hour)}:${dd(l.minute)}:${dd(l.second)}';
    }

    int n(Object? v) => (EstadoCreditoClaude.numero(v) ?? 0).toInt();
    return [
      for (final l in linhas)
        [
          quando(l['quando']),
          l['robo'] ?? '',
          l['modelo'] ?? '',
          l['prioridade'] ?? '',
          n(l['tokens_entrada']) + n(l['tokens_saida']) + n(l['tokens_cache_escrita']) + n(l['tokens_cache_leitura']),
          // Vírgula decimal: o CSV sai com ';' para o Excel em português.
          (EstadoCreditoClaude.numero(l['custo_usd']) ?? 0).toStringAsFixed(6).replaceAll('.', ','),
          n(l['tokens_entrada']),
          n(l['tokens_saida']),
          n(l['tokens_cache_escrita']),
          n(l['tokens_cache_leitura']),
          l['perfil'] ?? '',
          l['maquina'] ?? '',
          l['ok'] == false ? 'não' : 'sim',
          l['lote'] == true ? 'sim' : 'não',
        ],
    ];
  }

  // ── Lições dos robôs ─────────────────────────────────────────────────────

  Future<void> _lerLicoes() async {
    erroLicoes = null;
    try {
      final r = await _sb
          .from('licoes_robos')
          .select('id, criada_em, robo, errou, regra, origem, vezes, ativa, arquivada_em, arquivada_por, editada_em')
          .eq('ativa', !verArquivadas)
          .order(verArquivadas ? 'arquivada_em' : 'criada_em', ascending: false, nullsFirst: false)
          .limit(500);
      licoes = List<Map<String, dynamic>>.from(r).map(LicaoRobo.fromMap).toList();
      licoesAtivas = true;
    } catch (e) {
      licoes = [];
      if (servidorAindaSemIsto(e)) {
        licoesAtivas = false;
      } else {
        licoesAtivas = true;
        erroLicoes = '$e';
      }
    }
  }

  Future<void> mostrarArquivadas(bool sim) async {
    verArquivadas = sim;
    await _lerLicoes();
    notifyListeners();
  }

  Future<void> editarLicao(LicaoRobo l, {required String errou, required String regra}) async {
    await _sb.from('licoes_robos').update({
      'errou': errou.trim(),
      'regra': regra.trim(),
      'editada_em': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', l.id);
    await AdminAuditService.logAction(
      action: 'licao_robo_editar',
      entityType: 'licao_robo',
      details: {'id': l.id, 'robo': l.robo, 'old': {'errou': l.errou, 'regra': l.regra}, 'new': {'errou': errou.trim(), 'regra': regra.trim()}},
    );
    await _lerLicoes();
    notifyListeners();
  }

  Future<void> arquivarLicao(LicaoRobo l, {required bool arquivar}) async {
    final mudanca = arquivar
        ? <String, dynamic>{
            'ativa': false,
            'arquivada_em': DateTime.now().toUtc().toIso8601String(),
            'arquivada_por': _sb.auth.currentUser?.email ?? 'admin',
          }
        : <String, dynamic>{'ativa': true, 'arquivada_em': null, 'arquivada_por': null};
    await _sb.from('licoes_robos').update(mudanca).eq('id', l.id);
    await AdminAuditService.logAction(
      action: arquivar ? 'licao_robo_arquivar' : 'licao_robo_reativar',
      entityType: 'licao_robo',
      details: {'id': l.id, 'robo': l.robo},
    );
    await _lerLicoes();
    notifyListeners();
  }
}
