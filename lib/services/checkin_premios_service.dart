// lib/services/checkin_premios_service.dart
//
// Marcos do check-in (Bora Todo Dia, Bloco D — 21/10/2026).
// Além dos tokens da semana (Dia 1..7, que não mudam), a sequência contínua de
// check-ins dá prémios aos 10, 15 e 30 dias seguidos (o 7 é só mostrado: são os
// tokens do Dia 7). Falhar um dia volta ao dia 1; depois do dia 30 recomeça.
//
// Tudo vem do servidor (`platform_settings.checkin_marco_*`):
//  - `client_checkin_premios()`           → vista do mês + "Os meus prémios";
//  - `client_checkin_premio_reservar(id)` → guarda o vale para o carrinho (60 min)
//                                            e devolve o artigo-prémio a 0 €;
//  - `client_checkin_premio_libertar(id)` → o cliente tirou o prémio do carrinho;
//  - `client_checkin_premio_visto(ids)`   → a festa (confete) já foi mostrada;
//  - `client_checkin_premio_marcar_limpeza/lavagem(...)` → vale dos 30 dias.
// O vale só fica "usado" quando o pedido é criado (gatilho no servidor), por isso
// a app nunca decide sozinha se um prémio vale ou não.
//
// Escada de prémios (29/10/2026): os prémios de produto/serviço passam a ser UM
// por sequência, o mais alto a que o cliente chegar. Ao chegar a um degrau o
// prémio fica guardado; o cliente escolhe "Levantar agora" (vale criado, a
// sequência volta ao dia 1) ou "Continuar" (troca por um maior no degrau
// seguinte). Vem em `client_checkin_premios().escada`; os botões chamam
// `client_checkin_escada_levantar()` e `client_checkin_escada_continuar()`.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/tr.dart';

/// Prefixo dos artigos-prémio no catálogo (preço 0, escondidos do menu).
const String kPrefixoArtigoPremio = 'premio-checkin-';

/// O artigo do carrinho é um prémio do check-in?
bool ehArtigoPremio(String productId) => productId.startsWith(kPrefixoArtigoPremio);

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;

