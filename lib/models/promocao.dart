import '../services/pricing_service.dart';

/// Promoções com preço riscado (adendo 5 · item 4, 29/10/2026).
///
/// Este ficheiro só tem lógica pura (sem rede, sem ecrãs): a decisão "a promoção
/// está ativa agora?", o estado que o painel mostra, e as três linhas que o
/// cliente vê (preço riscado, preço novo e a linha dos 30 dias da Diretiva
/// Omnibus). O servidor decide com `product_promo_active`; a regra aqui é a mesma.

/// Uma promoção ativa, como o servidor a devolve em `store_active_promotions`.
/// Os preços são os de catálogo (`products.price` e `products.discount_price`),
/// ainda sem o markup das lojas não parceiras.
class PromocaoProduto {
  const PromocaoProduto({
    required this.productId,
    required this.preco,
    required this.precoPromocional,
    this.inicio,
    this.fim,
    this.maisBaixo30d,
  });

  final String productId;

  /// `products.price` — o preço normal.
  final double preco;

  /// `products.discount_price` — o preço da promoção.
  final double precoPromocional;
  final DateTime? inicio;
  final DateTime? fim;

  /// `product_lowest_price_30d` — o preço mais baixo dos 30 dias antes da promoção.
  final double? maisBaixo30d;

  /// Linha vinda do servidor; null se faltarem o id ou os preços.
  static PromocaoProduto? fromRow(Map<String, dynamic> m) {
    final id = (m['product_id'] ?? '').toString();
    final preco = _num(m['price']);
    final promo = _num(m['discount_price']);
    if (id.isEmpty || preco == null || promo == null) return null;
    return PromocaoProduto(
      productId: id,
      preco: preco,
      precoPromocional: promo,
      inicio: _data(m['starts_at']),
      fim: _data(m['ends_at']),
      maisBaixo30d: _num(m['lowest_price_30d']),
    );
  }

  /// O servidor só devolve promoções já em vigor; a app só tem de ver se não
  /// acabou entretanto (não compara o início com o relógio do telemóvel).
  bool aindaValida(DateTime agora) => fim == null || agora.isBefore(fim!);

  @override
  bool operator ==(Object other) =>
      other is PromocaoProduto &&
      other.productId == productId &&
      other.preco == preco &&
      other.precoPromocional == precoPromocional &&
      other.inicio == inicio &&
      other.fim == fim &&
      other.maisBaixo30d == maisBaixo30d;

  @override
  int get hashCode =>
      Object.hash(productId, preco, precoPromocional, inicio, fim, maisBaixo30d);
}

double? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _data(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// Estado de uma promoção, para o painel.
enum EstadoPromocao {
  /// Em vigor agora.
  ativa,

  /// Ainda não começou.
  agendada,

  /// Já acabou.
  expirada,

  /// O admin desligou (os dados ficam, nada se aplica).
  desligada,

  /// Preço promocional guardado sem data de início (ex.: carregado por um robô
  /// de catálogo): o servidor não o aplica até ter datas.
  semDatas,

  /// Preço promocional igual ou acima do normal (ou zero): nunca se aplica.
  invalida,
}

/// Estado de uma promoção neste instante. A mesma regra do servidor
/// (`product_promo_active`): preço promocional entre 0 e o preço normal, ligada
/// pelo admin, com data de início já passada e sem ter acabado.
EstadoPromocao estadoDaPromocao({
  required double preco,
  required double? precoPromocional,
  bool ativada = true,
  DateTime? inicio,
  DateTime? fim,
  required DateTime agora,
}) {
  if (precoPromocional == null ||
      precoPromocional <= 0 ||
      precoPromocional >= preco) {
    return EstadoPromocao.invalida;
  }
  if (!ativada) return EstadoPromocao.desligada;
  if (inicio == null) return EstadoPromocao.semDatas;
  if (agora.isBefore(inicio)) return EstadoPromocao.agendada;
  if (fim != null && !agora.isBefore(fim)) return EstadoPromocao.expirada;
  return EstadoPromocao.ativa;
}

/// "A promoção está ativa agora?" — a decisão pura que a app e o painel usam.
bool promocaoAtivaAgora({
  required double preco,
  required double? precoPromocional,
  bool ativada = true,
  DateTime? inicio,
  DateTime? fim,
  required DateTime agora,
}) =>
    estadoDaPromocao(
      preco: preco,
      precoPromocional: precoPromocional,
      ativada: ativada,
      inicio: inicio,
      fim: fim,
      agora: agora,
    ) ==
    EstadoPromocao.ativa;

/// O que o cliente vê numa promoção, já com o markup da loja aplicado
/// (exibido = cobrado).
class VistaPromocao {
  const VistaPromocao({
    required this.atual,
    this.riscado,
    this.maisBaixo30d,
  });

  /// O preço que se paga agora.
  final double atual;

  /// O preço anterior, riscado. Null quando não houve descida real.
  final double? riscado;

  /// O valor da linha legal "Preço mais baixo dos últimos 30 dias".
  /// Só vem preenchido quando se anuncia uma redução (há [riscado]).
  final double? maisBaixo30d;

  bool get temReducao => riscado != null;
}

/// Calcula o que mostrar. A Diretiva Omnibus diz que o "preço anterior" de uma
/// redução é o mais baixo dos 30 dias antes dela: se esse for mais baixo do que
/// o preço normal, é ele que se risca (nunca se risca um preço inflacionado);
/// e se o preço novo não for mais baixo do que ele, não se anuncia redução —
/// mostra-se só o preço que se paga.
VistaPromocao vistaDaPromocao(PromocaoProduto p, {required bool lojaParceira}) {
  final minimo = p.maisBaixo30d;
  final anterior = (minimo != null && minimo > 0 && minimo < p.preco)
      ? minimo
      : p.preco;
  final atual = PricingService.applyMarkup(p.precoPromocional, lojaParceira);
  final anteriorExibido = PricingService.applyMarkup(anterior, lojaParceira);
  if (anteriorExibido > atual) {
    return VistaPromocao(
      atual: atual,
      riscado: anteriorExibido,
      maisBaixo30d: anteriorExibido,
    );
  }
  return VistaPromocao(atual: atual);
}

/// Percentagem de desconto arredondada ("-25"), ou null se não houver redução.
int? percentagemDesconto(VistaPromocao v) {
  final r = v.riscado;
  if (r == null || r <= 0) return null;
  return (((r - v.atual) / r) * 100).round();
}
