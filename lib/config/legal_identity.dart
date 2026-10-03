/// Identidade legal de quem opera a Bora — fonte única na app.
///
/// A Bora é operada por um empresário em nome individual (lei portuguesa).
/// Estes dados aparecem no ecrã "Sobre / Informação legal" (cliente, estafeta
/// e parceiro) e são os mesmos que já constam em `ios/NOTAS-AO-REVISOR.md` e
/// `ios/CHECKLIST-APPLE.md`. Regra dos gémeos: **nunca** escrever outro NIF
/// ou outra morada noutro sítio — quem precisar lê daqui.
///
/// Missão ronda-fecho-2026-09-22, bloco D1.
library;

class LegalIdentity {
  LegalIdentity._();

  // ── Operador ───────────────────────────────────────────────────────────
  static const String appName = 'Bora';
  static const String nome = 'Danilo Fulfaro da Silva';
  static const String qualidade = 'empresário em nome individual';
  static const String nif = '322151171';
  static const String morada = 'Rua do Torreão 14, 6300-610 Guarda, Portugal';

  // ── Contactos ──────────────────────────────────────────────────────────
  static const String email = 'boraappbora@gmail.com';

  /// Como se mostra no ecrã.
  static const String telefone = '+351 937 501 673';

  /// Como vai no `tel:` (sem espaços, formato E.164).
  static const String telefoneE164 = '+351937501673';

  // ── Resolução alternativa de litígios (Lei n.º 144/2015) ───────────────
  static const String ralAviso =
      'Em caso de litígio, o consumidor pode recorrer a uma entidade de '
      'resolução alternativa de litígios de consumo (Lei n.º 144/2015).';

  static const String cniaccSigla = 'CNIACC';
  static const String cniaccNome =
      'Centro Nacional de Informação e Arbitragem de Conflitos de Consumo';
  static const String cniaccUrl = 'https://www.cniacc.pt';

  static const String caccdcSigla = 'CACCDC';
  static const String caccdcNome =
      'Centro de Arbitragem de Conflitos de Consumo do Distrito de Coimbra';

  /// O centro de Coimbra é o competente para o distrito da Guarda.
  static const String caccdcNota = 'Competente para a Guarda';
  static const String caccdcUrl = 'https://www.centrodearbitragemdecoimbra.com';

  static const String odrNome = 'Plataforma ODR da União Europeia';
  static const String odrNota = 'Resolução de litígios em linha';
  static const String odrUrl = 'https://ec.europa.eu/consumers/odr';

  // ── Livro de Reclamações Eletrónico ────────────────────────────────────
  static const String livroReclamacoesUrl =
      'https://www.livroreclamacoes.pt/Inicio/';

  // ── Documentos legais (site institucional) ─────────────────────────────
  static const String termosUrl = 'https://boraguarda.com/termos';
  static const String privacidadeUrl = 'https://boraguarda.com/privacidade';
}
