// Missão hermes-diretor-2026-11-20 (B10) — Store da sentinela (o vigia do Hermes), /admin/sentinela.
// Lê `sentinela_eventos` (RLS só admin) e, para o "o que o Hermes fez", o estado e o resultado da
// tarefa ligada em `despacho` (coluna despacho_id). "Marcar como visto" grava tratado_em e
// tratado_por='admin' e fica no admin_audit_log.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hermes_diretor_model.dart';
import '../services/admin_audit_service.dart';
import '../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import 'hermes_store_base.dart';

abstract class SentinelaFonte {
  Future<List<Map<String, dynamic>>> eventos();
  Future<List<Map<String, dynamic>>> tarefas(List<int> ids);
  Future<void> marcarVisto(int id);
}

class SentinelaFonteSupabase implements SentinelaFonte {
  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> eventos() async {
    final r = await _c
        .from('sentinela_eventos')
        .select('id, criado_em, tipo, gravidade, titulo, dados, despacho_id, tratado_em, tratado_por, resultado')
        .order('criado_em', ascending: false)
        .limit(300);
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Future<List<Map<String, dynamic>>> tarefas(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final r = await _c.from('despacho').select('id, estado, resultado').inFilter('id', ids);
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Future<void> marcarVisto(int id) async {
    await _c.from('sentinela_eventos').update({
      'tratado_em': DateTime.now().toUtc().toIso8601String(),
      'tratado_por': 'admin',
    }).eq('id', id);
    await AdminAuditService.logAction(
      action: 'sentinela_marcar_visto',
      entityType: 'sentinela_evento',
      details: {'id': id},
    );
  }
}

class SentinelaStore extends HermesStoreBase {
  SentinelaStore({SentinelaFonte? fonte}) : fonte = fonte ?? SentinelaFonteSupabase();

  final SentinelaFonte fonte;

  List<EventoSentinela> eventos = [];
  Map<int, TarefaLigada> tarefas = {};

  /// `null` = todas as gravidades; senão 'urgente' | 'normal' | 'info'.
  String? filtroGravidade;
  bool soPorVer = false;

  final Set<int> aMarcar = {};

  Future<void> carregar({bool silencioso = false}) async {
    if (!silencioso) {
      carregando = true;
      notifyListeners();
    }
    try {
      final linhas = await fonte.eventos();
      eventos = linhas.map(EventoSentinela.fromMap).toList();
      erro = null;
      naoLigado = false;
      // A tarefa ligada é um enfeite: se falhar, o evento continua a aparecer.
      try {
        final ids = <int>{for (final e in eventos) if (e.despachoId != null) e.despachoId!}.toList();
        final t = await fonte.tarefas(ids);
        tarefas = {
          for (final m in t) TarefaLigada.fromMap(m).id: TarefaLigada.fromMap(m),
        };
      } catch (_) {
        tarefas = {};
      }
    } catch (e) {
      if (servidorAindaSemIsto(e)) {
        naoLigado = true;
        erro = null;
        eventos = [];
        tarefas = {};
      } else {
        erro = e;
      }
    }
    carregando = false;
    notifyListeners();
  }

  void filtrar(String? gravidade) {
    filtroGravidade = gravidade;
    notifyListeners();
  }

  void mudarSoPorVer(bool v) {
    soPorVer = v;
    notifyListeners();
  }

  /// Eventos que passam nos filtros, mais recentes primeiro.
  List<EventoSentinela> get visiveis => eventos
      .where((e) =>
          (filtroGravidade == null || e.gravidade == filtroGravidade) && (!soPorVer || !e.tratado))
      .toList();

  int porVer(String gravidade) => eventos.where((e) => e.gravidade == gravidade && !e.tratado).length;

  TarefaLigada? tarefaDe(EventoSentinela e) => e.despachoId == null ? null : tarefas[e.despachoId];

  /// Lança se a escrita falhar (o ecrã mostra o erro).
  Future<void> marcarVisto(int id) async {
    aMarcar.add(id);
    notifyListeners();
    try {
      await fonte.marcarVisto(id);
      await carregar(silencioso: true);
    } finally {
      aMarcar.remove(id);
      notifyListeners();
    }
  }
}
