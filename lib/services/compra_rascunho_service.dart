// Compra guardada — cada toque do estafeta fica gravado (14/11/2026).
//
// Cicatriz (14/11/2026 16:32, pedido b2b746d7 · Auchan): o estafeta já tinha
// comprado tudo, trocado as pizzas e marcado o queijo em falta; entrou um Favor,
// a app trocou de pedido e TUDO o que ele marcou desapareceu. A lista de
// compras só vivia na memória da folha aberta por cima do mapa.
//
// Agora cada marcação (comprado, não há, produto acrescentado/trocado com o
// preço, sacos, valor do talão, foto do talão) é gravada:
//   1. logo no telemóvel (SharedPreferences — também na web), e
//   2. no servidor (`estafeta_guardar_progresso_compra`), com tentativas
//      repetidas e uma fila: sem rede, fica no telemóvel e sobe sozinha.
// Ao abrir a lista lê-se o mais recente dos dois. Um número crescente (`seq`)
// garante que uma gravação atrasada nunca apaga uma mais nova.
//
// NÃO mexe em dinheiro: o fecho continua a ser `finalizar_talao_nao_parceiro`
// com a mesma conta. Isto só guarda e lê o progresso.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';

/// O que a folha mostra, discretamente, ao lado do progresso.
enum EstadoGravacaoCompra { nada, aGuardar, guardado, soNoTelemovel }

/// Uma linha da lista original (orders.items): estado e quantidade.
@immutable
class ItemRascunho {
  const ItemRascunho({required this.estado, required this.quantidade});

  /// 'bought' | 'unavailable' | 'pending'
  final String estado;
  final int quantidade;

  Map<String, dynamic> toJson() => {'s': estado, 'q': quantidade};

  static ItemRascunho? fromJson(Object? v) {
    if (v is! Map) return null;
    final s = v['s']?.toString();
    if (s != 'bought' && s != 'unavailable' && s != 'pending') return null;
    final q = v['q'];
    return ItemRascunho(estado: s!, quantidade: q is num ? q.toInt() : 1);
  }
}

/// Produto acrescentado pelo estafeta (troca ou extra), com o preço da
/// prateleira que ele escreveu.
@immutable
class ExtraRascunho {
  const ExtraRascunho({
    required this.id,
    required this.nome,
    required this.precoCents,
    required this.quantidade,
    required this.estado,
  });

  final String id;
  final String nome;
  final int precoCents;
  final int quantidade;
  final String estado;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'preco_cents': precoCents,
        'qtd': quantidade,
        's': estado,
      };

  static ExtraRascunho? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id']?.toString() ?? '';
    final nome = v['nome']?.toString() ?? '';
    if (id.isEmpty || nome.isEmpty) return null;
    final p = v['preco_cents'];
    final q = v['qtd'];
    final s = v['s']?.toString();
    return ExtraRascunho(
      id: id,
      nome: nome,
      precoCents: p is num ? p.toInt() : 0,
      quantidade: q is num ? q.toInt() : 1,
      estado: (s == 'pending' || s == 'unavailable') ? s! : 'bought',
    );
  }
}

@immutable
class RascunhoCompra {
  const RascunhoCompra({
    required this.orderId,
    required this.itens,
    required this.extras,
    required this.seq,
    this.sacos,
    this.totalTalaoCents,
    this.fotoPath,
    this.pendente = true,
    this.atualizadoEm,
  });

  final String orderId;

  /// chave "<productId>#<n>" → estado da linha (ver [chavesDosItens]).
  final Map<String, ItemRascunho> itens;
  final List<ExtraRascunho> extras;
  final int? sacos;
  final int? totalTalaoCents;
  final String? fotoPath;

  /// Número crescente do telemóvel (milissegundos, nunca repete).
  final int seq;

  /// true enquanto o servidor ainda não confirmou ESTA versão.
  final bool pendente;
  final DateTime? atualizadoEm;

  int get marcados =>
      itens.values.where((i) => i.estado != 'pending').length +
      extras.length;

  bool get temProgresso =>
      marcados > 0 || totalTalaoCents != null || (fotoPath ?? '').isNotEmpty;

  RascunhoCompra copiar({
    bool? pendente,
    int? totalTalaoCents,
    String? fotoPath,
    DateTime? atualizadoEm,
  }) =>
      RascunhoCompra(
        orderId: orderId,
        itens: itens,
        extras: extras,
        seq: seq,
        sacos: sacos,
        totalTalaoCents: totalTalaoCents ?? this.totalTalaoCents,
        fotoPath: fotoPath ?? this.fotoPath,
        pendente: pendente ?? this.pendente,
        atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      );

