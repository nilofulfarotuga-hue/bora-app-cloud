// ÁREA DO ESTAFETA (15/11/2026, missão app-15-11 — ordem do Danilo): o admin
// escolhe um entregador e faz por ele o que ele faz no app, com tudo
// registrado no log de auditoria.
//
// Todas as chamadas ao servidor da área vivem aqui; o ecrã recebe um serviço
// falso nos testes. Só funções de admin que já existem no servidor
// (assinaturas lidas com pg_get_function_identity_arguments a 15/11/2026):
//   • presença ............. admin_driver_presence(p_driver text)
//   • posição .............. admin_live_drivers() — GPS dos últimos 5 min
//   • pedidos abertos ...... admin_live_orders(p_include_test_orders boolean)
//                            + admin_scheduled_orders() (hora dos agendados)
//   • dar / passar ......... admin_reassign_order(p_order_id, p_new_driver, p_motivo)
//   • outros entregadores .. admin_drivers_for_assignment(p_order_id, p_search)
//   • devolver à fila ...... admin_release_order_driver(p_order_id, p_motivo)
//   • entregue sem código .. admin_marcar_entregue_sem_codigo (via o botão que já existe)
//   • avisos ............... admin_driver_avisar_gps(p_driver text),
//                            admin_driver_avisar_sem_sinal(p_user_id uuid)
//   • ganhos ............... extrato_prestador(p_semanas int, p_user_id uuid)
//   • conta ................ driver_minha_conta_estado(p_user_id uuid)
//   • documentos ........... admin_documentos_verificacoes(p_user_id, p_limite),
//                            admin_robo_documentos_lembrar(p_user_id uuid)
//   • modo de trabalho ..... admin_set_driver_work_mode(p_driver_id uuid, p_mode)
//   • histórico ............ admin_audit_log (só leitura) + admin_driver_assignment_history
//
// As três que a Claude.ai aplicou a 15/11 às 15:06 (lidas com
// pg_get_functiondef; só para `authenticated`, com is_admin() lá dentro):
//   • ligar / desligar ..... admin_set_driver_online(p_driver text, p_online boolean,
//                            p_motivo text) — aceita drivers.id ou o id de login;
//                            ligar é recusado sem sinal do celular há 2 min
//   • Recolhi / A caminho .. admin_estafeta_avancar(p_order_id text, p_status text,
//                            p_motivo text) — só 'pickedUp' e 'onTheWay'
//   • fatura do mês ........ admin_fatura_mes_estafeta(p_user_id uuid, p_mes date) — só leitura
// As duas que mudam alguma coisa respondem {ok, error, mensagem, ...} e pedem
// motivo com 3 letras ou mais.
//
// Auditoria: dar, passar, devolver, avisos, lembrete, ligar/desligar e
// "Recolhi"/"A caminho" gravam no admin_audit_log dentro do servidor (com o
// motivo). Duas ações gravam também aqui, do lado
// da app (AdminAuditService, ação `area_estafeta_<acao>`, entidade = o
// entregador): o modo de trabalho (o servidor grava sem o motivo) e o
// "entregue sem código" (o servidor grava só pelo pedido, sem o entregador).
//
// Nunca escreve direto em tabelas. Textos em PT-BR (painel).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/gps_parado.dart';
import '../utils/hora_lisboa.dart';
import '../utils/periodo_entregas.dart';
import '../widgets/admin/admin_entregue_sem_codigo_button.dart';
import '../widgets/admin/escolher_estafeta_sheet.dart' show EstafetaParaAtribuir;
import 'admin_audit_service.dart';
import 'minha_conta.dart';
import 'robo_documentos.dart';

/// O que os botões que ainda não têm função no servidor dizem.
const String kFrasePrecisaFuncaoNova =
    'Precisa de uma função nova no servidor (proposta enviada)';

/// Motivo mínimo das ações que mudam alguma coisa (letras, sem espaços nas pontas).
const int kMotivoMinimo = 3;

/// Semanas pedidas ao extrato: 6 cobrem sempre "Este mês" e "Semana passada".
const int kSemanasExtrato = 6;

/// Quantos registros mostra "O que o admin já fez por ele".
const int kLimiteHistorico = 30;

/// Quantos trabalhos a secção de ganhos mostra de cada vez.
const int kMaxTrabalhosVisiveis = 100;

/// Sinal (heartbeat) com até 90 s conta como vivo — o mesmo limite do servidor.
const int kSinalFrescoSegundos = 90;

/// Estados em que admin_reassign_order entrega logo o pedido; nos outros
/// (novo, em preparo) só o reserva para quando a loja o marcar pronto.
const Set<String> kEstadosChamando = {
  'callingDriver',
  'driverAccepted',
  'pickedUp',
  'onTheWay',
};

/// Estados em que admin_release_order_driver devolve o pedido à fila.
const Set<String> kEstadosDevolverAFila = {'callingDriver', 'driverAccepted'};

/// Ele já tem a encomenda com ele.
const Set<String> kEstadosComEncomenda = {'pickedUp', 'onTheWay'};

/// Os dois modos de admin_set_driver_work_mode.
const List<String> kModosTrabalho = ['everything', 'rides_only'];

// ── Leitura tolerante das respostas ──────────────────────────────────────────

String _texto(Object? v) => v == null ? '' : v.toString().trim();

String? _textoOuNull(Object? v) {
  final t = _texto(v);
  return t.isEmpty ? null : t;
}

int? _inteiro(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.round();
  }
  return null;
}

