/// Atalhos da lupa (15/10/2026): a pesquisa única também leva aos serviços
/// do Bora que não são lojas — motorista, limpeza, beleza — e às secções da
/// home. Quem escreve "táxi" ou "barbearia" deixa de ver "não encontrámos".
///
/// As chaves são as de `categoriasDestino` (`home_destino.dart`) e abrem-se
/// com `abrirCategoria`. As palavras estão em minúsculas e sem acentos.
library;

import 'cozinhas.dart' show normalizarTexto;

const Map<String, List<String>> _palavrasAtalho = {
  'motorista': [
    'motorista', 'taxi', 'uber', 'bolt', 'boleia', 'corrida', 'viagem',
    'transporte', 'tvde', 'aeroporto', 'estacao', 'carro com motorista',
  ],
  'limpeza': [
    'limpeza', 'limpar', 'empregada', 'faxina', 'diarista', 'arrumar casa',
    'passar a ferro', 'engomar',
  ],
  'servicos': [
    'beleza', 'barbearia', 'barbeiro', 'cabeleireiro', 'cabelo', 'corte',
    'barba', 'unhas', 'manicure', 'pedicure', 'salao', 'estetica',
    'sobrancelha', 'pestanas', 'depilacao', 'massagem', 'marcacao',
  ],
  'supermercados': ['supermercado', 'mercado', 'mercearia', 'compras'],
  'farmacia': ['farmacia', 'medicamento', 'remedio'],
  'restaurantes': ['restaurante', 'comida', 'almoco', 'jantar'],
  'festas': ['festa', 'aniversario'],
  'sobremesas': ['sobremesa', 'doce'],
  'lojas': ['loja'],
};

/// Chaves de `categoriasDestino` que a pesquisa [q] pede, pela ordem do mapa.
///
/// Casa quando a pesquisa contém uma palavra inteira ("táxi para a estação")
/// ou quando é o começo de uma palavra com pelo menos 3 letras ("barb").
List<String> atalhosDaPesquisa(String q) {
  final n = normalizarTexto(q);
  if (n.length < 2) return const [];
  final termos = n.split(' ');
  final out = <String>[];
  _palavrasAtalho.forEach((chave, palavras) {
    final casa = palavras.any((p) =>
        (n.length >= 3 && p.startsWith(n)) ||
        (p.contains(' ') ? n.contains(p) : termos.contains(p)));
    if (casa) out.add(chave);
  });
  return out;
}