  Map<String, dynamic> toJson() => {
        'order_id': orderId,
        'itens': itens.map((k, v) => MapEntry(k, v.toJson())),
        'extras': extras.map((e) => e.toJson()).toList(),
        'seq': seq,
        if (sacos != null) 'sacos': sacos,
        if (totalTalaoCents != null) 'total_talao_cents': totalTalaoCents,
        if (fotoPath != null) 'foto': fotoPath,
        'pendente': pendente,
        if (atualizadoEm != null) 'atualizado_em': atualizadoEm!.toIso8601String(),
      };

  /// Lê tanto a cópia do telemóvel como a linha do servidor
  /// (`order_purchase_drafts`: client_seq, bag_count, receipt_*).
  static RascunhoCompra? fromJson(Object? raw, {bool? pendente}) {
    if (raw is! Map) return null;
    final orderId = (raw['order_id'] ?? '').toString();
    if (orderId.isEmpty) return null;
    final itens = <String, ItemRascunho>{};
    final rawItens = raw['itens'];
    if (rawItens is Map) {
      rawItens.forEach((k, v) {
        final it = ItemRascunho.fromJson(v);
        if (it != null) itens[k.toString()] = it;
      });
    }
    final extras = <ExtraRascunho>[];
    final rawExtras = raw['extras'];
    if (rawExtras is List) {
      for (final e in rawExtras) {
        final x = ExtraRascunho.fromJson(e);
        if (x != null) extras.add(x);
      }
    }
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final seq = asInt(raw['seq'] ?? raw['client_seq']) ?? 0;
    final quando = raw['atualizado_em'] ?? raw['updated_at'];
    final foto = (raw['foto'] ?? raw['receipt_photo_path'])?.toString();
    return RascunhoCompra(
      orderId: orderId,
      itens: itens,
      extras: extras,
      seq: seq,
      sacos: asInt(raw['sacos'] ?? raw['bag_count']),
      totalTalaoCents: asInt(raw['total_talao_cents'] ?? raw['receipt_total_cents']),
      fotoPath: (foto == null || foto.isEmpty) ? null : foto,
      pendente: pendente ?? (raw['pendente'] == true),
      atualizadoEm: quando == null ? null : DateTime.tryParse(quando.toString()),
    );
  }

  /// A versão a usar entre a do telemóvel e a do servidor: a que tem o `seq`
  /// maior; empate → a do servidor (confirmada). Uma cópia local ainda por
  /// enviar só perde para uma do servidor MAIS NOVA (outro telemóvel).
  static RascunhoCompra? escolher(RascunhoCompra? local, RascunhoCompra? servidor) {
    if (local == null) return servidor;
    if (servidor == null) return local;
    return local.seq > servidor.seq ? local : servidor;
  }
}

/// Chave estável de cada linha da lista original: "<productId>#<n>", n = 0 na
/// primeira vez que o produto aparece, 1 na segunda (mesmo produto com opções
/// diferentes). O servidor usa a mesma regra (`_rascunho_compra_itens_fecho`).
List<String> chavesDosItens(List<CartItem> canonicos) {
  final vistos = <String, int>{};
  return [
    for (final i in canonicos)
      () {
        final n = vistos[i.productId] ?? 0;
        vistos[i.productId] = n + 1;
        return '${i.productId}#$n';
      }(),
  ];
}

bool ehExtraDoEstafeta(CartItem i) => i.productId.startsWith('extra_');

/// Monta o rascunho a partir do que está no ecrã.
RascunhoCompra rascunhoDoEcra({
  required String orderId,
  required List<CartItem> itens,
  required int seq,
  int? sacos,
  int? totalTalaoCents,
  String? fotoPath,
}) {
  final canonicos = itens.where((i) => !ehExtraDoEstafeta(i)).toList();
  final chaves = chavesDosItens(canonicos);
  return RascunhoCompra(
    orderId: orderId,
    itens: {
      for (var k = 0; k < canonicos.length; k++)
        chaves[k]: ItemRascunho(
          estado: canonicos[k].purchaseStatus,
          quantidade: canonicos[k].quantity,
        ),
    },
    extras: [
      for (final e in itens.where(ehExtraDoEstafeta))
        ExtraRascunho(
          id: e.productId,
          nome: e.name,
          precoCents: (e.price * 100).round(),
          quantidade: e.quantity,
          estado: e.purchaseStatus,
        ),
    ],
    seq: seq,
    sacos: sacos,
    totalTalaoCents: totalTalaoCents,
    fotoPath: fotoPath,
  );
}

