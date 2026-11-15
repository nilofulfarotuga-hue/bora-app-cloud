// lib/services/loja_online_service.dart
//
// Loja Online (15/11/2026, fechar-tudo-15-11 ponto E, caixa 10). Duas partes:
//
//  * [LojaOnlineService] — o que a app do cliente lê: o interruptor
//    `loja_online_ativa` (platform_settings, nasce desligado) e as tabelas
//    `loja_online_nichos` / `loja_online_produtos` (só linhas ativas, pela RLS).
//    Se o interruptor estiver desligado, se as tabelas ainda não existirem
//    (PGRST205 / 42P01 / PGRST202) ou se a leitura falhar, devolve um estado
//    calmo: o ecrã mostra "Em breve" ou "tenta outra vez", nunca rebenta.
//
//  * [LojaOnlineAdminService] — o que o painel faz: liga/desliga o interruptor
//    pela RPC `admin_update_setting` (a mesma do resto do painel, auditada),
//    lista tudo (os admins veem também o que está desligado) e chama as RPCs
//    propostas `admin_loja_online_produto_estado` e
//    `admin_loja_online_nicho_da_semana` (SECURITY DEFINER, is_admin(),
//    log_admin_action). Enquanto não forem aplicadas, o painel diz
//    "Esta parte ainda não foi instalada no servidor.".
//
// Nada aqui calcula preços nem toca em pagamentos. As funções de rede são
// injetáveis para os testes correrem sem Supabase.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/loja_online_produto.dart';
import 'definicoes_publicas.dart';

const String kLojaOnlineChaveInterruptor = 'loja_online_ativa';
const String kLojaOnlineTabelaNichos = 'loja_online_nichos';
const String kLojaOnlineTabelaProdutos = 'loja_online_produtos';
const String kLojaOnlineRpcProdutoEstado = 'admin_loja_online_produto_estado';
const String kLojaOnlineRpcNichoDaSemana = 'admin_loja_online_nicho_da_semana';

/// checkup-15-11 (B3.7): true com a loja aberta a todos OU para quem está na
/// lista de permissão (as contas do Danilo) e para o admin. Enquanto a função
/// não estiver no servidor, a app usa só o interruptor (comportamento antigo).
const String kLojaOnlineRpcVisivel = 'loja_online_visivel_para_mim';
const String kLojaOnlineRpcEncomendas = 'admin_loja_online_encomendas';
const String kLojaOnlineRpcEncomendaEstado = 'admin_loja_online_encomenda_estado';
const String kLojaOnlineTabelaEncomendas = 'loja_online_encomendas';
const String kLojaOnlineEdgePagamento = 'loja-online-pagamento';
const String kLojaOnlineRpcAdminProdutos = 'admin_loja_online_produtos';

/// Juiz da Claude.ai 15/11 18:27 (A): o cliente lê só estas colunas (sem o custo do
/// fornecedor nem as ligações à Shopify/CJ). O servidor só deixa ler estas.
const String kLojaOnlineColunasCliente =
    'id, nicho_id, titulo, descricao, imagens, preco_bora_cents, prazo_min_dias, '
    'prazo_max_dias, ativo, destaque, criado_em, atualizado_em';

/// loja-nichos-15-11: as colunas novas (subcategoria e ordem por vendas). Se a
/// proposta N1 ainda não estiver no servidor, a app lê só as de cima.
const String kLojaOnlineColunasClienteNichos = '$kLojaOnlineColunasCliente, '
    'subcategoria_id, cj_listas, vendas_loja, ordem_manual';
const String kLojaOnlineTabelaSubcategorias = 'loja_online_subcategorias';
const String kLojaOnlineRpcNichoPublico = 'admin_loja_online_nicho_publico';
const String kLojaOnlineRpcProdutoOrdem = 'admin_loja_online_produto_ordem';
const String kLojaOnlineRpcProdutoSubcategoria =
    'admin_loja_online_produto_subcategoria';
const String kLojaOnlineRpcSubcategoriaAtivo =
    'admin_loja_online_subcategoria_ativo';

/// A mesma frase que `humanizeAdminRpcError` dá a uma função por instalar
/// (PGRST202); aqui serve também para tabela ou chave em falta.
const String kLojaOnlineNaoInstalada =
    'Esta parte ainda não foi instalada no servidor.';

typedef LerDefinicoesFn = Future<Map<String, dynamic>> Function(
    List<String> chaves);
typedef LerLinhasFn = Future<List<Map<String, dynamic>>> Function(
    String tabela);
typedef RpcFn = Future<dynamic> Function(
    String funcao, Map<String, dynamic> params);
