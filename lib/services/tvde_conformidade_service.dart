import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/falha_de_acao.dart' show kAcaoTimeout;

/// Conformidade TVDE (Lei 45/2018 na versão da Lei 59/2026).
///
/// Um só sítio para as RPCs da missão `tvde-conformidade-lei-59-2026`. Tudo o
/// que muda comportamento está atrás de interruptores em `platform_settings`
/// (mestre `tvde_compliance_enforce`, desligado por defeito) — a app lê-os em
/// [config] e, com tudo desligado, fica exatamente como estava.
class TvdeConformidadeConfig {
  const TvdeConformidadeConfig({
    this.mestre = false,
    this.soPagamentoEletronico = false,
    this.avaliarPassageiroDesativado = false,
    this.limiteHorasAtivo = false,
    this.bloqueioAtivo = false,
    this.opcoesCliente = false,
    this.ivaDiscriminar = false,
    this.limiteHoras = 10,
    this.livroReclamacoesUrl = 'https://www.livroreclamacoes.pt/Inicio/',
    this.emailContacto,
  });

  /// Tudo desligado — o comportamento de sempre. Usado em erro de rede.
  static const desligado = TvdeConformidadeConfig();

  final bool mestre;
  final bool soPagamentoEletronico;
  final bool avaliarPassageiroDesativado;
  final bool limiteHorasAtivo;
  final bool bloqueioAtivo;
  final bool opcoesCliente;
  final bool ivaDiscriminar;
  final num limiteHoras;
  final String livroReclamacoesUrl;
  final String? emailContacto;

  factory TvdeConformidadeConfig.fromMap(Map<String, dynamic> m) =>
      TvdeConformidadeConfig(
        mestre: m['mestre'] == true,
        soPagamentoEletronico: m['so_pagamento_eletronico'] == true,
        avaliarPassageiroDesativado: m['avaliar_passageiro_desativado'] == true,
        limiteHorasAtivo: m['limite_horas_ativo'] == true,
        bloqueioAtivo: m['bloqueio_ativo'] == true,
        opcoesCliente: m['opcoes_cliente'] == true,
        ivaDiscriminar: m['iva_discriminar'] == true,
        limiteHoras: (m['limite_horas'] as num?) ?? 10,
        livroReclamacoesUrl: (m['livro_reclamacoes_url'] as String?) ??
            'https://www.livroreclamacoes.pt/Inicio/',
        emailContacto: m['email_contacto'] as String?,
      );
}

class TvdeConformidadeService {
  TvdeConformidadeService._();
  static final instance = TvdeConformidadeService._();

  SupabaseClient get _sb => Supabase.instance.client;

  TvdeConformidadeConfig? _cache;
  DateTime? _cacheEm;

  /// Interruptores lidos do servidor (cache de 60 s). Em erro devolve
  /// [TvdeConformidadeConfig.desligado]: nunca bloqueia nada por falta de rede.
  Future<TvdeConformidadeConfig> config({bool forcar = false}) async {
    final c = _cache;
    final em = _cacheEm;
    if (!forcar && c != null && em != null &&
        DateTime.now().difference(em) < const Duration(seconds: 60)) {
      return c;
    }
    try {
      final res =
          await _sb.rpc('tvde_conformidade_config').timeout(kAcaoTimeout);
      final cfg = TvdeConformidadeConfig.fromMap(
          Map<String, dynamic>.from(res as Map));
      _cache = cfg;
      _cacheEm = DateTime.now();
      return cfg;
    } catch (e) {
      debugPrint('[TvdeConformidade] config falhou: $e');
      return c ?? TvdeConformidadeConfig.desligado;
    }
  }

