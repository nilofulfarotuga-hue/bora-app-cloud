/// AGENDAR PEDIDOS (item 5 do adendo 5, 29/10/2026) — as chamadas ao servidor e o
/// estado da escolha do cliente. A lógica pura vive em `agendar_pedido.dart`.
///
/// Tudo está atrás do interruptor `scheduled_orders_enabled` (nasce DESLIGADO):
/// com ele desligado, [AgendarPedidoEstado.ligado] é false, a app não mostra
/// nada e nenhuma chamada de gravação sai. Falhar a ler a configuração
/// (sem rede, função ainda não aplicada) conta como DESLIGADO — nunca abre a
/// funcionalidade por engano.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_service_type.dart';
import '../utils/hora_lisboa.dart';
import 'agendar_pedido.dart';

/// O que o servidor diz sobre os pedidos agendados.
class ConfigAgendar {
  const ConfigAgendar({
    this.ligado = false,
    this.maxDias = kAgendarMaxDiasPadrao,
    this.antecedenciaMin = kAgendarAntecedenciaPadraoMin,
  });

  final bool ligado;
  final int maxDias;
  final int antecedenciaMin;

  static const desligado = ConfigAgendar();

  factory ConfigAgendar.fromJson(Object? raw) {
    if (raw is! Map) return desligado;
    return ConfigAgendar(
      ligado: raw['enabled'] == true,
      maxDias: (raw['max_days'] as num?)?.toInt() ?? kAgendarMaxDiasPadrao,
      antecedenciaMin:
          (raw['min_lead_minutes'] as num?)?.toInt() ?? kAgendarAntecedenciaPadraoMin,
    );
  }
}

/// Um pedido com hora marcada (lista do parceiro e do painel).
class PedidoAgendado {
  const PedidoAgendado({
    required this.id,
    required this.estado,
    required this.quando,
    this.lojaId,
    this.lojaNome,
    this.clienteNome,
    this.notas,
    this.totalEur = 0,
    this.metodo,
    this.pagamento,
    this.prepMin,
    this.aceiteEm,
    this.itens = '',
    this.parceiro,
    this.tipoServico,
  });

  final String id;
  final String estado;

  /// Loja parceira? (`is_partner_store`, só no painel; `null` = o servidor
  /// não disse.)
  final bool? parceiro;

  /// `restaurant` ou `storeShopping` (só no painel).
  final String? tipoServico;

  /// Início da janela (instante).
  final DateTime quando;
  final String? lojaId;
  final String? lojaNome;
  final String? clienteNome;
  final String? notas;
  final double totalEur;
  final String? metodo;
  final String? pagamento;
  final int? prepMin;
  final DateTime? aceiteEm;

  /// "2× Hambúrguer, 1× Batatas" (vazio se o servidor não mandou itens).
  final String itens;

  /// Já foi aceite pela loja (a preparar ou mais além)?
  bool get aceite => estado != 'created';

  /// Fim da janela de 30 minutos.
  DateTime get ate => quando.add(const Duration(minutes: kAgendarJanelaMinutos));

  /// Últimos 4 caracteres do id, em maiúsculas (como o resto da app mostra).
  String get codigo =>
      (id.length >= 4 ? id.substring(id.length - 4) : id).toUpperCase();

