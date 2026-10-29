/// Etiquetas do menu (adendo 4 · item 5, 29/10/2026): vegetariano, picante e
/// sem glúten.
///
/// A IA sugere-as a partir da descrição do prato (Edge Function
/// `etiquetas-menu-ia`) e o parceiro corrige no ecrã dos produtos. Guardam-se em
/// `products.diet_tags` (texto, uma etiqueta por entrada) com a origem em
/// `diet_tags_source` ('ia' ou 'parceiro').
///
/// Atenção: NÃO substituem os alergénios (os 14 da lei, `allergens`). "Sem
/// glúten" é uma indicação do parceiro, não uma garantia médica.
library;

/// Os nomes gravados na base, por ordem fixa de apresentação.
const List<String> kEtiquetasDieta = <String>[
  'vegetariano',
  'picante',
  'sem_gluten',
];

/// O texto que o cliente lê (PT-PT).
const Map<String, String> kEtiquetasDietaTexto = <String, String>{
  'vegetariano': 'Vegetariano',
  'picante': 'Picante',
  'sem_gluten': 'Sem glúten',
};

/// Só as etiquetas conhecidas, sem repetidas, por ordem fixa. Aceita "sem
/// gluten", "Sem-Glúten" e afins.
List<String> normalizarEtiquetas(Iterable<Object?>? bruto) {
  if (bruto == null) return const <String>[];
  final vistas = <String>{
    for (final e in bruto)
      e
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll('ú', 'u')
          .replaceAll(RegExp(r'[\s-]+'), '_'),
  };
  return <String>[
    for (final t in kEtiquetasDieta)
      if (vistas.contains(t)) t,
  ];
}

/// `products.diet_tags` (text[]) vindo da base → lista limpa. Nunca lança.
List<String> etiquetasDeLinha(Object? coluna) =>
    coluna is List ? normalizarEtiquetas(coluna) : const <String>[];
