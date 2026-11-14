// Fila de pedidos do estafeta (adenda 1 do Danilo, 14/11/2026 16:45).
//
// Cicatriz (14/11/2026, pedidos b2b746d7 · Auchan e 09ee41da · Favor): a meio
// da compra no mercado o estafeta aceitou um Favor e a app trocou de pedido.
//
// Regra do Danilo:
// - O pedido EM CURSO fica no ecrã. O que ele aceitar por cima fica EM ESPERA:
//   não aparece nem troca o pedido; só aparece depois de ele ENTREGAR o atual,
//   e aí abre com aviso.
// - Em curso = o que ele aceitou quando estava livre (o servidor guarda-o em
//   estafeta_pedido_em_curso). Quando o entrega, o seguinte da fila passa a
//   em curso: o já recolhido; senão o da mesma loja (a volta continua); senão
//   Favor URGENTE (errand_speed 'express', ~10 €) → entregas → Favor normal,
//   e dentro de cada grupo pela hora de aceitação.
// - Pedidos da MESMA loja do em curso seguem juntos (o agrupamento que já
//   existia: DriverCapacityService) e o que já está recolhido nunca se esconde.
//
// GÉMEO no servidor: public.fila_do_estafeta / _fila_proximo_em_curso (migração
// 20261114190000_compra_guardada_e_fila_estafeta.sql) — o painel e o aviso ao
// cliente usam esse. Mudar um = mudar o outro (testes nos dois lados).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';
import 'compra_rascunho_service.dart';

class FilaEstafeta {
  const FilaEstafeta._(this.ativos, this.emEspera);

  /// No ecrã agora: o em curso à cabeça (+ mesma loja / já recolhidos).
  final List<OrderModel> ativos;

  /// À espera, já pela ordem em que vão abrir.
  final List<OrderModel> emEspera;

  OrderModel? get emCurso => ativos.isEmpty ? null : ativos.first;

  static const FilaEstafeta vazia = FilaEstafeta._([], []);

  static bool _ehFavor(OrderModel o) => o.serviceType == OrderServiceType.errand;

  static bool _recolhido(OrderModel o) =>
      o.status == OrderStatus.pickedUp || o.status == OrderStatus.onTheWay;

  static bool _ativoNaFila(OrderModel o) =>
      o.status == OrderStatus.driverAccepted || _recolhido(o);

  static DateTime aceite(OrderModel o) => o.driverAssignedAt ?? o.createdAt;

  /// 1 = Favor urgente · 2 = entrega · 3 = Favor normal.
  static int classe(OrderModel o) {
    if (!_ehFavor(o)) return 2;
    return (o.errandSpeed ?? 'normal') == 'express' ? 1 : 3;
  }

