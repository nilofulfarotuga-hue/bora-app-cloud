// lib/models/loja_online_produto.dart
//
// Loja Online (15/11/2026, missão fechar-tudo-15-11 ponto E, caixa 10): os
// produtos físicos da loja Shopify da Bora (dropshipping: o fornecedor envia
// pelo correio, de qualquer origem, no prazo que der) tal como o cliente os vê
// dentro da app. Começa pelo nicho "pets"; um nicho em destaque por semana.
//
// O preço já chega final: `preco_bora_cents` = 2 × custo do fornecedor (regra
// do Danilo, AUTORIZO de 14/11/2026 12:19), aplicada pela importação da
// Shopify no servidor. Aqui não se calcula preço nenhum e não há pagamento:
// nesta primeira versão o botão "Encomendar" está desligado.
//
// Tudo tolerante a dados incompletos: as tabelas ainda não existem em
// produção (proposta em docs/propostas/fechar-tudo-15-11/E_loja_online
// .PROPOSTA.sql) e a importação da Shopify é o passo seguinte.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../l10n/tr.dart';

int _inteiro(Object? v, [int recurso = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.toInt() ?? recurso;
  }
  return recurso;
}

bool _booleano(Object? v, [bool recurso = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.replaceAll('"', '').trim().toLowerCase();
    if (s == 'true' || s == 't' || s == '1' || s == 'sim') return true;
    if (s == 'false' || s == 'f' || s == '0' || s == 'nao' || s == 'não') {
      return false;
    }
  }
  return recurso;
}

String _texto(Object? v) => v == null ? '' : '$v'.trim();

DateTime? _data(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse('$v'.trim());
}

