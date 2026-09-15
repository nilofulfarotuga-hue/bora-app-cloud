/// B6 (2026-06-12) — Os 14 alergénios de declaração obrigatória na UE
/// (Regulamento 1169/2011, Anexo II). Slugs = valores guardados em
/// `products.allergens` (text[]); labels = exibição PT-PT.
/// Informativo apenas — nunca bloqueia a criação de pedidos.
const Map<String, String> kAllergenLabels = {
  'gluten': 'Glúten',
  'crustaceos': 'Crustáceos',
  'ovos': 'Ovos',
  'peixe': 'Peixe',
  'amendoins': 'Amendoins',
  'soja': 'Soja',
  'leite': 'Leite',
  'frutos_casca_rija': 'Frutos de casca rija',
  'aipo': 'Aipo',
  'mostarda': 'Mostarda',
  'sesamo': 'Sésamo',
  'sulfitos': 'Dióxido de enxofre e sulfitos',
  'tremocos': 'Tremoços',
  'moluscos': 'Moluscos',
};
