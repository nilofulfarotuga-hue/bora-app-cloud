// Missão hermes-diretor-2026-11-20 (B10) — Store das autorizações do Hermes (/admin/autorizacoes).
// Lê `hermes_autorizacoes` (RLS só admin; sem escrita direta) e decide SÓ pela RPC
// `admin_hermes_autorizacao_decidir(p_id, p_decisao, p_motivo)` → {ok, estado, erro?}.
// Enquanto a tabela não existir no servidor, `naoLigado` fica true e nada rebenta.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hermes_diretor_model.dart';
import '../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import 'hermes_store_base.dart';

/// O que o store precisa do servidor. Em testes entra uma fonte falsa (sem rede).
abstract class AutorizacoesFonte {
  Future<List<Map<String, dynamic>>> listar();

  /// Devolve o jsonb da RPC `{ok, estado, erro?}`.
  Future<Object?> decidir(int id, String decisao, String motivo);
}

class AutorizacoesFonteSupabase implements AutorizacoesFonte {
  SupabaseClient get _c => Supabase.instance.client;

  static const _colunas = 'id, criada_em, pedida_por, acao, porque, valor_eur, operacao, estado, expira_em, '
      'decidida_em, decidida_por, via, texto_literal, usada_em, resultado, teste';

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final r = await _c.from('hermes_autorizacoes').select(_colunas).order('criada_em', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(r);
  }

  @override
  Future<Object?> decidir(int id, String decisao, String motivo) async {
    // A própria RPC regista quem decidiu e por que via; não se escreve na tabela diretamente.
    return await _c.rpc('admin_hermes_autorizacao_decidir',
        params: {'p_id': id, 'p_decisao': decisao, 'p_motivo': motivo});
  }
}

class AutorizacoesStore extends HermesStoreBase {
  AutorizacoesStore({AutorizacoesFonte? fonte}) : fonte = fonte ?? AutorizacoesFonteSupabase();

  final AutorizacoesFonte fonte;

  List<AutorizacaoHermes> lista = [];

  /// Ids que estão a ser decididos agora (o botão fica parado para não haver duplo toque).
  final Set<int> aDecidir = {};

  /// [silencioso] = recarga automática: não mostra o círculo nem apaga a lista.
  Future<void> carregar({bool silencioso = false}) async {
    if (!silencioso) {
      carregando = true;
      notifyListeners();
    }
    try {
      final linhas = await fonte.listar();
      lista = linhas.map(AutorizacaoHermes.fromMap).toList();
      erro = null;
      naoLigado = false;
    } catch (e) {
      if (servidorAindaSemIsto(e)) {
        naoLigado = true;
        erro = null;
        lista = [];
      } else {
        erro = e;
      }
    }
    carregando = false;
    notifyListeners();
  }

  List<AutorizacaoHermes> pendentes(DateTime agora) {
    final l = lista.where((a) => a.estaPendente(agora)).toList()
      ..sort((a, b) => (a.criadaEm ?? DateTime(2000)).compareTo(b.criadaEm ?? DateTime(2000)));
    return l;
  }

  List<AutorizacaoHermes> historico(DateTime agora) =>
      lista.where((a) => !a.estaPendente(agora)).toList();

  /// Decide um pedido. Devolve a resposta da RPC; lança se a chamada falhar (o ecrã mostra o erro).
  Future<ResultadoDecisao> decidir(int id, {required bool autorizar, String motivo = ''}) async {
    aDecidir.add(id);
    notifyListeners();
    try {
      final r = await fonte.decidir(id, autorizar ? 'autorizada' : 'recusada', motivo);
      final res = ResultadoDecisao.fromJson(r);
      await carregar(silencioso: true);
      return res;
    } finally {
      aDecidir.remove(id);
      notifyListeners();
    }
  }
}
