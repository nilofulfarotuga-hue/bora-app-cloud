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
  });

  final String id;
  final String estado;

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
  AgendarPedidoEstado._(this.api);

  /// Só para testes: um estado novo, com a sua porta de mentira.
  @visibleForTesting
  AgendarPedidoEstado.paraTeste(this.api);

  static final AgendarPedidoEstado instance =
      AgendarPedidoEstado._(AgendarPedidoSupabase());

  AgendarPedidoApi api;

  /// Só para testes: volta ao estado de fábrica (desligado, sem escolha) com
  /// outra porta. O estado global é partilhado entre testes.
  @visibleForTesting
  void reporParaTeste(AgendarPedidoApi novaApi) {
    api = novaApi;
    _config = ConfigAgendar.desligado;
    _configEm = null;
    _aCarregar = null;
    _escolha = null;
    _escolhaLoja = null;
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
        notifyListeners();
      }
    } catch (e) {
      // Sem rede ou função ainda por aplicar: fica como estava (desligado de origem).
      debugPrint('AgendarPedidoEstado: config indisponível ($e)');
    }
    return _config;
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

  /// Depois de o pedido ser criado: grava a hora no servidor
  /// (`client_set_order_schedule`). Sem escolha para esta loja, ou com o
  /// interruptor desligado, não faz nada e devolve true. Tenta 3 vezes; se
  /// falhar devolve false (a hora segue na nota do pedido para o parceiro ver).
  /// Limpa a escolha quando acaba, com sucesso ou não: o carrinho foi-se.
  Future<bool> gravarEscolha(
    String orderId, {
    required String? restaurantId,
    Duration pausa = const Duration(milliseconds: 600),
  }) async {
    if (!ligado || !escolhaPara(restaurantId)) return true;
    final janela = _escolha!;
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
