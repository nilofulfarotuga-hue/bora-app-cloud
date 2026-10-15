// lib/services/receita_service.dart
//
// Receita do Dia (Bora Todo Dia, novidade n.º 2 — 15/10/2026).
// Uma receita por dia; tudo vem do servidor:
//  - `client_receita_de_hoje()` → receita de hoje + estado do aviso diário;
//  - `client_receita_aviso(p_ligado)` → liga/desliga o aviso (opt-in);
//  - `assistant_basket_quote` (o mesmo do Bora Assistente) → cota os
//    ingredientes nos supermercados não-parceiros e devolve as propostas,
//    a mais completa e mais barata primeiro.
// Se o servidor estiver desligado, sem a função ou sem rede, `hoje()` devolve
// `null` e o cartão não aparece. Não mexe em preços: o carrinho enche-se pelo
// caminho normal (`encherCarrinhoDaProposta`).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/restaurant_model.dart';
import 'assistant_service.dart';

class ReceitaIngrediente {
  const ReceitaIngrediente({
    required this.nome,
    required this.quantidade,
    required this.pesquisa,
    this.unidades = 1,
  });

  final String nome;
  final String quantidade;

  /// Termo para achar o produto no supermercado ("azeite virgem extra").
  /// Testado contra o catálogo: termos genéricos ("azeite") davam produtos
  /// errados (atum em azeite).
  final String pesquisa;

  /// Quantas embalagens vão para o carrinho (ex.: 3 latas de atum).
  final int unidades;

  factory ReceitaIngrediente.fromJson(Map<String, dynamic> m) {
    final nome = '${m['nome'] ?? ''}'.trim();
    final pesquisa = '${m['pesquisa'] ?? ''}'.trim();
    final u = m['unidades'];
    return ReceitaIngrediente(
      nome: nome,
      quantidade: '${m['quantidade'] ?? ''}'.trim(),
      pesquisa: pesquisa.isEmpty ? nome : pesquisa,
      unidades: (u is num ? u.toInt() : int.tryParse('${u ?? ''}') ?? 1)
          .clamp(1, 20),
    );
  }
}

class ReceitaDoDia {
  const ReceitaDoDia({
    required this.id,
    required this.titulo,
    required this.resumo,
    required this.ingredientes,
    required this.passos,
    this.tempoMin,
    this.doses,
    this.fotoUrl,
  });

  final String id;
  final String titulo;
  final String resumo;
  final List<ReceitaIngrediente> ingredientes;
  final List<String> passos;
  final int? tempoMin;
  final int? doses;
  final String? fotoUrl;

  static int? _intOuNull(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  factory ReceitaDoDia.fromJson(Map<String, dynamic> m) {
    final ing = (m['ingredientes'] is List)
        ? (m['ingredientes'] as List)
            .whereType<Map>()
            .map((e) => ReceitaIngrediente.fromJson(e.cast<String, dynamic>()))
            .where((e) => e.nome.isNotEmpty)
            .toList()
        : const <ReceitaIngrediente>[];
    final passos = (m['passos'] is List)
        ? (m['passos'] as List)
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];
    final foto = '${m['foto_url'] ?? ''}'.trim();
    return ReceitaDoDia(
      id: '${m['id'] ?? ''}',
      titulo: '${m['titulo'] ?? ''}'.trim(),
      resumo: '${m['resumo'] ?? ''}'.trim(),
      ingredientes: ing,
      passos: passos,
      tempoMin: _intOuNull(m['tempo_min']),
      doses: _intOuNull(m['doses']),
      fotoUrl: foto.isEmpty ? null : foto,
    );
  }
}

/// O que `client_receita_de_hoje()` devolve.
class ReceitaHoje {
  const ReceitaHoje({
    required this.receita,
    required this.avisoDisponivel,
    required this.avisoHora,
    required this.avisoLigado,
  });

  final ReceitaDoDia receita;

  /// O aviso diário está ligado no painel (se não, o interruptor não aparece).
  final bool avisoDisponivel;

  /// Hora do aviso, em Lisboa (0-23).
  final int avisoHora;

  /// Este cliente pediu o aviso.
  final bool avisoLigado;

  ReceitaHoje copyWith({bool? avisoLigado}) => ReceitaHoje(
        receita: receita,
        avisoDisponivel: avisoDisponivel,
        avisoHora: avisoHora,
        avisoLigado: avisoLigado ?? this.avisoLigado,
      );