/// Repõe no ecrã o que estava marcado. Devolve a lista nova (originais com o
/// estado gravado + acrescentados). Linhas que o rascunho não conhece ficam
/// como vieram (ex.: a loja mudou a lista entretanto).
List<CartItem> aplicarRascunho(List<CartItem> canonicos, RascunhoCompra r) {
  final chaves = chavesDosItens(canonicos);
  final out = <CartItem>[];
  for (var k = 0; k < canonicos.length; k++) {
    final item = canonicos[k];
    final gravado = r.itens[chaves[k]];
    if (gravado != null) item.purchaseStatus = gravado.estado;
    out.add(item);
  }
  for (final e in r.extras) {
    out.add(CartItem(
      productId: e.id,
      name: e.nome,
      price: e.precoCents / 100.0,
      quantity: e.quantidade < 1 ? 1 : e.quantidade,
      purchaseStatus: e.estado,
    ));
  }
  return out;
}

/// Resultado de uma ida ao servidor.
enum _Envio { ok, fechado, falhou, atrasado }

class CompraRascunhoService {
  CompraRascunhoService._();

  static const String rpcGuardar = 'estafeta_guardar_progresso_compra';
  static const String rpcLer = 'estafeta_ler_progresso_compra';
  static const String _prefixo = 'bora.compra_rascunho.v1.';
  static const Duration _limiteRede = Duration(seconds: 8);
  static const Duration _guardarLocalMax = Duration(days: 3);

  static final Map<String, ValueNotifier<EstadoGravacaoCompra>> _estados = {};
  static final Map<String, RascunhoCompra> _memoria = {};
  static final Set<String> _aEnviar = <String>{};
  static final Map<String, Timer> _reenvio = {};
  static final Map<String, int> _falhasSeguidas = {};

  /// Pedidos cuja lista de compras o estafeta abriu nesta sessão — o mapa
  /// nunca lhes tira o foco sozinho.
  static final Set<String> _comprasAbertas = <String>{};

  static int _ultimoSeq = 0;

  /// Só para testes: trocam o envio ao servidor e a leitura do servidor.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic> params)?
      enviarParaTeste;
  @visibleForTesting
  static Future<Object?> Function(String orderId)? lerParaTeste;

  @visibleForTesting
  static void limparParaTeste() {
    _estados.clear();
    _memoria.clear();
    _aEnviar.clear();
    for (final t in _reenvio.values) {
      t.cancel();
    }
    _reenvio.clear();
    _falhasSeguidas.clear();
    _comprasAbertas.clear();
    _ultimoSeq = 0;
  }

  static ValueNotifier<EstadoGravacaoCompra> estado(String orderId) =>
      _estados.putIfAbsent(
          orderId, () => ValueNotifier(EstadoGravacaoCompra.nada));

  static int proximoSeq() {
    final agora = DateTime.now().millisecondsSinceEpoch;
    _ultimoSeq = math.max(agora, _ultimoSeq + 1);
    return _ultimoSeq;
  }

  static void marcarCompraAberta(String orderId) => _comprasAbertas.add(orderId);

  /// Compra em curso neste telemóvel: a lista foi aberta ou já tem marcações.
  static bool temCompraEmCurso(String orderId) =>
      _comprasAbertas.contains(orderId) ||
      (_memoria[orderId]?.temProgresso ?? false);

  /// O rascunho que está em memória (síncrono, para o 1.º desenho da folha).
  static RascunhoCompra? emMemoria(String orderId) => _memoria[orderId];

  /// Cada toque: grava já no telemóvel e manda para o servidor.
  static Future<void> guardar(RascunhoCompra r) async {
    final pend = r.copiar(pendente: true, atualizadoEm: DateTime.now());
    _memoria[r.orderId] = pend;
    estado(r.orderId).value = EstadoGravacaoCompra.aGuardar;
    await _gravarLocal(pend);
    unawaited(_enviar(r.orderId));
  }

  /// O talão (valor e/ou caminho da foto no servidor) entra no rascunho.
  static Future<void> guardarTalao(
    String orderId, {
    int? totalCents,
    String? fotoPath,
  }) async {
    final atual = _memoria[orderId] ?? await _lerLocal(orderId);
    if (atual == null) return;
    await guardar(RascunhoCompra(
      orderId: orderId,
      itens: atual.itens,
      extras: atual.extras,
      seq: proximoSeq(),
      sacos: atual.sacos,
      totalTalaoCents: totalCents ?? atual.totalTalaoCents,
      fotoPath: fotoPath ?? atual.fotoPath,
    ));
  }

