// Missão hermes-diretor-2026-11-20 (B10) — Stores da aba "Agentes" e do cartão de previsão do
// crédito, em /admin/motores.
//
// Agentes: `agentes_estado` (RLS agentes_estado_admin, ALL para is_admin(): o painel escreve por
// update direto; não existe RPC de agentes). Ligado ao relógio = ligado + horario_ligado;
// a pedido = ligado sem horario_ligado; arquivado = coluna nova `arquivado` (nunca se apaga).
// Auditoria das últimas 24 h: vista `despacho_auditoria_24h` (uma linha por `para`) e RPC
// `despacho_auditoria_resumo()` (o total). Gasto do mês do Hermes: soma de `ia_gastos` onde
// robo começa por "hermes" (o livro de gastos não diz qual agente chamou, por isso é o total).
//
// Previsão: RPC `admin_credito_claude_previsao()`.
// Enquanto as colunas/funções novas não existirem no servidor, nada rebenta.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/credito_claude_model.dart' show EstadoCreditoClaude;
import '../models/hermes_diretor_model.dart';
import '../services/admin_audit_service.dart';
import '../utils/hora_lisboa.dart';
import '../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import 'hermes_store_base.dart';

abstract class AgentesFonte {
  /// [comColunasNovas] = pedir também `arquivado` e `substituto` (podem ainda não existir).
  Future<List<Map<String, dynamic>>> agentes({required bool comColunasNovas});
  Future<List<Map<String, dynamic>>> auditoria24h();

  /// Devolve o jsonb da RPC `despacho_auditoria_resumo()`.
  Future<Object?> auditoriaResumo();
  Future<double> gastoMesHermesUsd();
  Future<void> gravarEstado(String agente, Map<String, dynamic> campos, {required Map<String, dynamic> auditoria});
}

class AgentesFonteSupabase implements AgentesFonte {
  SupabaseClient get _c => Supabase.instance.client;

  static const _base = 'agente, ligado, horario_ligado, cadencia_min, teto_dia_eur, departamento, papel, nota, '
      'ultima_corrida, erro';