  /// `null` quando o servidor diz que não há receita para mostrar.
  static ReceitaHoje? fromJson(Map<String, dynamic> m) {
    if (m['enabled'] != true || m['receita'] is! Map) return null;
    final r =
        ReceitaDoDia.fromJson((m['receita'] as Map).cast<String, dynamic>());
    if (r.titulo.isEmpty || r.ingredientes.isEmpty) return null;
    final hora = m['aviso_hora'];
    return ReceitaHoje(
      receita: r,
      avisoDisponivel: m['aviso_disponivel'] == true,
      avisoHora: (hora is num ? hora.toInt() : int.tryParse('$hora') ?? 10)
          .clamp(0, 23),
      avisoLigado: m['aviso_ligado'] == true,
    );
  }
}

/// Resultado de cotar os ingredientes: a proposta escolhida ou o motivo.
class ReceitaCesto {
  const ReceitaCesto({this.proposta, this.erro});
  final AssistantProposal? proposta;

  /// 'sem_morada' | 'sem_loja' | 'sem_mercados'
  final String? erro;
}

class ReceitaService {
  ReceitaService._();
  static final ReceitaService instance = ReceitaService._();

  static const Duration _limite = Duration(seconds: 15);

  /// Receita de hoje, ou `null` (desligada, sem função, sem rede, sem sessão).
  /// Nunca rebenta: quem chama esconde o cartão.
  Future<ReceitaHoje?> hoje() async {
    try {
      final res = await Supabase.instance.client
          .rpc('client_receita_de_hoje')
          .timeout(_limite);
      if (res is! Map) return null;
      return ReceitaHoje.fromJson(res.cast<String, dynamic>());
    } catch (e) {
      debugPrint('[ReceitaService] hoje: $e');
      return null;
    }
  }

  /// Liga/desliga o aviso diário. Lança se o servidor falhar.
  Future<bool> definirAviso(bool ligado) async {
    final res = await Supabase.instance.client
        .rpc('client_receita_aviso', params: {'p_ligado': ligado})
        .timeout(_limite);
    if (res is Map && res['ok'] == true) return res['aviso_ligado'] == true;
    throw StateError('resposta_invalida');
  }

  /// Supermercados não-parceiros abertos à venda (a regra do Danilo: o cesto
  /// da receita vai ao mercado não-parceiro mais barato).
  static List<String> mercadosNaoParceiros(List<RestaurantModel> lojas) => [
        for (final r in lojas)
          if (r.category == BusinessCategory.supermarket &&
              !r.isPartner &&
              r.isOnline &&
              !r.comingSoon)
            r.id,
      ];

  /// Cota os ingredientes nos [mercados] pelo motor do Bora Assistente e
  /// escolhe a melhor proposta aberta (o servidor já ordena: mais completa
  /// primeiro, depois a mais barata). Lança se o servidor falhar.
  ///
  /// [lat]/[lng] = morada escolhida no carrinho (como o Bora Assistente faz);
  /// sem ela o servidor usa a morada gravada por omissão do cliente.
  Future<ReceitaCesto> cotarCesto(
    ReceitaDoDia receita,
    List<String> mercados, {
    double? lat,
    double? lng,
    bool apartamento = false,
  }) async {
    if (mercados.isEmpty) return const ReceitaCesto(erro: 'sem_mercados');
    final res = await Supabase.instance.client.rpc(
      'assistant_basket_quote',
      params: {
        'p_input': {
          'items': [
            for (final i in receita.ingredientes)
              {'query': i.pesquisa, 'quantity': i.unidades},
          ],
          'restaurant_ids': mercados,
          if (lat != null && lng != null) ...{
            'dropoff_lat': lat,
            'dropoff_lng': lng,
          },
          'apartment_delivery': apartamento,
          'persist': true,
        },
      },
    ).timeout(const Duration(seconds: 30));
    if (res is! Map) throw StateError('resposta_invalida');
    final m = res.cast<String, dynamic>();
    if (m['ok'] != true) {
      return ReceitaCesto(
        erro: m['error'] == 'SEM_MORADA' ? 'sem_morada' : 'sem_loja',
      );
    }
    final propostas = (m['proposals'] is List)
        ? (m['proposals'] as List)
            .whereType<Map>()
            .map((e) => AssistantProposal.fromJson(e.cast<String, dynamic>()))
            .where((p) => !p.isPartner && p.items.isNotEmpty)
            .toList()
        : const <AssistantProposal>[];
    if (propostas.isEmpty) return const ReceitaCesto(erro: 'sem_loja');
    final aberta = propostas.where((p) => p.open).toList();
    return ReceitaCesto(
        proposta: aberta.isNotEmpty ? aberta.first : propostas.first);
  }
}