  /// Fica com o rascunho de `seq` maior entre o que está em memória e [r].
  /// Nunca troca um mais novo por um mais velho (revisão 14/11: uma leitura
  /// lenta do servidor apagava o toque dado entretanto).
  static RascunhoCompra _ficarComOMaisNovo(RascunhoCompra r) {
    _ultimoSeq = math.max(_ultimoSeq, r.seq);
    final atual = _memoria[r.orderId];
    if (atual != null && atual.seq >= r.seq) return atual;
    _memoria[r.orderId] = r;
    return r;
  }

  /// 1.ª fase ao abrir a lista: o que está em memória ou no telemóvel (sem rede,
  /// em milissegundos).
  static Future<RascunhoCompra?> carregarLocal(String orderId) async {
    final emMem = _memoria[orderId];
    if (emMem != null) return emMem;
    final local = await _lerLocal(orderId);
    if (local == null) return null;
    final r = _ficarComOMaisNovo(local);
    if (r.pendente) {
      estado(orderId).value = EstadoGravacaoCompra.soNoTelemovel;
      unawaited(_enviar(orderId));
    }
    return r;
  }

  /// 2.ª fase: o do servidor, SÓ se for mais novo do que o que este telemóvel
  /// já tem (outro telemóvel, ou o telemóvel foi limpo). null = nada de novo.
  static Future<RascunhoCompra?> carregarServidor(String orderId) async {
    Object? res;
    try {
      final ler = lerParaTeste;
      res = ler != null
          ? await ler(orderId)
          : await Supabase.instance.client
              .rpc(rpcLer, params: {'p_order_id': orderId}).timeout(_limiteRede);
    } catch (e) {
      // Sem rede ou função ainda por publicar: vale a cópia do telemóvel.
      debugPrint('[CompraRascunho] ler $orderId: $e');
      return null;
    }
    if (res is! Map || res['ok'] != true) return null;
    if (res['finalized'] == true) {
      await concluir(orderId);
      return null;
    }
    final servidor = RascunhoCompra.fromJson(res['rascunho'], pendente: false);
    if (servidor == null) return null;
    final antes = _memoria[orderId];
    final r = _ficarComOMaisNovo(servidor);
    if (!identical(r, servidor)) return null; // o telemóvel tem um mais novo
    await _gravarLocal(r);
    if (antes == null || !antes.pendente) {
      estado(orderId).value = EstadoGravacaoCompra.guardado;
    }
    return r;
  }

  /// As duas fases juntas (telemóvel e servidor). null = começar do zero.
  static Future<RascunhoCompra?> carregar(String orderId) async {
    final local = await carregarLocal(orderId);
    final servidor = await carregarServidor(orderId);
    return servidor ?? _memoria[orderId] ?? local;
  }

