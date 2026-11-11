// Serviço da receita / pedidos especiais da farmácia (missão farmacias-2026-11-11).
// Fala só com as RPCs e o bucket privado descritos em
// .claude/.ai/missoes/farmacias-2026-11-11/CONTRATO.md. Nada de valores cravados:
// a taxa e o texto da autorização vêm do servidor (farmacia_consentimento).
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/pedido_prescricao.dart';

class PrescricaoConsentimento {
  final String versao;
  final String texto;
  final int taxaServicoCents;
  const PrescricaoConsentimento({
    required this.versao,
    required this.texto,
    required this.taxaServicoCents,
  });
}

/// Erro com mensagem já em português para mostrar ao utilizador.
class PrescricaoErro implements Exception {
  final String mensagem;
  PrescricaoErro(this.mensagem);
  @override
  String toString() => mensagem;
}

class PrescricaoService {
  PrescricaoService({SupabaseClient? client}) : _sbOverride = client;

  final SupabaseClient? _sbOverride;
  SupabaseClient get _sb => _sbOverride ?? Supabase.instance.client;

  static const bucket = 'prescricoes';
  static const tabela = 'pedidos_prescricao';

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
      throw PrescricaoErro(mensagemDe(e));
    }
  }

  // ---------------------------------------------------------------- cliente

  /// Os 3 botões e a receita só aparecem se o servidor disser que sim (farmácia + modo + lista).
  Future<bool> botoesVisiveis(String restaurantId) async {
    try {
      final r = await _sb.rpc('farmacia_botoes_visiveis', params: {'p_restaurant_id': restaurantId});
      return r == true;
    } catch (_) {
      return false; // sem resposta = escondido (nunca mostrar a quem não pode ver)
    }
  }

  Future<PrescricaoConsentimento> consentimento(String restaurantId) async {
    final r = await _rpc<dynamic>('farmacia_consentimento', {'p_restaurant_id': restaurantId});
    final m = Map<String, dynamic>.from(r as Map);
    return PrescricaoConsentimento(
      versao: (m['versao'] ?? '').toString(),
      texto: (m['texto'] ?? '').toString(),
      taxaServicoCents: (m['taxa_servico_cents'] as num?)?.toInt() ?? 0,
    );
  }

  /// Sobe um ficheiro para a pasta do cliente no bucket privado e devolve o caminho
  /// (nunca um URL público). [sufixo] = 'receita' | 'assinatura' | 'pedido'.
  Future<String> subirFicheiro({
    required Uint8List bytes,
    required String sufixo,
    required String extensao,
    String contentType = 'image/jpeg',
  }) async {
    final uid = _uid;
    if (uid == null) throw PrescricaoErro('Tem de entrar na sua conta.');
    final ext = extensao.replaceAll('.', '').toLowerCase();
    final caminho = '$uid/${const Uuid().v4()}-$sufixo.$ext';
    try {
      await _sb.storage.from(bucket).uploadBinary(
            caminho,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } catch (e) {
      throw PrescricaoErro('Não foi possível enviar a imagem. Verifique a internet e tente outra vez.');
    }
    return caminho;
  }

  /// URL assinado de curta duração (5 min) para ver uma foto privada.
  Future<String?> urlAssinado(String? caminho, {int segundos = 300}) async {
    if (caminho == null || caminho.isEmpty) return null;
    try {
      return await _sb.storage.from(bucket).createSignedUrl(caminho, segundos);
    } catch (_) {
      return null;
    }
  }

  Future<String> criar({
    required String restaurantId,
    required PrescricaoTipo tipo,
    String? receitaFotoPath,
    String? receitaNumero,
    String? receitaCodigoAcesso,
    String? receitaCodigoOpcao,
    String? descricao,
    String? pedidoFotoPath,
    String? morada,
    double? lat,
    double? lng,
    String? nota,
    String? assinaturaPath,
    String? consentimentoVersao,
  }) async {
    final r = await _rpc<dynamic>('prescricao_criar', {
      'p_restaurant_id': restaurantId,
      'p_tipo': tipo == PrescricaoTipo.pedidoLivre ? 'pedido_livre' : 'receita',
      'p_receita_foto_path': receitaFotoPath,
      'p_receita_numero': _limpo(receitaNumero),
      'p_receita_codigo_acesso': _limpo(receitaCodigoAcesso),
      'p_receita_codigo_opcao': _limpo(receitaCodigoOpcao),
      'p_descricao': _limpo(descricao),
      'p_pedido_foto_path': pedidoFotoPath,
      'p_morada': _limpo(morada),
      'p_lat': lat,
      'p_lng': lng,
      'p_nota': _limpo(nota),
      'p_assinatura_path': assinaturaPath,
      'p_consentimento_versao': consentimentoVersao,
    });
    return r.toString();
  }

  /// [metodo] = 'card' | 'mbway' | 'cash'. Devolve o mapa que o servidor manda
  /// (estado, códigos, total, is_demo).
  Future<Map<String, dynamic>> confirmar(String id, {required String metodo, bool soDisponiveis = true}) async {
    final r = await _rpc<dynamic>('prescricao_confirmar', {
      'p_id': id,
      'p_metodo': metodo,
      'p_so_disponiveis': soDisponiveis,
    });
    return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r as Map);
  }

  Future<void> cancelar(String id) => _rpc<dynamic>('prescricao_cancelar', {'p_id': id});

  Future<PedidoPrescricao?> obter(String id) async {
    final r = await _sb.from(tabela).select().eq('id', id).maybeSingle();
    return r == null ? null : PedidoPrescricao.fromMap(r);
  }

  /// Tempo real de um pedido (a resposta da farmácia aparece em segundos).
  Stream<PedidoPrescricao?> acompanhar(String id) {
    return _sb
        .from(tabela)
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((linhas) => linhas.isEmpty ? null : PedidoPrescricao.fromMap(linhas.first));
  }

  /// Pedidos do cliente atual (mais recentes primeiro), opcionalmente de uma loja.
  Future<List<PedidoPrescricao>> meus({String? restaurantId, int limite = 30}) async {
    final uid = _uid;
    if (uid == null) return const [];
    var q = _sb.from(tabela).select().eq('user_id', uid);
    if (restaurantId != null) q = q.eq('restaurant_id', restaurantId);
    final r = await q.order('created_at', ascending: false).limit(limite);
    return (r as List).map((e) => PedidoPrescricao.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<String> lembreteDefinir({
    required String restaurantId,
    String? prescricaoId,
    String? orderId,
    required int diaDoMes,
  }) async {
    final r = await _rpc<dynamic>('farmacia_lembrete_definir', {
      'p_restaurant_id': restaurantId,
      'p_prescricao_id': prescricaoId,
      'p_order_id': orderId,
      'p_dia': diaDoMes,
    });
    return r.toString();
  }

  Future<void> lembreteDesligar(String id) => _rpc<dynamic>('farmacia_lembrete_desligar', {'p_id': id});

  Future<List<Map<String, dynamic>>> meusLembretes() async {
    final uid = _uid;
    if (uid == null) return const [];
    final r = await _sb
        .from('farmacia_lembretes')
        .select()
        .eq('user_id', uid)
        .eq('ativo', true)
        .order('created_at', ascending: false);
    return (r as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ---------------------------------------------------------------- farmácia

  /// Pedidos da loja (a RLS só deixa ver os da loja de que a pessoa é dona).
  Stream<List<PedidoPrescricao>> daLoja(String restaurantId) {
    return _sb
        .from(tabela)
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false)
        .map((linhas) => linhas.map(PedidoPrescricao.fromMap).toList());
  }

  Future<void> responder(
    String id, {
    required bool aceita,
    int? valorCents,
    bool parcial = false,
    String? itensDisponiveis,
    int? tempoPreparacaoMin,
    String? motivo,
    String? motivoTexto,
    String? voltaATer,
  }) =>
      _rpc<dynamic>('prescricao_responder', {
        'p_id': id,
        'p_aceita': aceita,
        'p_valor_cents': valorCents,
        'p_parcial': parcial,
        'p_itens_disponiveis': _limpo(itensDisponiveis),
        'p_tempo_preparacao_min': tempoPreparacaoMin,
        'p_motivo': motivo,
        'p_motivo_texto': _limpo(motivoTexto),
        'p_volta_a_ter': _limpo(voltaATer),
      });

  // ---------------------------------------------------------------- admin (PT-BR nos ecrãs)

  Future<List<Map<String, dynamic>>> adminListar({String? estado, String? restaurantId, int limite = 200}) async {
    final r = await _rpc<dynamic>('admin_prescricoes_listar', {
      'p_estado': estado,
      'p_restaurant_id': restaurantId,
      'p_limite': limite,
    });
    return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> adminForcar(String id, {required String estado, required String motivo}) =>
      _rpc<dynamic>('admin_prescricao_forcar', {'p_id': id, 'p_estado': estado, 'p_motivo': motivo});

  Future<void> adminFarmaciaDefinir({
    required String restaurantId,
    String? modo,
    bool? soLista,
    double? extraPct,
    DateTime? extraInicio,
  }) =>
      _rpc<dynamic>('admin_farmacia_definir', {
        'p_restaurant_id': restaurantId,
        'p_modo': modo,
        'p_so_lista': soLista,
        'p_extra_pct': extraPct,
        'p_extra_inicio': extraInicio?.toUtc().toIso8601String(),
      });

  /// Substitui a lista de permissão da loja pelos emails dados (contas que já existem).
  /// Devolve os emails que não correspondem a nenhuma conta.
  Future<List<String>> adminListaPermissaoDefinir(String restaurantId, List<String> emails) async {
    final r = await _rpc<dynamic>('admin_loja_lista_permissao_definir', {
      'p_restaurant_id': restaurantId,
      'p_emails': emails.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList(),
    });
    return (r as List? ?? const []).map((e) => e.toString()).toList();
  }

  /// Emails na lista de permissão da loja.
  Future<List<String>> adminListaPermissao(String restaurantId) async {
    final r = await _rpc<dynamic>('admin_loja_lista_permissao_listar', {'p_restaurant_id': restaurantId});
    return (r as List? ?? const []).map((e) => e.toString()).toList();
  }

  /// Lojas de categoria farmácia com os campos de visibilidade, receita e comissão extra.
  Future<List<Map<String, dynamic>>> adminFarmacias() async {
    final r = await _rpc<dynamic>('admin_farmacias_listar', {});
    return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> adminFarmaciaAbrir(String restaurantId) =>
      _rpc<dynamic>('admin_farmacia_abrir', {'p_restaurant_id': restaurantId});

  static String? _limpo(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
