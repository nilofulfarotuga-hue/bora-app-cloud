// lib/services/loja_online_pagamento_service.dart
//
// Loja Online — pagamento (checkup-geral-15-11, B3.7). Ordem do Danilo 15/11 17:53; AUTORIZO de
// 14/11/2026 12:19: cartão e MB WAY pelo caminho Stripe que já existe, nunca dinheiro.
//
// O preço NUNCA sai daqui: a Edge `loja-online-pagamento` lê-o da base (preco_bora_cents) e
// grava a encomenda. A app só manda o produto, a quantidade, a morada e o método.
// Separado do loja_online_service.dart de propósito: esse ficheiro não toca em pagamentos.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_address.dart';
import 'client_address_service.dart';
import 'loja_online_service.dart';
import 'payment_service.dart';
import 'stripe_contas.dart';

enum LojaOnlineMetodo { cartao, mbway }

extension LojaOnlineMetodoServidor on LojaOnlineMetodo {
  String get servidor => this == LojaOnlineMetodo.mbway ? 'mbway' : 'card';
}

/// Estado de uma encomenda tal como o servidor o grava.
const Set<String> kEncomendaEstadosFinais = {
  'paga',
  'encomendada_fornecedor',
  'enviada',
  'entregue',
};

/// Telemóvel português (9X XXX XXXX) → 9 algarismos, ou null.
String? lojaOnlineTelemovel(String bruto) {
  var s = bruto.replaceAll(RegExp(r'[\s().-]'), '');
  if (s.startsWith('+351')) s = s.substring(4);
  if (s.startsWith('00351')) s = s.substring(5);
  return RegExp(r'^9[1236][0-9]{7}$').hasMatch(s) ? s : null;
}

/// Código postal português 1234-567 (aceita "1234567" e devolve com hífen), ou null.
String? lojaOnlineCodigoPostal(String bruto) {
  final s = bruto.replaceAll(' ', '');
  final m = RegExp(r'^([0-9]{4})-?([0-9]{3})$').firstMatch(s);
  return m == null ? null : '${m.group(1)}-${m.group(2)}';
}

/// loja-nichos-15-11 (C): código postal e localidade de uma morada escrita ou
/// escolhida nas sugestões ("Rua X 5, 6300-123 Guarda, Portugal").
({String? codigoPostal, String? localidade}) lojaOnlinePartesDaMorada(
    String morada) {
  final m = RegExp(r'([0-9]{4})-?([0-9]{3})\s*([^,0-9][^,]*)?').firstMatch(morada);
  if (m == null) return (codigoPostal: null, localidade: null);
  final loc = (m.group(3) ?? '').trim();
  return (
    codigoPostal: '${m.group(1)}-${m.group(2)}',
    localidade: loc.isEmpty ? null : loc,
  );
}

/// O que a app já sabe do cliente para encher o pagamento sozinho.
class LojaOnlinePerfil {
  const LojaOnlinePerfil({this.nome = '', this.telefone = '', this.moradas = const []});
  final String nome;
  final String telefone;

  /// Moradas guardadas (a predefinida primeiro), as mesmas dos pedidos.
  final List<ClientAddress> moradas;
}

/// Lê as moradas guardadas. Nunca lança: sem sessão ou sem rede, lista vazia.
Future<List<ClientAddress>> lojaOnlineMoradasGuardadas() async {
  try {
    return await ClientAddressService.instance.list();
  } catch (e) {
    debugPrint('[LojaOnline] moradas guardadas: $e');
    return const [];
  }
}

/// O que falta preencher (frases em PT-PT, já prontas para .tr). Vazio = pode pagar.
List<String> lojaOnlineFaltas({
  required String nome,
  required String telefone,
  required String morada,
  required String codigoPostal,
  required String localidade,
}) {
  final f = <String>[];
  if (nome.trim().length < 3) f.add('Escreve o teu nome completo.');
  if (lojaOnlineTelemovel(telefone) == null) {
    f.add('Escreve um telemóvel português válido.');
  }
  if (morada.trim().length < 5) f.add('Escreve a morada com rua e número.');
  if (lojaOnlineCodigoPostal(codigoPostal) == null) {
    f.add('O código postal tem de ser 1234-567.');
  }
  if (localidade.trim().length < 2) f.add('Escreve a localidade.');
  return f;
}

class LojaOnlinePedidoPagamento {
  const LojaOnlinePedidoPagamento({
    required this.produtoId,
    required this.quantidade,
    required this.metodo,
    required this.nome,
    required this.telefone,
    required this.morada,
    required this.codigoPostal,
    required this.localidade,
    this.email,
  });

  final String produtoId;
  final int quantidade;
  final LojaOnlineMetodo metodo;
  final String nome;
  final String telefone;
  final String morada;
  final String codigoPostal;
  final String localidade;
  final String? email;

  Map<String, dynamic> corpo() => StripeContas.marcar({
        'acao': 'criar',
        'produto_id': produtoId,
        'quantidade': quantidade,
        'metodo': metodo.servidor,
        'nome': nome.trim(),
        'telefone': lojaOnlineTelemovel(telefone) ?? telefone,
        'email': email,
        'morada': morada.trim(),
        'codigo_postal': lojaOnlineCodigoPostal(codigoPostal) ?? codigoPostal,
        'localidade': localidade.trim(),
      });
}