  /// Compra fechada: o rascunho do telemóvel já não serve (o do servidor
  /// fica como histórico para o painel).
  static Future<void> concluir(String orderId) async {
    _memoria.remove(orderId);
    _comprasAbertas.remove(orderId);
    _reenvio.remove(orderId)?.cancel();
    _falhasSeguidas.remove(orderId);
    estado(orderId).value = EstadoGravacaoCompra.nada;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefixo$orderId');
    } catch (_) {}
  }

  /// Ao abrir o mapa / voltar à app: sobe o que ficou só no telemóvel e
  /// apaga cópias com mais de 3 dias.
  static Future<void> reenviarPendentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefixo))) {
        final r = RascunhoCompra.fromJson(_decode(prefs.getString(k)));
        if (r == null) {
          await prefs.remove(k);
          continue;
        }
        final quando = r.atualizadoEm;
        if (quando != null &&
            DateTime.now().difference(quando) > _guardarLocalMax) {
          await prefs.remove(k);
          continue;
        }
        final fica = _ficarComOMaisNovo(r);
        if (fica.pendente) unawaited(_enviar(r.orderId));
      }
    } catch (e) {
      debugPrint('[CompraRascunho] reenviarPendentes: $e');
    }
  }

  // ── envio com fila e tentativas ─────────────────────────────────────────
  static Future<void> _enviar(String orderId) async {
    // Um envio de cada vez por pedido; quem chega a meio deixa o mais recente
    // em memória e o envio em curso repete com ele.
    if (!_aEnviar.add(orderId)) return;
    _reenvio.remove(orderId)?.cancel();
    var reCarimbos = 0;
    try {
      for (var tentativa = 0; tentativa < 3; tentativa++) {
        final r = _memoria[orderId];
        if (r == null || !r.pendente) return;
        final res = await _mandar(r);
        if (res == _Envio.fechado) {
          await concluir(orderId);
          return;
        }
        if (res == _Envio.atrasado && reCarimbos < 2) {
          // O servidor tem um número maior (relógio que andou para trás, outro
          // telemóvel). O que está NESTE ecrã é o último toque: volta a ir com
          // um número acima do do servidor — nunca se mostra "Guardado" falso.
          reCarimbos++;
          final agora = _memoria[orderId] ?? r;
          _memoria[orderId] = RascunhoCompra(
            orderId: agora.orderId,
            itens: agora.itens,
            extras: agora.extras,
            seq: proximoSeq(),
            sacos: agora.sacos,
            totalTalaoCents: agora.totalTalaoCents,
            fotoPath: agora.fotoPath,
            atualizadoEm: DateTime.now(),
          );
          await _gravarLocal(_memoria[orderId]!);
          tentativa = -1;
          continue;
        }
        if (res == _Envio.ok) {
          _falhasSeguidas.remove(orderId);
          final agora = _memoria[orderId];
          if (agora != null && agora.seq == r.seq) {
            final feito = agora.copiar(pendente: false);
            _memoria[orderId] = feito;
            await _gravarLocal(feito);
            estado(orderId).value = EstadoGravacaoCompra.guardado;
            return;
          }
          // Houve um toque durante o envio: manda já o mais recente.
          tentativa = -1;
          continue;
        }
        await Future<void>.delayed(Duration(seconds: 1 + tentativa * 2));
      }
      // Sem rede: fica no telemóvel e volta a tentar sozinho, cada vez mais
      // espaçado (30 s, 1 min, 2 min … até 5 min).
      estado(orderId).value = EstadoGravacaoCompra.soNoTelemovel;
      final n = (_falhasSeguidas[orderId] ?? 0) + 1;
      _falhasSeguidas[orderId] = n;
      final espera = Duration(seconds: math.min(300, 30 * (1 << math.min(n - 1, 4))));
      _reenvio[orderId] = Timer(espera, () => unawaited(_enviar(orderId)));
    } finally {
      _aEnviar.remove(orderId);
    }
  }

  static Future<_Envio> _mandar(RascunhoCompra r) async {
    final params = <String, dynamic>{
      'p_order_id': r.orderId,
      'p_itens': r.itens.map((k, v) => MapEntry(k, v.toJson())),
      'p_extras': r.extras.map((e) => e.toJson()).toList(),
      'p_sacos': r.sacos,
      'p_total_talao_cents': r.totalTalaoCents,
      'p_foto_url': r.fotoPath,
      'p_seq': r.seq,
    };
    try {
      final fn = enviarParaTeste;
      final Object? res = fn != null
          ? await fn(params)
          : await Supabase.instance.client
              .rpc(rpcGuardar, params: params)
              .timeout(_limiteRede);
      if (res is Map && res['ok'] == true) {
        if (res['finalized'] == true) return _Envio.fechado;
        if (res['applied'] == false && res['stale'] == true) {
          final s = res['seq'];
          if (s is num) _ultimoSeq = math.max(_ultimoSeq, s.toInt());
          return _Envio.atrasado;
        }
        return _Envio.ok;
      }
      final erro = res is Map ? res['error']?.toString() : null;
      // Pedido entregue/cancelado ou já não é dele: não há nada a guardar.
      if (erro == 'ORDER_CLOSED' ||
          erro == 'NOT_ASSIGNED_DRIVER' ||
          erro == 'ORDER_NOT_FOUND') {
        return _Envio.fechado;
      }
      debugPrint('[CompraRascunho] servidor recusou ${r.orderId}: $res');
      return _Envio.falhou;
    } catch (e) {
      debugPrint('[CompraRascunho] envio ${r.orderId}: $e');
      return _Envio.falhou;
    }
  }

  // ── cópia no telemóvel ──────────────────────────────────────────────────
  static Object? _decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<RascunhoCompra?> _lerLocal(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return RascunhoCompra.fromJson(_decode(prefs.getString('$_prefixo$orderId')));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _gravarLocal(RascunhoCompra r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefixo${r.orderId}', jsonEncode(r.toJson()));
    } catch (e) {
      debugPrint('[CompraRascunho] gravar no telemóvel ${r.orderId}: $e');
    }
  }
}
