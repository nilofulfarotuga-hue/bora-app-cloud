// Sugestões da lupa desde a 1.ª letra (17/11/2026, missão lupa-sugestoes-17-11).
//
// O Danilo (17/11 08:41): "se a pessoa coloca a letra A, aparece lá as opções
// que tem na loja, sem carregar o servidor. Como é que os grandes fazem."
// Como a Uber Eats e a Glovo: com 1 ou 2 letras não se pesquisa o catálogo
// inteiro; pede-se à RPC `lupa_sugestoes` uma lista pequena, já pronta no
// servidor (palavras do catálogo, produtos mais pedidos, secções e lojas),
// procurada pelo começo do texto num índice. A partir de 3 letras continua a
// pesquisa completa de sempre (pesquisa_lupa.dart).
//  * espera [kEsperaSugestoes] (250 ms) entre letras;
//  * a mesma sugestão (texto + loja) fica [kMemoriaSugestoes] (10 min) no
//    telemóvel;
//  * com 1-2 letras nunca se mostra "não encontrei".
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'pesquisa_lupa.dart';

/// Espera entre letras antes de pedir sugestões.
const Duration kEsperaSugestoes = Duration(milliseconds: 250);

/// Quanto tempo as sugestões de um prefixo ficam no telemóvel.
const Duration kMemoriaSugestoes = Duration(minutes: 10);

/// O que a lupa mostra para um texto.
enum ModoLupa {
  /// Nada escrito (ou só espaços/pontuação).
  vazio,

  /// 1 ou 2 letras: sugestões.
  sugestoes,

  /// 3 letras ou mais: a pesquisa completa.
  pesquisa,
}

/// Decide o modo pelas letras que o servidor conta (sem acentos, espaços nem
/// pontuação), igual a `letrasDaPesquisa`.
ModoLupa modoDaLupa(String texto) {
  final n = letrasDaPesquisa(texto);
  if (n == 0) return ModoLupa.vazio;
  if (n < kLetrasProdutos) return ModoLupa.sugestoes;
  return ModoLupa.pesquisa;
}

enum TipoSugestao { palavra, produto, seccao, loja }

TipoSugestao _tipo(Object? v) => switch ('${v ?? ''}') {
      'produto' => TipoSugestao.produto,
      'seccao' => TipoSugestao.seccao,
      'loja' => TipoSugestao.loja,
      _ => TipoSugestao.palavra,
    };

/// Uma linha da RPC `lupa_sugestoes`.
class SugestaoLupa {
  const SugestaoLupa({
    required this.texto,
    required this.tipo,
    this.ref,
    this.restaurantId,
  });

  factory SugestaoLupa.deMapa(Map<String, dynamic> m) => SugestaoLupa(
        texto: '${m['texto'] ?? ''}',
        tipo: _tipo(m['tipo']),
        ref: m['ref'] == null ? null : '${m['ref']}',
        restaurantId:
            m['restaurant_id'] == null ? null : '${m['restaurant_id']}',
      );

  /// O que se mostra (e o que se pesquisa ao tocar).
  final String texto;
  final TipoSugestao tipo;

  /// Produto: o id do produto. Loja: o id da loja. Secção: a secção
  /// (category_root) tal como está nos produtos.
  final String? ref;

  /// A loja da sugestão (produto, secção da loja, loja); null nas palavras
  /// da lupa geral.
  final String? restaurantId;

  @override
  bool operator ==(Object other) =>
      other is SugestaoLupa &&
      other.texto == texto &&
      other.tipo == tipo &&
      other.ref == ref &&
      other.restaurantId == restaurantId;

  @override
  int get hashCode => Object.hash(texto, tipo, ref, restaurantId);
}

/// De onde vêm as sugestões (nos testes, uma função falsa).
typedef FonteSugestoes = Future<List<SugestaoLupa>> Function(
    String texto, String? restaurantId);

/// Memória partilhada pelas três lupas (página inicial, loja e menu).
final MemoriaPesquisa<List<SugestaoLupa>> memoriaSugestoes =
    MemoriaPesquisa<List<SugestaoLupa>>(
  validade: kMemoriaSugestoes,
  maximo: 80,
);

/// Lê as linhas da RPC, ignorando o que não for um mapa ou vier sem texto.
List<SugestaoLupa> sugestoesDasLinhas(Object? linhas) {
  if (linhas is! List) return const <SugestaoLupa>[];
  return List<SugestaoLupa>.unmodifiable(
    linhas
        .whereType<Map<String, dynamic>>()
        .map(SugestaoLupa.deMapa)
        .where((s) => s.texto.trim().isNotEmpty),
  );
}

/// O pedido verdadeiro ao servidor. Com o interruptor
/// `lupa_sugestoes_enabled` desligado, o servidor devolve lista vazia.
Future<List<SugestaoLupa>> sugestoesDoServidor(
    String texto, String? restaurantId) async {
  final linhas = await Supabase.instance.client.rpc(
    'lupa_sugestoes',
    params: {'p_q': texto, 'p_restaurant_id': restaurantId},
  ).timeout(const Duration(seconds: 6));
  return sugestoesDasLinhas(linhas);
}