/// Frase para o cliente a partir do erro devolvido pela Edge.
String lojaOnlineErroPagamento(String? erro) {
  switch (erro) {
    case 'loja_fechada':
      return 'A loja ainda não está aberta.';
    case 'produto_indisponivel':
      return 'Este produto já não está disponível.';
    case 'telefone_invalido':
      return 'Escreve um telemóvel português válido.';
    case 'morada_incompleta':
      return 'Falta completar a morada de envio.';
    case 'quantidade_invalida':
      return 'Podes encomendar de 1 a 5 unidades.';
    case 'pagamento_recusado':
      return 'O pagamento foi recusado. Não te foi cobrado nada. Tenta outra vez ou escolhe outro método.';
    case 'demasiadas_tentativas':
      return 'Tens pagamentos à espera. Espera uns minutos e tenta outra vez.';
    default:
      return 'Não foi possível iniciar o pagamento. Tenta outra vez.';
  }
}

typedef InvocarFn = Future<Map<String, dynamic>?> Function(
    String funcao, Map<String, dynamic> corpo);

class LojaOnlinePagamentoService {
  LojaOnlinePagamentoService({InvocarFn? invocar, PaymentService? pagamentos})
      : _invocar = invocar ?? _invocarNoSupabase,
        _pagamentos = pagamentos;

  final InvocarFn _invocar;
  final PaymentService? _pagamentos;

  /// Cria a encomenda e o pagamento. Devolve a resposta da Edge (encomenda_id, clientSecret...).
  /// Lança [StateError] com a frase para o cliente.
  Future<Map<String, dynamic>> criar(LojaOnlinePedidoPagamento p) async {
    final r = await _invocar(kLojaOnlineEdgePagamento, p.corpo());
    if (r == null || r['ok'] != true || r['encomenda_id'] == null) {
      throw StateError(lojaOnlineErroPagamento(r?['error']?.toString()));
    }
    return r;
  }

  /// Cartão: abre a folha da Stripe (telemóvel) ou o Payment Element (web) na conta devolvida.
  Future<void> pagarComCartao(Map<String, dynamic> criado) async {
    final segredo = criado['clientSecret'] as String?;
    if (segredo == null) throw StateError(lojaOnlineErroPagamento(null));
    await (_pagamentos ?? PaymentService()).processPayment(
      segredo,
      vertical: 'loja_online',
      referenciaId: criado['encomenda_id'] as String?,
      paymentIntentId: criado['paymentIntentId'] as String?,
      publishableKey: StripeContas.chaveDaResposta(criado),
    );
  }

  /// Pergunta ao servidor (que pergunta à Stripe) como está o pagamento. Devolve o estado.
  Future<String> confirmar(String encomendaId) async {
    final r = await _invocar(kLojaOnlineEdgePagamento, {
      'acao': 'confirmar',
      'encomenda_id': encomendaId,
    });
    return (r?['estado'] ?? 'aguarda_pagamento').toString();
  }

  /// Repete [confirmar] até ficar paga, falhar ou acabar o tempo.
  Future<String> esperarPagamento(
    String encomendaId, {
    Duration intervalo = const Duration(seconds: 4),
    Duration limite = const Duration(minutes: 5),
  }) async {
    final fim = DateTime.now().add(limite);
    var estado = 'aguarda_pagamento';
    while (DateTime.now().isBefore(fim)) {
      try {
        estado = await confirmar(encomendaId);
      } catch (e) {
        debugPrint('[LojaOnlinePagamento] confirmar: $e');
      }
      if (kEncomendaEstadosFinais.contains(estado) ||
          estado == 'falhou_pagamento' ||
          estado == 'cancelada') {
        return estado;
      }
      await Future<void>.delayed(intervalo);
    }
    return estado;
  }

  static Future<Map<String, dynamic>?> _invocarNoSupabase(
      String funcao, Map<String, dynamic> corpo) async {
    try {
      final r =
          await Supabase.instance.client.functions.invoke(funcao, body: corpo);
      final d = r.data;
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } on FunctionException catch (e) {
      final d = e.details;
      return d is Map ? Map<String, dynamic>.from(d) : {'error': '$d'};
    }
  }
}

/// As encomendas do próprio cliente (a RLS só deixa ver as suas).
Future<List<Map<String, dynamic>>> lojaOnlineMinhasEncomendas() async {
  final r = await Supabase.instance.client
      .from(kLojaOnlineTabelaEncomendas)
      .select(
          'id, titulo, quantidade, total_cents, estado, prazo_min_dias, prazo_max_dias, tracking, criado_em')
      .order('criado_em', ascending: false)
      .limit(50);
  return List<Map<String, dynamic>>.from(r);
}

/// Estado da encomenda em frase curta para o cliente (PT-PT, passa por .tr no ecrã).
String lojaOnlineEstadoCliente(String estado) {
  switch (estado) {
    case 'aguarda_pagamento':
      return 'À espera do pagamento';
    case 'paga':
      return 'Paga, a preparar';
    case 'encomendada_fornecedor':
      return 'A caminho do armazém';
    case 'enviada':
      return 'Enviada pelo correio';
    case 'entregue':
      return 'Entregue';
    case 'falhou_pagamento':
      return 'Pagamento não concluído';
    case 'cancelada':
      return 'Cancelada';
    default:
      return estado;
  }
}