DateTime? _data(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

class CheckinMarco {
  const CheckinMarco({
    required this.chave,
    required this.dia,
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.atingido,
    required this.faltam,
    this.tokens,
  });

  final String chave;
  final int dia;

  /// 'tokens' (só se mostra), 'produto' ou 'servico'.
  final String tipo;
  final String titulo;
  final String descricao;
  final bool atingido;

  /// Check-ins que ainda faltam (0 se já atingido neste ciclo).
  final int faltam;

  /// Só no marco 'tokens': os tokens do Dia 7.
  final int? tokens;

  factory CheckinMarco.fromJson(Map<String, dynamic> m) => CheckinMarco(
        chave: '${m['chave'] ?? ''}',
        dia: _int(m['dia']),
        tipo: '${m['tipo'] ?? ''}',
        titulo: '${m['titulo'] ?? ''}',
        descricao: '${m['descricao'] ?? ''}',
        atingido: m['atingido'] == true,
        faltam: _int(m['faltam']),
        tokens: m['tokens'] == null ? null : _int(m['tokens']),
      );
}

/// Um vale (prémio) da pessoa.
class CheckinVale {
  const CheckinVale({
    required this.id,
    required this.marco,
    required this.chave,
    required this.tipo,
    required this.estado,
    required this.titulo,
    this.lojaId,
    this.lojaNome,
    this.produtoId,
    this.quantidade = 1,
    this.opcoes = const [],
    this.opcao,
    this.valorCents = 0,
    this.validoAte,
    this.ativarEm,
    this.esperarAte,
    this.usadoEm,
    this.pedidoId,
    this.marcacaoTipo,
    this.origem = 'checkin',
    this.visto = false,
  });

  final String id;
  final int marco;
  final String chave;

  /// 'produto' | 'servico'.
  final String tipo;

  /// 'por_usar' | 'reservado' | 'usado' | 'expirado' | 'anulado' |
  /// 'guardado' (tecto do mês) | 'a_espera_pedido' (falta 1 pedido pago).
  final String estado;
  final String titulo;
  final String? lojaId;
  final String? lojaNome;
  final String? produtoId;
  final int quantidade;

  /// No vale dos 30 dias: ['limpeza', 'lavagem'].
  final List<String> opcoes;
  final String? opcao;
  final int valorCents;
  final DateTime? validoAte;
  final DateTime? ativarEm;
  final DateTime? esperarAte;
  final DateTime? usadoEm;
  final String? pedidoId;
  final String? marcacaoTipo;
  final String origem;
  final bool visto;

  bool get ehProduto => tipo == 'produto';
  bool get ehServico => tipo == 'servico';

  /// Pode ser usado agora (no carrinho ou numa marcação).
  bool get usavel => estado == 'por_usar' || estado == 'reservado';

  /// Fica na secção "Por usar" (inclui os que esperam pelo tecto ou por um pedido).
  bool get ativo => usavel || estado == 'guardado' || estado == 'a_espera_pedido';

  factory CheckinVale.fromJson(Map<String, dynamic> m) => CheckinVale(
        id: '${m['id']}',
        marco: _int(m['marco']),
        chave: '${m['chave'] ?? ''}',
        tipo: '${m['tipo'] ?? ''}',
        estado: '${m['estado'] ?? ''}',
        titulo: '${m['titulo'] ?? ''}',
        lojaId: m['loja_id'] as String?,
        lojaNome: m['loja_nome'] as String?,
        produtoId: m['produto_id'] as String?,
        quantidade: _int(m['quantidade'], 1),
        opcoes: (m['opcoes'] is List)
            ? (m['opcoes'] as List).map((e) => '$e').toList()
            : const [],
        opcao: m['opcao'] as String?,
        valorCents: _int(m['valor_cents']),
        validoAte: _data(m['valido_ate']),
        ativarEm: _data(m['ativar_em']),
        esperarAte: _data(m['esperar_ate']),
        usadoEm: _data(m['usado_em']),
        pedidoId: m['pedido_id'] as String?,
        marcacaoTipo: m['marcacao_tipo'] as String?,
        origem: '${m['origem'] ?? 'checkin'}',
        visto: m['visto'] == true,
      );
}

/// Um degrau da escada: o prémio guardado ou o próximo maior.
class CheckinDegrau {
  const CheckinDegrau({
    required this.chave,
    required this.dia,
    required this.titulo,
    this.tipo = '',
    this.descricao = '',
    this.faltam = 0,
    this.guardadoEm,
    this.guardadoEmTexto = '',
    this.garantidoAte,
  });

  final String chave;
  final int dia;
  final String titulo;

  /// 'produto' | 'servico' (só no guardado).
  final String tipo;
  final String descricao;

  /// Só no próximo maior: check-ins que faltam até lá.
  final int faltam;

  /// Só no guardado: quando chegou ao degrau e até quando fica garantido.
  final DateTime? guardadoEm;
  final DateTime? garantidoAte;

  /// `guardado_em` tal como veio do servidor (marca da festa, uma por degrau).
  final String guardadoEmTexto;

  static CheckinDegrau? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    return CheckinDegrau(
      chave: '${m['chave'] ?? ''}',
      dia: _int(m['dia']),
      titulo: '${m['titulo'] ?? ''}',
      tipo: '${m['tipo'] ?? ''}',
      descricao: '${m['descricao'] ?? ''}',
      faltam: _int(m['faltam']),
      guardadoEm: _data(m['guardado_em']),
      guardadoEmTexto: '${m['guardado_em'] ?? ''}',
      garantidoAte: _data(m['garantido_ate']),
    );
  }
}

/// A escada de prémios (29/10/2026). `null`/ausente no JSON = desligada.
class CheckinEscada {
  const CheckinEscada({
    required this.ativa,
    required this.texto,
    this.guardado,
    this.decisao,
    this.pendenteDecisao = false,
    this.podeContinuar = false,
    this.proximoMaior,
    this.ultimoDia = 0,
    this.levantados = 0,
    this.reinicioData,
    this.ultimoValeId,
  });

