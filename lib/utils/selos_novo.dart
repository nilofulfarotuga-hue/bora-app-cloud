// Selo "Novo" no canto dos atalhos da página inicial (17/11/2026).
// Pedido do Danilo: "tem que pôr as novidades na app, lá nos cantinhos que
// coloca novidade". Até aqui só a Casa tinha selo (`casa_novo_ate`); agora
// qualquer atalho pode ter, por uma só definição em `platform_settings`:
//
//   selos_novo = {"farmacia": "2026-12-01", "festas": "2026-11-30", ...}
//
// chave do atalho → último dia (AAAA-MM-DD, relógio de Lisboa) em que o selo
// aparece. O painel (Faixas da home → "Selo Novo nos atalhos") liga, desliga e
// muda a data. A Casa continua com a sua `casa_novo_ate` (painel > Casa).
library;

import 'dart:convert';

import '../models/casa_models.dart' show casaSeloNovoVisivel;

/// Chave de `platform_settings` com o mapa atalho → último dia com selo.
const String kSelosNovoChave = 'selos_novo';

/// Quantos dias dura o selo quando se liga no painel sem escolher data.
const int kSelosNovoDias = 14;

/// Atalhos da página inicial que podem levar o selo: chave → nome no painel.
/// A chave é sempre [chaveAtalho] do rótulo do atalho (ver o teste).
const Map<String, String> kAtalhosHome = {
  'restaurantes': 'Restaurantes',
  'supermercados': 'Supermercados',
  'farmacia': 'Farmácia',
  'lojas': 'Lojas',
  'enviar encomenda': 'Enviar Encomenda',
  'levar compras': 'Levar Compras',
  'favores': 'Favores',
  'reservar mesa': 'Reservar Mesa',
  'beleza': 'Beleza',
  'limpeza': 'Limpeza',
  'festas': 'Festas',
  'sobremesas': 'Sobremesas',
  'lavagem auto': 'Lavagem Auto',
  'loja online': 'Loja Online',
  'bora motorista': 'Bora Motorista',
};

const Map<String, String> _semAcento = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i',
  'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c',
};

/// Chave de um atalho a partir do rótulo ("Casa e\nManutenção" →
/// "casa e manutencao"): minúsculas, sem acentos, espaços simples.
String chaveAtalho(String rotulo) {
  final b = StringBuffer();
  for (final ch in rotulo.toLowerCase().split('')) {
    b.write(_semAcento[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Lê o valor de `selos_novo` (mapa JSON ou texto JSON). Ilegível = sem selos.
Map<String, String> lerSelosNovo(Object? valor) {
  Object? v = valor;
  if (v is String) {
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const {};
    }
  }
  if (v is! Map) return const {};
  final out = <String, String>{};
  v.forEach((k, d) {
    final s = (d ?? '').toString().trim();
    if (s.isNotEmpty) out['$k'] = s;
  });
  return out;
}

/// O atalho com este rótulo mostra o selo "Novo" agora? (até ao fim do dia
/// marcado, hora de Lisboa).
bool seloNovoNoAtalho(
        Map<String, String> selos, String rotulo, DateTime agora) =>
    casaSeloNovoVisivel(selos[chaveAtalho(rotulo)], agora);