double? _decimal(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

DateTime? _data(Object? v) {
  if (v is DateTime) return v;
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

Map<String, dynamic> _mapaDe(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// As linhas de uma função que devolve `table(...)` ou um array jsonb.
List<Map<String, dynamic>> _linhas(Object? res) {
  if (res is! List) return <Map<String, dynamic>>[];
  return res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// A resposta jsonb de uma ação ({ok, error, motivo, ...}).
Map<String, dynamic> _resposta(Object? res) => res is Map
    ? Map<String, dynamic>.from(res)
    : <String, dynamic>{'ok': false, 'error': 'resposta_vazia'};

final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

bool _eUuid(String s) => _uuid.hasMatch(s.trim());

// ── Textos e regras puras ────────────────────────────────────────────────────

/// Erro já em palavras simples (PT-BR), para mostrar tal e qual.
class AreaEstafetaErro implements Exception {
  const AreaEstafetaErro(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// "a1b2c3d4-…" → "A1B2C3" (o mesmo código curto que o servidor usa nos avisos).
String codigoPedido(String id) {
  final limpo = id.replaceAll('-', '');
  return (limpo.length > 6 ? limpo.substring(0, 6) : limpo).toUpperCase();
}

/// O status do pedido em PT-BR.
String estadoPedidoPtBr(String status) => switch (status) {
      'created' => 'Novo, esperando a loja aceitar',
      'preparing' => 'Em preparo na loja',
      'callingDriver' => 'Chamando entregador',
      'driverAccepted' => 'Aceito, indo para a loja',
      'pickedUp' => 'Retirado na loja (está com ele)',
      'onTheWay' => 'A caminho do cliente',
      'delivered' => 'Entregue',
      'cancelled' => 'Cancelado',
      'rejected' => 'Recusado',
      _ => status,
    };

/// O motivo escrito chega? (mínimo [kMotivoMinimo] letras, sem contar espaços nas pontas)
bool motivoSuficiente(String? motivo) =>
    (motivo ?? '').trim().length >= kMotivoMinimo;

/// A resposta `{ok:false, error|motivo}` de uma ação, em palavras simples.
String mensagemDoServidor(Map<String, dynamic> r) {
  final erro = _textoOuNull(r['error']);
  switch (erro) {
    case 'pedido_nao_encontrado':
      return 'pedido não encontrado.';
    case 'pedido_ja_terminal':
      final st = _textoOuNull(r['status']);
      return st == null
          ? 'o pedido já terminou.'
          : 'o pedido já terminou (${estadoPedidoPtBr(st)}).';
    case 'takeaway_sem_estafeta':
      return 'é um pedido para retirar na loja, não leva entregador.';
    case 'estafeta_nao_encontrado':
      return 'entregador não encontrado.';
    case 'estafeta_nao_aprovado':
      return 'o entregador ainda não está aprovado.';
    case 'estafeta_ja_tem_a_encomenda':
      return 'ele já tem a encomenda com ele: passe o pedido para outro '
          'entregador ou feche a entrega.';
    case 'resposta_vazia':
      return 'o servidor não respondeu.';
  }
  final motivo = _textoOuNull(r['motivo']);
  switch (motivo) {
    case 'nada_a_pedir':
      return 'não falta nenhum documento para pedir.';
    case 'demo':
      return 'é uma conta de demonstração: não se manda lembrete.';
  }
  return motivo ?? erro ?? 'o servidor não confirmou.';
}

/// Nome técnico entre parênteses, "(nome_de_funcao)": sai dos textos do
/// servidor antes de aparecerem no painel.
final RegExp _nomeTecnico = RegExp(r'\s*\((?:[a-z0-9]+_)+[a-z0-9]+\)');

String _semNomesTecnicos(String s) => s.replaceAll(_nomeTecnico, '').trim();

/// Primeira letra maiúscula (as frases de [mensagemDoServidor] começam em minúscula).
String _frase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// O pormenor que o gatilho do servidor juntou a "O servidor recusou: …".
String _detalheDaRecusa(Map<String, dynamic> r) {
  const prefixo = 'O servidor recusou:';
  final m = _texto(r['mensagem']);
  if (!m.startsWith(prefixo)) return '';
  return m.substring(prefixo.length).trim().replaceAll(RegExp(r'[.\s]+$'), '');
}

/// A recusa de admin_set_driver_online ou de admin_estafeta_avancar
/// (`{ok:false, error, mensagem, ...}`) numa frase para o admin. Os códigos que
/// vêm com nomes técnicos ou escritos para o entregador têm frase própria; os
/// outros usam a `mensagem` do servidor (já em português), sem nomes técnicos.
String mensagemDaRecusa(Map<String, dynamic> r) {
  switch (_textoOuNull(r['error'])) {
    case 'SEM_SINAL':
      final ultimo = _data(r['ultimo_sinal']);
      final quando = ultimo == null
          ? 'Ele nunca mandou sinal.'
          : 'Último sinal: ${dataHoraLisboaDe(ultimo)} (hora de Lisboa).';
      return 'O celular dele não está mandando sinal agora: peça para ele abrir '
          'o app. $quando';
    case 'CONTA_APAGADA':
      return 'A conta dele foi apagada: reative a conta primeiro.';
    case 'CONTA_BLOQUEADA':
      return 'A conta dele está suspensa ou banida: reative a conta primeiro.';
    case 'CONTA_RECUSADA':
      return 'O cadastro dele foi recusado.';
    case 'CONTA_NAO_APROVADA':
      final faltas = r['faltas'];
      final lista = faltas is List
          ? faltas.map(_texto).where((s) => s.isNotEmpty).join(', ')
          : '';
      return lista.isEmpty
          ? 'O cadastro dele ainda não foi aprovado.'
          : 'O cadastro dele ainda não foi aprovado. Falta: $lista.';
    case 'DOCUMENTO_EXPIRADO':
      final documento = _detalheDaRecusa(r);
      return 'Ele tem um documento vencido'
          '${documento.isEmpty ? '' : ' ($documento)'}: ele precisa atualizar '
          'a validade no app antes de ficar ligado.';
    case 'TVDE_BLOQUEADO':
      final porque = _detalheDaRecusa(r);
      return 'As corridas TVDE dele estão bloqueadas'
          '${porque.isEmpty ? '' : ' ($porque)'}: faltam documentos na área '
          'Conformidade.';
    case 'LIMITE_HORAS':
      return 'Ele chegou ao limite legal de horas de serviço das últimas 24 horas.';
    case 'sem_estafeta':
      return 'Este pedido não tem entregador.';
    case 'target_not_allowed':
      return 'Só dá para marcar "Recolhi" ou "A caminho".';
    case 'invalid_status':
      final agora = _textoOuNull(r['status']);
      return agora == null
          ? 'O pedido mudou de estado. Atualize a lista e veja de novo.'
          : 'O pedido agora está em "${estadoPedidoPtBr(agora)}". Atualize a '
              'lista e veja de novo.';
  }
  final mensagem = _textoOuNull(r['mensagem']);
  if (mensagem != null) return _semNomesTecnicos(mensagem);
  return _frase(mensagemDoServidor(r));
}

/// Link do Google Maps para uma posição.
Uri linkGoogleMaps(double lat, double lng) =>
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

/// Faz corridas de passageiros (TVDE)? Só para esses o modo de trabalho conta.
bool eVeiculoDePassageiros(String? veiculo) =>
    veiculo == 'carro_passageiros' || veiculo == 'carPassengers';

/// 'rides_only' → "Só corridas de passageiros"; o resto → "Tudo (corridas + entregas)".
String rotuloModoTrabalho(Object? modo) => modo == 'rides_only'
    ? 'Só corridas de passageiros'
    : 'Tudo (corridas + entregas)';

/// "22/09 19:05" (hora de Lisboa) ou "—".
String dataHoraLisboaDe(DateTime? d) =>
    d == null ? '—' : dataHoraLisboa(d.toUtc().toIso8601String());

// ── Agora: presença e posição ────────────────────────────────────────────────

/// Uma linha de admin_driver_presence.
class PresencaEstafeta {
  const PresencaEstafeta({
    required this.ligado,
    required this.ligadoAgora,
    this.ultimoSinal,
    this.temNotificacoes = false,
    this.aparelhos = 0,
    this.plataforma,
    this.pedidosEmCurso = 0,
    this.gpsIdadeS,
    this.gpsFresco = true,
  });

  factory PresencaEstafeta.fromRow(Map<String, dynamic> r) => PresencaEstafeta(
        ligado: r['is_online'] == true,
        ligadoAgora: r['online_agora'] == true,
        ultimoSinal: _data(r['last_heartbeat_at']),
        temNotificacoes: r['tem_notificacoes'] == true,
        aparelhos: _inteiro(r['tokens_ativos']) ?? 0,
        plataforma: _textoOuNull(r['last_platform']),
        pedidosEmCurso: _inteiro(r['pedidos_em_curso']) ?? 0,
        gpsIdadeS: _inteiro(r['gps_age_s']),
        // Sem a coluna (função antiga) não se inventa alarme.
        gpsFresco: r['gps_fresco'] != false,
      );

  /// O botão "ligado" do app (`is_online`).
  final bool ligado;

  /// Ligado de verdade: sinal vivo (90 s) E GPS fresco — decidido no servidor.
  final bool ligadoAgora;
  final DateTime? ultimoSinal;
  final bool temNotificacoes;
  final int aparelhos;
  final String? plataforma;
  final int pedidosEmCurso;

  /// Segundos desde a última posição (null = nunca mandou posição).
  final int? gpsIdadeS;
  final bool gpsFresco;
}

enum NivelPresenca { ligado, semSinal, desligado }

NivelPresenca nivelPresenca(PresencaEstafeta? p) {
  if (p == null || !p.ligado) return NivelPresenca.desligado;
  return p.ligadoAgora ? NivelPresenca.ligado : NivelPresenca.semSinal;
}

/// A presença numa frase: "Ligado, GPS há 12 s", "Ligado mas sem sinal há
/// 7 min", "Ligado mas GPS parado há 19 min", "Desligado".
String textoPresenca(PresencaEstafeta? p, DateTime agora) {
  if (p == null) return 'Sem dados de presença';
  if (!p.ligado) return 'Desligado';
  if (p.ligadoAgora) {
    final idade = p.gpsIdadeS;
    return idade == null ? 'Ligado, sem GPS' : 'Ligado, GPS ${gpsIdadeTexto(idade)}';
  }
  final sinal = p.ultimoSinal;
  if (sinal == null) return 'Ligado mas nunca mandou sinal';
  final idadeSinal = agora.toUtc().difference(sinal.toUtc()).inSeconds;
  if (idadeSinal <= kSinalFrescoSegundos && !p.gpsFresco) {
    final idade = p.gpsIdadeS;
    return idade == null
        ? 'Ligado mas sem GPS'
        : 'Ligado mas GPS ${gpsParadoHaTexto(idade)}';
  }
  return 'Ligado mas sem sinal ${gpsIdadeTexto(idadeSinal)}';
}

/// "15/11 14:05 (há 12 s)" ou "nunca".
String textoUltimoSinal(DateTime? sinal, DateTime agora) {
  if (sinal == null) return 'nunca';
  final s = agora.toUtc().difference(sinal.toUtc()).inSeconds;
  return '${dataHoraLisboaDe(sinal)} (${gpsIdadeTexto(s)})';
}

/// "Ligar por ele" serve quando o botão dele está desligado (sem dados, o
/// servidor decide).
bool podeLigarPorEle(PresencaEstafeta? p) => p == null || !p.ligado;

/// "Desligar por ele" serve quando o botão dele está ligado (sem dados, o
/// servidor decide).
bool podeDesligarPorEle(PresencaEstafeta? p) => p == null || p.ligado;

/// O aviso da janela "Desligar por ele" (null quando não há pedidos com ele).
String? avisoAntesDeDesligar(PresencaEstafeta? p) {
  final n = p?.pedidosEmCurso ?? 0;
  if (n <= 0) return null;
  return 'Ele tem $n pedido(s) em andamento: continuam com ele. Para tirar um '
      'pedido dele, use "Passar para outro entregador" em "Pedidos dele agora".';
}

/// A resposta de admin_set_driver_online que deu certo, numa frase. Ao ligar,
/// junta os avisos do servidor (sem notificações, app sem bater), sem nomes
/// técnicos; ao desligar, diz se ficaram pedidos com ele.
String textoLigouDesligou(
  Map<String, dynamic> r, {
  required String nome,
  required bool ligar,
}) {
  if (!ligar) {
    final emCurso = _inteiro(r['pedidos_em_curso']) ?? 0;
    return [
      r['antes'] == false
          ? '$nome já estava desligado.'
          : '$nome foi desligado: não recebe pedidos novos.',
      if (emCurso > 0) 'Ele tem $emCurso pedido(s) em andamento: continuam com ele.',
    ].join(' ');
  }
  if (r['nada_mudou'] == true) return '$nome já estava ligado.';
  final avisos = r['avisos'];
  return [
    '$nome está ligado: os pedidos em espera são oferecidos a ele em até 15 segundos.',
    if (avisos is List)
      for (final a in avisos)
        if (_textoOuNull(a) != null) _semNomesTecnicos(_texto(a)),
  ].join(' ');
}

/// A última posição conhecida (só aparece com GPS nos últimos 5 min).
class PosicaoEstafeta {
  const PosicaoEstafeta({required this.lat, required this.lng, this.quando});

  final double lat;
  final double lng;
  final DateTime? quando;

  Uri get linkMaps => linkGoogleMaps(lat, lng);
}

/// A posição dele nas linhas de admin_live_drivers (`driver_id` pode ser o id
/// de login ou o drivers.id). null quando não está lá.
PosicaoEstafeta? posicaoDoEntregador(
  List<Map<String, dynamic>> linhas, {
  required String userId,
  required String driverId,
}) {
  for (final r in linhas) {
    final id = _texto(r['driver_id']);
    if (id.isEmpty || (id != userId && id != driverId)) continue;
    final lat = _decimal(r['latitude']);
    final lng = _decimal(r['longitude']);
    if (lat == null || lng == null) continue;
    return PosicaoEstafeta(lat: lat, lng: lng, quando: _data(r['last_updated']));
  }
  return null;
}

// ── Pedidos ──────────────────────────────────────────────────────────────────

/// Um pedido aberto (linha de admin_live_orders). O valor pago pelo cliente
/// fica de fora de propósito: no painel do entregador manda o ganho dele.
class PedidoAberto {
  const PedidoAberto({
    required this.id,
    required this.status,
    this.tipoServico,
    this.loja,
    this.recolha,
    this.entrega,
    this.entregadorId,
    this.criadoEm,
    this.agendadoPara,
  });

  factory PedidoAberto.fromRow(Map<String, dynamic> r, {DateTime? agendadoPara}) =>
      PedidoAberto(
        id: _texto(r['id']),
        status: _texto(r['status']),
        tipoServico: _textoOuNull(r['service_type']),
        loja: _textoOuNull(r['vendor_name']),
        recolha: _textoOuNull(r['pickup_address']),
        entrega: _textoOuNull(r['dropoff_address']),
        entregadorId: _textoOuNull(r['assigned_driver_id']),
        criadoEm: _data(r['created_at']),
        agendadoPara: agendadoPara,
      );

  final String id;
  final String status;
  final String? tipoServico;
  final String? loja;
  final String? recolha;
  final String? entrega;

  /// `orders.assigned_driver_id` (texto: id de login ou drivers.id antigo).
  final String? entregadorId;
  final DateTime? criadoEm;

  /// `scheduled_for` quando o pedido é agendado (admin_scheduled_orders).
  final DateTime? agendadoPara;

  String get codigo => codigoPedido(id);
  bool get semEntregador => entregadorId == null;

  /// Retirar na loja não leva entregador (o servidor recusa).
  bool get levaEntregador => tipoServico != 'takeaway';
  bool get jaChamaEntregador => kEstadosChamando.contains(status);
  bool get podeDevolverAFila => kEstadosDevolverAFila.contains(status);

  bool eDele(String userId, String driverId) {
    final id = entregadorId;
    return id != null && (id == userId || id == driverId);
  }
}

/// Os pedidos que estão com ele.
List<PedidoAberto> pedidosDele(
  List<PedidoAberto> todos, {
  required String userId,
  required String driverId,
}) =>
    todos.where((p) => p.eDele(userId, driverId)).toList();

/// Pedidos sem entregador que levam entregador: primeiro os que já estão a
/// chamar, depois em preparo, depois novos; dentro de cada um, o mais antigo
/// primeiro.
List<PedidoAberto> pedidosEsperandoEntregador(List<PedidoAberto> todos) {
  int prioridade(String s) => switch (s) {
        'callingDriver' => 0,
        'preparing' => 1,
        'created' => 2,
        _ => 3,
      };
  final lista = todos.where((p) => p.semEntregador && p.levaEntregador).toList();
  lista.sort((a, b) {
    final c = prioridade(a.status).compareTo(prioridade(b.status));
    if (c != 0) return c;
    final ta = a.criadoEm;
    final tb = b.criadoEm;
    if (ta == null || tb == null) return 0;
    return ta.compareTo(tb);
  });
  return lista;
}

/// Porque não dá para devolver à fila (null quando dá).
String? motivoSemDevolverAFila(PedidoAberto p) {
  if (p.podeDevolverAFila) return null;
  if (kEstadosComEncomenda.contains(p.status)) {
    return 'Ele já está com a encomenda: não dá para devolver à fila.';
  }
  return 'Neste estado não dá para devolver à fila.';
}

/// `id → scheduled_for` a partir de admin_scheduled_orders.
Map<String, DateTime> horasAgendadasDaResposta(Object? res) {
  final m = <String, DateTime>{};
  for (final r in _linhas(res)) {
    final id = _textoOuNull(r['id']);
    final quando = _data(r['scheduled_for']);
    if (id != null && quando != null) m[id] = quando;
  }
  return m;
}

/// Os avisos da janela "Dar este pedido a ele" (null quando não há nenhum).
String? avisoAntesDeDar(
  PedidoAberto p, {
  PresencaEstafeta? presenca,
  required DateTime agora,
}) {
  final partes = <String>[];
  final agendado = p.agendadoPara;
  if (agendado != null) {
    partes.add('Pedido agendado para ${dataHoraLisboaDe(agendado)} (hora de '
        'Lisboa): só dê a ele perto da hora.');
  }
  if (!p.jaChamaEntregador) {
    partes.add('Ainda não está pronto: fica reservado para ele e ele recebe a '
        'oferta quando a loja marcar pronto.');
  }
  if (presenca != null && !presenca.ligadoAgora) {
    partes.add('Atenção: ${textoPresenca(presenca, agora)}. Ele pode não ver o '
        'aviso agora.');
  }
  return partes.isEmpty ? null : partes.join('\n');
}

/// Os dois passos que admin_estafeta_avancar aceita, com o nome do botão do app.
enum ProximoPasso {
  recolhi('pickedUp', 'Recolhi'),
  aCaminho('onTheWay', 'A caminho');

  const ProximoPasso(this.status, this.rotulo);

  /// O `p_status` que vai ao servidor.
  final String status;
  final String rotulo;
}

/// O único passo válido a partir do status do pedido (o mesmo do app dele):
/// aceito → "Recolhi"; retirado → "A caminho". Nos outros estados, nenhum.
ProximoPasso? proximoPasso(String status) => switch (status) {
      'driverAccepted' => ProximoPasso.recolhi,
      'pickedUp' => ProximoPasso.aCaminho,
      _ => null,
    };

/// O aviso da janela de "Recolhi" (texto pedido a 15/11 para esta janela).
const String kAvisoRecolhiDinheiro = 'Em pedido a dinheiro com pagamento na '
    'loja, marcar Recolhi registra a compra como paga.';

/// A resposta de admin_estafeta_avancar que deu certo, numa frase.
String textoAvancou(
  Map<String, dynamic> r, {
  required String codigo,
  required ProximoPasso passo,
}) {
  final estado = estadoPedidoPtBr(_textoOuNull(r['status']) ?? passo.status);
  return r['idempotent'] == true
      ? 'O pedido $codigo já estava em "$estado": nada mudou.'
      : 'Pedido $codigo marcado como "$estado".';
}

// ── Ganhos ───────────────────────────────────────────────────────────────────

/// Um trabalho do extrato (`extrato_prestador.trabalhos[]`).
class TrabalhoGanho {
  const TrabalhoGanho({
    required this.tipo,
    this.quando,
    this.quandoTxt = '',
    this.descricao = '',
    this.pagamento,
    this.ganhouCents,
    this.clientePagouCents,
  });

  factory TrabalhoGanho.fromJson(Map<String, dynamic> j) => TrabalhoGanho(
        tipo: _texto(j['tipo']),
        quando: _data(j['quando']),
        quandoTxt: _texto(j['quando_txt']),
        descricao: _texto(j['descricao']),
        pagamento: _textoOuNull(j['pagamento']),
        ganhouCents: _inteiro(j['ganhou_cents']),
        clientePagouCents: _inteiro(j['cliente_pagou_cents']),
      );

  /// 'entrega' | 'corrida' | 'compensacao'.
  final String tipo;
  final DateTime? quando;

  /// "15/11 14:05", já em hora de Lisboa (vem do servidor).
  final String quandoTxt;
  final String descricao;

  /// 'cash' | 'mbway' | 'card' | …
  final String? pagamento;

  /// O que ele ganhou (null = o servidor não sabe; nunca se finge zero).
  final int? ganhouCents;

  /// O que o cliente pagou: só se mostra, em pequeno, quando foi em dinheiro.
  final int? clientePagouCents;

  bool get emDinheiro => pagamento == 'cash';
}

/// O extrato que interessa à área: a lista de trabalhos.
class ExtratoGanhos {
  const ExtratoGanhos({required this.trabalhos});

  factory ExtratoGanhos.fromJson(Object? res) {
    if (res is! Map) {
      throw const AreaEstafetaErro('O servidor não devolveu o extrato.');
    }
    if (res['ok'] != true) {
      final erro = _textoOuNull(res['error']);
      final motivo = switch (erro) {
        'forbidden' => 'sem permissão de admin',
        'auth_required' => 'a sessão expirou, entre de novo',
        _ => erro ?? 'erro desconhecido',
      };
      throw AreaEstafetaErro('Não consegui ler os ganhos: $motivo.');
    }
    final lista = res['trabalhos'];
    return ExtratoGanhos(trabalhos: [
      if (lista is List)
        for (final e in lista)
          if (e is Map) TrabalhoGanho.fromJson(Map<String, dynamic>.from(e)),
    ]);
  }

  /// Mais recentes primeiro (a ordem do servidor).
  final List<TrabalhoGanho> trabalhos;
}

/// Os trabalhos do período, pelos dias de Lisboa (a mesma conta do app).
List<TrabalhoGanho> trabalhosDoPeriodo(
  List<TrabalhoGanho> todos,
  PeriodoEntregas periodo,
  DateTime agora,
) =>
    todos.where((t) {
      final q = t.quando;
      return q != null && entregaNoPeriodo(q, periodo, agora);
    }).toList();

/// Soma do que ele ganhou (os sem valor conhecido não entram).
int totalGanhoCents(Iterable<TrabalhoGanho> lista) =>
    lista.fold<int>(0, (soma, t) => soma + (t.ganhouCents ?? 0));

/// Quantos não têm valor conhecido (para dizer que ficaram fora do total).
int trabalhosSemValor(Iterable<TrabalhoGanho> lista) =>
    lista.where((t) => t.ganhouCents == null).length;

String tipoTrabalhoPtBr(String tipo) => switch (tipo) {
      'entrega' => 'Entrega',
      'corrida' => 'Corrida',
      'compensacao' => 'Compensação',
      _ => tipo,
    };

String pagamentoPtBr(String? pagamento) => switch (pagamento) {
      'cash' => 'dinheiro',
      'mbway' => 'MB Way',
      'card' => 'cartão',
      _ => pagamento ?? '',
    };

// ── Conta, documentos e modo de trabalho ─────────────────────────────────────

/// driver_minha_conta_estado: o semáforo da conta (o mesmo que ele vê no app).
class ContaDoEstafeta {
  const ContaDoEstafeta({required this.estado, this.aprovacao});

  factory ContaDoEstafeta.fromJson(Object? res) => ContaDoEstafeta(
        estado: EstadoMinhaConta.fromJson(res),
        aprovacao: res is Map ? _textoOuNull(res['approval_status']) : null,
      );

  final EstadoMinhaConta estado;
  final String? aprovacao;
}

String aprovacaoPtBr(String? s) => switch (s) {
      'approved' => 'Aprovado',
      'pending' => 'Em análise',
      'rejected' => 'Recusado',
      'suspended' => 'Suspenso',
      'banned' => 'Banido',
      _ => s ?? 'Sem informação',
    };

/// O modo de trabalho (`drivers.work_mode`) e o veículo.
class ModoTrabalho {
  const ModoTrabalho({this.modo, this.veiculo});

  final String? modo;
  final String? veiculo;

  /// Sem valor, o servidor trata como 'everything'.
  String get modoEfetivo => modo ?? 'everything';
  bool get fazCorridasDePassageiros => eVeiculoDePassageiros(veiculo);
}

// ── Fatura do mês ────────────────────────────────────────────────────────────

/// Os dois meses que "Fatura do mês" deixa escolher.
enum MesFatura {
  esteMes('Este mês'),
  mesPassado('Mês passado');

  const MesFatura(this.rotulo);
  final String rotulo;
}

/// O 1.º dia do mês escolhido, pelo calendário de Lisboa (data UTC à
/// meia-noite; em janeiro, o mês passado é dezembro do ano anterior).
DateTime primeiroDiaDoMes(MesFatura qual, DateTime agora) {
  final hoje = diaLisboa(agora);
  final recuo = qual == MesFatura.mesPassado ? 1 : 0;
  return DateTime.utc(hoje.year, hoje.month - recuo, 1);
}

/// "2026-11-01": o `p_mes` (date) de admin_fatura_mes_estafeta.
String mesParaServidor(DateTime primeiroDia) {
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${primeiroDia.year.toString().padLeft(4, '0')}-${dois(primeiroDia.month)}-01';
}

/// admin_fatura_mes_estafeta: o recibo verde dele num mês, só leitura (a mesma
/// conta que ele vê no app, a linha dele em driver_monthly_invoice_summary).
/// O servidor manda euros; aqui guarda-se em cêntimos.
class FaturaDoMes {
  const FaturaDoMes({
    required this.ano,
    required this.mes,
    this.nomeMes = '',
    this.temEntregas = false,
    this.entregas = 0,
    this.totalCents,
    this.nif,
    this.atividadeAberta = false,
    this.cliente,
    this.clienteNif,
    this.textoRecibo,
    this.notas = const <String>[],
    this.reciboPassado = false,
    this.reciboNumero,
    this.reciboData,
    this.marcadoEm,
  });

  factory FaturaDoMes.fromJson(Object? res) {
    if (res is! Map) {
      throw const AreaEstafetaErro('O servidor não devolveu a fatura do mês.');
    }
    final m = Map<String, dynamic>.from(res);
    final e = _mapaDe(m['estafeta']);
    final adquirente = _mapaDe(m['adquirente']);
    final total = _decimal(e['total_a_faturar']);
    return FaturaDoMes(
      ano: _inteiro(m['ano']) ?? 0,
      mes: _inteiro(m['mes']) ?? 0,
      nomeMes: _texto(m['nome_mes']),
      temEntregas: m['tem_entregas'] == true && e.isNotEmpty,
      entregas: _inteiro(e['entregas']) ?? 0,
      totalCents: total == null ? null : (total * 100).round(),
      nif: _textoOuNull(e['nif']),
      atividadeAberta: e['atividade_aberta'] == true,
      cliente: _textoOuNull(e['cliente']) ?? _textoOuNull(adquirente['nome']),
      clienteNif: _textoOuNull(e['cliente_nif']) ?? _textoOuNull(adquirente['nif']),
      textoRecibo: _textoOuNull(e['texto_recibo']),
      notas: [
        for (final chave in const ['iva', 'retencao', 'prazo'])
          if (_textoOuNull(e[chave]) != null) _texto(e[chave]),
      ],
      reciboPassado: e['recibo_passado'] == true,
      reciboNumero: _textoOuNull(e['recibo_numero']),
      reciboData: _data(e['recibo_data']),
      marcadoEm: _data(e['marcado_em']),
    );
  }

  final int ano;
  final int mes;

  /// "novembro" (vem do servidor).
  final String nomeMes;

  /// Teve entregas no mês: só então há recibo.
  final bool temEntregas;
  final int entregas;

  /// O total do recibo = o que ele ganhou nas entregas do mês (null = sem valor).
  final int? totalCents;

  /// O NIF dele e se tem atividade aberta nas Finanças.
  final String? nif;
  final bool atividadeAberta;

  /// A quem ele passa o recibo (a Bora) e o NIF.
  final String? cliente;
  final String? clienteNif;
  final String? textoRecibo;

  /// IVA, retenção e prazo, como o servidor os escreve.
  final List<String> notas;

  /// Ele já marcou no app que passou o recibo.
  final bool reciboPassado;
  final String? reciboNumero;

  /// Data do recibo (dia, sem hora).
  final DateTime? reciboData;
  final DateTime? marcadoEm;

  /// "novembro de 2026".
  String get mesTexto => nomeMes.isEmpty
      ? '${mes.toString().padLeft(2, '0')}/$ano'
      : '$nomeMes de $ano';

  /// "Bora … Lda (NIF 500000000)".
  String get paraQuem {
    final nifCliente = clienteNif;
    final nome = cliente ?? '—';
    return nifCliente == null ? nome : '$nome (NIF $nifCliente)';
  }
}

/// "Sim, n.º 7, de 05/12/2026 (marcado em 05/12 10:00)" ou "Ainda não".
String textoReciboPassado(FaturaDoMes f) {
  if (!f.reciboPassado) return 'Ainda não';
  String dois(int n) => n.toString().padLeft(2, '0');
  final dia = f.reciboData;
  final partes = <String>[
    'Sim',
    if (f.reciboNumero != null) 'n.º ${f.reciboNumero}',
    if (dia != null) 'de ${dois(dia.day)}/${dois(dia.month)}/${dia.year}',
  ];
  final marcado = f.marcadoEm;
  return marcado == null
      ? partes.join(', ')
      : '${partes.join(', ')} (marcado em ${dataHoraLisboaDe(marcado)})';
}

// ── O que o admin já fez por ele ─────────────────────────────────────────────

/// Um registro do log de auditoria (ou do histórico de atribuições).
class RegistoAdmin {
  const RegistoAdmin({
    this.quando,
    required this.acao,
    this.quem = 'sistema',
    this.detalhes = const <String, dynamic>{},
    this.pedidoId,
  });

  /// Linha de `admin_audit_log`.
  factory RegistoAdmin.doRegisto(Map<String, dynamic> r) {
    final det = _mapaDe(r['details']);
    final doPedido = _texto(r['entity_type']) == 'order';
    return RegistoAdmin(
      quando: _data(r['created_at']),
      acao: _texto(r['action']),
      quem: _textoOuNull(r['admin_email']) ?? 'sistema',
      detalhes: det,
      pedidoId: doPedido
          ? _textoOuNull(r['entity_id_text'])
          : _textoOuNull(det['pedido']),
    );
  }

  /// Linha de admin_driver_assignment_history.
  factory RegistoAdmin.doHistorico(Map<String, dynamic> r) => RegistoAdmin(
        quando: _data(r['created_at']),
        acao: _texto(r['action']),
        quem: _textoOuNull(r['quem']) ?? 'sistema',
        detalhes: _mapaDe(r['details']),
        pedidoId: _textoOuNull(r['order_id']),
      );

  final DateTime? quando;
  final String acao;
  final String quem;
  final Map<String, dynamic> detalhes;
  final String? pedidoId;

  String? get motivo => _textoOuNull(detalhes['motivo']);

  /// O servidor grava algumas ações duas vezes na mesma transação: mesma
  /// ação, mesmo pedido, mesmo segundo = o mesmo registro.
  String get chave {
    final q = quando?.toUtc().toIso8601String() ?? '';
    final segundo = q.length >= 19 ? q.substring(0, 19) : q;
    return '$segundo|$acao|${pedidoId ?? ''}';
  }
}

/// Junta as duas fontes, sem repetidos, mais recentes primeiro.
List<RegistoAdmin> juntarHistorico(
  Iterable<RegistoAdmin> a,
  Iterable<RegistoAdmin> b, {
  int limite = kLimiteHistorico,
}) {
  final vistos = <String>{};
  final todos = <RegistoAdmin>[];
  for (final r in [...a, ...b]) {
    if (vistos.add(r.chave)) todos.add(r);
  }
  todos.sort((x, y) {
    final qx = x.quando;
    final qy = y.quando;
    if (qx == null && qy == null) return 0;
    if (qx == null) return 1;
    if (qy == null) return -1;
    return qy.compareTo(qx);
  });
  return todos.take(limite).toList();
}

/// O nome da ação em PT-BR. [idsDele] = id de login e drivers.id.
String rotuloRegistoAdmin(RegistoAdmin r, {required Set<String> idsDele}) {
  final para = _textoOuNull(r.detalhes['para']);
  final de = _textoOuNull(r.detalhes['de']);
  final paraEle = para != null && idsDele.contains(para);
  final deEle = de != null && idsDele.contains(de);
  switch (r.acao) {
    case 'order_reassigned':
      if (paraEle) return 'Pedido dado a ele (painel)';
      if (deEle) return 'Pedido passado para outro entregador (painel)';
      return 'Pedido reatribuído (painel)';
    case 'order_reassigned_by_agent':
      return paraEle
          ? 'Pedido dado a ele (agente)'
          : 'Pedido passado para outro entregador (agente)';
    case 'order_preassigned':
      return paraEle
          ? 'Pedido reservado para ele (painel)'
          : 'Reserva passada para outro entregador (painel)';
    case 'order_driver_released':
      return 'Pedido devolvido à fila (painel)';
    case 'order_driver_released_by_agent':
      return 'Pedido devolvido à fila (agente)';
    case 'preassign_released':
      return 'Reserva liberada pelo sistema';
    case 'driver_avisado_gps':
      return 'Aviso de GPS enviado para o celular';
    case 'driver_aviso_sem_sinal':
      return 'Aviso "sem sinal" enviado para o celular';
    case 'robo_documentos_lembrar':
      return 'Lembrete de documentos enviado';
    case 'tvde_set_work_mode':
      return 'Modo de trabalho: ${rotuloModoTrabalho(r.detalhes['mode'])}';
    case 'area_estafeta_modo_trabalho':
      return 'Área do entregador: modo de trabalho mudado para '
          '${rotuloModoTrabalho(r.detalhes['depois'])}';
    case 'area_estafeta_entregue_sem_codigo':
      return 'Área do entregador: pedido marcado entregue sem código';
    case 'driver_set_online':
      return r.detalhes['depois'] == true ? 'Ligado pelo painel' : 'Desligado pelo painel';
    case 'order_estafeta_avancar':
      // Aqui 'de' e 'para' são estados do pedido, não entregadores.
      return r.detalhes['para'] == ProximoPasso.aCaminho.status
          ? 'Pedido marcado "A caminho" (painel)'
          : 'Pedido marcado "Recolhi" (painel)';
    case 'driver_force_approve':
    case 'driver_approved':
    case 'driver_approve':
      return 'Cadastro aprovado';
    case 'driver_reject':
      return 'Cadastro recusado';
    case 'driver_ban':
      return 'Banido';
    case 'driver_reactivate':
      return 'Reativado';
    case 'driver_suspend':
      return 'Suspenso';
    case 'driver_force_logout':
      return 'Sessão encerrada pelo painel';
    case 'driver_update_name':
      return 'Nome alterado';
    case 'driver_update_iban':
      return 'IBAN alterado';
    case 'driver_update_vehicle_type':
      return 'Tipo de veículo alterado';
    case 'driver_soft_delete':
      return 'Conta apagada';
  }
  const prefixo = 'area_estafeta_';
  if (r.acao.startsWith(prefixo)) {
    return 'Área do entregador: ${r.acao.substring(prefixo.length).replaceAll('_', ' ')}';
  }
  return r.acao.replaceAll('_', ' ');
}

/// "15/11 14:05 · Pedido dado a ele (painel) · pedido A1B2C3 · por x@bora.pt · motivo: …"
String linhaDoHistorico(RegistoAdmin r, {required Set<String> idsDele}) {
  final partes = <String>[
    dataHoraLisboaDe(r.quando),
    rotuloRegistoAdmin(r, idsDele: idsDele),
    if (r.pedidoId != null) 'pedido ${codigoPedido(r.pedidoId!)}',
    'por ${r.quem}',
    if (r.motivo != null) 'motivo: ${r.motivo}',
  ];
  return partes.join(' · ');
}

// ── O serviço ────────────────────────────────────────────────────────────────

/// As chamadas ao servidor da Área do estafeta. O ecrã usa
/// [AdminAreaEstafetaSupabase]; os testes passam uma subclasse falsa.
abstract class AdminAreaEstafetaService {
  const AdminAreaEstafetaService();

  /// admin_driver_presence (aceita drivers.id ou o id de login).
  Future<PresencaEstafeta?> presenca(String driverId);

  /// admin_live_drivers: a posição dele, se tiver GPS nos últimos 5 min.
  Future<PosicaoEstafeta?> posicao({required String userId, required String driverId});

  /// admin_live_orders sem os pedidos de teste, com a hora dos agendados.
  Future<List<PedidoAberto>> pedidosAbertos();

  /// admin_drivers_for_assignment: os aprovados, os disponíveis primeiro.
  Future<List<EstafetaParaAtribuir>> outrosEntregadores(String orderId);

  /// admin_reassign_order: dar a ele (= aceitar por ele) ou passar a outro.
  Future<Map<String, dynamic>> atribuirPedido({
    required String orderId,
    required String novoEntregador,
    required String motivo,
  });

  /// admin_release_order_driver: tira-o do pedido e o pedido volta à fila.
  Future<Map<String, dynamic>> devolverAFila({
    required String orderId,
    required String motivo,
  });

  /// admin_marcar_entregue_sem_codigo (o mesmo caminho do botão do painel).
  Future<Map<String, dynamic>> marcarEntregueSemCodigo(String orderId, String motivo);

  /// admin_estafeta_avancar: "Recolhi" ('pickedUp') ou "A caminho"
  /// ('onTheWay') por ele. O servidor grava no log com o motivo.
  Future<Map<String, dynamic>> avancarPedido({
    required String orderId,
    required String status,
    required String motivo,
  });

  /// admin_driver_avisar_gps: push "Sem sinal de GPS".
  Future<Map<String, dynamic>> avisarGps(String driverId);

  /// admin_driver_avisar_sem_sinal: push "estás ligado, mas sem sinal".
  Future<Map<String, dynamic>> avisarSemSinal(String userId);

  /// admin_set_driver_online: liga ou desliga por ele (aceita drivers.id ou o
  /// id de login). O servidor grava no log com o motivo.
  Future<Map<String, dynamic>> ligarDesligar({
    required String driverId,
    required bool ligar,
    required String motivo,
  });

  /// admin_fatura_mes_estafeta (só leitura): o recibo verde do mês que começa
  /// em [mes] (ver [primeiroDiaDoMes]).
  Future<FaturaDoMes> faturaDoMes({required String userId, required DateTime mes});

  /// extrato_prestador das últimas [kSemanasExtrato] semanas.
  Future<ExtratoGanhos> ganhos(String userId);

  /// driver_minha_conta_estado.
  Future<ContaDoEstafeta> conta(String userId);

  /// admin_documentos_verificacoes: as últimas verificações do robô.
  Future<List<VereditoRobo>> documentos(String userId);

  /// admin_robo_documentos_lembrar: aviso no app + email com o que falta.
  Future<Map<String, dynamic>> lembrarDocumentos(String userId);

  /// drivers.work_mode e vehicle_type (só leitura).
  Future<ModoTrabalho> modoTrabalho(String driverId);

  /// admin_set_driver_work_mode ('everything' | 'rides_only').
  Future<Map<String, dynamic>> definirModoTrabalho({
    required String driverId,
    required String modo,
  });

  /// Grava `area_estafeta_<acao>` no admin_audit_log, com o entregador como
  /// entidade. true = ficou gravado.
  Future<bool> registarAuditoria({
    required String acao,
    required String driverId,
    required Map<String, dynamic> detalhes,
  });

  /// O que o painel já fez por ele (log + histórico de atribuições).
  Future<List<RegistoAdmin>> historico({
    required String userId,
    required String driverId,
  });
}

/// A implementação real (Supabase da app, ou o cliente passado).
class AdminAreaEstafetaSupabase extends AdminAreaEstafetaService {
  const AdminAreaEstafetaSupabase({this.client});

  final SupabaseClient? client;

  SupabaseClient get _c => client ?? Supabase.instance.client;

  @override
  Future<PresencaEstafeta?> presenca(String driverId) async {
    final res = await _c.rpc('admin_driver_presence', params: {'p_driver': driverId});
    final linhas = _linhas(res);
    if (linhas.isNotEmpty) return PresencaEstafeta.fromRow(linhas.first);
    if (res is Map) return PresencaEstafeta.fromRow(Map<String, dynamic>.from(res));
    return null;
  }

  @override
  Future<PosicaoEstafeta?> posicao({required String userId, required String driverId}) async {
    final res = await _c.rpc('admin_live_drivers');
    return posicaoDoEntregador(_linhas(res), userId: userId, driverId: driverId);
  }

  @override
  Future<List<PedidoAberto>> pedidosAbertos() async {
    // A hora dos agendados vem à parte e é só ajuda: começa já e, se falhar,
    // os pedidos aparecem na mesma (com o aviso geral de conferir a hora).
    final agendados = _horasAgendadas();
    final res = await _c.rpc('admin_live_orders', params: {'p_include_test_orders': false});
    final horas = await agendados;
    return [
      for (final r in _linhas(res))
        PedidoAberto.fromRow(r, agendadoPara: horas[_texto(r['id'])]),
    ];
  }

  Future<Map<String, DateTime>> _horasAgendadas() async {
    try {
      return horasAgendadasDaResposta(await _c.rpc('admin_scheduled_orders'));
    } catch (e) {
      debugPrint('[AreaEstafeta] admin_scheduled_orders: $e');
      return <String, DateTime>{};
    }
  }

  @override
  Future<List<EstafetaParaAtribuir>> outrosEntregadores(String orderId) async {
    final res = await _c.rpc('admin_drivers_for_assignment',
        params: {'p_order_id': orderId, 'p_search': null});
    return _linhas(res).map(EstafetaParaAtribuir.fromRow).toList();
  }

  @override
  Future<Map<String, dynamic>> atribuirPedido({
    required String orderId,
    required String novoEntregador,
    required String motivo,
  }) async =>
      _resposta(await _c.rpc('admin_reassign_order', params: {
        'p_order_id': orderId,
        'p_new_driver': novoEntregador,
        'p_motivo': motivo,
      }));

  @override
  Future<Map<String, dynamic>> devolverAFila({
    required String orderId,
    required String motivo,
  }) async =>
      _resposta(await _c.rpc('admin_release_order_driver',
          params: {'p_order_id': orderId, 'p_motivo': motivo}));

  @override
  Future<Map<String, dynamic>> marcarEntregueSemCodigo(String orderId, String motivo) =>
      AdminEntregueSemCodigoButton.marcarNoServidor(orderId, motivo);

  @override
  Future<Map<String, dynamic>> avancarPedido({
    required String orderId,
    required String status,
    required String motivo,
  }) async =>
      _resposta(await _c.rpc('admin_estafeta_avancar', params: {
        'p_order_id': orderId,
        'p_status': status,
        'p_motivo': motivo,
      }));

  @override
  Future<Map<String, dynamic>> avisarGps(String driverId) async =>
      _resposta(await _c.rpc('admin_driver_avisar_gps', params: {'p_driver': driverId}));

  @override
  Future<Map<String, dynamic>> avisarSemSinal(String userId) async => _resposta(
      await _c.rpc('admin_driver_avisar_sem_sinal', params: {'p_user_id': userId}));

  @override
  Future<Map<String, dynamic>> ligarDesligar({
    required String driverId,
    required bool ligar,
    required String motivo,
  }) async =>
      _resposta(await _c.rpc('admin_set_driver_online', params: {
        'p_driver': driverId,
        'p_online': ligar,
        'p_motivo': motivo,
      }));

  @override
  Future<FaturaDoMes> faturaDoMes({required String userId, required DateTime mes}) async =>
      FaturaDoMes.fromJson(await _c.rpc('admin_fatura_mes_estafeta',
          params: {'p_user_id': userId, 'p_mes': mesParaServidor(mes)}));

  @override
  Future<ExtratoGanhos> ganhos(String userId) async => ExtratoGanhos.fromJson(
      await _c.rpc('extrato_prestador',
          params: {'p_semanas': kSemanasExtrato, 'p_user_id': userId}));

  @override
  Future<ContaDoEstafeta> conta(String userId) async => ContaDoEstafeta.fromJson(
      await _c.rpc('driver_minha_conta_estado', params: {'p_user_id': userId}));

  @override
  Future<List<VereditoRobo>> documentos(String userId) async {
    final res = await _c.rpc('admin_documentos_verificacoes',
        params: {'p_user_id': userId, 'p_limite': 5});
    return _linhas(res).map(VereditoRobo.fromMap).toList();
  }

  @override
  Future<Map<String, dynamic>> lembrarDocumentos(String userId) async => _resposta(
      await _c.rpc('admin_robo_documentos_lembrar', params: {'p_user_id': userId}));

  @override
  Future<ModoTrabalho> modoTrabalho(String driverId) async {
    final r = await _c
        .from('drivers')
        .select('work_mode, vehicle_type')
        .eq('id', driverId)
        .maybeSingle();
    return ModoTrabalho(
      modo: _textoOuNull(r?['work_mode']),
      veiculo: _textoOuNull(r?['vehicle_type']),
    );
  }

  @override
  Future<Map<String, dynamic>> definirModoTrabalho({
    required String driverId,
    required String modo,
  }) async {
    // A função devolve {driver_id, work_mode} (sem 'ok'); erro = exceção.
    final r = _mapaDe(await _c.rpc('admin_set_driver_work_mode',
        params: {'p_driver_id': driverId, 'p_mode': modo}));
    return <String, dynamic>{...r, 'ok': _texto(r['work_mode']) == modo};
  }

  @override
  Future<bool> registarAuditoria({
    required String acao,
    required String driverId,
    required Map<String, dynamic> detalhes,
  }) async {
    final id = await AdminAuditService.logAction(
      action: 'area_estafeta_$acao',
      entityType: 'driver',
      entityId: driverId,
      details: detalhes,
    );
    return id != null;
  }

  @override
  Future<List<RegistoAdmin>> historico({
    required String userId,
    required String driverId,
  }) async {
    final ids = <String>{userId.trim(), driverId.trim()}..removeWhere((s) => s.isEmpty);
    final uuids = ids.where(_eUuid).toList();
    Object? erro;
    var doRegisto = <RegistoAdmin>[];
    var doHistorico = <RegistoAdmin>[];
    if (ids.isNotEmpty) {
      try {
        final filtros = <String>[
          if (uuids.isNotEmpty) 'entity_id.in.(${uuids.join(',')})',
          'entity_id_text.in.(${ids.join(',')})',
        ];
        final res = await _c
            .from('admin_audit_log')
            .select('created_at, action, admin_email, entity_type, entity_id_text, details')
            .or(filtros.join(','))
            .order('created_at', ascending: false)
            .limit(kLimiteHistorico);
        doRegisto = _linhas(res).map(RegistoAdmin.doRegisto).toList();
      } catch (e) {
        erro = e;
        debugPrint('[AreaEstafeta] admin_audit_log: $e');
      }
    }
    try {
      final res = await _c.rpc('admin_driver_assignment_history',
          params: {'p_driver': userId.isNotEmpty ? userId : driverId, 'p_limit': kLimiteHistorico});
      doHistorico = _linhas(res).map(RegistoAdmin.doHistorico).toList();
    } catch (e) {
      erro ??= e;
      debugPrint('[AreaEstafeta] admin_driver_assignment_history: $e');
    }
    // "Recolhi" / "A caminho" ficam gravados pelo pedido, com o id de login
    // dele nos detalhes (`estafeta_user_id`): lê-se à parte e, se falhar, o
    // resto do histórico aparece na mesma.
    var dosPedidos = <RegistoAdmin>[];
    final uid = userId.trim().toLowerCase();
    if (_eUuid(uid)) {
      try {
        final res = await _c
            .from('admin_audit_log')
            .select('created_at, action, admin_email, entity_type, entity_id_text, details')
            .eq('action', 'order_estafeta_avancar')
            .eq('details->>estafeta_user_id', uid)
            .order('created_at', ascending: false)
            .limit(kLimiteHistorico);
        dosPedidos = _linhas(res).map(RegistoAdmin.doRegisto).toList();
      } catch (e) {
        debugPrint('[AreaEstafeta] admin_audit_log (Recolhi/A caminho): $e');
      }
    }
    if (doRegisto.isEmpty && doHistorico.isEmpty && dosPedidos.isEmpty && erro != null) {
      throw erro;
    }
    return juntarHistorico([...doRegisto, ...dosPedidos], doHistorico);
  }
}