  final bool ativa;
  final String texto;
  final CheckinDegrau? guardado;

  /// `null` | 'pendente' | 'continuar'.
  final String? decisao;

  /// Chegou a um degrau e ainda não escolheu (mostra os dois botões).
  final bool pendenteDecisao;
  final bool podeContinuar;
  final CheckinDegrau? proximoMaior;

  /// Dia do degrau mais alto (no último não há "continuar").
  final int ultimoDia;
  final int levantados;
  final DateTime? reinicioData;
  final String? ultimoValeId;

  /// Tem um prémio guardado e já não está à espera da escolha
  /// (escolheu continuar, ou falhou um dia com o prémio ainda garantido).
  bool get temGuardadoSemEscolha => ativa && guardado != null && !pendenteDecisao;

  static CheckinEscada? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    final d = m['decisao'];
    return CheckinEscada(
      ativa: m['ativa'] == true,
      texto: '${m['texto'] ?? ''}',
      guardado: CheckinDegrau.fromJson(m['guardado']),
      decisao: d == null ? null : '$d',
      pendenteDecisao: m['pendente_decisao'] == true,
      podeContinuar: m['pode_continuar'] == true,
      proximoMaior: CheckinDegrau.fromJson(m['proximo_maior']),
      ultimoDia: _int(m['ultimo_dia']),
      levantados: _int(m['levantados']),
      reinicioData: _data(m['reinicio_data']),
      ultimoValeId: m['ultimo_vale_id'] == null ? null : '${m['ultimo_vale_id']}',
    );
  }
}

/// Resposta de "Levantar agora" / "Continuar".
class CheckinEscadaResultado {
  const CheckinEscadaResultado({required this.ok, this.reason, this.vale, this.estado});

  final bool ok;

  /// Só quando `ok == false`: 'sem_sessao' | 'sem_premio' | 'expirado' |
  /// 'ja_levantado' | 'ultimo_degrau' | 'sem_rede'.
  final String? reason;

  /// Só no "Levantar": o vale criado.
  final CheckinVale? vale;

  /// O estado dos marcos depois da escolha (sem texto, vales nem novos).
  final CheckinPremiosEstado? estado;

  factory CheckinEscadaResultado.fromJson(Map<String, dynamic> m) {
    final v = m['vale'];
    final e = m['estado'];
    return CheckinEscadaResultado(
      ok: m['ok'] == true,
      reason: m['reason'] == null ? null : '${m['reason']}',
      vale: v is Map ? CheckinVale.fromJson(v.cast<String, dynamic>()) : null,
      estado: e is Map ? CheckinPremiosEstado.fromJson(e.cast<String, dynamic>()) : null,
    );
  }
}

/// Mensagem curta em PT-PT quando "Levantar" ou "Continuar" não deu.
String mensagemErroEscada(String? reason) {
  switch (reason) {
    case 'sem_sessao':
      return 'Entra na tua conta para escolher o prémio.'.tr;
    case 'sem_premio':
      return 'Já não tens nenhum prémio guardado.'.tr;
    case 'expirado':
      return 'Este prémio já expirou.'.tr;
    case 'ja_levantado':
      return 'Este prémio já foi levantado.'.tr;
    case 'ultimo_degrau':
      return 'Este já é o prémio maior: só dá para levantar.'.tr;
    default:
      return 'Não foi possível. Tenta de novo.'.tr;
  }
}

/// Estado dos marcos + os vales da pessoa.
class CheckinPremiosEstado {
  const CheckinPremiosEstado({
    required this.marcosAtivos,
    required this.cicloDias,
    required this.diasSeguidos,
    required this.diaMarco,
    required this.hojeFeito,
    required this.marcos,
    required this.texto,
    required this.vales,
    required this.novos,
    this.proximo,
    this.cicloInicio,
    this.escada,
  });

  final bool marcosAtivos;
  final int cicloDias;

  /// Dias seguidos da sequência a correr (0 = sem sequência).
  final int diasSeguidos;