typedef LerDefinicaoFn = Future<Map<String, dynamic>?> Function(String chave);
typedef LerVisivelFn = Future<bool> Function();

/// A parte do servidor ainda não foi instalada: tabela, função ou coluna em
/// falta. Códigos do PostgREST (`PGRST205` tabela fora da cache, `PGRST202`
/// função fora da cache) e do Postgres (`42P01` tabela, `42883` função,
/// `42703` coluna).
bool lojaOnlineServidorEmFalta(Object e) {
  if (e is! PostgrestException) return false;
  final code = e.code ?? '';
  if (code == 'PGRST205' ||
      code == 'PGRST202' ||
      code == '42P01' ||
      code == '42883' ||
      code == '42703') {
    return true;
  }
  final m = e.message.toLowerCase();
  return m.contains('could not find the table') ||
      m.contains('could not find the function') ||
      m.contains('schema cache') ||
      m.contains('does not exist');
}

bool lojaOnlineComoBool(Object? v, [bool recurso = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.replaceAll('"', '').trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  return recurso;
}

enum LojaOnlineEstado {
  /// Interruptor desligado no painel: para o cliente a loja ainda não existe.
  desligada,

  /// Tabelas ainda por instalar no servidor.
  emBreve,

  /// Rede ou servidor falharam: oferecer "tentar outra vez".
  erro,

  /// Há catálogo para mostrar (pode estar vazio).
  pronta,
}

@immutable
class LojaOnlineCatalogo {
  const LojaOnlineCatalogo({
    required this.estado,
    this.nichos = const [],
    this.produtos = const [],
    this.subcategorias = const [],
  });

  final LojaOnlineEstado estado;
  final List<LojaOnlineNicho> nichos;
  final List<LojaOnlineProduto> produtos;
  final List<LojaOnlineSubcategoria> subcategorias;

  LojaOnlineVitrine get vitrine =>
      LojaOnlineVitrine.montar(nichos, produtos, subcategorias);
}

class LojaOnlineService {
  LojaOnlineService({
    LerDefinicoesFn? lerDefinicoes,
    LerLinhasFn? lerAtivos,
    DateTime Function()? agora,
    LerVisivelFn? lerVisivel,
  })  : _lerDefinicoes = lerDefinicoes ?? lerDefinicoesPublicas,
        _lerAtivos = lerAtivos ?? _lerAtivosNoSupabase,
        _agora = agora ?? DateTime.now,
        _lerVisivel = lerVisivel ?? _lerVisivelNoSupabase;

  static final LojaOnlineService instance = LojaOnlineService();

  final LerDefinicoesFn _lerDefinicoes;
  final LerLinhasFn _lerAtivos;
  final DateTime Function() _agora;
  final LerVisivelFn _lerVisivel;

  /// O interruptor tal como foi lido do servidor. Nasce desligado e só liga
  /// com `loja_online_ativa = true` em platform_settings. O ecrã inicial ouve
  /// isto para mostrar (ou não) o ladrilho "Loja Online".
  final ValueNotifier<bool> ativa = ValueNotifier<bool>(false);

  DateTime? _interruptorLidoEm;

  /// Cache curta: o admin liga no painel e a app apanha a seguir.
  static const Duration validadeInterruptor = Duration(minutes: 2);

  /// Lê `loja_online_ativa` (com cache de 2 min). Nunca lança; se a leitura
  /// falhar fica o último valor conhecido (ou desligado).
  Future<bool> atualizarInterruptor({bool forcar = false}) async {
    final lidoEm = _interruptorLidoEm;
    if (!forcar &&
        lidoEm != null &&
        _agora().difference(lidoEm) < validadeInterruptor) {
      return ativa.value;
    }
    // 1.º a função do servidor (lista de permissão: contas do Danilo veem a
    // loja antes de abrir). Se ainda não existir ou falhar, fica o interruptor.
    try {
      ativa.value = await _lerVisivel();
      _interruptorLidoEm = _agora();
      return ativa.value;
    } catch (e) {
      debugPrint('[LojaOnline] visivel_para_mim indisponível: $e');
    }
    try {
      final lido = await _lerDefinicoes([kLojaOnlineChaveInterruptor]);
      if (lido.containsKey(kLojaOnlineChaveInterruptor)) {
        ativa.value = lojaOnlineComoBool(lido[kLojaOnlineChaveInterruptor]);
        _interruptorLidoEm = _agora();
      } else {
        // Chave por instalar no servidor: a loja não existe para o cliente.
        ativa.value = false;
      }
    } catch (e) {
      debugPrint('[LojaOnline] interruptor: $e');
    }
    return ativa.value;
  }

  /// Interruptor + catálogo. Com o interruptor desligado nem toca nas tabelas.
  Future<LojaOnlineCatalogo> carregar({bool forcar = false}) async {
    final ligada = await atualizarInterruptor(forcar: forcar);
    if (!ligada) {
      return const LojaOnlineCatalogo(estado: LojaOnlineEstado.desligada);
    }
    try {
      final nichos = (await _lerAtivos(kLojaOnlineTabelaNichos))
          .map(LojaOnlineNicho.fromJson)
          .toList(growable: false);
      final produtos = (await _lerAtivos(kLojaOnlineTabelaProdutos))
          .map(LojaOnlineProduto.fromJson)
          .toList(growable: false);
      // loja-nichos-15-11: sem a tabela das subcategorias (N1 por aplicar) a
      // loja continua, só sem os separadores Cão/Gato/…
      var subcategorias = const <LojaOnlineSubcategoria>[];
      try {
        subcategorias = (await _lerAtivos(kLojaOnlineTabelaSubcategorias))
            .map(LojaOnlineSubcategoria.fromJson)
            .toList(growable: false);
      } catch (e) {
        debugPrint('[LojaOnline] subcategorias indisponíveis: $e');
      }
      return LojaOnlineCatalogo(
        estado: LojaOnlineEstado.pronta,
        nichos: nichos,
        produtos: produtos,
        subcategorias: subcategorias,
      );
    } catch (e) {
      if (lojaOnlineServidorEmFalta(e)) {
        debugPrint('[LojaOnline] tabelas por instalar: $e');
        return const LojaOnlineCatalogo(estado: LojaOnlineEstado.emBreve);
      }
      debugPrint('[LojaOnline] catálogo falhou: $e');
      return const LojaOnlineCatalogo(estado: LojaOnlineEstado.erro);
    }
  }

  static Future<bool> _lerVisivelNoSupabase() async {
    final r = await Supabase.instance.client.rpc(kLojaOnlineRpcVisivel);
    return r == true;
  }

  /// Só linhas ativas (a RLS já filtra; o `eq` é cinto e suspensórios).
  static Future<List<Map<String, dynamic>>> _lerAtivosNoSupabase(
      String tabela) async {
    if (tabela == kLojaOnlineTabelaNichos ||
        tabela == kLojaOnlineTabelaSubcategorias) {
      return await Supabase.instance.client
          .from(tabela)
          .select()
          .eq('ativo', true)
          .order('ordem', ascending: true);
    }
    // A ordem final (mais vendidos) faz-se na app ([compararMaisVendidos]).
    try {
      return await Supabase.instance.client
          .from(tabela)
          .select(kLojaOnlineColunasClienteNichos)
          .eq('ativo', true);
    } catch (e) {
      if (!lojaOnlineServidorEmFalta(e)) rethrow;
      return await Supabase.instance.client
          .from(tabela)
          .select(kLojaOnlineColunasCliente)
          .eq('ativo', true);
    }
  }
}

/// O lado do painel (PT-BR nos ecrãs). Tudo injetável para os testes.
class LojaOnlineAdminService {
  LojaOnlineAdminService({
    RpcFn? rpc,
    LerLinhasFn? lerTabela,
    LerDefinicaoFn? lerDefinicao,
  })  : _rpc = rpc ?? _rpcNoSupabase,
        _lerTabela = lerTabela ?? _lerTabelaNoSupabase,
        _lerDefinicao = lerDefinicao ?? _lerDefinicaoNoSupabase;

  final RpcFn _rpc;
  final LerLinhasFn _lerTabela;
  final LerDefinicaoFn _lerDefinicao;

  /// `true`/`false` do interruptor; `null` quando a chave ainda não existe
  /// em platform_settings (a proposta SQL é que a cria).
  Future<bool?> lerInterruptor() async {
    final linha = await _lerDefinicao(kLojaOnlineChaveInterruptor);
    if (linha == null || !linha.containsKey('value')) return null;
    return lojaOnlineComoBool(linha['value']);
  }

  /// Pela RPC do painel (`admin_update_setting`, auditada). Se a chave não
  /// existir o servidor responde `unknown_setting`.
  Future<void> mudarInterruptor(bool ligado) async {
    await _rpc('admin_update_setting', {
      'p_key': kLojaOnlineChaveInterruptor,
      'p_value': ligado,
    });
  }

  Future<List<LojaOnlineNicho>> listarNichos() async {
    final linhas = await _lerTabela(kLojaOnlineTabelaNichos);
    return linhas.map(LojaOnlineNicho.fromJson).toList(growable: false);
  }

  Future<List<LojaOnlineProduto>> listarProdutos() async {
    final linhas = await _lerTabela(kLojaOnlineTabelaProdutos);
    return linhas.map(LojaOnlineProduto.fromJson).toList(growable: false);
  }

  /// Liga/desliga ou destaca um produto (null = não mexe nesse campo).
  Future<void> produtoEstado({
    required String id,
    bool? ativo,
    bool? destaque,
    required String motivo,
  }) async {
    await _rpc(kLojaOnlineRpcProdutoEstado, {
      'p_id': id,
      'p_ativo': ativo,
      'p_destaque': destaque,
      'p_motivo': motivo,
    });
  }

  /// loja-nichos-15-11: abrir (true) ou fechar (false) um nicho a todos os
  /// clientes. Fechado, só o admin e as contas da lista de permissão o veem.
  Future<void> nichoPublico({
    required String nichoId,
    required bool publico,
    required String motivo,
  }) async {
    await _rpc(kLojaOnlineRpcNichoPublico, {
      'p_nicho_id': nichoId,
      'p_publico': publico,
      'p_motivo': motivo,
    });
  }

  /// Fixar a posição de um produto (1 = primeiro) ou voltar à ordem
  /// automática por vendas (null).
  Future<void> produtoOrdem({
    required String id,
    required int? ordemManual,
    required String motivo,
  }) async {
    await _rpc(kLojaOnlineRpcProdutoOrdem, {
      'p_id': id,
      'p_ordem_manual': ordemManual,
      'p_motivo': motivo,
    });
  }

  /// null quando a proposta N1 ainda não está no servidor (sem tabela).
  Future<List<LojaOnlineSubcategoria>?> listarSubcategorias() async {
    try {
      final linhas = await _lerTabela(kLojaOnlineTabelaSubcategorias);
      return linhas.map(LojaOnlineSubcategoria.fromJson).toList(growable: false);
    } catch (e) {
      if (lojaOnlineServidorEmFalta(e)) return null;
      rethrow;
    }
  }

  /// Mudar a subcategoria de um produto (null = sem subcategoria).
  Future<void> produtoSubcategoria({
    required String id,
    required String? subcategoriaId,
    required String motivo,
  }) async {
    await _rpc(kLojaOnlineRpcProdutoSubcategoria, {
      'p_id': id,
      'p_subcategoria_id': subcategoriaId,
      'p_motivo': motivo,
    });
  }

  /// Ligar/desligar uma subcategoria (desligada some da montra).
  Future<void> subcategoriaAtivo({
    required String id,
    required bool ativo,
    required String motivo,
  }) async {
    await _rpc(kLojaOnlineRpcSubcategoriaAtivo, {
      'p_id': id,
      'p_ativo': ativo,
      'p_motivo': motivo,
    });
  }

  Future<void> nichoDaSemana({
    required String nichoId,
    required String motivo,
  }) async {
    await _rpc(kLojaOnlineRpcNichoDaSemana, {
      'p_nicho_id': nichoId,
      'p_motivo': motivo,
    });
  }

  static Future<dynamic> _rpcNoSupabase(
      String funcao, Map<String, dynamic> params) async {
    final r = await Supabase.instance.client.rpc(funcao, params: params);
    return r;
  }

  /// O admin vê tudo. Os produtos (com o custo) vêm pela função do painel
  /// admin_loja_online_produtos(); se ainda não estiver no servidor, lê as
  /// colunas de cliente (sem custo) para o ecrã não ficar vazio.
  static Future<List<Map<String, dynamic>>> _lerTabelaNoSupabase(
      String tabela) async {
    if (tabela == kLojaOnlineTabelaNichos ||
        tabela == kLojaOnlineTabelaSubcategorias) {
      return await Supabase.instance.client
          .from(tabela)
          .select()
          .order('ordem', ascending: true);
    }
    try {
      final r =
          await Supabase.instance.client.rpc(kLojaOnlineRpcAdminProdutos);
      return List<Map<String, dynamic>>.from(r as List);
    } catch (e) {
      if (!lojaOnlineServidorEmFalta(e)) rethrow;
      return await Supabase.instance.client
          .from(tabela)
          .select(kLojaOnlineColunasCliente)
          .order('criado_em', ascending: false);
    }
  }

  static Future<Map<String, dynamic>?> _lerDefinicaoNoSupabase(
      String chave) async {
    return await Supabase.instance.client
        .from('platform_settings')
        .select('key, value')
        .eq('key', chave)
        .maybeSingle();
  }
}
