// ÁREA DO PARCEIRO (15/11/2026, missão painel-admin-15-11 — ordem do Danilo):
// o admin escolhe uma loja e faz por ela o que o parceiro faz na app dele,
// com cada ação registrada no log de auditoria (admin_audit_log).
//
// Todas as chamadas ao servidor do ecrã AdminAreaParceiroScreen vivem aqui; o
// teste troca este serviço por um falso. Assinaturas e guardas lidas no
// servidor (pg_get_function_identity_arguments + prosrc) a 15/11/2026:
//   • loja ................. restaurants (leitura; o admin lê todas pela RLS)
//                            + is_partner_open(p_restaurant_id text, p_at timestamptz)
//   • forçar abrir/fechar .. admin_set_partner_override(p_restaurant_id text,
//                            p_state text, p_reason text, p_ends_at timestamptz)
//   • voltar ao horário .... admin_clear_partner_override(p_restaurant_id text)
//   • pausar / tirar pausa . partner_pausar_loja(p_restaurant_id text, p_minutos int)
//                            — aceita o admin (_parceiro_pode_loja chama is_admin())
//   • ligar modo ocupado ... partner_set_busy(p_restaurant_id text, p_extra_minutes int)
//                            — aceita o admin (mesma guarda)
//   • desligar modo ocupado  admin_partner_busy_desligar(p_restaurant_id text)
//   • pedidos agora ........ admin_live_orders(p_include_test_orders boolean),
//                            filtrado pelo nome da loja (vendor_name). A tabela
//                            orders não tem regra de leitura para o admin e
//                            ainda não há função de admin que filtre pela loja.
//   • quanto a loja recebe . partner_loja_recebe(p_order_ids text[]) — só leitura
//   • encomendas telefone .. encomendas_telefone (leitura; RLS só admin)
//   • chamar entregador já . admin_chamar_estafeta_ja(p_order_id text)
//   • forçar chamada ....... admin_forcar_chamada(p_order_id text)
//   • hora de pronto ....... partner_set_ready_at(p_order_id text, p_ready_at timestamptz)
//                            — aceita o admin (_parceiro_pode_loja)
//   • entregue sem código .. admin_marcar_entregue_sem_codigo(p_pedido text, p_motivo text)
//   • menu ................. admin_list_products_by_partner_v3(p_restaurant_id,
//                            p_search, p_only_inactive, p_only_by_weight, p_limit, p_offset)
//   • disponível/esgotado .. admin_set_product_availability(p_product_id text,
//                            p_available boolean, p_reason text)
//   • dinheiro (leitura) ... partner_my_weekly_closeout(p_restaurant_id text)
//                            + extrato_parceiro(p_restaurant_id text, p_dias int)
//   • reservas (leitura) ... reservations (RLS reservations_admin_read)
//   • histórico ............ admin_audit_log (leitura; RLS só admin)
//   • auditoria da área .... log_admin_action(p_action_type text, p_entity_type text,
//                            p_entity_id text, p_details jsonb) — grava entity_id_text
//
// Auditoria: as funções admin_* acima gravam no admin_audit_log dentro do
// servidor; as partner_* não gravam nada. A área grava uma linha sua
// (`area_parceiro_<acao>`, entidade = a loja, com o motivo) sempre que o
// registo do servidor não existe, não guarda o motivo escrito aqui ou fica
// preso só ao pedido — assim "O que o admin já fez nesta loja" mostra tudo.
// Forçar abrir/fechar e disponível/esgotado não precisam: o servidor já grava
// o motivo e a loja.
//
// Nunca escreve direto em tabelas. Dinheiro: só leitura, nenhum pagamento.
// Preços, categorias e fotos: na ficha da loja (AdminPartnerDetailScreen).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/hora_lisboa.dart';

/// Tempo máximo de cada chamada ao servidor (PADRAO_BORA 3.15, regra 5).
const Duration kAreaParceiroLimite = Duration(seconds: 20);

/// Motivo mínimo das ações que mudam alguma coisa (letras, sem espaços nas pontas).
const int kAreaParceiroMotivoMinimo = 3;

/// Quantos produtos a lista do menu traz de uma vez.
const int kAreaParceiroMaxProdutos = 200;

/// Quantas linhas mostra "O que o admin já fez nesta loja".
const int kAreaParceiroMaxHistorico = 30;

/// Dias do extrato pedido a pedido (a semana, como o fecho do parceiro).
const int kAreaParceiroDiasExtrato = 7;

/// Origem gravada nos detalhes das linhas de auditoria da área.
const String kAreaParceiroOrigem = 'painel: área do parceiro';

/// Motivo com pelo menos [kAreaParceiroMotivoMinimo] letras.
bool motivoAreaParceiroOk(String? motivo) =>
    (motivo ?? '').trim().length >= kAreaParceiroMotivoMinimo;

// ─── Leitura tolerante das respostas do servidor ────────────────────────────

String _texto(Object? v) => v == null ? '' : v.toString().trim();