  /// Dia dentro do ciclo dos marcos (1..ciclo), 0 sem sequência.
  final int diaMarco;
  final bool hojeFeito;
  final List<CheckinMarco> marcos;
  final CheckinMarco? proximo;
  final String texto;
  final List<CheckinVale> vales;

  /// Vales que ainda não tiveram festa no ecrã.
  final List<String> novos;

  /// Dia 1 da sequência atual (null sem sequência).
  final DateTime? cicloInicio;

  /// A escada de prémios; `null` = servidor antigo (sem escada).
  final CheckinEscada? escada;

  /// A escada está ligada para esta pessoa.
  bool get escadaAtiva => escada?.ativa == true;

  /// O dia de hoje na sequência: `dia_marco` se já fez o check-in de hoje,
  /// senão o seguinte (depois do último dia do ciclo vem o Dia 1).
  /// 0 = levantou hoje depois do check-in (amanhã é o Dia 1).
  int get diaDeHoje {
    if (hojeFeito) return diaMarco;
    final ciclo = cicloDias <= 0 ? 30 : cicloDias;
    return diaMarco >= ciclo ? 1 : diaMarco + 1;
  }

  /// Junta a resposta de "Levantar"/"Continuar" (sem texto, vales nem novos)
  /// a este estado: fica a sequência e a escada novas, o resto mantém-se.
  CheckinPremiosEstado juntar(CheckinPremiosEstado parcial) => CheckinPremiosEstado(
        marcosAtivos: parcial.marcosAtivos,
        cicloDias: parcial.cicloDias,
        diasSeguidos: parcial.diasSeguidos,
        diaMarco: parcial.diaMarco,
        hojeFeito: parcial.hojeFeito,
        marcos: parcial.marcos.isEmpty ? marcos : parcial.marcos,
        proximo: parcial.proximo ?? proximo,
        texto: texto,
        vales: vales,
        novos: novos,
        cicloInicio: parcial.cicloInicio,
        escada: parcial.escada ?? escada,
      );

  List<CheckinVale> get porUsar => vales.where((v) => v.ativo).toList();
  List<CheckinVale> get historico => vales.where((v) => !v.ativo).toList();

  /// Vale de produto que se pode aplicar nesta loja (o primeiro a acabar).
  CheckinVale? valeParaLoja(String? lojaId) {
    if (lojaId == null || lojaId.isEmpty) return null;
    final lista = vales
        .where((v) => v.ehProduto && v.usavel && v.lojaId == lojaId)
        .toList()
      ..sort((a, b) => (a.validoAte ?? DateTime(9999)).compareTo(b.validoAte ?? DateTime(9999)));
    return lista.isEmpty ? null : lista.first;
  }

  factory CheckinPremiosEstado.fromJson(Map<String, dynamic> m) {
    final marcos = (m['marcos'] is List)
        ? (m['marcos'] as List)
            .whereType<Map>()
            .map((e) => CheckinMarco.fromJson(e.cast<String, dynamic>()))
            .toList()
        : <CheckinMarco>[];
    final p = m['proximo'];
    return CheckinPremiosEstado(
      marcosAtivos: m['marcos_ativos'] == true,
      cicloDias: _int(m['ciclo_dias'], 30),
      diasSeguidos: _int(m['dias_seguidos']),
      diaMarco: _int(m['dia_marco']),
      hojeFeito: m['hoje_feito'] == true,
      marcos: marcos,
      proximo: p is Map
          ? CheckinMarco(
              chave: '${p['chave'] ?? ''}',
              dia: _int(p['dia']),
              tipo: marcos
                      .where((x) => x.chave == '${p['chave']}')
                      .map((x) => x.tipo)
                      .firstOrNull ??
                  '',
              titulo: '${p['titulo'] ?? ''}',
              descricao: '',
              atingido: false,
              faltam: _int(p['faltam']),
            )
          : null,
      texto: '${m['texto'] ?? ''}',
      vales: (m['vales'] is List)
          ? (m['vales'] as List)
              .whereType<Map>()
              .map((e) => CheckinVale.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      novos: (m['novos'] is List) ? (m['novos'] as List).map((e) => '$e').toList() : const [],
      cicloInicio: _data(m['ciclo_inicio']),
      escada: CheckinEscada.fromJson(m['escada']),
    );
  }
}

/// O artigo-prémio devolvido pela reserva, para entrar no carrinho.
class ReservaPremio {
  const ReservaPremio({
    required this.vale,
    required this.produtoId,
    required this.nome,
    required this.descricao,
    required this.fotoUrl,
    required this.lojaId,
    required this.lojaNome,
  });

