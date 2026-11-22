// Missão hermes-diretor-2026-11-20 (B10) — Store do ecrã /admin/licoes-robos.
// Lições dos robôs (`licoes_robos`: ligar/desligar e editar a regra) e, por baixo de cada robô,
// os casos de teste (`robos_casos_teste`: ligar/desligar) com o último resultado da regressão
// (RPC `robos_regressao_resumo(p_robo)`). Reaproveita o modelo LicaoRobo e as mesmas colunas
// (ativa / arquivada_em / arquivada_por / editada_em) que o ecrã de motores já usava, para
// os robôs continuarem a ler as lições do mesmo modo.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/credito_claude_model.dart' show LicaoRobo;
import '../models/hermes_diretor_model.dart';
import '../services/admin_audit_service.dart';
import '../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import 'hermes_store_base.dart';

/// Os robôs que têm lições e testes, pela ordem em que aparecem no ecrã.
const List<String> kRobosLicoes = ['suporte', 'amigo', 'whatsapp', 'hermes'];

abstract class LicoesRobosFonte {
  Future<List<Map<String, dynamic>>> licoes();
  Future<List<Map<String, dynamic>>> casos();

  /// Devolve o jsonb da RPC de resumo da regressão.
  Future<Object?> resumoRegressao(String robo);
  Future<void> definirAtiva(LicaoRobo l, bool ativa);
  Future<void> editar(LicaoRobo l, {required String errou, required String regra});
  Future<void> definirCasoAtivo(CasoTesteRobo c, bool ativo);
}