String? _textoOuNull(Object? v) {
  final t = _texto(v);
  return t.isEmpty ? null : t;
}

int _inteiro(Object? v) => _inteiroOuNull(v) ?? 0;

int? _inteiroOuNull(Object? v) {
  final d = v is num ? v.toDouble() : double.tryParse(_texto(v));
  if (d == null || d.isNaN || d.isInfinite) return null;
  return d.round();
}

double _decimal(Object? v) => _decimalOuNull(v) ?? 0;

double? _decimalOuNull(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(_texto(v));
}

DateTime? _data(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

bool _sim(Object? v) => v == true || _texto(v) == 'true';

Map<String, dynamic> _mapa(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _lista(Object? v) => v is List
    ? <Map<String, dynamic>>[
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e),
      ]
    : <Map<String, dynamic>>[];

/// Erro já em palavras simples (PT-BR) para o ecrã mostrar tal e qual.
class AreaParceiroErro implements Exception {
  const AreaParceiroErro(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// Nome da loja normalizado para comparar com o `vendor_name` dos pedidos.
String nomeLojaNormalizado(String? nome) =>
    _texto(nome).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// "#1A2B3C4D" — o código curto do pedido que o painel mostra.
String codigoCurtoPedido(String id) {
  final limpo = id.replaceAll('-', '');
  final curto = limpo.length > 8 ? limpo.substring(0, 8) : limpo;
  return '#${curto.toUpperCase()}';
}

/// Estado do pedido em palavras do painel (PT-BR).
String estadoPedidoLojaPtBr(String status) => switch (status) {
      'created' => 'Novo, esperando a loja aceitar',
      'preparing' => 'Em preparo',
      'readyForPickup' => 'Pronto para retirada',
      'callingDriver' => 'Chamando entregador',
      'driverAccepted' => 'Entregador aceitou',
      'pickedUp' => 'Coletado',
      'onTheWay' => 'A caminho do cliente',
      'delivered' => 'Entregue',
      'cancelled' => 'Cancelado',
      'rejected' => 'Recusado',
      _ => status.isEmpty ? '—' : status,
    };

/// Situação da candidatura da loja (approval_status) em PT-BR.
String aprovacaoLojaPtBr(String? s) {
  if (s == null || s == 'approved') return 'aprovada';
  return switch (s) {
    'pending' => 'por aprovar',
    'rejected' => 'recusada',
    'suspended' => 'suspensa',
    _ => s,
  };
}

// ─── Modelos ────────────────────────────────────────────────────────────────

/// A loja agora: como o cliente a vê e o que o admin pode mudar.
@immutable
class LojaAgora {
  const LojaAgora({
    required this.id,
    required this.nome,
    this.parceira = false,
    this.online = true,
    this.aprovacao,
    this.emBreve = false,
    this.estadoLido = true,
    this.aberta = false,
    this.abreAs,
    this.abreDia,
    this.fechaEmMinutos,
    this.forcada = false,
    this.motivoForcada,
    this.forcadaAte,
    this.ocupadoMinutos = 0,
    this.ocupadoAte,
    this.pausadaAte,
    this.retirada = false,
    this.reservas = false,
  });

  final String id;
  final String nome;
  final bool parceira;
  final bool online;
  final String? aprovacao;
  final bool emBreve;

  /// false quando is_partner_open falhou: [aberta] não é de confiança.
  final bool estadoLido;

  /// Aberta agora para os clientes (is_partner_open).
  final bool aberta;
  final String? abreAs;
  final String? abreDia;
  final int? fechaEmMinutos;

  /// Aberta ou fechada à força pelo admin (partner_status_override).
  final bool forcada;
  final String? motivoForcada;
  final DateTime? forcadaAte;

  /// Modo ocupado (busy_extra_minutes / busy_until).
  final int ocupadoMinutos;
  final DateTime? ocupadoAte;

  /// Pausa da loja (pausa_ate), posta pela loja ou pelo admin.
  final DateTime? pausadaAte;

  /// Retirada no balcão (take-away) ligada.
  final bool retirada;

  /// Reservas de mesa ligadas.
  final bool reservas;

  bool get aprovada => aprovacao == null || aprovacao == 'approved';

  bool ocupadaEm(DateTime agora) =>
      ocupadoMinutos > 0 && ocupadoAte != null && ocupadoAte!.isAfter(agora);

  bool pausadaEm(DateTime agora) =>
      pausadaAte != null && pausadaAte!.isAfter(agora);

  /// Junta a linha de `restaurants` e a resposta de `is_partner_open`.
  factory LojaAgora.deMapas(
      Map<String, dynamic> loja, Map<String, dynamic>? estado) {
    final e = estado ?? const <String, dynamic>{};
    return LojaAgora(
      id: _texto(loja['id']),
      nome: _textoOuNull(loja['name']) ?? _texto(loja['id']),
      parceira: _sim(loja['is_partner']),
      online: loja['is_online'] != false,
      aprovacao: _textoOuNull(loja['approval_status']),
      emBreve: _sim(loja['coming_soon']),
      estadoLido: estado != null,
      aberta: _sim(e['is_open']),
      abreAs: _textoOuNull(e['opens_at']),
      abreDia: _textoOuNull(e['opens_dia']),
      fechaEmMinutos: _inteiroOuNull(e['closes_in_minutes']),
      forcada: _sim(e['override_active']),
      motivoForcada: _textoOuNull(e['override_reason']),
      forcadaAte: _data(e['override_ends_at']),
      ocupadoMinutos: _inteiro(loja['busy_extra_minutes']),
      ocupadoAte: _data(loja['busy_until']),
      pausadaAte: _data(loja['pausa_ate']),
      retirada: _sim(loja['takeaway_enabled']),
      reservas: _sim(loja['reservations_enabled']),
    );
  }
}

/// Um pedido em curso da loja (linha de admin_live_orders).
@immutable
class PedidoDaLoja {
  const PedidoDaLoja({
    required this.id,
    required this.status,
    this.tipoServico,
    this.loja,
    this.cliente,
    this.total = 0,
    this.criadoEm,
    this.entregadorId,
    this.teste = false,
  });

  final String id;
  final String status;
  final String? tipoServico;
  final String? loja;
  final String? cliente;
  final double total;
  final DateTime? criadoEm;
  final String? entregadorId;
  final bool teste;

  bool get temEntregador => entregadorId != null;
  bool get retirada => tipoServico == 'takeaway';
  String get codigo => codigoCurtoPedido(id);

  /// O mapa que o diálogo de cancelamento do painel (AdminCancelOrderDialog) lê.
  Map<String, dynamic> paraCancelar() => <String, dynamic>{
        'id': id,
        'status': status,
        'total': total,
        'customer_name': cliente,
        'vendor_name': loja,
      };

  static PedidoDaLoja? doMapa(Map<String, dynamic> m) {
    final id = _textoOuNull(m['id']);
    if (id == null) return null;
    return PedidoDaLoja(
      id: id,
      status: _texto(m['status']),
      tipoServico: _textoOuNull(m['service_type']),
      loja: _textoOuNull(m['vendor_name']),
      cliente: _textoOuNull(m['customer_name']),
      total: _decimal(m['total'] ?? m['price']),
      criadoEm: _data(m['created_at']),
      entregadorId: _textoOuNull(m['assigned_driver_id']),
      teste: _sim(m['is_test_order']),
    );
  }
}

/// Fica só com os pedidos desta loja (pelo nome), mais recentes primeiro.
List<PedidoDaLoja> pedidosDaLoja(
    Iterable<Map<String, dynamic>> linhas, String nomeLoja) {
  final alvo = nomeLojaNormalizado(nomeLoja);
  if (alvo.isEmpty) return const <PedidoDaLoja>[];
  final out = <PedidoDaLoja>[];
  for (final l in linhas) {
    if (nomeLojaNormalizado(_texto(l['vendor_name'])) != alvo) continue;
    final p = PedidoDaLoja.doMapa(l);
    if (p != null) out.add(p);
  }
  final zero = DateTime.utc(2000);
  out.sort((a, b) => (b.criadoEm ?? zero).compareTo(a.criadoEm ?? zero));
  return out;
}

/// Um produto do menu da loja (linha de admin_list_products_by_partner_v3).
@immutable
class ProdutoDoMenu {
  const ProdutoDoMenu({
    required this.id,
    required this.nome,
    this.preco,
    this.disponivel = true,
    this.categoria,
    this.aoPeso = false,
  });

  final String id;
  final String nome;

  /// Preço na app (só para reconhecer o produto; não se edita aqui).
  final double? preco;
  final bool disponivel;
  final String? categoria;
  final bool aoPeso;

  ProdutoDoMenu comDisponivel(bool valor) => ProdutoDoMenu(
        id: id,
        nome: nome,
        preco: preco,
        disponivel: valor,
        categoria: categoria,
        aoPeso: aoPeso,
      );

  static ProdutoDoMenu? doMapa(Map<String, dynamic> m) {
    final id = _textoOuNull(m['id']);
    if (id == null) return null;
    return ProdutoDoMenu(
      id: id,
      nome: _textoOuNull(m['name']) ?? id,
      preco: _decimalOuNull(m['price']),
      disponivel: m['is_available'] != false,
      categoria: _textoOuNull(m['category']),
      aoPeso: _sim(m['sold_by_weight']),
    );
  }
}

/// Uma linha do extrato da loja (extrato_parceiro → pedidos), em cêntimos.
@immutable
class LinhaDoExtrato {
  const LinhaDoExtrato({
    required this.quando,
    this.pedidoId,
    this.cliente,
    this.pagamento,
    this.clientePagouCents,
    this.parteBoraCents,
    this.ficaCents,
  });

  final String quando;
  final String? pedidoId;
  final String? cliente;
  final String? pagamento;
  final int? clientePagouCents;
  final int? parteBoraCents;
  final int? ficaCents;

  static LinhaDoExtrato doMapa(Map<String, dynamic> m) => LinhaDoExtrato(
        quando: _textoOuNull(m['quando_txt']) ?? '—',
        pedidoId: _textoOuNull(m['pedido_id']),
        cliente: _textoOuNull(m['cliente']),
        pagamento: _textoOuNull(m['pagamento']),
        clientePagouCents: _inteiroOuNull(m['cliente_pagou_cents']),
        parteBoraCents: _inteiroOuNull(m['parte_bora_cents']),
        ficaCents: _inteiroOuNull(m['fica_para_o_parceiro_cents']),
      );
}

/// O dinheiro da semana da loja — SÓ LEITURA. Valores da semana em euros
/// (partner_my_weekly_closeout); valores do extrato em cêntimos.
@immutable
class DinheiroDaSemana {
  const DinheiroDaSemana({
    this.semanaLida = false,
    this.inicio,
    this.fim,
    this.pedidos = 0,
    this.vendas = 0,
    this.parteBora = 0,
    this.ficaParaLoja = 0,
    this.saldo = 0,
    this.direcao = 'zero',
    this.extratoLido = false,
    this.linhas = const <LinhaDoExtrato>[],
    this.transferidoCents,
    this.semanasTransferidas,
    this.porTransferirCents,
    this.semanasPorTransferir,
    this.aviso,
  });

  final bool semanaLida;
  final DateTime? inicio;
  final DateTime? fim;
  final int pedidos;
  final double vendas;
  final double parteBora;
  final double ficaParaLoja;
  final double saldo;

  /// 'bora_pays_partner' / 'partner_pays_bora' / 'zero'.
  final String direcao;

  final bool extratoLido;
  final List<LinhaDoExtrato> linhas;
  final int? transferidoCents;
  final int? semanasTransferidas;
  final int? porTransferirCents;
  final int? semanasPorTransferir;

  /// Parte que não deu para ler (a outra aparece na mesma).
  final String? aviso;

  bool get boraPagaALoja => direcao.startsWith('bora_pays');
  bool get lojaPagaABora => direcao.endsWith('_pays_bora');

  static DinheiroDaSemana deMapas({
    Map<String, dynamic>? fecho,
    Map<String, dynamic>? extrato,
    String? aviso,
  }) {
    final semana = _mapa(fecho?['current_week']);
    final transf = _mapa(extrato?['transferido']);
    final porTr = _mapa(extrato?['por_transferir']);
    return DinheiroDaSemana(
      semanaLida: semana.isNotEmpty,
      inicio: _data(semana['week_start']),
      fim: _data(semana['week_end']),
      pedidos: _inteiro(semana['total_orders']),
      vendas: _decimal(semana['gross_sales']),
      parteBora: _decimal(semana['commission_total']),
      ficaParaLoja: _decimal(semana['partner_share']),
      saldo: _decimal(semana['net_balance']),
      direcao: _textoOuNull(semana['direction']) ?? 'zero',
      extratoLido: extrato != null,
      linhas: <LinhaDoExtrato>[
        for (final l in _lista(extrato?['pedidos'])) LinhaDoExtrato.doMapa(l),
      ],
      transferidoCents: _inteiroOuNull(transf['total_cents']),
      semanasTransferidas: _inteiroOuNull(transf['semanas']),
      porTransferirCents: _inteiroOuNull(porTr['total_cents']),
      semanasPorTransferir: _inteiroOuNull(porTr['semanas']),
      aviso: aviso,
    );
  }
}

/// Contagem das reservas de mesa da loja (de hoje em diante).
@immutable
class ResumoReservas {
  const ResumoReservas({this.hoje = 0, this.proximas = 0, this.porDecidir = 0});

  final int hoje;
  final int proximas;
  final int porDecidir;

  static const Set<String> _terminadas = <String>{
    'cancelled',
    'canceled',
    'declined',
    'rejected',
    'no_show',
    'finished',
    'completed',
  };

  /// [linhas] = reservas com `reserved_for` desde o início de hoje (Lisboa).
  static ResumoReservas contar(
      Iterable<Map<String, dynamic>> linhas, DateTime agora) {
    final inicioHoje = inicioDiaLisboaUtc(agora);
    final fimHoje = inicioHoje.add(const Duration(days: 1));
    var hoje = 0;
    var proximas = 0;
    var porDecidir = 0;
    for (final l in linhas) {
      final estado = _texto(l['status']);
      if (_terminadas.contains(estado)) continue;
      final quando = _data(l['reserved_for']);
      if (quando == null) continue;
      if (!quando.isBefore(inicioHoje) && quando.isBefore(fimHoje)) hoje++;
      if (!quando.isBefore(agora)) proximas++;
      if (estado == 'pending') porDecidir++;
    }
    return ResumoReservas(hoje: hoje, proximas: proximas, porDecidir: porDecidir);
  }
}

/// Uma linha de admin_audit_log desta loja.
@immutable
class AcaoDoAdmin {
  const AcaoDoAdmin({
    required this.acao,
    this.quem,
    this.quando,
    this.tipo,
    this.entidade,
    this.detalhes = const <String, dynamic>{},
  });

  final String acao;
  final String? quem;
  final DateTime? quando;
  final String? tipo;
  final String? entidade;
  final Map<String, dynamic> detalhes;

  String? get motivo =>
      _textoOuNull(detalhes['motivo']) ?? _textoOuNull(detalhes['reason']);

  String? get pedidoId =>
      _textoOuNull(detalhes['order_id']) ??
      (tipo == 'order' ? _textoOuNull(entidade) : null);

  static AcaoDoAdmin doMapa(Map<String, dynamic> m) => AcaoDoAdmin(
        acao: _textoOuNull(m['action']) ?? 'acao_admin',
        quem: _textoOuNull(m['admin_email']),
        quando: _data(m['created_at']),
        tipo: _textoOuNull(m['entity_type']),
        entidade: _textoOuNull(m['entity_id_text']) ?? _textoOuNull(m['entity_id']),
        detalhes: _mapa(m['details']),
      );
}

/// As ações que a área grava do lado da app (entidade = a loja).
class AcoesAreaParceiro {
  const AcoesAreaParceiro._();

  static const String prefixo = 'area_parceiro_';
  static const String voltarAoHorario = 'area_parceiro_voltar_ao_horario';
  static const String pausar = 'area_parceiro_pausar';
  static const String tirarPausa = 'area_parceiro_tirar_pausa';
  static const String ligarModoOcupado = 'area_parceiro_ligar_modo_ocupado';
  static const String desligarModoOcupado = 'area_parceiro_desligar_modo_ocupado';
  static const String escolherEntregador = 'area_parceiro_escolher_entregador';
  static const String chamarEntregadorJa = 'area_parceiro_chamar_entregador_ja';
  static const String forcarChamada = 'area_parceiro_forcar_chamada';
  static const String horaPronto = 'area_parceiro_hora_pronto';
  static const String cancelarPedido = 'area_parceiro_cancelar_pedido';
  static const String entregueSemCodigo = 'area_parceiro_entregue_sem_codigo';
  static const String chamarEntregadorBalcao =
      'area_parceiro_chamar_entregador_balcao';

  static const Map<String, String> rotulos = <String, String>{
    voltarAoHorario: 'Voltou a loja ao horário normal',
    pausar: 'Pausou a loja',
    tirarPausa: 'Tirou a pausa da loja',
    ligarModoOcupado: 'Ligou o modo ocupado',
    desligarModoOcupado: 'Desligou o modo ocupado',
    escolherEntregador: 'Escolheu o entregador de um pedido',
    chamarEntregadorJa: 'Chamou o entregador já',
    forcarChamada: 'Forçou a chamada de um entregador',
    horaPronto: 'Prometeu a hora de pronto de um pedido',
    cancelarPedido: 'Cancelou um pedido',
    entregueSemCodigo: 'Marcou um pedido entregue sem código',
    chamarEntregadorBalcao: 'Chamou entregador para um pedido feito na loja',
  };
}

/// O que o admin fez, em palavras do painel (PT-BR).
String rotuloAcaoNaLoja(AcaoDoAdmin a) {
  final daArea = AcoesAreaParceiro.rotulos[a.acao];
  if (daArea != null) return 'Área do parceiro: $daArea';
  final d = a.detalhes;
  final produto = _textoOuNull(d['product_name']);
  String comProduto(String base) => produto == null ? base : '$base: $produto';
  switch (a.acao) {
    case 'partner_status_override_set':
      return _texto(d['forced_state']) == 'open'
          ? 'Forçou ABRIR a loja'
          : 'Forçou FECHAR a loja';
    case 'partner_status_override_cleared':
      return 'Voltou a loja ao horário normal';
    case 'partner_busy_desligado':
      return 'Desligou o modo ocupado';
    case 'product_activate':
      return comProduto('Deixou disponível');
    case 'product_deactivate':
      return comProduto('Marcou esgotado');
    case 'product_unavailable':
      return comProduto('Produto indisponível');
    case 'partner_toggle':
      return 'Ligou ou desligou a loja';
    case 'partner_hours_updated':
      return 'Mudou o horário';
    case 'partner_approve':
      return 'Aprovou a loja';
    case 'partner_reject':
      return 'Recusou a loja';
    case 'parceiro_dados_fiscais':
      return 'Mudou os dados fiscais';
    case 'restaurant_reactivated':
      return 'Reativou a loja';
    case 'chamar_estafeta_ja':
      return 'Chamou o entregador já (encomenda por telefone)';
    case 'forcar_chamada_reforco':
      return 'Forçou a chamada de reforço';
    case 'entregue_sem_codigo':
      return 'Marcou entregue sem código';
    case 'order_preassigned':
    case 'order_reassigned':
      return 'Escolheu o entregador de um pedido';
  }
  return a.acao;
}

/// "15/11 10:00 · admin@bora.pt · motivo: … · pedido #1A2B3C4D"
String detalheAcaoNaLoja(AcaoDoAdmin a) {
  final pedido = a.pedidoId;
  return <String>[
    dataHoraLisboa(a.quando?.toIso8601String()),
    if (a.quem != null) a.quem!,
    if (a.motivo != null) 'motivo: ${a.motivo}',
    if (pedido != null) 'pedido ${codigoCurtoPedido(pedido)}',
  ].join(' · ');
}

/// Resposta de admin_chamar_estafeta_ja em palavras simples.
String chamarJaEmPalavras(Map<String, dynamic> r) {
  if (r['ok'] == true) {
    return 'Entregador chamado às ${_textoOuNull(r['chamado_as']) ?? 'agora'}.';
  }
  switch (_texto(r['motivo'])) {
    case 'nao_e_encomenda_por_telefone':
      return 'Só serve para encomendas feitas por telefone. Nos outros pedidos o '
          'entregador é chamado quando a loja marca pronto.';
    case 'encomenda_cancelada':
      return 'Esta encomenda por telefone foi cancelada.';
    case 'estafeta_ja_chamado':
      return 'O entregador já tinha sido chamado.';
    case 'pedido_nao_esta_em_preparacao':
      return 'O pedido não está em preparo (agora: '
          '${estadoPedidoLojaPtBr(_texto(r['estado']))}).';
    case 'nao_libertou':
      return 'Não deu para chamar agora (o pedido mudou). Atualize e tente de novo.';
  }
  return 'Resposta inesperada do servidor: '
      '${_textoOuNull(r['motivo']) ?? _textoOuNull(r['error']) ?? r}';
}

/// Respostas {ok:false, error} das funções partner_* e do modo ocupado.
String respostaLojaEmPalavras(Map<String, dynamic> r) {
  switch (_texto(r['error'])) {
    case 'forbidden':
      return 'Sem permissão para agir nesta loja.';
    case 'minutos_invalidos':
      return 'Tempo inválido.';
    case 'desligado':
      return 'O modo ocupado está desligado para todas as lojas (painel: Modo '
          'ocupado dos parceiros).';
    case 'loja_nao_encontrada':
      return 'Loja não encontrada.';
    case 'pedido_nao_encontrado':
      return 'Pedido não encontrado.';
    case 'so_entregas_de_parceiro':
      return 'Só serve para entregas de loja parceira.';
    case 'pedido_nao_esta_em_preparacao':
      return 'O pedido já não está em preparo.';
    case 'hora_invalida':
      return 'Hora inválida: tem de ser daqui a no máximo 4 horas.';
  }
  return 'Não foi possível: '
      '${_textoOuNull(r['error']) ?? 'resposta inesperada do servidor'}.';
}

// ─── O serviço ──────────────────────────────────────────────────────────────

/// Tudo o que o ecrã da Área do Parceiro pede ao servidor.
abstract class AdminAreaParceiroService {
  const AdminAreaParceiroService();

  // Leituras
  Future<LojaAgora> lerLoja(String restaurantId);
  Future<List<PedidoDaLoja>> pedidosAgora({required String nomeLoja});
  Future<Map<String, int>> lojaRecebeCents(List<String> pedidoIds);
  Future<Set<String>> encomendasPorTelefoneAbertas(String restaurantId);
  Future<List<ProdutoDoMenu>> menu(String restaurantId, {String? procurar});
  Future<DinheiroDaSemana> dinheiroDaSemana(String restaurantId);
  Future<ResumoReservas> reservas(String restaurantId, {required DateTime agora});
  Future<List<AcaoDoAdmin>> historico(String restaurantId);

  // Loja
  Future<Map<String, dynamic>> forcarEstado(String restaurantId,
      {required bool abrir, required String motivo, DateTime? ate});
  Future<Map<String, dynamic>> voltarAoHorario(String restaurantId);
  Future<Map<String, dynamic>> pausarLoja(String restaurantId, int minutos);
  Future<Map<String, dynamic>> ligarModoOcupado(String restaurantId, int minutos);
  Future<Map<String, dynamic>> desligarModoOcupado(String restaurantId);

  // Menu
  Future<Map<String, dynamic>> definirDisponivel(String productId,
      {required bool disponivel, required String motivo});

  // Pedidos
  Future<Map<String, dynamic>> chamarEntregadorJa(String pedidoId);
  Future<Map<String, dynamic>> forcarChamada(String pedidoId);
  Future<Map<String, dynamic>> prometerHoraPronto(String pedidoId, DateTime? hora);
  Future<Map<String, dynamic>> marcarEntregueSemCodigo(String pedidoId, String motivo);

  /// Grava `acao` no admin_audit_log com a loja como entidade (entity_id_text).
  /// Nunca lança: devolve false se não gravou.
  Future<bool> registarAuditoria({
    required String acao,
    required String restaurantId,
    required Map<String, dynamic> detalhes,
  });
}

/// O serviço de verdade (Supabase). Nenhuma escrita direta em tabelas.
class SupabaseAdminAreaParceiroService extends AdminAreaParceiroService {
  SupabaseAdminAreaParceiroService({SupabaseClient? client}) : _cliente = client;

  final SupabaseClient? _cliente;

  SupabaseClient get _db => _cliente ?? Supabase.instance.client;

  Future<dynamic> _rpc(String nome, [Map<String, dynamic>? params]) =>
      _db.rpc(nome, params: params).timeout(kAreaParceiroLimite);

  @override
  Future<LojaAgora> lerLoja(String restaurantId) async {
    final linha = await _db
        .from('restaurants')
        .select('id, name, is_partner, is_online, approval_status, coming_soon, '
            'busy_extra_minutes, busy_until, pausa_ate, takeaway_enabled, '
            'reservations_enabled')
        .eq('id', restaurantId)
        .maybeSingle()
        .timeout(kAreaParceiroLimite);
    if (linha == null) throw const AreaParceiroErro('Loja não encontrada.');
    Map<String, dynamic>? estado;
    try {
      final r = await _rpc('is_partner_open', <String, dynamic>{
        'p_restaurant_id': restaurantId,
        'p_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (r is Map) estado = Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('[AreaParceiro] is_partner_open: $e');
    }
    return LojaAgora.deMapas(Map<String, dynamic>.from(linha), estado);
  }

  @override
  Future<List<PedidoDaLoja>> pedidosAgora({required String nomeLoja}) async {
    final r = await _rpc(
        'admin_live_orders', <String, dynamic>{'p_include_test_orders': true});
    return pedidosDaLoja(_lista(r), nomeLoja);
  }

  @override
  Future<Map<String, int>> lojaRecebeCents(List<String> pedidoIds) async {
    if (pedidoIds.isEmpty) return const <String, int>{};
    final r = await _rpc(
        'partner_loja_recebe', <String, dynamic>{'p_order_ids': pedidoIds});
    return <String, int>{
      for (final e in _mapa(r).entries) e.key: _inteiro(e.value),
    };
  }

  @override
  Future<Set<String>> encomendasPorTelefoneAbertas(String restaurantId) async {
    final r = await _db
        .from('encomendas_telefone')
        .select('order_id')
        .eq('restaurant_id', restaurantId)
        .isFilter('libertado_em', null)
        .isFilter('cancelado_em', null)
        .limit(200)
        .timeout(kAreaParceiroLimite);
    return <String>{
      for (final l in _lista(r))
        if (_textoOuNull(l['order_id']) != null) _texto(l['order_id']),
    };
  }

  @override
  Future<List<ProdutoDoMenu>> menu(String restaurantId, {String? procurar}) async {
    final r = await _rpc('admin_list_products_by_partner_v3', <String, dynamic>{
      'p_restaurant_id': restaurantId,
      'p_search': _textoOuNull(procurar),
      'p_only_inactive': false,
      'p_only_by_weight': false,
      'p_limit': kAreaParceiroMaxProdutos,
      'p_offset': 0,
    });
    return _lista(r)
        .map(ProdutoDoMenu.doMapa)
        .whereType<ProdutoDoMenu>()
        .toList();
  }

  @override
  Future<DinheiroDaSemana> dinheiroDaSemana(String restaurantId) async {
    Map<String, dynamic>? fecho;
    Map<String, dynamic>? extrato;
    final faltou = <String>[];
    try {
      fecho = _mapa(await _rpc('partner_my_weekly_closeout',
          <String, dynamic>{'p_restaurant_id': restaurantId}));
    } catch (e) {
      debugPrint('[AreaParceiro] partner_my_weekly_closeout: $e');
      faltou.add('o fecho da semana');
    }
    try {
      final r = _mapa(await _rpc('extrato_parceiro', <String, dynamic>{
        'p_restaurant_id': restaurantId,
        'p_dias': kAreaParceiroDiasExtrato,
      }));
      if (r['ok'] == true) {
        extrato = r;
      } else {
        faltou.add('o extrato (${_textoOuNull(r['error']) ?? 'sem resposta'})');
      }
    } catch (e) {
      debugPrint('[AreaParceiro] extrato_parceiro: $e');
      faltou.add('o extrato');
    }
    if (fecho == null && extrato == null) {
      throw AreaParceiroErro(
          'Não consegui ler o dinheiro da loja (${faltou.join(' e ')}).');
    }
    return DinheiroDaSemana.deMapas(
      fecho: fecho,
      extrato: extrato,
      aviso: faltou.isEmpty ? null : 'Não deu para ler ${faltou.join(' e ')}.',
    );
  }

  @override
  Future<ResumoReservas> reservas(String restaurantId,
      {required DateTime agora}) async {
    final r = await _db
        .from('reservations')
        .select('id, status, reserved_for')
        .eq('restaurant_id', restaurantId)
        .gte('reserved_for', inicioDiaLisboaUtc(agora).toIso8601String())
        .order('reserved_for')
        .limit(500)
        .timeout(kAreaParceiroLimite);
    return ResumoReservas.contar(_lista(r), agora);
  }

  @override
  Future<List<AcaoDoAdmin>> historico(String restaurantId) async {
    const colunas =
        'id, action, entity_type, entity_id_text, admin_email, details, created_at';
    List<Map<String, dynamic>> linhas;
    try {
      // A loja como entidade OU o id da loja nos detalhes (produtos, pedidos
      // por telefone). Os valores vão entre aspas (regra do PostgREST).
      if (restaurantId.contains('"') || restaurantId.contains(r'\')) {
        throw const AreaParceiroErro('id com aspas');
      }
      final r = await _db
          .from('admin_audit_log')
          .select(colunas)
          .or('entity_id_text.eq."$restaurantId",'
              'details->>restaurant_id.eq."$restaurantId"')
          .order('created_at', ascending: false)
          .limit(kAreaParceiroMaxHistorico)
          .timeout(kAreaParceiroLimite);
      linhas = _lista(r);
    } catch (e) {
      debugPrint('[AreaParceiro] historico (loja + detalhes): $e — só pela loja');
      final r = await _db
          .from('admin_audit_log')
          .select(colunas)
          .eq('entity_id_text', restaurantId)
          .order('created_at', ascending: false)
          .limit(kAreaParceiroMaxHistorico)
          .timeout(kAreaParceiroLimite);
      linhas = _lista(r);
    }
    return linhas.map(AcaoDoAdmin.doMapa).toList();
  }

  @override
  Future<Map<String, dynamic>> forcarEstado(String restaurantId,
          {required bool abrir, required String motivo, DateTime? ate}) async =>
      _mapa(await _rpc('admin_set_partner_override', <String, dynamic>{
        'p_restaurant_id': restaurantId,
        'p_state': abrir ? 'open' : 'closed',
        'p_reason': motivo.trim(),
        'p_ends_at': ate?.toUtc().toIso8601String(),
      }));

  @override
  Future<Map<String, dynamic>> voltarAoHorario(String restaurantId) async =>
      _mapa(await _rpc('admin_clear_partner_override',
          <String, dynamic>{'p_restaurant_id': restaurantId}));

  @override
  Future<Map<String, dynamic>> pausarLoja(String restaurantId, int minutos) async =>
      _mapa(await _rpc('partner_pausar_loja', <String, dynamic>{
        'p_restaurant_id': restaurantId,
        'p_minutos': minutos,
      }));

  @override
  Future<Map<String, dynamic>> ligarModoOcupado(
          String restaurantId, int minutos) async =>
      _mapa(await _rpc('partner_set_busy', <String, dynamic>{
        'p_restaurant_id': restaurantId,
        'p_extra_minutes': minutos,
      }));

  @override
  Future<Map<String, dynamic>> desligarModoOcupado(String restaurantId) async =>
      _mapa(await _rpc('admin_partner_busy_desligar',
          <String, dynamic>{'p_restaurant_id': restaurantId}));

  @override
  Future<Map<String, dynamic>> definirDisponivel(String productId,
          {required bool disponivel, required String motivo}) async =>
      _mapa(await _rpc('admin_set_product_availability', <String, dynamic>{
        'p_product_id': productId,
        'p_available': disponivel,
        'p_reason': motivo.trim(),
      }));

  @override
  Future<Map<String, dynamic>> chamarEntregadorJa(String pedidoId) async =>
      _mapa(await _rpc(
          'admin_chamar_estafeta_ja', <String, dynamic>{'p_order_id': pedidoId}));

  @override
  Future<Map<String, dynamic>> forcarChamada(String pedidoId) async =>
      _mapa(await _rpc(
          'admin_forcar_chamada', <String, dynamic>{'p_order_id': pedidoId}));

  @override
  Future<Map<String, dynamic>> prometerHoraPronto(
          String pedidoId, DateTime? hora) async =>
      _mapa(await _rpc('partner_set_ready_at', <String, dynamic>{
        'p_order_id': pedidoId,
        'p_ready_at': hora?.toUtc().toIso8601String(),
      }));

  @override
  Future<Map<String, dynamic>> marcarEntregueSemCodigo(
          String pedidoId, String motivo) async =>
      _mapa(await _rpc('admin_marcar_entregue_sem_codigo', <String, dynamic>{
        'p_pedido': pedidoId,
        'p_motivo': motivo.trim(),
      }));

  @override
  Future<bool> registarAuditoria({
    required String acao,
    required String restaurantId,
    required Map<String, dynamic> detalhes,
  }) async {
    try {
      // Sobrecarga de texto (p_action_type): guarda o id da loja em entity_id_text.
      await _rpc('log_admin_action', <String, dynamic>{
        'p_action_type': acao,
        'p_entity_type': 'restaurant',
        'p_entity_id': restaurantId,
        'p_details': <String, dynamic>{...detalhes, 'origem': kAreaParceiroOrigem},
      });
      return true;
    } catch (e) {
      debugPrint('[AreaParceiro] log_admin_action($acao): $e');
      return false;
    }
  }
}