  Future<Map<String, dynamic>> _mapa(String rpc,
      [Map<String, dynamic>? params]) async {
    final res = await _sb.rpc(rpc, params: params).timeout(kAcaoTimeout);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> _lista(String rpc,
      [Map<String, dynamic>? params]) async {
    final res = await _sb.rpc(rpc, params: params).timeout(kAcaoTimeout);
    return (res as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ── Cliente ───────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> precoDiscriminado(double distanciaKm) =>
      _mapa('tvde_fare_breakdown', {'p_distance_km': distanciaKm});
  Future<Map<String, dynamic>> operadorPlataforma() =>
      _mapa('tvde_operador_plataforma');
  Future<Map<String, dynamic>> preferencias() => _mapa('tvde_prefs_obter');
  Future<Map<String, dynamic>> guardarPreferencias(Map<String, dynamic> p) =>
      _mapa('tvde_prefs_guardar', {'p': p});
  Future<Map<String, dynamic>> mobilidadeDisponivel() =>
      _mapa('tvde_mobilidade_disponivel');
  Future<Map<String, dynamic>> criarQueixa({
    String? rideId,
    required String categoria,
    required String descricao,
    String? contacto,
  }) =>
      _mapa('tvde_queixa_criar', {
        'p_ride': rideId,
        'p_categoria': categoria,
        'p_descricao': descricao,
        'p_contacto': contacto,
      });
  Future<List<Map<String, dynamic>>> minhasQueixas() =>
      _lista('tvde_minhas_queixas');
  Future<Map<String, dynamic>> registarSos({
    required String rideId,
    double? lat,
    double? lng,
    bool ligou112 = false,
    bool partilhou = false,
  }) =>
      _mapa('tvde_sos_registar', {
        'p_ride': rideId,
        'p_lat': lat,
        'p_lng': lng,
        'p_ligou_112': ligou112,
        'p_partilhou': partilhou,
      });

  // ── Motorista ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> minhaConformidade() =>
      _mapa('tvde_minha_conformidade');
  Future<List<Map<String, dynamic>>> operadoresAprovados() =>
      _lista('tvde_operadores_aprovados');
  Future<Map<String, dynamic>> guardarDadosMotorista(Map<String, dynamic> p) =>
      _mapa('tvde_motorista_guardar_conformidade', {'p': p});
  Future<Map<String, dynamic>> submeterVeiculo(Map<String, dynamic> p) =>
      _mapa('tvde_motorista_submeter_veiculo', {'p': p});
  Future<Map<String, dynamic>> registarDocumento({
    required String tipo,
    required String caminho,
    DateTime? validade,
  }) =>
      _mapa('tvde_motorista_registar_documento', {
        'p_doc_type': tipo,
        'p_file_path': caminho,
        'p_validade': validade?.toIso8601String().substring(0, 10),
      });

  /// Pré-verificação antes de ficar online. Em erro de rede devolve ok=true:
  /// o travão verdadeiro é o gatilho no servidor.
  Future<Map<String, dynamic>> podeFicarOnline() async {
    try {
      return await _mapa('tvde_driver_pode_ficar_online');
    } catch (e) {
      debugPrint('[TvdeConformidade] podeFicarOnline falhou: $e');
      return const {'ok': true, 'motivos': []};
    }
  }
}

/// Tradução das exceções do servidor para texto que se lê (PT-PT).
String mensagemErroConformidade(Object e) {
  final s = e.toString();
  if (s.contains('TVDE_BLOQUEADO')) {
    final i = s.indexOf('TVDE_BLOQUEADO:');
    final motivos = i >= 0 ? s.substring(i + 15).split('\n').first.trim() : '';
    return 'Não podes ficar online: $motivos';
  }
  if (s.contains('LIMITE_HORAS')) {
    return 'Atingiste o limite legal de horas de serviço nas últimas 24 horas.';
  }
  if (s.contains('PAGAMENTO_ELETRONICO_OBRIGATORIO')) {
    return 'No TVDE só se aceita pagamento por cartão ou MB Way.';
  }
  if (s.contains('descricao_curta')) return 'Descreve o que aconteceu.';
  if (s.contains('matricula_de_outro')) {
    return 'Este carro já está registado. Fala com o teu operador.';
  }
  if (s.contains('lugares_invalidos')) {
    return 'Um carro TVDE tem no máximo 9 lugares.';
  }
  if (s.contains('operador_invalido')) return 'Escolhe um operador da lista.';
  return 'Não foi possível concluir. Tenta outra vez.';
}
