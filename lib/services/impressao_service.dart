// Serviço "Imprimir documentos" e "Personalizados" (missão a3-guarda-16-11, parte 2).
// Fala só com as RPCs e o bucket privado da migração 20261117100100_impressao.sql.
// Nada de preços cravados: o preço vem sempre do servidor (impressao_cotar / impressao_criar).
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/pedido_impressao.dart';

/// Erro com mensagem já em português para mostrar ao utilizador.
class ImpressaoErro implements Exception {
  final String mensagem;
  ImpressaoErro(this.mensagem);
  @override
  String toString() => mensagem;
}

/// O que a loja oferece (linha de impressao_lojas que o cliente pode ler).
class ImpressaoLoja {
  final String restaurantId;
  final bool ligado;
  final bool personalizados;
  final bool permiteLevantar;
  final bool permiteEntrega;
  final int maxFicheiros;
  final int maxPaginas;
  const ImpressaoLoja({
    required this.restaurantId,
    required this.ligado,
    required this.personalizados,
    required this.permiteLevantar,
    required this.permiteEntrega,
    required this.maxFicheiros,
    required this.maxPaginas,
  });
}

class ImpressaoService {
  ImpressaoService({SupabaseClient? client}) : _sbOverride = client;

  final SupabaseClient? _sbOverride;
  SupabaseClient get _sb => _sbOverride ?? Supabase.instance.client;

  static const bucket = 'impressoes';
  static const tabela = 'pedidos_impressao';

  /// Chaves da tabela de preços, pela ordem do painel, com o nome que a loja lê.
  static const chavesPreco = <String, String>{
    'a4_pb_face': 'A4 preto e branco (por face)',
    'a4_cor_face': 'A4 a cores (por face)',
    'a3_fator_pct': 'A3 = A4 × (em %, 200 = dobro)',
    'papel_cartolina_folha': 'Cartolina (a mais, por folha)',
    'papel_fotografico_folha': 'Papel fotográfico (a mais, por folha)',
    'acab_agrafar': 'Agrafar (por cópia)',
    'acab_argolas': 'Encadernar com argolas (por cópia)',
    'acab_plastificar_a4': 'Plastificar A4 (por folha)',
    'acab_plastificar_a3': 'Plastificar A3 (por folha)',
  };

  String? get _uid => _sb.auth.currentUser?.id;

  /// A mensagem do servidor vem como "CODIGO: texto legível". Mostra-se só o texto.
  static String mensagemDe(Object e) {
    var m = e is PostgrestException ? e.message : e.toString();
    final i = m.indexOf(':');
    if (i > 0 && i < 40 && m.substring(0, i).toUpperCase() == m.substring(0, i)) {
      m = m.substring(i + 1).trim();
    }
    if (m.isEmpty) return 'Não foi possível concluir. Tente outra vez.';
    return m;
  }

  Future<T> _rpc<T>(String nome, Map<String, dynamic> params) async {
    try {
      final r = await _sb.rpc(nome, params: params);
      return r as T;
    } catch (e) {
      throw ImpressaoErro(mensagemDe(e));
    }
  }

  // ---------------------------------------------------------------- cliente

  /// A loja tem o serviço? Sem resposta = não (nunca mostrar a quem não pode ver).
  Future<ImpressaoLoja?> loja(String restaurantId) async {
    try {
      final r = await _sb.from('impressao_lojas').select().eq('restaurant_id', restaurantId).maybeSingle();
      if (r == null) return null;
      return ImpressaoLoja(
        restaurantId: restaurantId,
        ligado: r['ligado'] == true,
        personalizados: r['personalizados_ligado'] == true,
        permiteLevantar: r['permite_levantar'] != false,
        permiteEntrega: r['permite_entrega'] != false,
        maxFicheiros: (r['max_ficheiros'] as num?)?.toInt() ?? 10,
        maxPaginas: (r['max_paginas'] as num?)?.toInt() ?? 500,
      );
    } catch (_) {
      return null;
    }
  }