  factory PedidoAgendado.fromJson(Map<String, dynamic> j) {
    final itensBrutos = j['items'];
    final partes = <String>[];
    if (itensBrutos is List) {
      for (final it in itensBrutos) {
        if (it is! Map) continue;
        final nome = (it['name'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        final q = (it['quantity'] as num?)?.toInt() ?? 1;
        partes.add('$q× $nome');
      }
    }
    return PedidoAgendado(
      id: (j['id'] ?? '').toString(),
      estado: (j['status'] ?? 'created').toString(),
      quando: DateTime.parse(j['scheduled_for'].toString()).toUtc(),
      lojaId: j['restaurant_id']?.toString(),
      lojaNome: j['restaurant_name']?.toString(),
      clienteNome: j['customer_name']?.toString(),
      notas: j['customer_notes']?.toString(),
      totalEur: (j['price'] as num?)?.toDouble() ?? 0,
      metodo: j['payment_method']?.toString(),
      pagamento: j['payment_status']?.toString(),
      prepMin: (j['prep_time_minutes'] as num?)?.toInt(),
      aceiteEm: j['accepted_at'] == null
          ? null
          : DateTime.tryParse(j['accepted_at'].toString())?.toUtc(),
      itens: partes.join(', '),
      parceiro: j['is_partner_store'] is bool ? j['is_partner_store'] as bool : null,
      tipoServico: j['service_type']?.toString(),
    );
  }
}

/// A porta do cliente e do parceiro. Em teste troca-se por uma de mentira.
abstract class AgendarPedidoApi {
  Future<ConfigAgendar> config();
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia);
  Future<void> gravar(String orderId, DateTime instante);
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId);
}

class AgendarPedidoSupabase implements AgendarPedidoApi {
  AgendarPedidoSupabase([SupabaseClient? c]) : _c = c;
  final SupabaseClient? _c;
  SupabaseClient get _sb => _c ?? Supabase.instance.client;

  @override
  Future<ConfigAgendar> config() async =>
      ConfigAgendar.fromJson(await _sb.rpc('scheduled_orders_config'));

