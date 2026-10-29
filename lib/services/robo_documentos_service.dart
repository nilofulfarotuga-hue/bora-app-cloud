/// ROBÔ "FISCAL DE DOCUMENTOS" — as chamadas ao servidor (missão
/// final-app-2026-10-29, adendo 3). A lógica pura vive em `robo_documentos.dart`.
///
///   • Painel (só admin): ler/mudar as definições, ver vereditos, prontos para
///     aprovar, desfazer, lembrar um candidato, analisar pendentes.
///   • App do candidato: o estado dos seus documentos e a verificação "na hora"
///     (Edge `verificar-documento-previa`). Tudo falha ABERTO: sem rede ou com
///     erro, o candidato segue como antes.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'robo_documentos.dart';

/// As colunas dos vereditos que o painel precisa (sem nome nem NIF: nunca se guardam).
const String kColunasVeredito =
    'id,user_id,papel,campo,decisao,acao,modo,tipo_detectado,tipo_documento_esperado,'
    'confianca,motivo_pt,nome_bate,nif_bate,legivel,path,created_at,revertido_em';

/// Junta os vereditos às linhas do painel (`_robo` = campo → veredito). Falha aberta.
Future<void> juntarVereditosRobo(
  SupabaseClient sb,
  List<Map<String, dynamic>> linhas, {
  String chaveUser = 'user_id',
}) async {
  final ids = linhas
      .map((d) => d[chaveUser]?.toString())
      .whereType<String>()
      .toSet()
      .toList();
  if (ids.isEmpty) return;
  try {
    final rs = await sb
        .from('documentos_verificacoes')
        .select(kColunasVeredito)
        .inFilter('user_id', ids)
        .order('id', ascending: false)
        .limit(500);
    final porUser = <String, List<Map<String, dynamic>>>{};
    for (final r in List<Map<String, dynamic>>.from(rs)) {
      porUser.putIfAbsent(r['user_id'].toString(), () => []).add(r);
    }
    for (final d in linhas) {
      final uid = d[chaveUser]?.toString();
      d['_robo'] = ultimoPorCampo(porUser[uid] ?? const []);
    }
  } catch (_) {
    // sem veredito, o painel mostra tudo como dantes
  }
}

/// A porta do painel. Em teste troca-se por uma de mentira.
abstract class RoboAdminApi {
  Future<Map<String, dynamic>> config();
  Future<Map<String, dynamic>> definir(String chave, Object valor);
  Future<List<Map<String, dynamic>>> prontos();
  Future<List<VereditoRobo>> historico({String? userId, int limite = 100});
  Future<void> desfazer(int id);
  Future<Map<String, dynamic>> lembrar(String userId);
  Future<Map<String, dynamic>> analisarPendentes();
}

class RoboAdminSupabase implements RoboAdminApi {
  RoboAdminSupabase([SupabaseClient? c]) : _c = c;
  final SupabaseClient? _c;
  SupabaseClient get _sb => _c ?? Supabase.instance.client;

  static Map<String, dynamic> _mapa(Object? r) =>
      r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> config() async =>
      _mapa(await _sb.rpc('admin_robo_documentos_config'));

  @override
  Future<Map<String, dynamic>> definir(String chave, Object valor) async =>
      _mapa(await _sb.rpc('admin_robo_documentos_definir',
          params: {'p_chave': chave, 'p_valor': valor}));

  @override
  Future<List<Map<String, dynamic>>> prontos() async {
    final r = await _sb.rpc('admin_documentos_prontos');
    return r is List
        ? r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  @override
  Future<List<VereditoRobo>> historico({String? userId, int limite = 100}) async {
    final r = await _sb.rpc('admin_documentos_verificacoes',
        params: {'p_user_id': userId, 'p_limite': limite});
    return r is List
        ? r
            .whereType<Map>()
            .map((e) => VereditoRobo.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : const [];
  }

  @override
  Future<void> desfazer(int id) async {
    await _sb.rpc('admin_documentos_desfazer', params: {'p_id': id});
  }

  @override
  Future<Map<String, dynamic>> lembrar(String userId) async =>
      _mapa(await _sb.rpc('admin_robo_documentos_lembrar', params: {'p_user_id': userId}));

  @override
  Future<Map<String, dynamic>> analisarPendentes() async =>
      _mapa(await _sb.rpc('admin_robo_documentos_varrer'));
}

// ── A app do candidato ───────────────────────────────────────────────────────────

/// O que a verificação "na hora" devolveu.
class PreviaRobo {
  const PreviaRobo({
    required this.ativo,
    this.decisao,
    this.motivoPt,
    this.tipoDetetado,
    this.confianca,
  });

  factory PreviaRobo.fromJson(Map<String, dynamic> j) => PreviaRobo(
        ativo: j['ativo'] == true,
        decisao: j['decisao']?.toString(),
        motivoPt: j['motivo_pt']?.toString(),
        tipoDetetado: j['tipo_detectado']?.toString(),
        confianca: (j['confianca'] is num) ? (j['confianca'] as num).toDouble() : null,
      );

  final bool ativo;
  final String? decisao;
  final String? motivoPt;
  final String? tipoDetetado;
  final double? confianca;

  /// Só se avisa o candidato quando o robô está a agir E tem a certeza de que está errado.
  bool get avisar => ativo && decisao == 'errado';
}

class RoboDocumentosApp {
  RoboDocumentosApp._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// O estado dos documentos da pessoa (null = sem sessão, sem rede ou erro).
  static Future<EstadoDocumentosApp?> estado() async {
    try {
      if (_sb.auth.currentUser == null) return null;
      final r = await _sb.rpc('provider_documentos_estado').timeout(const Duration(seconds: 8));
      if (r is Map) return EstadoDocumentosApp.fromJson(Map<String, dynamic>.from(r));
    } catch (_) {
      // falha aberta
    }
    return null;
  }

  /// "Isto parece o ficheiro certo?" — o ficheiro já está no balde privado da
  /// pessoa. null = não deu para verificar (a app deixa seguir).
  static Future<PreviaRobo?> previa({
    required String campo,
    required String path,
    String? nif,
  }) async {
    try {
      final r = await _sb.functions
          .invoke('verificar-documento-previa', body: {
            'campo': campo,
            'path': path,
            if (nif != null) 'nif': nif,
          })
          .timeout(const Duration(seconds: 30));
      final d = r.data;
      if (d is Map) return PreviaRobo.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {
      // falha aberta
    }
    return null;
  }
}