class LicoesRobosFonteSupabase implements LicoesRobosFonte {
  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> licoes() async {
    final r = await _c
        .from('licoes_robos')
        .select('id, criada_em, robo, errou, regra, origem, vezes, ativa, arquivada_em, arquivada_por, editada_em')
        .order('criada_em', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Future<List<Map<String, dynamic>>> casos() async {
    final r = await _c
        .from('robos_casos_teste')
        .select('id, robo, pergunta, deve_conter, nao_pode_conter, ativo, ultimo_resultado, ultima_resposta, ultima_corrida_em')
        .order('robo')
        .order('id')
        .limit(500);
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Future<Object?> resumoRegressao(String robo) async {
    return await _c.rpc('robos_regressao_resumo', params: {'p_robo': robo});
  }

  @override
  Future<void> definirAtiva(LicaoRobo l, bool ativa) async {
    final mudanca = ativa
        ? <String, dynamic>{'ativa': true, 'arquivada_em': null, 'arquivada_por': null}
        : <String, dynamic>{
            'ativa': false,
            'arquivada_em': DateTime.now().toUtc().toIso8601String(),
            'arquivada_por': _c.auth.currentUser?.email ?? 'admin',
          };
    await _c.from('licoes_robos').update(mudanca).eq('id', l.id);
    await AdminAuditService.logAction(
      action: ativa ? 'licao_robo_reativar' : 'licao_robo_arquivar',
      entityType: 'licao_robo',
      details: {'id': l.id, 'robo': l.robo},
    );
  }

  @override
  Future<void> editar(LicaoRobo l, {required String errou, required String regra}) async {
    await _c.from('licoes_robos').update({
      'errou': errou.trim(),
      'regra': regra.trim(),
      'editada_em': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', l.id);
    await AdminAuditService.logAction(
      action: 'licao_robo_editar',
      entityType: 'licao_robo',
      details: {
        'id': l.id,
        'robo': l.robo,
        'old': {'errou': l.errou, 'regra': l.regra},
        'new': {'errou': errou.trim(), 'regra': regra.trim()},
      },
    );
  }

  @override
  Future<void> definirCasoAtivo(CasoTesteRobo c, bool ativo) async {
    await _c.from('robos_casos_teste').update({'ativo': ativo}).eq('id', c.id);
    await AdminAuditService.logAction(
      action: ativo ? 'caso_teste_robo_ativar' : 'caso_teste_robo_desativar',
      entityType: 'caso_teste_robo',
      details: {'id': c.id, 'robo': c.robo},
    );
  }
}

class LicoesRobosStore extends HermesStoreBase {
  LicoesRobosStore({LicoesRobosFonte? fonte}) : fonte = fonte ?? LicoesRobosFonteSupabase();

  final LicoesRobosFonte fonte;

  List<LicaoRobo> licoes = [];
  List<CasoTesteRobo> casos = [];
  Map<String, ResumoRegressao> resumos = {};

  /// `true` enquanto a tabela licoes_robos / robos_casos_teste não existir no servidor.
  bool licoesNaoLigado = false;
  bool casosNaoLigado = false;
  Object? erroCasos;

  final Set<int> aGravar = {};

  Future<void> carregar({bool silencioso = false}) async {
    if (!silencioso) {
      carregando = true;
      notifyListeners();
    }
    erro = null;
    erroCasos = null;
    try {
      licoes = (await fonte.licoes()).map(LicaoRobo.fromMap).toList();
      licoesNaoLigado = false;
    } catch (e) {
      licoes = [];
      if (servidorAindaSemIsto(e)) {
        licoesNaoLigado = true;
      } else {
        licoesNaoLigado = false;
        erro = e;
      }
    }
    try {
      casos = (await fonte.casos()).map(CasoTesteRobo.fromMap).toList();
      casosNaoLigado = false;
    } catch (e) {
      casos = [];
      if (servidorAindaSemIsto(e)) {
        casosNaoLigado = true;
      } else {
        casosNaoLigado = false;
        erroCasos = e;
      }
    }
    // O resumo vem da RPC; se ela ainda não existir, o ecrã calcula a partir dos casos.
    final novos = <String, ResumoRegressao>{};
    if (!casosNaoLigado) {
      for (final robo in robos) {
        try {
          novos[robo] = ResumoRegressao.fromJson(await fonte.resumoRegressao(robo));
        } catch (_) {
          // sem resumo da RPC: fica o cálculo local em resumoDe()
        }
      }
    }
    resumos = novos;
    naoLigado = licoesNaoLigado && casosNaoLigado;
    carregando = false;
    notifyListeners();
  }

  /// Os 4 robôs de sempre, mais qualquer outro que apareça nos dados.
  List<String> get robos {
    final extra = <String>{
      for (final l in licoes) l.robo,
      for (final c in casos) c.robo,
    }..removeAll(kRobosLicoes);
    extra.removeWhere((r) => r.isEmpty);
    return [...kRobosLicoes, ...(extra.toList()..sort())];
  }

  List<LicaoRobo> licoesDe(String robo) => licoes.where((l) => l.robo == robo).toList();

  List<CasoTesteRobo> casosDe(String robo) => casos.where((c) => c.robo == robo).toList();

  /// Resumo da RPC; se não veio, conta-se a partir dos casos ativos.
  ResumoRegressao resumoDe(String robo) {
    final r = resumos[robo];
    if (r != null) return r;
    final ativos = casosDe(robo).where((c) => c.ativo).toList();
    DateTime? ultima;
    for (final c in ativos) {
      final q = c.ultimaCorridaEm;
      if (q != null && (ultima == null || q.isAfter(ultima))) ultima = q;
    }
    return ResumoRegressao(
      casos: ativos.length,
      passaram: ativos.where((c) => c.ultimoResultado == 'passou').length,
      falharam: ativos.where((c) => c.ultimoResultado == 'falhou').length,
      nuncaCorridos: ativos.where((c) => c.ultimoResultado == null).length,
      ultimaCorridaEm: ultima,
    );
  }

  Future<void> _gravar(int id, Future<void> Function() escrever) async {
    aGravar.add(id);
    notifyListeners();
    try {
      await escrever();
      await carregar(silencioso: true);
    } finally {
      aGravar.remove(id);
      notifyListeners();
    }
  }

  /// Liga ou desliga uma lição (desligada = os robôs deixam de a ler). Lança se falhar.
  Future<void> definirLicaoAtiva(LicaoRobo l, bool ativa) =>
      _gravar(l.id, () => fonte.definirAtiva(l, ativa));

  Future<void> editarLicao(LicaoRobo l, {required String errou, required String regra}) =>
      _gravar(l.id, () => fonte.editar(l, errou: errou, regra: regra));

  Future<void> definirCasoAtivo(CasoTesteRobo c, bool ativo) =>
      _gravar(-c.id, () => fonte.definirCasoAtivo(c, ativo));
}