  static int _porAceite(OrderModel a, OrderModel b) {
    final c = aceite(a).compareTo(aceite(b));
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  static int _porFila(OrderModel a, OrderModel b) {
    final c = classe(a) - classe(b);
    return c != 0 ? c : _porAceite(a, b);
  }

  /// [meus] = os pedidos atribuídos a este estafeta (OrderStore.myOrders).
  /// [emCursoId] = o em curso (do servidor, ou o último deste telemóvel);
  /// se já não estiver ativo, escolhe-se o seguinte como o servidor faz.
  /// [lojaAnterior] = loja do em curso que acabou (a volta continua).
  static FilaEstafeta calcular(
    List<OrderModel> meus, {
    String? emCursoId,
    String? lojaAnterior,
    bool Function(String orderId)? compraComecada,
  }) {
    final lista = meus.where(_ativoNaFila).toList();
    if (lista.isEmpty) return vazia;

    OrderModel? ancora =
        emCursoId == null ? null : lista.where((o) => o.id == emCursoId).firstOrNull;
    if (ancora == null) {
      final ordenados = [...lista]..sort((a, b) {
          final ra = _recolhido(a) ? 0 : 1;
          final rb = _recolhido(b) ? 0 : 1;
          if (ra != rb) return ra - rb;
          // compra já começada (servidor: rascunho com marcações)
          final ca = (compraComecada?.call(a.id) ?? false) ? 0 : 1;
          final cb = (compraComecada?.call(b.id) ?? false) ? 0 : 1;
          if (ca != cb) return ca - cb;
          bool mesma(OrderModel o) =>
              !_ehFavor(o) && lojaAnterior != null && o.restaurantId == lojaAnterior;
          final la = mesma(a) ? 0 : 1;
          final lb = mesma(b) ? 0 : 1;
          if (la != lb) return la - lb;
          return _porFila(a, b);
        });
      ancora = ordenados.first;
    }
    final a = ancora;

    bool ativo(OrderModel o) {
      if (o.id == a.id) return true;
      if (_recolhido(o)) return true;
      return !_ehFavor(o) &&
          !_ehFavor(a) &&
          o.restaurantId != null &&
          o.restaurantId == a.restaurantId;
    }

    final ativos = lista.where((o) => ativo(o) && o.id != a.id).toList()
      ..sort(_porAceite)
      ..insert(0, a);
    final espera = lista.where((o) => !ativo(o)).toList()..sort(_porFila);
    return FilaEstafeta._(ativos, espera);
  }

  // ── o em curso entre desenhos (telemóvel) e o do servidor ───────────────
  static String? _emCursoServidor;
  static String? _emCursoMemoria;
  static String? _lojaMemoria;
  static String? _chaveLidaDoServidor;
  static DateTime? _falhaEm;

  @visibleForTesting
  static void limparParaTeste() {
    _emCursoServidor = null;
    _emCursoMemoria = null;
    _lojaMemoria = null;
    _chaveLidaDoServidor = null;
    _falhaEm = null;
  }

  /// A fila deste estafeta, a usar nos ecrãs: o em curso do servidor quando o
  /// há; senão o último que este telemóvel mostrou; senão a regra de recurso.
  static FilaEstafeta doEstafeta(List<OrderModel> meus) {
    final f = calcular(
      meus,
      emCursoId: _emCursoServidor != null &&
              meus.any((o) => o.id == _emCursoServidor && _ativoNaFila(o))
          ? _emCursoServidor
          : _emCursoMemoria,
      lojaAnterior: _lojaMemoria,
      compraComecada: CompraRascunhoService.temCompraEmCurso,
    );
    final cur = f.emCurso;
    if (cur != null && cur.id != _emCursoMemoria) {
      _emCursoMemoria = cur.id;
      _lojaMemoria = _ehFavor(cur) ? null : cur.restaurantId;
      unawaited(_gravarMemoria());
    }
    return f;
  }

  // Revisão 14/11: a app reiniciada sem resposta do servidor não pode
  // esquecer o em curso (escondia a compra a meio) — fica no telemóvel.
  static const String _chaveMemoria = 'bora.fila_estafeta.em_curso.v1';

  /// Ao abrir o mapa/início: o em curso que este telemóvel guardou.
  /// true = havia (o ecrã redesenha).
  static Future<bool> carregarMemoria() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_chaveMemoria);
      if (v == null || v.isEmpty || _emCursoMemoria != null) return false;
      final partes = v.split('|');
      _emCursoMemoria = partes.first;
      _lojaMemoria = partes.length > 1 && partes[1].isNotEmpty ? partes[1] : null;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _gravarMemoria() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _chaveMemoria, '${_emCursoMemoria ?? ''}|${_lojaMemoria ?? ''}');
    } catch (_) {}
  }

  /// Pergunta ao servidor qual é o em curso (estafeta_minha_fila), uma vez por
  /// mudança nos pedidos. true = mudou (o ecrã redesenha).
  static Future<bool> atualizarDoServidor(List<OrderModel> meus) async {
    final chave = (meus.where(_ativoNaFila).map((o) => '${o.id}:${o.status.name}').toList()
          ..sort())
        .join(',');
    final falha = _falhaEm;
    if (chave == _chaveLidaDoServidor &&
        (falha == null ||
            DateTime.now().difference(falha) < const Duration(seconds: 60))) {
      return false;
    }
    _chaveLidaDoServidor = chave;
    _falhaEm = null;
    if (chave.isEmpty) {
      final mudou = _emCursoServidor != null;
      _emCursoServidor = null;
      return mudou;
    }
    try {
      final res = await Supabase.instance.client
          .rpc('estafeta_minha_fila')
          .timeout(const Duration(seconds: 8));
      // Os pedidos mudaram enquanto se esperava: esta resposta já é velha
      // (a pergunta seguinte traz a certa).
      if (chave != _chaveLidaDoServidor) return false;
      String? novo;
      if (res is List) {
        for (final r in res) {
          if (r is Map && r['em_curso'] == true) novo = r['order_id']?.toString();
        }
      }
      final mudou = novo != _emCursoServidor;
      _emCursoServidor = novo;
      return mudou;
    } catch (e) {
      // Sem rede / função por publicar: fica a regra do telemóvel e volta a
      // perguntar daqui a um minuto (o mapa redesenha de 3 em 3 s).
      _falhaEm = DateTime.now();
      debugPrint('[FilaEstafeta] estafeta_minha_fila: $e');
      return false;
    }
  }
}