  final CheckinVale vale;
  final String produtoId;
  final String nome;
  final String descricao;
  final String fotoUrl;
  final String lojaId;
  final String lojaNome;

  static ReservaPremio? fromJson(Map<String, dynamic> m) {
    if (m['ok'] != true) return null;
    final p = (m['produto'] as Map?)?.cast<String, dynamic>();
    final l = (m['loja'] as Map?)?.cast<String, dynamic>();
    final v = (m['vale'] as Map?)?.cast<String, dynamic>();
    if (p == null || v == null) return null;
    return ReservaPremio(
      vale: CheckinVale.fromJson(v),
      produtoId: '${p['id']}',
      nome: '${p['name'] ?? ''}',
      descricao: '${p['description'] ?? ''}',
      fotoUrl: '${p['photo_url'] ?? ''}',
      lojaId: '${p['restaurant_id'] ?? l?['id'] ?? ''}',
      lojaNome: '${l?['name'] ?? ''}',
    );
  }
}

/// Texto curto do estado de um vale.
String textoEstadoVale(CheckinVale v) {
  switch (v.estado) {
    case 'por_usar':
    case 'reservado':
      return 'Por usar'.tr;
    case 'guardado':
      return 'Guardado'.tr;
    case 'a_espera_pedido':
      return 'Falta 1 pedido para desbloquear o prémio'.tr;
    case 'usado':
      return 'Usado'.tr;
    case 'expirado':
      return 'Expirado'.tr;
    case 'anulado':
      return 'Anulado'.tr;
    default:
      return v.estado;
  }
}

class CheckinPremiosService {
  CheckinPremiosService._();
  static final CheckinPremiosService instance = CheckinPremiosService._();

  static const Duration _limite = Duration(seconds: 15);

  /// Último estado lido (o carrinho usa-o para mostrar "Tens um prémio").
  final ValueNotifier<CheckinPremiosEstado?> ultimo = ValueNotifier(null);

  SupabaseClient get _db => Supabase.instance.client;

  /// Estado dos marcos e vales, ou `null` (servidor sem a função, sem rede,
  /// sem sessão). Nunca rebenta: quem chama esconde a parte dos marcos.
  Future<CheckinPremiosEstado?> estado() async {
    try {
      final res = await _db.rpc('client_checkin_premios').timeout(_limite);
      if (res is! Map || res['ok'] != true) return null;
      final e = CheckinPremiosEstado.fromJson(res.cast<String, dynamic>());
      ultimo.value = e;
      return e;
    } catch (e) {
      debugPrint('[CheckinPremios] estado: $e');
      return null;
    }
  }

  /// Escada: "Levantar agora" — cria o vale do prémio guardado e a sequência
  /// volta ao dia 1. Nunca rebenta: sem rede devolve `ok: false`.
  Future<CheckinEscadaResultado> levantar() => _escada('client_checkin_escada_levantar');

  /// Escada: "Continuar" — fica com o prémio guardado e troca por um maior
  /// no degrau seguinte.
  Future<CheckinEscadaResultado> continuar() => _escada('client_checkin_escada_continuar');

  Future<CheckinEscadaResultado> _escada(String funcao) async {
    try {
      final res = await _db.rpc(funcao).timeout(_limite);
      if (res is! Map) return const CheckinEscadaResultado(ok: false);
      return CheckinEscadaResultado.fromJson(res.cast<String, dynamic>());
    } catch (e) {
      debugPrint('[CheckinPremios] $funcao: $e');
      return const CheckinEscadaResultado(ok: false, reason: 'sem_rede');
    }
  }

