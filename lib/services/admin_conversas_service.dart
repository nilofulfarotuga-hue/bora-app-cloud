// CONVERSAS AO VIVO (15/11/2026, missão app-15-11 — pedido do Danilo de
// 12/11/2026 06:22): o painel vê numa lista só, ao vivo, as conversas dos 3
// robôs que falam com clientes — o robô do suporte da app, o Amigo Bora e os
// robôs das lojas no WhatsApp —, abre a conversa, assume (o robô cala-se),
// devolve ao robô e responde como "Equipa Bora".
//
// Contratos do servidor: docs/propostas/app-15-11/conversas_ao_vivo.PROPOSTA.sql
// (admin_conversas_ao_vivo, admin_conversa_mensagens, admin_conversa_assumir,
// admin_conversa_devolver, admin_conversa_responder; só admin). É uma PROPOSTA:
// até ser aplicada, as funções não existem (PostgREST PGRST202) e o painel diz
// isso com calma — ver [funcaoEmFalta] e [kConversasFuncaoEmFalta].
// Textos em PT-BR (painel). Nada de dinheiro.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// As 3 origens (o `origem` / `p_origem` das RPCs).
const String kOrigemSuporteApp = 'suporte_app';
const String kOrigemAmigo = 'amigo';
const String kOrigemWhatsappLoja = 'whatsapp_loja';
const List<String> kOrigensConversa = [
  kOrigemSuporteApp,
  kOrigemAmigo,
  kOrigemWhatsappLoja,
];

/// As tabelas de mensagens das 3 origens (tempo real da lista).
const List<String> kTabelasMensagensRobos = [
  'support_chatbot_messages',
  'assistant_chat_messages',
  'assistant_messages',
];

/// O que o painel diz enquanto a migração não está aplicada.
const String kConversasFuncaoEmFalta =
    'Esta função ainda não foi instalada no servidor (proposta conversas_ao_vivo).';

/// A função (RPC) ainda não existe no servidor? O PostgREST responde
/// PGRST202 "Could not find the function … in the schema cache"; o Postgres,
/// 42883 (undefined_function).
bool funcaoEmFalta(Object e) {
  if (e is PostgrestException) {
    if (e.code == 'PGRST202' || e.code == '42883') return true;
    if (e.message.contains('Could not find the function')) return true;
  }
  final t = e.toString();
  return t.contains('PGRST202') || t.contains('Could not find the function');
}

String _texto(Object? v) => v == null ? '' : v.toString();

String? _textoOuNull(Object? v) {
  final t = _texto(v).trim();
  return t.isEmpty ? null : t;
}

int _inteiro(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.round() ?? 0;
  }
  return 0;
}