  /// Sobe um ficheiro para a pasta do cliente no bucket privado e devolve o caminho.
  Future<String> subirFicheiro({
    required Uint8List bytes,
    required String extensao,
    required String contentType,
  }) async {
    final uid = _uid;
    if (uid == null) throw ImpressaoErro('Tem de entrar na sua conta.');
    final ext = extensao.replaceAll('.', '').toLowerCase();
    final caminho = '$uid/${const Uuid().v4()}.$ext';
    try {
      await _sb.storage.from(bucket).uploadBinary(
            caminho,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } catch (e) {
      throw ImpressaoErro('Não foi possível enviar o ficheiro. Verifique a internet e tente outra vez.');
    }
    return caminho;
  }

  /// URL assinado de curta duração para abrir um ficheiro privado.
  Future<String?> urlAssinado(String? caminho, {int segundos = 600}) async {
    if (caminho == null || caminho.isEmpty) return null;
    try {
      return await _sb.storage.from(bucket).createSignedUrl(caminho, segundos);
    } catch (_) {
      return null;
    }
  }

  /// Preço calculado pelo servidor, antes de pagar.
  Future<Map<String, dynamic>> cotar(String restaurantId, Map<String, dynamic> opcoes) async {
    final r = await _rpc<dynamic>('impressao_cotar', {'p_restaurant_id': restaurantId, 'p_opcoes': opcoes});
    return Map<String, dynamic>.from(r as Map);
  }

  /// Cria o pedido. [dados] leva 'tipo' ('impressao' | 'personalizado') e as opções.
  Future<Map<String, dynamic>> criar(String restaurantId, Map<String, dynamic> dados) async {
    final r = await _rpc<dynamic>('impressao_criar', {'p_restaurant_id': restaurantId, 'p_dados': dados});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<Map<String, dynamic>> confirmarOrcamento(String id, String metodo) async {
    final r = await _rpc<dynamic>('impressao_confirmar_orcamento', {'p_id': id, 'p_metodo': metodo});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> cancelar(String id) => _rpc<dynamic>('impressao_cancelar', {'p_id': id});

  Future<List<PedidoImpressao>> meus({String? restaurantId, int limite = 30}) async {
    final uid = _uid;
    if (uid == null) return const [];
    var q = _sb.from(tabela).select().eq('user_id', uid);
    if (restaurantId != null) q = q.eq('restaurant_id', restaurantId);
    final r = await q.order('created_at', ascending: false).limit(limite);
    return (r as List).map((e) => PedidoImpressao.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Stream<PedidoImpressao?> acompanhar(String id) => _sb
      .from(tabela)
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((l) => l.isEmpty ? null : PedidoImpressao.fromMap(Map<String, dynamic>.from(l.first)));

  // ---------------------------------------------------------------- loja (parceiro)

  Stream<List<PedidoImpressao>> daLoja(String restaurantId) => _sb
      .from(tabela)
      .stream(primaryKey: ['id'])
      .eq('restaurant_id', restaurantId)
      .order('created_at', ascending: false)
      .limit(100)
      .map((l) => l.map((e) => PedidoImpressao.fromMap(Map<String, dynamic>.from(e))).toList());

  /// [acao]: 'aceitar' | 'recusar' | 'orcamentar' | 'pronto' | 'entregue'.
  Future<void> lojaResponder(String id, String acao, {int? valorCents, String? motivo, String? codigo}) =>
      _rpc<dynamic>('impressao_loja_responder', {
        'p_id': id,
        'p_acao': acao,
        'p_valor_cents': valorCents,
        'p_motivo': motivo,
        'p_codigo': codigo,
      });

  /// Tabela de preços da loja: chave → (valor, provisório).
  Future<Map<String, ({int valor, bool provisorio})>> precos(String restaurantId) async {
    final r = await _sb.from('impressao_precos').select('chave,valor,provisorio').eq('restaurant_id', restaurantId);
    return {
      for (final e in (r as List))
        (e['chave'] as String): (valor: (e['valor'] as num).toInt(), provisorio: e['provisorio'] == true),
    };
  }

  Future<void> precosDefinir(String restaurantId, Map<String, int> valores) =>
      _rpc<dynamic>('impressao_precos_definir', {'p_restaurant_id': restaurantId, 'p_precos': valores});

  // ---------------------------------------------------------------- admin

  Future<List<PedidoImpressao>> adminListar({String? estado, String? restaurantId}) async {
    final r = await _rpc<dynamic>('admin_impressao_listar', {
      'p_estado': estado,
      'p_restaurant_id': restaurantId,
      'p_limite': 300,
    });
    return (r as List? ?? const []).map((e) => PedidoImpressao.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<Map<String, dynamic>>> adminLojas() async {
    final r = await _sb.from('impressao_lojas').select('*, restaurants(name)').order('restaurant_id');
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> adminLojaDefinir(String restaurantId, {required bool ligado, bool? personalizados}) =>
      _rpc<dynamic>('admin_impressao_loja_definir', {
        'p_restaurant_id': restaurantId,
        'p_ligado': ligado,
        'p_personalizados': personalizados,
      });
}