  @override
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia) async {
    final r = await _sb.rpc('scheduled_windows_for_store', params: {
      'p_restaurant_id': restaurantId,
      'p_day': '${dia.year.toString().padLeft(4, '0')}-'
          '${dia.month.toString().padLeft(2, '0')}-'
          '${dia.day.toString().padLeft(2, '0')}',
    });
    final out = <JanelaAgendada>[];
    if (r is List) {
      for (final e in r) {
        if (e is! Map) continue;
        final inicio = DateTime.tryParse('${e['inicio']}');
        if (inicio == null) continue;
        final parede = paredeLisboa(inicio);
        out.add(JanelaAgendada(
          inicio: parede,
          fim: parede.add(const Duration(minutes: kAgendarJanelaMinutos)),
        ));
      }
    }
    return out;
  }

  @override
  Future<void> gravar(String orderId, DateTime instante) async {
    await _sb.rpc('client_set_order_schedule', params: {
      'p_order_id': orderId,
      'p_scheduled_for': instante.toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId) async {
    final r = await _sb.rpc('partner_scheduled_orders',
        params: {'p_restaurant_id': restaurantId});
    return _lista(r);
  }
}

/// A marcação da hora ANTES de o pedido nascer (30/10/2026). Uma porta à
/// parte da [AgendarPedidoApi] para as portas de mentira que já existem nos
/// testes continuarem a servir.
abstract class AgendarMarcacaoApi {
  /// `client_preparar_agendamento(loja, hora)`: o servidor guarda a hora deste
  /// cliente nesta loja (vale 20 min, usa-se uma vez) e o `create_order` de
  /// sempre grava-a no pedido. [instante] `null` apaga a marcação ("Entregar
  /// agora"). Lança com o código do servidor quando recusa.
  Future<void> preparar(String restaurantId, DateTime? instante);

  /// O `scheduled_for` que o pedido ficou a ter (`null` = sem hora).
  Future<DateTime?> horaDoPedido(String orderId);
}

class AgendarMarcacaoSupabase implements AgendarMarcacaoApi {
  AgendarMarcacaoSupabase([SupabaseClient? c]) : _c = c;
  final SupabaseClient? _c;
  SupabaseClient get _sb => _c ?? Supabase.instance.client;

  @override
  Future<void> preparar(String restaurantId, DateTime? instante) async {
    final r = await _sb.rpc('client_preparar_agendamento', params: {
      'p_restaurant_id': restaurantId,
      'p_scheduled_for': instante?.toUtc().toIso8601String(),
    });
    if (r is Map && r['ok'] != true) {
      throw StateError('${r['error'] ?? 'client_preparar_agendamento recusou'}');
    }
  }

  @override
  Future<DateTime?> horaDoPedido(String orderId) async {
    final r = await _sb
        .from('orders')
        .select('scheduled_for')
        .eq('id', orderId)
        .maybeSingle();
    final v = r?['scheduled_for'];
    return v == null ? null : DateTime.tryParse(v.toString())?.toUtc();
  }
}

/// Os códigos que o servidor devolve ao marcar a hora; tudo o resto conta
/// como falta de rede ([kErroAgendarRede]).
const List<String> kErrosAgendarConhecidos = [
  'schedule_window_invalid',
  'scheduled_orders_disabled',
  'auth_required',
  'schedule_required',
];
const String kErroAgendarRede = 'rede';

/// O código do erro de uma chamada de agendamento.
String codigoErroAgendar(Object e) {
  final t = e is PostgrestException ? '${e.message} ${e.details ?? ''}' : e.toString();
  for (final c in kErrosAgendarConhecidos) {
    if (t.contains(c)) return c;
  }
  return kErroAgendarRede;
}

List<PedidoAgendado> _lista(Object? r) {
  final out = <PedidoAgendado>[];
  if (r is List) {
    for (final e in r) {
      if (e is! Map) continue;
      try {
        out.add(PedidoAgendado.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        // uma linha estragada não deita a lista abaixo
      }
    }
  }
  return out;
}

/// O que o painel mostra do interruptor.
class ConfigAgendarAdmin {
  const ConfigAgendarAdmin({
    this.ligado = false,
    this.maxDias = kAgendarMaxDiasPadrao,
    this.antecedenciaMin = kAgendarAntecedenciaPadraoMin,
    this.revisorOk = false,
    this.total = 0,
    this.proximas24h = 0,
  });

  final bool ligado;
  final int maxDias;
  final int antecedenciaMin;

  /// O revisor independente já disse SIM? Sem isto o servidor recusa ligar.
  final bool revisorOk;
  final int total;
  final int proximas24h;

  factory ConfigAgendarAdmin.fromJson(Object? raw) {
    if (raw is! Map) return const ConfigAgendarAdmin();
    return ConfigAgendarAdmin(
      ligado: raw['enabled'] == true,
      maxDias: (raw['max_days'] as num?)?.toInt() ?? kAgendarMaxDiasPadrao,
      antecedenciaMin:
          (raw['min_lead_minutes'] as num?)?.toInt() ?? kAgendarAntecedenciaPadraoMin,
      revisorOk: raw['revisor_ok'] == true,
      total: (raw['total_agendados'] as num?)?.toInt() ?? 0,
      proximas24h: (raw['proximas_24h'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A porta do painel admin.
abstract class AgendarPedidoAdminApi {
  Future<ConfigAgendarAdmin> config();
  Future<ConfigAgendarAdmin> definir(String chave, Object valor);
  Future<List<PedidoAgendado>> pedidos();
}

class AgendarPedidoAdminSupabase implements AgendarPedidoAdminApi {
  AgendarPedidoAdminSupabase([SupabaseClient? c]) : _c = c;
  final SupabaseClient? _c;
  SupabaseClient get _sb => _c ?? Supabase.instance.client;

  @override
  Future<ConfigAgendarAdmin> config() async =>
      ConfigAgendarAdmin.fromJson(await _sb.rpc('admin_scheduled_orders_config'));

  @override
  Future<ConfigAgendarAdmin> definir(String chave, Object valor) async =>
      ConfigAgendarAdmin.fromJson(await _sb.rpc('admin_scheduled_orders_definir',
          params: {'p_chave': chave, 'p_valor': valor}));

  @override
  Future<List<PedidoAgendado>> pedidos() async =>
      _lista(await _sb.rpc('admin_scheduled_orders'));
}

/// O estado do agendamento do lado do cliente: a configuração do servidor (com
/// cache curta) e a janela que o cliente escolheu no carrinho.
class AgendarPedidoEstado extends ChangeNotifier {
  AgendarPedidoEstado._(this.api) : marcacao = AgendarMarcacaoSupabase();

  /// Só para testes: um estado novo, com a sua porta de mentira.
  @visibleForTesting
  AgendarPedidoEstado.paraTeste(this.api, {AgendarMarcacaoApi? marcacao})
      : marcacao = marcacao ?? AgendarMarcacaoSupabase();

  static final AgendarPedidoEstado instance =
      AgendarPedidoEstado._(AgendarPedidoSupabase());

  AgendarPedidoApi api;

  /// A marcação da hora antes de criar o pedido (ver [prepararAntesDeCriar]).
  AgendarMarcacaoApi marcacao;

  /// Só para testes: volta ao estado de fábrica (desligado, sem escolha) com
  /// outra porta. O estado global é partilhado entre testes.
  @visibleForTesting
  void reporParaTeste(AgendarPedidoApi novaApi, {AgendarMarcacaoApi? novaMarcacao}) {
    api = novaApi;
    marcacao = novaMarcacao ?? AgendarMarcacaoSupabase();
    _config = ConfigAgendar.desligado;
    _configEm = null;
    _aCarregar = null;
    _escolha = null;
    _escolhaLoja = null;
    _lojas.clear();
    _aVerificar.clear();
    _marcacaoNoServidor = false;
    notifyListeners();
  }

  ConfigAgendar _config = ConfigAgendar.desligado;
  DateTime? _configEm;
  Future<ConfigAgendar>? _aCarregar;

  ConfigAgendar get config => _config;
  bool get ligado => _config.ligado;

  /// Quanto tempo a configuração lida vale antes de se voltar a perguntar.
  static const Duration validade = Duration(minutes: 5);

  /// Lê a configuração do servidor (cache de 5 min; chamadas em simultâneo
  /// partilham o mesmo pedido). Qualquer erro devolve a configuração atual
  /// (por defeito DESLIGADA): nunca lança.
  Future<ConfigAgendar> carregarConfig({bool forcar = false, DateTime? agora}) {
    final t = agora ?? DateTime.now();
    final fresca = _configEm != null && t.difference(_configEm!) < validade;
    if (!forcar && fresca) return Future.value(_config);
    return _aCarregar ??= _ler(t).whenComplete(() => _aCarregar = null);
  }

  Future<ConfigAgendar> _ler(DateTime t) async {
    try {
      final nova = await api.config();
      _configEm = t;
      if (nova.ligado != _config.ligado ||
          nova.maxDias != _config.maxDias ||
          nova.antecedenciaMin != _config.antecedenciaMin) {
        _config = nova;
        if (!nova.ligado) _escolha = null;
        // As janelas dependem da configuração: volta-se a perguntar às lojas.
        _lojas.clear();
        notifyListeners();
      }
    } catch (e) {
      // Sem rede ou função ainda por aplicar: fica como estava (desligado de origem).
      debugPrint('AgendarPedidoEstado: config indisponível ($e)');
    }
    return _config;
  }

  // ── Que lojas aceitam pedidos agendados (30/10/2026) ──────────────────────
  // Decide o SERVIDOR, pelas janelas (`scheduled_windows_for_store`), e não o
  // `isPartner`: desde 30/10 os mercados e as lojas não parceiras também têm
  // janelas; festas, loja offline, "em breve" e não aprovadas continuam sem
  // nenhuma. Interruptor desligado = sem janelas.
  final Map<String, ({DateTime em, DateTime? primeiroDia})> _lojas = {};
  final Map<String, Future<bool>> _aVerificar = {};

  /// A loja tem janelas nos próximos dias? `null` = ainda não se sabe (ou a
  /// última pergunta falhou): quem chama trata como "não".
  bool? lojaTemJanelas(String? restaurantId) {
    if (restaurantId == null) return null;
    final r = _lojas[restaurantId];
    return r == null ? null : r.primeiroDia != null;
  }

  /// O primeiro dia (Lisboa, meia-noite UTC) em que o servidor deu janelas.
  DateTime? primeiroDiaComJanelas(String? restaurantId) =>
      restaurantId == null ? null : _lojas[restaurantId]?.primeiroDia;

  /// Pergunta ao servidor, dia a dia a partir de hoje, até ao primeiro com
  /// janelas (normalmente 1 ou 2 perguntas). A resposta vale 5 minutos e as
  /// perguntas em simultâneo para a mesma loja partilham o mesmo pedido.
  /// Nunca lança: sem rede fica "não se sabe" e devolve false.
  Future<bool> verificarLoja(String restaurantId, {DateTime? agora, bool forcar = false}) {
    final t = agora ?? DateTime.now();
    final r = _lojas[restaurantId];
    if (!forcar && r != null && t.difference(r.em) < validade) {
      return Future.value(r.primeiroDia != null);
    }
    // Bloco, não seta: o `remove` devolve este mesmo Future e o whenComplete
    // ficaria à espera dele próprio (nunca acabava).
    return _aVerificar[restaurantId] ??= _verificar(restaurantId, t).whenComplete(() {
      _aVerificar.remove(restaurantId);
    });
  }

  Future<bool> _verificar(String restaurantId, DateTime t) async {
    final cfg = await carregarConfig(agora: t);
    // Desligado (ou configuração por ler): nem se pergunta pelas janelas, e
    // não se guarda nada — quando a configuração chegar volta-se a perguntar.
    if (!cfg.ligado) return false;
    final p = paredeLisboa(t);
    final hoje = DateTime.utc(p.year, p.month, p.day);
    DateTime? primeiro;
    try {
      for (var i = 0; i <= cfg.maxDias && primeiro == null; i++) {
        final dia = hoje.add(Duration(days: i));
        if ((await api.janelas(restaurantId, dia)).isNotEmpty) primeiro = dia;
      }
    } catch (e) {
      debugPrint('AgendarPedidoEstado.verificarLoja($restaurantId): $e');
      return lojaTemJanelas(restaurantId) ?? false;
    }
    final antes = _lojas[restaurantId];
    _lojas[restaurantId] = (em: t, primeiroDia: primeiro);
    if (antes == null || antes.primeiroDia != primeiro) notifyListeners();
    return primeiro != null;
  }

  // ── A escolha do cliente ──────────────────────────────────────────────────
  JanelaAgendada? _escolha;
  String? _escolhaLoja;

  JanelaAgendada? get escolha => _escolha;
  String? get escolhaLoja => _escolhaLoja;

  /// A escolha vale para esta loja? (outra loja → não vale, nunca se aplica.)
  bool escolhaPara(String? restaurantId) =>
      _escolha != null && restaurantId != null && _escolhaLoja == restaurantId;

  void escolher(String restaurantId, JanelaAgendada janela) {
    if (_escolha == janela && _escolhaLoja == restaurantId) return;
    _escolha = janela;
    _escolhaLoja = restaurantId;
    notifyListeners();
  }

  void limpar() {
    if (_escolha == null && _escolhaLoja == null) return;
    _escolha = null;
    _escolhaLoja = null;
    notifyListeners();
  }

  /// A frase que segue na nota do pedido para o parceiro (null se não há
  /// escolha válida para esta loja, ou o interruptor está desligado).
  String? notaParaLoja(String? restaurantId) {
    if (!ligado || !escolhaPara(restaurantId)) return null;
    return notaAgendadoParaParceiro(_escolha!);
  }

  // ── Marcar a hora ANTES de criar o pedido (30/10/2026) ────────────────────
  /// Há (ou pode haver) uma marcação deste aparelho no servidor ainda por usar.
  bool _marcacaoNoServidor = false;

  /// Chamado imediatamente ANTES de criar o pedido (dinheiro, MB Way, saldo e
  /// o rascunho do cartão). O `create_order` de sempre não muda: o servidor
  /// aplica a hora marcada ao pedido deste cliente nesta loja.
  ///
  /// * "Agendar" (escolha válida para esta loja e interruptor ligado):
  ///   `client_preparar_agendamento(loja, início da janela)`. Uma segunda
  ///   tentativa só se faltar a rede. Devolve `null` se ficou marcado, ou o
  ///   código do erro ([kErrosAgendarConhecidos] ou [kErroAgendarRede]) —
  ///   nesse caso o pedido NÃO deve ser criado (nasceria "para agora").
  /// * "Entregar agora": `client_preparar_agendamento(loja, null)` para não
  ///   ficar marcação velha (só com o interruptor ligado ou se este aparelho
  ///   marcou alguma). Nunca trava: devolve sempre `null`.
  /// * Favores, envios, recolha (takeaway) ou sem loja: não faz nada.
  Future<String?> prepararAntesDeCriar({
    required String? restaurantId,
    required OrderServiceType tipo,
    Duration pausa = const Duration(milliseconds: 500),
  }) async {
    if (restaurantId == null ||
        (tipo != OrderServiceType.restaurant &&
            tipo != OrderServiceType.storeShopping)) {
      return null;
    }
    if (ligado && escolhaPara(restaurantId)) {
      final instante = _escolha!.instante;
      var codigo = kErroAgendarRede;
      for (var i = 0; i < 2; i++) {
        try {
          await marcacao.preparar(restaurantId, instante);
          _marcacaoNoServidor = true;
          return null;
        } catch (e) {
          codigo = codigoErroAgendar(e);
          debugPrint('AgendarPedidoEstado.prepararAntesDeCriar tentativa ${i + 1}: $e');
          if (codigo != kErroAgendarRede) break;
          if (i == 0) await Future<void>.delayed(pausa);
        }
      }
      return codigo;
    }
    if (ligado || _marcacaoNoServidor) {
      try {
        await marcacao.preparar(restaurantId, null);
        _marcacaoNoServidor = false;
      } catch (e) {
        debugPrint('AgendarPedidoEstado: apagar a marcação falhou (não-fatal): $e');
      }
    }
    return null;
  }

  /// Depois de o pedido ser criado: confirma que ficou com a hora. Normalmente
  /// o servidor já a gravou ao criar (marcação prévia); só se o pedido ainda
  /// não tiver `scheduled_for` (ou não se conseguir ler) é que se chama a
  /// reserva `client_set_order_schedule`. Sem escolha para esta loja, ou com o
  /// interruptor desligado, não faz nada e devolve true. A reserva tenta 3
  /// vezes; se falhar devolve false (a hora segue na nota do pedido para o
  /// parceiro ver). Limpa a escolha quando acaba, com sucesso ou não: o
  /// carrinho foi-se.
  Future<bool> gravarEscolha(
    String orderId, {
    required String? restaurantId,
    Duration pausa = const Duration(milliseconds: 600),
  }) async {
    if (!ligado || !escolhaPara(restaurantId)) return true;
    final janela = _escolha!;
    try {
      if (await marcacao.horaDoPedido(orderId) != null) {
        _marcacaoNoServidor = false;
        limpar();
        return true;
      }
    } catch (e) {
      debugPrint('AgendarPedidoEstado.gravarEscolha: não deu para ler a hora ($e)');
    }
    var ok = false;
    for (var i = 0; i < 3 && !ok; i++) {
      try {
        await api.gravar(orderId, janela.instante);
        ok = true;
      } catch (e) {
        debugPrint('AgendarPedidoEstado.gravarEscolha tentativa ${i + 1}: $e');
        if (i < 2) await Future<void>.delayed(pausa);
      }
    }
    limpar();
    return ok;
  }
}