DateTime? _data(Object? v) {
  if (v is DateTime) return v;
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// As linhas de uma RPC que devolve `table(...)` (tolera null e lixo).
List<Map<String, dynamic>> linhasDaRpc(Object? res) {
  if (res is! List) return const [];
  return res
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

/// Uma conversa da lista (`admin_conversas_ao_vivo`).
class ConversaAoVivo {
  const ConversaAoVivo({
    required this.origem,
    required this.conversaId,
    this.clienteUserId,
    required this.clienteNome,
    required this.canal,
    this.ultimaMensagemEm,
    required this.ultimaMensagemResumo,
    required this.ultimoAutor,
    required this.estado,
    required this.naoLidas,
  });

  /// 'suporte_app' | 'amigo' | 'whatsapp_loja'.
  final String origem;

  /// uuid da sessão/conversa; nas lojas, `<tenant_id>:<numero>`.
  final String conversaId;

  /// Só nas conversas da app (o WhatsApp das lojas não tem conta Bora).
  final String? clienteUserId;

  /// Como vem do servidor ("Cliente" quando não há nome; nas lojas,
  /// "Nome · Loja"). Para mostrar, usar `nomeClienteParaMostrar`.
  final String clienteNome;
  final String canal;
  final DateTime? ultimaMensagemEm;
  final String ultimaMensagemResumo;

  /// 'cliente' | 'robo' | 'equipa'.
  final String ultimoAutor;

  /// 'robo' | 'equipa' | 'pediu_pessoa' | 'desligado'.
  final String estado;

  /// Mensagens do cliente que a equipa ainda não leu.
  final int naoLidas;

  factory ConversaAoVivo.fromJson(Map<String, dynamic> j) => ConversaAoVivo(
        origem: _texto(j['origem']).trim(),
        conversaId: _texto(j['conversa_id']).trim(),
        clienteUserId: _textoOuNull(j['cliente_user_id']),
        clienteNome: _texto(j['cliente_nome']).trim(),
        canal: _texto(j['canal']).trim(),
        ultimaMensagemEm: _data(j['ultima_mensagem_em']),
        ultimaMensagemResumo: _texto(j['ultima_mensagem_resumo']),
        ultimoAutor: _texto(j['ultimo_autor']).trim(),
        estado: _texto(j['estado']).trim(),
        naoLidas: _inteiro(j['nao_lidas']),
      );
}

/// Um balão da conversa (`admin_conversa_mensagens`).
class MensagemConversa {
  const MensagemConversa({
    required this.id,
    required this.autor,
    required this.texto,
    this.ferramenta,
    this.criadoEm,
  });

  final String id;

  /// 'cliente' | 'robo' | 'equipa' | 'ferramenta'.
  final String autor;
  final String texto;

  /// Nome da ferramenta que o robô usou (só nas linhas 'ferramenta').
  final String? ferramenta;
  final DateTime? criadoEm;

  bool get daFerramenta => autor == 'ferramenta';

  factory MensagemConversa.fromJson(Map<String, dynamic> j) => MensagemConversa(
        id: _texto(j['id']),
        autor: _texto(j['autor']).trim(),
        texto: _texto(j['texto']),
        ferramenta: _textoOuNull(j['ferramenta']),
        criadoEm: _data(j['criado_em']),
      );
}

/// O servidor manda as mais recentes primeiro; o ecrã quer a mais antiga em
/// cima e a mais recente em baixo. Ordem estável: no mesmo instante fica a
/// ordem do servidor (invertida).
List<MensagemConversa> mensagensDaMaisAntiga(List<MensagemConversa> doServidor) {
  final l = doServidor.reversed.toList();
  final indices = List<int>.generate(l.length, (i) => i);
  final zero = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  indices.sort((a, b) {
    final c = (l[a].criadoEm ?? zero).compareTo(l[b].criadoEm ?? zero);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in indices) l[i]];
}

/// As RPCs das conversas ao vivo. Os testes passam um cliente ou uma
/// subclasse falsa; por defeito usa o Supabase da app.
class AdminConversasService {
  const AdminConversasService({this.client});

  final SupabaseClient? client;

  SupabaseClient get _c => client ?? Supabase.instance.client;

  /// A lista, as mais recentes primeiro (a ordem do servidor).
  /// [soEsperaEquipa]: só as que têm mensagens por ler ou pediram uma pessoa.
  Future<List<ConversaAoVivo>> listar({
    int limite = 200,
    bool soEsperaEquipa = false,
    String? origem,
  }) async {
    final res = await _c.rpc('admin_conversas_ao_vivo', params: {
      'p_limite': limite,
      'p_so_nao_lidas': soEsperaEquipa,
      'p_origem': origem,
    });
    return linhasDaRpc(res).map(ConversaAoVivo.fromJson).toList();
  }

  /// A conversa da mais antiga para a mais recente. O servidor marca-a como
  /// lida pela equipa.
  Future<List<MensagemConversa>> mensagens(
    String origem,
    String conversaId, {
    int limite = 300,
  }) async {
    final res = await _c.rpc('admin_conversa_mensagens', params: {
      'p_origem': origem,
      'p_conversa_id': conversaId,
      'p_limite': limite,
    });
    return mensagensDaMaisAntiga(
        linhasDaRpc(res).map(MensagemConversa.fromJson).toList());
  }

  /// A equipa assume: o robô cala-se (no Amigo e nas lojas, 12 h).
  Future<Map<String, dynamic>> assumir(String origem, String conversaId) =>
      _acao('admin_conversa_assumir',
          {'p_origem': origem, 'p_conversa_id': conversaId});

  /// Devolve a conversa ao robô.
  Future<Map<String, dynamic>> devolver(String origem, String conversaId) =>
      _acao('admin_conversa_devolver',
          {'p_origem': origem, 'p_conversa_id': conversaId});

  /// Responde como "Equipa Bora" (e o robô fica calado nessa conversa).
  Future<Map<String, dynamic>> responder(
          String origem, String conversaId, String texto) =>
      _acao('admin_conversa_responder', {
        'p_origem': origem,
        'p_conversa_id': conversaId,
        'p_texto': texto,
      });

  Future<Map<String, dynamic>> _acao(
      String rpc, Map<String, dynamic> params) async {
    final res = await _c.rpc(rpc, params: params);
    return res is Map
        ? Map<String, dynamic>.from(res)
        : <String, dynamic>{'ok': false};
  }

  /// Tempo real da lista: [aoMudar] corre quando entra uma mensagem nova numa
  /// das 3 origens. Um canal por tabela: as do Amigo e das lojas só entram na
  /// publicação do tempo real com a migração, e um canal com erro não pode
  /// calar o do suporte (que já funciona hoje). Devolve a função que desliga
  /// tudo. Nunca lança (sem Supabase, não liga nada).
  VoidCallback ouvirMensagensNovas(void Function() aoMudar) {
    final canais = <RealtimeChannel>[];
    final sufixo = DateTime.now().microsecondsSinceEpoch;
    for (final tabela in kTabelasMensagensRobos) {
      try {
        final canal = _c.channel('admin_conversas_${tabela}_$sufixo')
          ..onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: tabela,
            callback: (_) => aoMudar(),
          )
          ..subscribe();
        canais.add(canal);
      } catch (e) {
        debugPrint('[AdminConversas] tempo real $tabela: $e');
      }
    }
    return () {
      for (final canal in canais) {
        try {
          canal.unsubscribe().ignore();
        } catch (_) {}
      }
    };
  }
}
