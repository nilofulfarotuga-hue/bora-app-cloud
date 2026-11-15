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

/// Etiqueta curta do prazo para a montra ("7 a 17 dias úteis"). Vazia se não houver prazo.
/// checkup-15-11 (Juiz da Claude.ai 18:27, ponto D): o cliente vê "dias úteis" já na montra.
String textoPrazoCurto(int prazoMinDias, int prazoMaxDias) {
  final a = prazoMinDias < 0 ? 0 : prazoMinDias;
  final b = prazoMaxDias < 0 ? 0 : prazoMaxDias;
  if (a == 0 && b == 0) return '';
  final lo = a == 0 ? b : (b == 0 ? a : (a < b ? a : b));
  final hi = a == 0 ? b : (b == 0 ? a : (a < b ? b : a));
  if (lo == hi) return '{0} dias úteis'.trArgs([lo]);
  return '{0} a {1} dias úteis'.trArgs([lo, hi]);
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
    this.publico = false,
  });

  final String id;
  final String slug;
  final String nome;
  final int ordem;
  final bool ativo;
  final DateTime? destaqueDesde;

  /// loja-nichos-15-11: aberto a todos os clientes. false = só o admin e as
  /// contas da lista de permissão o veem (até o Danilo dizer "abrir").
  final bool publico;

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
      publico: _booleano(m['publico'], false),
    );
  }

  @override
  bool operator ==(Object other) => other is LojaOnlineNicho && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// loja-nichos-15-11: subcategoria de um nicho (ex.: Pets › Cão, Gato…).
@immutable
class LojaOnlineSubcategoria {
  const LojaOnlineSubcategoria({
    required this.id,
    required this.nichoId,
    required this.slug,
    required this.nome,
    this.ordem = 100,
    this.ativo = true,
  });

  final String id;
  final String nichoId;
  final String slug;
  final String nome;
  final int ordem;
  final bool ativo;

  factory LojaOnlineSubcategoria.fromJson(Map<String, dynamic> m) {
    final slug = _texto(m['slug']);
    final nome = _texto(m['nome']);
    return LojaOnlineSubcategoria(
      id: _texto(m['id']),
      nichoId: _texto(m['nicho_id']),
      slug: slug,
      nome: nome.isEmpty ? slug : nome,
      ordem: _inteiro(m['ordem'], 100),
      ativo: _booleano(m['ativo'], true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LojaOnlineSubcategoria && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// loja-nichos-15-11 (ordem do Danilo 18:52): os MAIS VENDIDOS à frente.
/// 1.º a posição fixada no painel (ordem_manual, 1 = primeiro); 2.º as vendas
/// reais pagas na nossa loja; 3.º o ranking de vendas da CJ; 4.º os destaques;
/// 5.º os mais novos; por fim o título (ordem estável).
int compararMaisVendidos(LojaOnlineProduto a, LojaOnlineProduto b) {
  final ma = a.ordemManual, mb = b.ordemManual;
  if (ma != null || mb != null) {
    if (ma == null) return 1;
    if (mb == null) return -1;
    if (ma != mb) return ma.compareTo(mb);
  }
  if (a.vendasLoja != b.vendasLoja) return b.vendasLoja.compareTo(a.vendasLoja);
  if (a.cjListas != b.cjListas) return b.cjListas.compareTo(a.cjListas);
  if (a.destaque != b.destaque) return a.destaque ? -1 : 1;
  final ca = a.criadoEm, cb = b.criadoEm;
  if (ca != null && cb != null && ca != cb) return cb.compareTo(ca);
  return a.titulo.compareTo(b.titulo);
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
    this.subcategoriaId,
    this.cjListas = 0,
    this.vendasLoja = 0,
    this.ordemManual,
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

  /// loja-nichos-15-11: subcategoria (null = só no nicho, aparece em "Todos").
  final String? subcategoriaId;

  /// Ranking de vendas da CJ (lojas que listam o produto).
  final int cjListas;

  /// Unidades vendidas e pagas na nossa loja (o servidor conta sozinho).
  final int vendasLoja;

  /// Posição fixada no painel (1 = primeiro). null = ordem automática.
  final int? ordemManual;

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
      subcategoriaId: _texto(m['subcategoria_id']).isEmpty
          ? null
          : _texto(m['subcategoria_id']),
      cjListas: _inteiro(m['cj_listas']),
      vendasLoja: _inteiro(m['vendas_loja']),
      ordemManual: m['ordem_manual'] == null || _texto(m['ordem_manual']).isEmpty
          ? null
          : _inteiro(m['ordem_manual']),
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
  const LojaOnlineNichoComProdutos(this.nicho, this.produtos,
      [this.subcategorias = const []]);
  final LojaOnlineNicho nicho;

  /// Já pela ordem dos mais vendidos ([compararMaisVendidos]).
  final List<LojaOnlineProduto> produtos;

  /// loja-nichos-15-11: só as subcategorias ativas que têm produtos, por ordem.
  final List<LojaOnlineSubcategoria> subcategorias;

  /// Os produtos de uma subcategoria (null = todos), na mesma ordem.
  List<LojaOnlineProduto> daSubcategoria(String? subcategoriaId) =>
      subcategoriaId == null
          ? produtos
          : produtos.where((p) => p.subcategoriaId == subcategoriaId).toList();
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
    List<LojaOnlineProduto> produtos, [
    List<LojaOnlineSubcategoria> subcategorias = const [],
  ]) {
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
      // loja-nichos-15-11: os mais vendidos à frente.
      final ps = produtosAtivos.where((p) => p.nichoId == n.id).toList()
        ..sort(compararMaisVendidos);
      if (ps.isEmpty) continue;
      final comProdutos = ps.map((p) => p.subcategoriaId).toSet();
      final subs = subcategorias
          .where((s) => s.nichoId == n.id && s.ativo && comProdutos.contains(s.id))
          .toList()
        ..sort((a, b) {
          final c = a.ordem.compareTo(b.ordem);
          return c != 0 ? c : a.nome.compareTo(b.nome);
        });
      porNicho.add(LojaOnlineNichoComProdutos(n, ps, subs));
    }

    return LojaOnlineVitrine(
      nichoDaSemana: nichoSemana,
      novidade: novidade,
      porNicho: porNicho,
    );
  }
}