  @override
  Future<List<Map<String, dynamic>>> agentes({required bool comColunasNovas}) async {
    final r = await _c
        .from('agentes_estado')
        .select(comColunasNovas ? '$_base, arquivado, substituto' : _base)
        .order('departamento')
        .order('agente');
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Future<List<Map<String, dynamic>>> auditoria24h() async {
    final r = await _c.from('despacho_auditoria_24h').select('para, terminadas, precisavam, auditadas_ok, devolvidas, percentagem');
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Future<Object?> auditoriaResumo() async => await _c.rpc('despacho_auditoria_resumo');

  @override
  Future<double> gastoMesHermesUsd() async {
    final agora = DateTime.now().toUtc();
    final hojeLx = paredeLisboa(agora);
    final inicioMes = instanteDeLisboa(DateTime.utc(hojeLx.year, hojeLx.month, 1));
    var soma = 0.0;
    // O PostgREST devolve no máximo 1000 linhas por pedido: lê-se às páginas.
    for (var de = 0; de < 50000; de += 1000) {
      final p = await _c
          .from('ia_gastos')
          .select('id, custo_usd')
          .ilike('robo', 'hermes%')
          .gte('quando', inicioMes.toIso8601String())
          .order('id', ascending: true)
          .range(de, de + 999);
      for (final l in p) {
        soma += EstadoCreditoClaude.numero(l['custo_usd']) ?? 0;
      }
      if (p.length < 1000) break;
    }
    return soma;
  }

  @override
  Future<void> gravarEstado(String agente, Map<String, dynamic> campos, {required Map<String, dynamic> auditoria}) async {
    await _c
        .from('agentes_estado')
        .update({...campos, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('agente', agente);
    await AdminAuditService.logAction(
      action: 'agente_estado_mudar',
      entityType: 'agente',
      details: auditoria,
    );
  }
}

class AgentesHermesStore extends HermesStoreBase {
  AgentesHermesStore({AgentesFonte? fonte}) : fonte = fonte ?? AgentesFonteSupabase();

  final AgentesFonte fonte;

  List<AgenteEstado> agentes = [];
  Map<String, AuditoriaAgente> auditoriaPorAgente = {};
  AuditoriaAgente? auditoriaTotal;

  /// `false` enquanto a vista/RPC de auditoria não existir (a aba avisa com uma nota calma).
  bool auditoriaLigada = true;

  /// Gasto do mês do Hermes em dólares; nulo = não deu para ler.
  double? gastoHermesMesUsd;

  /// `true` enquanto as colunas arquivado/substituto não existirem no servidor
  /// (então "Arquivar" fica desligado).
  bool arquivarEmFalta = false;

  final Set<String> aGravar = {};

  Future<void> carregar({bool silencioso = false}) async {
    if (!silencioso) {
      carregando = true;
      notifyListeners();
    }
    erro = null;
    try {
      List<Map<String, dynamic>> linhas;
      try {
        linhas = await fonte.agentes(comColunasNovas: true);
        arquivarEmFalta = false;
      } catch (e) {
        if (!servidorAindaSemIsto(e)) rethrow;
        // Colunas novas ainda por criar: lê sem elas e avisa.
        linhas = await fonte.agentes(comColunasNovas: false);
        arquivarEmFalta = true;
      }
      agentes = linhas.map(AgenteEstado.fromMap).toList();
      naoLigado = false;
    } catch (e) {
      if (servidorAindaSemIsto(e)) {
        naoLigado = true;
        agentes = [];
      } else {
        erro = e;
      }
    }
    // Auditoria, total e gasto são extras: falhar aqui não esconde os agentes.
    try {
      final linhas = await fonte.auditoria24h();
      auditoriaPorAgente = {
        for (final m in linhas) '${m['para']}': AuditoriaAgente.fromMap(m),
      };
      final t = await fonte.auditoriaResumo();
      auditoriaTotal = t is Map ? AuditoriaAgente.fromMap(Map<String, dynamic>.from(t)) : null;
      auditoriaLigada = true;
    } catch (e) {
      auditoriaPorAgente = {};
      auditoriaTotal = null;
      auditoriaLigada = !servidorAindaSemIsto(e);
    }
    try {
      gastoHermesMesUsd = await fonte.gastoMesHermesUsd();
    } catch (_) {
      gastoHermesMesUsd = null;
    }
    carregando = false;
    notifyListeners();
  }

  /// Muda o estado de um agente. Nunca apaga. Lança se a escrita falhar.
  Future<void> mudarEstado(AgenteEstado a, EstadoAgente novo) async {
    if (novo == EstadoAgente.arquivado && arquivarEmFalta) {
      throw StateError('Arquivar ainda não foi ligado no servidor.');
    }
    final campos = switch (novo) {
      EstadoAgente.relogio => <String, dynamic>{'ligado': true, 'horario_ligado': true, 'arquivado': false},
      EstadoAgente.aPedido => <String, dynamic>{'ligado': true, 'horario_ligado': false, 'arquivado': false},
      EstadoAgente.arquivado => <String, dynamic>{'ligado': false, 'horario_ligado': false, 'arquivado': true},
    };
    if (arquivarEmFalta) campos.remove('arquivado');
    aGravar.add(a.agente);
    notifyListeners();
    try {
      await fonte.gravarEstado(
        a.agente,
        campos,
        auditoria: {'agente': a.agente, 'de': a.estado.name, 'para': novo.name},
      );
      await carregar(silencioso: true);
    } finally {
      aGravar.remove(a.agente);
      notifyListeners();
    }
  }
}

// ── Previsão do crédito ──────────────────────────────────────────────────────

abstract class PrevisaoClaudeFonte {
  /// Devolve o jsonb da RPC `admin_credito_claude_previsao()`.
  Future<Object?> previsao();
}

class PrevisaoClaudeFonteSupabase implements PrevisaoClaudeFonte {
  @override
  Future<Object?> previsao() async => await Supabase.instance.client.rpc('admin_credito_claude_previsao');
}

class PrevisaoClaudeStore extends HermesStoreBase {
  PrevisaoClaudeStore({PrevisaoClaudeFonte? fonte}) : fonte = fonte ?? PrevisaoClaudeFonteSupabase();

  final PrevisaoClaudeFonte fonte;

  PrevisaoClaude? previsao;

  Future<void> carregar() async {
    carregando = true;
    notifyListeners();
    try {
      previsao = PrevisaoClaude.fromJson(await fonte.previsao());
      erro = null;
      naoLigado = false;
    } catch (e) {
      if (servidorAindaSemIsto(e)) {
        naoLigado = true;
        erro = null;
      } else {
        erro = e;
      }
    }
    carregando = false;
    notifyListeners();
  }
}
