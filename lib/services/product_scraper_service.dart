import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/partner_product.dart';

/// Attempts to scrape product data from Portuguese supermarket websites.
/// Falls back to a realistic hardcoded list if scraping fails or returns
/// fewer than [_minScrapedItems] usable results.
class ProductScraperService {
  static const _timeout = Duration(seconds: 10);
  static const _minScrapedItems = 3;

  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'pt-PT,pt;q=0.9,en;q=0.7',
  };

  // ─── Public API ──────────────────────────────────────────────────────────

  Future<List<PartnerProduct>> scrapeProducts(String source) async {
    try {
      switch (source) {
        case 'continente':
          return await _scrapeContinente();
        case 'pingodoce':
          return await _scrapePingoDoce();
        case 'lidl':
          return await _scrapeLidl();
        default:
          debugPrint(
              'ProductScraperService: unknown source "$source", using fallback');
          return _fallback(source);
      }
    } catch (e) {
      debugPrint('ProductScraperService: "$source" scraping error => $e');
      return _fallback(source);
    }
  }

  // ─── Per-store scrapers ──────────────────────────────────────────────────

  Future<List<PartnerProduct>> _scrapeContinente() async {
    final scraped = <_ScrapedItem>[];

    for (final query in ['leite', 'arroz', 'fruta', 'higiene']) {
      try {
        final items = await _fetchAndParse(
          'https://www.continente.pt/pesquisa/?q=$query&start=0&sz=12',
          source: 'continente',
        );
        for (final item in items) {
          if (!scraped.any(
              (s) => s.name.toLowerCase() == item.name.toLowerCase())) {
            scraped.add(item);
          }
        }
        if (scraped.length >= 15) break;
      } catch (_) {
        continue;
      }
    }

    if (scraped.length < _minScrapedItems) {
      debugPrint(
          'ProductScraperService: continente — only ${scraped.length} items scraped, using fallback');
      return _fallback('continente');
    }

    return _mapToProducts(scraped, 'continente');
  }

  Future<List<PartnerProduct>> _scrapePingoDoce() async {
    final scraped = <_ScrapedItem>[];

    for (final query in ['leite', 'arroz', 'fruta', 'pao']) {
      try {
        final items = await _fetchAndParse(
          'https://www.pingodoce.pt/pesquisa/?q=$query',
          source: 'pingodoce',
        );
        for (final item in items) {
          if (!scraped.any(
              (s) => s.name.toLowerCase() == item.name.toLowerCase())) {
            scraped.add(item);
          }
        }
        if (scraped.length >= 15) break;
      } catch (_) {
        continue;
      }
    }

    if (scraped.length < _minScrapedItems) {
      debugPrint(
          'ProductScraperService: pingodoce — only ${scraped.length} items scraped, using fallback');
      return _fallback('pingodoce');
    }

    return _mapToProducts(scraped, 'pingodoce');
  }

  Future<List<PartnerProduct>> _scrapeLidl() async {
    try {
      final items = await _fetchAndParse(
        'https://www.lidl.pt/q/pesquisar?q=leite',
        source: 'lidl',
      );
      if (items.length < _minScrapedItems) return _fallback('lidl');
      return _mapToProducts(items, 'lidl');
    } catch (_) {
      return _fallback('lidl');
    }
  }

  // ─── HTTP + parsing ──────────────────────────────────────────────────────

  Future<List<_ScrapedItem>> _fetchAndParse(
    String url, {
    required String source,
  }) async {
    final uri = Uri.parse(url);
    final response =
        await http.get(uri, headers: _defaultHeaders).timeout(_timeout);

    if (response.statusCode != 200) {
      debugPrint(
          'ProductScraperService: HTTP ${response.statusCode} for $url');
      return const [];
    }

    final html = response.body;

    // 1. Try JSON-LD structured data (common in modern e-commerce for SEO)
    final jsonLdItems = _parseJsonLd(html);
    if (jsonLdItems.length >= _minScrapedItems) return jsonLdItems;

    // 2. Fallback to regex-based price + name extraction
    return _parsePricesFromHtml(html);
  }

  /// Parses `<script type="application/ld+json">` blocks looking for
  /// Product or ItemList schemas with name + price.
  List<_ScrapedItem> _parseJsonLd(String html) {
    final items = <_ScrapedItem>[];
    final jsonLdRegex = RegExp(
      r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final block in jsonLdRegex.allMatches(html)) {
      final json = block.group(1) ?? '';

      // Extract name values from the JSON text
      final nameRegex = RegExp(r'"name"\s*:\s*"([^"]{3,80})"');
      // Extract price values
      final priceRegex = RegExp(r'"price"\s*:\s*"?(\d+[.,]\d{1,2})"?');

      final names = nameRegex.allMatches(json).map((m) => m.group(1)!).toList();
      final prices = priceRegex
          .allMatches(json)
          .map((m) => double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0.0)
          .where((p) => p > 0 && p < 500)
          .toList();

      final count = names.length < prices.length ? names.length : prices.length;
      for (var i = 0; i < count && items.length < 20; i++) {
        if (items.any((e) => e.name.toLowerCase() == names[i].toLowerCase())) {
          continue;
        }
        items.add(_ScrapedItem(name: names[i], price: prices[i]));
      }
    }

    return items;
  }

  /// Extracts product names and prices from raw HTML using simple patterns.
  /// Looks for price occurrences in the form "1,99 €" / "€1.99" and finds
  /// plausible product names in tag content near each price.
  List<_ScrapedItem> _parsePricesFromHtml(String html) {
    final items = <_ScrapedItem>[];

    // Strip scripts and styles first
    final cleaned = html
        .replaceAll(
          RegExp(r'<script[^>]*>.*?</script>', dotAll: true),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>.*?</style>', dotAll: true),
          '',
        );

    // Price: "1,99 €" / "€ 1,99" / "1.99€"
    final priceRegex =
        RegExp(r'(\d{1,3})[,.](\d{2})\s*€|€\s*(\d{1,3})[,.](\d{2})');

    // Tag content: text between > and < that looks like a product name
    final tagText = RegExp(r'>([^<\n]{4,80})<');

    // Filter out noise tokens
    final noiseRegex = RegExp(
      r'^\d|^€|shopping|pesquisa|login|menu|continente|pingo|lidl|mercadona|adicionar|carrinho|ver mais',
      caseSensitive: false,
    );

    for (final priceMatch in priceRegex.allMatches(cleaned).take(25)) {
      // Parse price value
      double price;
      final g1 = priceMatch.group(1);
      final g2 = priceMatch.group(2);
      final g3 = priceMatch.group(3);
      final g4 = priceMatch.group(4);
      if (g1 != null && g2 != null) {
        price = double.tryParse('$g1.$g2') ?? 0;
      } else if (g3 != null && g4 != null) {
        price = double.tryParse('$g3.$g4') ?? 0;
      } else {
        continue;
      }
      if (price <= 0 || price > 200) continue;

      // Look back up to 500 chars before the price for a name candidate
      final start = (priceMatch.start - 500).clamp(0, cleaned.length);
      final snippet = cleaned.substring(start, priceMatch.start);

      final candidates = tagText
          .allMatches(snippet)
          .map((m) => m.group(1)!.trim())
          .where((t) => t.length >= 4 && t.length <= 80)
          .where((t) => !noiseRegex.hasMatch(t))
          .toList();

      if (candidates.isEmpty) continue;

      final name = candidates.last;
      if (items.any((e) => e.name.toLowerCase() == name.toLowerCase())) {
        continue;
      }

      items.add(_ScrapedItem(name: name, price: price));
    }

    return items;
  }

  // ─── PartnerProduct mapping ──────────────────────────────────────────────

  List<PartnerProduct> _mapToProducts(
    List<_ScrapedItem> items,
    String sourceLabel,
  ) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return [
      for (var i = 0; i < items.length; i++)
        PartnerProduct(
          id: 'scraped-$sourceLabel-$ts-$i',
          restaurantId: '', // overridden by syncProductsFromExternalSource
          name: items[i].name,
          description: items[i].name,
          price: items[i].price,
          photoUrl: '',
          isAvailable: true,
          source: ProductSource.scraped,
        ),
    ];
  }

  // ─── Fallback data ───────────────────────────────────────────────────────

  List<PartnerProduct> _fallback(String source) {
    debugPrint('ProductScraperService: using fallback data for "$source"');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final raw = _kFallbackItems[source] ?? _kGenericFallback;
    return [
      for (var i = 0; i < raw.length; i++)
        PartnerProduct(
          id: 'scraped-$source-$ts-$i',
          restaurantId: '',
          name: raw[i].$1,
          description: raw[i].$1,
          price: raw[i].$2,
          photoUrl: '',
          isAvailable: true,
          source: ProductSource.scraped,
        ),
    ];
  }

  // Names here must NOT overlap with seed names in RestaurantStore._kDefaultProducts
  // (case-insensitive exact match). Seed products for each store already cover the
  // basics; fallback adds items the seed omits.
  static const _kFallbackItems = <String, List<(String, double)>>{
    'continente': [
      // Seed already has: Banana, Leite UHT 1L, Pão de forma integral,
      //   Ovos L (6 un), Massa esparguete 500g, Azeite 75cl
      ('Arroz agulha 1kg', 1.29),
      ('Açúcar branco 1kg', 0.99),
      ('Farinha de trigo 1kg', 0.89),
      ('Iogurte natural 4x125g', 1.59),
      ('Manteiga sem sal 250g', 2.39),
      ('Queijo flamengo fatiado 200g', 1.99),
      ('Fiambre da perna 150g', 2.49),
      ('Água mineral 1.5L', 0.49),
      ('Sumo de laranja 1L', 1.79),
      ('Café moído 250g', 2.99),
      ('Detergente loiça 500ml', 1.49),
      ('Papel higiénico 12 un', 3.99),
      ('Tomate em rama 1kg', 1.49),
      ('Cenoura 1kg', 0.89),
    ],
    'pingodoce': [
      // Seed already has: Banana, Leite meio-gordo 1L, Pão de forma,
      //   Ovos M (10 un), Arroz carolino 1kg, Azeite virgem extra 75cl
      ('Massa fusilli 500g', 1.19),
      ('Açúcar amarelo 1kg', 1.09),
      ('Iogurte grego natural 4x150g', 1.79),
      ('Manteiga com sal 250g', 2.49),
      ('Queijo da ilha fatiado 200g', 2.29),
      ('Fiambre extra 100g', 1.99),
      ('Água das Pedras 1.5L', 0.65),
      ('Sumo tropical 1L', 1.89),
      ('Café solúvel 200g', 3.49),
      ('Detergente roupa líquido 2L', 5.99),
      ('Peito de frango 500g', 3.49),
      ('Cenoura 1kg', 1.09),
      ('Batata 2kg', 1.89),
      ('Maçã golden 1kg', 1.59),
    ],
    'lidl': [
      ('Banana bio 1kg', 1.39),
      ('Leite gordo Milbona 1L', 0.85),
      ('Pão de mistura 500g', 1.59),
      ('Ovos XL 10 un', 2.49),
      ('Arroz longo 1kg', 1.29),
      ('Azeite virgem extra bio 75cl', 5.49),
      ('Massa penne 500g', 0.99),
      ('Manteiga Milbona 250g', 1.99),
      ('Iogurte natural Milbona 4un', 1.49),
      ('Queijo Edam fatiado 200g', 1.89),
      ('Fiambre Milbona 100g', 1.49),
      ('Água Saskia 1.5L', 0.39),
      ('Sumo laranja Freeway 1L', 1.29),
      ('Café Bellarom 500g', 3.49),
    ],
  };

  static const _kGenericFallback = <(String, double)>[
    ('Leite UHT 1L', 0.85),
    ('Pão de forma 500g', 1.49),
    ('Banana 1kg', 1.29),
    ('Ovos M 10 un', 2.39),
    ('Arroz 1kg', 1.19),
    ('Azeite 75cl', 4.79),
    ('Massa 500g', 1.09),
    ('Açúcar 1kg', 0.99),
    ('Iogurte natural 4un', 1.59),
    ('Água mineral 1.5L', 0.49),
  ];
}

class _ScrapedItem {
  const _ScrapedItem({required this.name, required this.price});
  final String name;
  final double price;
}