  Future<void> marcarVistos(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _db.rpc('client_checkin_premio_visto', params: {'p_ids': ids}).timeout(_limite);
    } catch (e) {
      debugPrint('[CheckinPremios] visto: $e');
    }
  }

  /// Guarda o vale para o carrinho. `null` se já não estiver disponível.
  Future<ReservaPremio?> reservar(String valeId) async {
    final res = await _db
        .rpc('client_checkin_premio_reservar', params: {'p_vale_id': valeId}).timeout(_limite);
    if (res is! Map) return null;
    return ReservaPremio.fromJson(res.cast<String, dynamic>());
  }

  Future<void> libertar(String valeId) async {
    try {
      await _db.rpc('client_checkin_premio_libertar', params: {'p_vale_id': valeId}).timeout(_limite);
    } catch (e) {
      debugPrint('[CheckinPremios] libertar: $e');
    }
  }

  /// Liberta todos os vales reservados deste artigo (o cliente tirou-o do carrinho).
  Future<void> libertarArtigo(String produtoId) async {
    final e = ultimo.value ?? await estado();
    if (e == null) return;
    for (final v in e.vales.where((v) => v.produtoId == produtoId && v.estado == 'reservado')) {
      await libertar(v.id);
    }
  }

  Future<Map<String, dynamic>> marcarLimpeza({
    required String valeId,
    required DateTime quando,
    required String rua,
    required String cidade,
    required String codigoPostal,
    double? lat,
    double? lng,
    String notas = '',
  }) async {
    final res = await _db.rpc('client_checkin_premio_marcar_limpeza', params: {
      'p_vale_id': valeId,
      'p_scheduled_at': quando.toUtc().toIso8601String(),
      'p_address_street': rua,
      'p_address_city': cidade,
      'p_address_postal': codigoPostal,
      'p_lat': lat,
      'p_lng': lng,
      'p_notes': notas,
    }).timeout(_limite);
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> marcarLavagem({
    required String valeId,
    required String matricula,
    required String telefone,
    required bool agora,
    DateTime? quando,
    required String rua,
    required String cidade,
    required String codigoPostal,
    double? lat,
    double? lng,
    String carro = '',
    String cor = '',
    String notas = '',
  }) async {
    final res = await _db.rpc('client_checkin_premio_marcar_lavagem', params: {
      'p_vale_id': valeId,
      'p_plate': matricula,
      'p_client_phone': telefone,
      'p_when_mode': agora ? 'now' : 'later',
      'p_scheduled_at': (quando ?? DateTime.now()).toUtc().toIso8601String(),
      'p_address_street': rua,
      'p_address_city': cidade,
      'p_address_postal': codigoPostal,
      'p_lat': lat,
      'p_lng': lng,
      'p_car_make_model': carro,
      'p_car_color': cor,
      'p_pickup_notes': notas,
    }).timeout(_limite);
    return (res as Map).cast<String, dynamic>();
  }
}

/// Mensagem em PT-PT para um erro do servidor ao usar um vale.
String mensagemErroPremio(Object e) {
  final s = '$e';
  if (s.contains('lead_time_too_short')) {
    return 'A limpeza marca-se com pelo menos 12 horas de antecedência.'.tr;
  }
  if (s.contains('out_of_service_area')) return 'Essa morada fica fora da zona da lavagem.'.tr;
  if (s.contains('plate_required')) return 'Escreve a matrícula do carro.'.tr;
  if (s.contains('phone_required')) return 'Escreve o teu telemóvel.'.tr;
  if (s.contains('checkin_premio_expirado')) return 'Este prémio já expirou.'.tr;
  if (s.contains('checkin_premio_estado') || s.contains('checkin_premio_sem_vale')) {
    return 'Este prémio já não está disponível.'.tr;
  }
  if (s.contains('cleaning_disabled') || s.contains('carwash_disabled')) {
    return 'Este serviço está em pausa de momento.'.tr;
  }
  return 'Não foi possível usar o prémio. Tenta de novo.'.tr;
}
