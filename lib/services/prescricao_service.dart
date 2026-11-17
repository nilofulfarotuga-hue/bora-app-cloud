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

  /// 17/11/2026: a farmácia está aberta agora? (sem a migração receita_cartao_mbway o
  /// servidor não manda e fica true — o pedido continua a ser recusado no fim, como antes).
  final bool aberta;

  /// "09:00" quando está fechada (hora de Lisboa) e [abreDia] ("hoje", "amanhã"…).
  final String? abreAs;
  final String? abreDia;
  const PrescricaoConsentimento({
    required this.versao,
    required this.texto,
    required this.taxaServicoCents,
    this.aberta = true,
    this.abreAs,
    this.abreDia,
  });

  /// "A farmácia está fechada. Abre às 09:00." (ou null se aberta).
  String? get avisoFechada {
    if (aberta) return null;
    final quando = abreAs == null
        ? ''
        : (abreDia == null || abreDia == 'hoje')
            ? ' Abre às $abreAs.'
            : ' Abre $abreDia às $abreAs.';
    return 'A farmácia está fechada neste momento.$quando Pode enviar quando abrir.';
  }
}

/// Entrega de um pedido à farmácia ligado a um pedido real (estado e estafeta).
class PrescricaoEntrega {
  final String prescricaoId;
  final String orderId;
  final String? estadoPedido;
  final String? estafetaNome;
  const PrescricaoEntrega({
    required this.prescricaoId,
    required this.orderId,
    this.estadoPedido,
    this.estafetaNome,
  });

  /// Frase curta para a farmácia (PT-PT).
  String get rotulo {
    final quem = (estafetaNome ?? '').isEmpty ? 'O estafeta' : estafetaNome!;
    switch (estadoPedido) {
      case 'created':
      case 'preparing':
      case 'callingDriver':
        return 'À procura de estafeta';
      case 'driverAccepted':
        return '$quem vem a caminho da farmácia';
      case 'pickedUp':
      case 'onTheWay':
        return '$quem já levantou e está a entregar';
      case 'delivered':
        return 'Entregue ao cliente';
      case 'cancelled':
      case 'rejected':
        return 'Pedido cancelado';
      default:
        return 'Pedido criado';
    }
  }
}

/// Erro com mensagem já em português para mostrar ao utilizador.
class PrescricaoErro implements Exception {
  final String mensagem;

  /// Código do servidor ("RECEITA_REAL_POR_LIGAR", "PAGAMENTO_EM_CURSO"…), quando veio.
  final String? codigo;
  PrescricaoErro(this.mensagem, {this.codigo});
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

  /// "CODIGO: texto" → "CODIGO" (null se a mensagem não traz código).
  static String? codigoDe(Object e) {
    if (e is PrescricaoErro) return e.codigo;
    final m = e is PostgrestException ? e.message : e.toString();
    final i = m.indexOf(':');
    if (i > 0 && i < 40 && m.substring(0, i).toUpperCase() == m.substring(0, i)) return m.substring(0, i).trim();
    return null;
  }

  Future<T> _rpc<T>(String nome, Map<String, dynamic> params) async {
    try {
      final r = await _sb.rpc(nome, params: params);
      return r as T;
    } catch (e) {
      throw PrescricaoErro(mensagemDe(e), codigo: codigoDe(e));
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
      aberta: m['aberta'] != false,
      abreAs: m['abre_as']?.toString(),
      abreDia: m['abre_dia']?.toString(),
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

  /// Cartão / MB Way em loja real (17/11/2026): o servidor monta o Favor e devolve
  /// `cart_input` (cartão) ou `order_id` (MB Way). Ver prescricao_pagamento_service.dart.
  Future<Map<String, dynamic>> prepararPagamento(String id, {required String metodo, bool soDisponiveis = true}) async {
    try {
      final r = await _sb.rpc('prescricao_preparar_pedido', params: {
        'p_id': id,
        'p_metodo': metodo,
        'p_so_disponiveis': soDisponiveis,
      });
      return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r as Map);
    } on PostgrestException catch (e) {
      // Servidor ainda sem a função (migração por aplicar): frase clara, sem erro técnico.
      if (e.code == 'PGRST202' || e.message.contains('Could not find the function')) {
        throw PrescricaoErro('Por agora, nesta farmácia, pague em dinheiro ao estafeta. Escolha "Dinheiro na entrega".');
      }
      throw PrescricaoErro(mensagemDe(e), codigo: codigoDe(e));
    } catch (e) {
      throw PrescricaoErro(mensagemDe(e), codigo: codigoDe(e));
    }
  }

  /// O cliente fechou a folha do cartão sem pagar: o dinheiro e o cancelar deixam de esperar
  /// pelo cartão. Sem a função no servidor não faz nada.
  Future<void> desistirDoCartao(String id) async {
    try {
      await _sb.rpc('prescricao_pagamento_desistir', params: {'p_id': id});
    } catch (_) {}
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

  /// Moradas guardadas na conta com coordenadas (as mesmas do checkout), a principal primeiro.
  Future<List<({String morada, double lat, double lng})>> moradasGuardadas({int limite = 5}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final r = await _sb
          .from('client_addresses')
          .select('address, lat, lng, is_default')
          .eq('user_id', uid)
          .not('lat', 'is', null)
          .not('lng', 'is', null)
          .order('is_default', ascending: false)
          .limit(limite);
      return (r as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((m) => (m['address'] ?? '').toString().trim().isNotEmpty)
          .map((m) => (
                morada: m['address'].toString().trim(),
                lat: (m['lat'] as num).toDouble(),
                lng: (m['lng'] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
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

  /// Estado da entrega e 1.º nome do estafeta dos pedidos ligados (só a farmácia dona e o
  /// admin recebem linhas). Sem a função no servidor devolve lista vazia.
  Future<List<PrescricaoEntrega>> entregas(List<String> prescricaoIds) async {
    if (prescricaoIds.isEmpty) return const [];
    try {
      final r = await _sb.rpc('farmacia_prescricoes_entrega', params: {'p_ids': prescricaoIds});
      return (r as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((m) => PrescricaoEntrega(
                prescricaoId: m['prescricao_id'].toString(),
                orderId: (m['order_id'] ?? '').toString(),
                estadoPedido: m['estado_pedido'] as String?,
                estafetaNome: m['estafeta_nome'] as String?,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
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

  /// app-15-11: a farmácia fecha um pedido de DEMONSTRAÇÃO confirmado ("levantado").
  /// Função do servidor da proposta docs/propostas/app-15-11/farmacias_servidor.PROPOSTA.sql;
  /// enquanto não estiver aplicada, a mensagem diz isso em vez de um erro técnico.
  Future<void> fecharDemo(String id) async {
    try {
      await _sb.rpc('farmacia_prescricao_fechar_demo', params: {'p_id': id});
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.message.contains('Could not find the function')) {
        throw PrescricaoErro('Esta opção ainda não está disponível. Fale com a equipa Bora.');
      }
      throw PrescricaoErro(mensagemDe(e));
    } catch (e) {
      throw PrescricaoErro(mensagemDe(e));
    }
  }

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

  /// Nome da loja (a RLS só devolve se a pessoa a pode ver).
  Future<String?> nomeDaLoja(String restaurantId) async {
    final r = await _sb.from('restaurants').select('name').eq('id', restaurantId).maybeSingle();
    return r?['name'] as String?;
  }

  static String? _limpo(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