/// `imagens` chega como `text[]` (lista) do Supabase; tolera também uma lista
/// em JSON dentro de uma string, uma string separada por vírgulas ou um só URL.
List<String> _listaDeTexto(Object? v) {
  if (v == null) return const [];
  if (v is List) {
    return v
        .map((e) => _texto(e))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
  final s = _texto(v);
  if (s.isEmpty) return const [];
  if (s.startsWith('[')) {
    try {
      final j = jsonDecode(s);
      if (j is List) return _listaDeTexto(j);
    } catch (_) {
      // Não era JSON: cai na separação por vírgulas.
    }
  }
  if (s.startsWith('{') && s.endsWith('}')) {
    // Forma textual de um array do Postgres: {a,b}
    return _listaDeTexto(s.substring(1, s.length - 1));
  }
  return s
      .split(',')
      .map((e) => e.trim().replaceAll('"', ''))
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

/// "12,90 €" a partir de cêntimos. Não é cálculo de preço: só formato.
String formatarEurosCents(int cents) {
  final v = cents / 100;
  return '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
}

/// Frase do prazo, em grande na ficha do produto. Vazia se não houver prazo.
String textoPrazoCorreio(int prazoMinDias, int prazoMaxDias) {
  var a = prazoMinDias < 0 ? 0 : prazoMinDias;
  var b = prazoMaxDias < 0 ? 0 : prazoMaxDias;
  if (a == 0 && b == 0) return '';
  if (a == 0) a = b;
  if (b == 0) b = a;
  if (a > b) {
    final t = a;
    a = b;
    b = t;
  }
  if (a == b) {
    if (a == 1) return 'Chega pelo correio em 1 dia útil'.tr;
    return 'Chega pelo correio em {0} dias úteis'.trArgs([a]);
  }
  return 'Chega pelo correio em {0} a {1} dias úteis'.trArgs([a, b]);
}

/// Um nicho da loja (pets, casa, …). O "nicho da semana" é o ativo com o
/// `destaque_desde` mais recente.
@immutable
class LojaOnlineNicho {
  const LojaOnlineNicho({
    required this.id,
    required this.slug,
    required this.nome,
    this.ordem = 100,
    this.ativo = true,
    this.destaqueDesde,
  });

  final String id;
  final String slug;
  final String nome;
  final int ordem;
  final bool ativo;
  final DateTime? destaqueDesde;

  factory LojaOnlineNicho.fromJson(Map<String, dynamic> m) {
    final slug = _texto(m['slug']);
    final nome = _texto(m['nome']);
    return LojaOnlineNicho(
      id: _texto(m['id']),
      slug: slug,
      nome: nome.isEmpty ? slug : nome,
      ordem: _inteiro(m['ordem'], 100),
      ativo: _booleano(m['ativo'], true),
      destaqueDesde: _data(m['destaque_desde']),
    );
  }

  @override
  bool operator ==(Object other) => other is LojaOnlineNicho && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class LojaOnlineProduto {
  const LojaOnlineProduto({
    required this.id,
    required this.titulo,
    this.shopifyProductId = '',
    this.shopifyVariantId,
    this.nichoId = '',
    this.descricao = '',
    this.imagens = const [],
    this.custoFornecedorCents = 0,
    this.precoBoraCents = 0,
    this.prazoMinDias = 0,
    this.prazoMaxDias = 0,
    this.ativo = false,
    this.destaque = false,
    this.criadoEm,
    this.atualizadoEm,
  });

  final String id;
  final String shopifyProductId;
  final String? shopifyVariantId;
  final String nichoId;
  final String titulo;
  final String descricao;
  final List<String> imagens;

  /// Custo no fornecedor (só o painel o vê; o cliente nunca).
  final int custoFornecedorCents;

  /// Preço final ao cliente, IVA e envio incluídos (2 × custo, pela importação).
  final int precoBoraCents;
  final int prazoMinDias;
  final int prazoMaxDias;

  /// Nasce desligado: só aparece ao cliente depois de o painel ligar.
  final bool ativo;

  /// Entra na "Novidade da semana" do seu nicho.
  final bool destaque;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  factory LojaOnlineProduto.fromJson(Map<String, dynamic> m) {
    final titulo = _texto(m['titulo']);
    final variante = _texto(m['shopify_variant_id']);
    return LojaOnlineProduto(
      id: _texto(m['id']),
      shopifyProductId: _texto(m['shopify_product_id']),
      shopifyVariantId: variante.isEmpty ? null : variante,
      nichoId: _texto(m['nicho_id']),
      titulo: titulo.isEmpty ? 'Produto'.tr : titulo,
      descricao: _texto(m['descricao']),
      imagens: _listaDeTexto(m['imagens']),
      custoFornecedorCents: _inteiro(m['custo_fornecedor_cents']),
      precoBoraCents: _inteiro(m['preco_bora_cents']),
      prazoMinDias: _inteiro(m['prazo_min_dias']),
      prazoMaxDias: _inteiro(m['prazo_max_dias']),
      ativo: _booleano(m['ativo'], false),
      destaque: _booleano(m['destaque'], false),
      criadoEm: _data(m['criado_em']),
      atualizadoEm: _data(m['atualizado_em']),
    );
  }

  String get precoTexto => formatarEurosCents(precoBoraCents);
  String get custoTexto => formatarEurosCents(custoFornecedorCents);
  String get prazoTexto => textoPrazoCorreio(prazoMinDias, prazoMaxDias);
  String? get fotoPrincipal => imagens.isEmpty ? null : imagens.first;

  @override
  bool operator ==(Object other) =>
      other is LojaOnlineProduto && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Um nicho com os seus produtos ativos, já ordenados (destaques primeiro).
@immutable
class LojaOnlineNichoComProdutos {
  const LojaOnlineNichoComProdutos(this.nicho, this.produtos);
  final LojaOnlineNicho nicho;
  final List<LojaOnlineProduto> produtos;
}

/// O que o ecrã da loja mostra, montado só a partir dos dados (sem rede):
/// a "Novidade da semana" (produtos em destaque do nicho da semana) e depois
/// cada nicho com os seus produtos. Produtos de nichos desligados não aparecem.
@immutable
class LojaOnlineVitrine {
  const LojaOnlineVitrine({
    required this.nichoDaSemana,
    required this.novidade,
    required this.porNicho,
  });

  final LojaOnlineNicho? nichoDaSemana;
  final List<LojaOnlineProduto> novidade;
  final List<LojaOnlineNichoComProdutos> porNicho;

  bool get vazia => porNicho.isEmpty;

  /// Quantos produtos entram na "Novidade da semana" no máximo.
  static const int maxNovidade = 6;

  static LojaOnlineVitrine montar(
    List<LojaOnlineNicho> nichos,
    List<LojaOnlineProduto> produtos,
  ) {
    final ativos = nichos.where((n) => n.ativo).toList()
      ..sort((a, b) {
        final c = a.ordem.compareTo(b.ordem);
        return c != 0 ? c : a.nome.compareTo(b.nome);
      });
    final produtosAtivos = produtos.where((p) => p.ativo).toList();

    LojaOnlineNicho? semana;
    for (final n in ativos) {
      final d = n.destaqueDesde;
      if (d == null) continue;
      final atual = semana?.destaqueDesde;
      if (atual == null || d.isAfter(atual)) semana = n;
    }
    semana ??= ativos.isEmpty ? null : ativos.first;
    final nichoSemana = semana;

    int ordemProdutos(LojaOnlineProduto a, LojaOnlineProduto b) {
      if (a.destaque != b.destaque) return a.destaque ? -1 : 1;
      final ca = a.criadoEm, cb = b.criadoEm;
      if (ca != null && cb != null && ca != cb) return cb.compareTo(ca);
      return a.titulo.compareTo(b.titulo);
    }

    final doNichoSemana = nichoSemana == null
        ? <LojaOnlineProduto>[]
        : (produtosAtivos.where((p) => p.nichoId == nichoSemana.id).toList()
          ..sort(ordemProdutos));
    final destacados = doNichoSemana.where((p) => p.destaque).toList();
    final novidade = (destacados.isNotEmpty ? destacados : doNichoSemana)
        .take(maxNovidade)
        .toList(growable: false);

    final porNicho = <LojaOnlineNichoComProdutos>[];
    for (final n in ativos) {
      final ps = produtosAtivos.where((p) => p.nichoId == n.id).toList()
        ..sort(ordemProdutos);
      if (ps.isNotEmpty) porNicho.add(LojaOnlineNichoComProdutos(n, ps));
    }

    return LojaOnlineVitrine(
      nichoDaSemana: nichoSemana,
      novidade: novidade,
      porNicho: porNicho,
    );
  }
}
