/// Identidade legal de quem opera a Bora — fonte única na app.
///
/// Desde 09/10/2026 a Bora é operada pela sociedade unipessoal
/// "Danilo Fulfaro da Silva - Unipessoal Lda" (DL 24/2014, art. 4.º; RGPD,
/// art. 13.º — identidade do prestador/responsável). Estes dados aparecem no
/// ecrã "Sobre / Informação legal" (cliente, estafeta e parceiro). Regra dos
/// gémeos: **nunca** escrever outro NIPC ou outra morada noutro sítio da app —
/// quem precisar lê daqui.
///
/// Missão ronda-fecho-2026-09-22, bloco D1; empresa em vez do empresário em
/// nome individual na missão fechar-tudo-2026-11-10, bloco E1. O Bora
/// Motorista (TVDE, fechado) tem textos próprios que não mudam aqui.
library;

class LegalIdentity {
  LegalIdentity._();

  // ── Operador ───────────────────────────────────────────────────────────
  static const String appName = 'Bora';
  static const String nome = 'Danilo Fulfaro da Silva - Unipessoal Lda';
  static const String qualidade = 'sociedade unipessoal por quotas';

  /// Número de identificação de pessoa coletiva (é o NIF da sociedade).
  static const String nipc = '519686233';

  /// Sede da sociedade.
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

  // A plataforma europeia de resolução de litígios em linha (ODR) fechou
  // (Regulamento (UE) 2024/3228): o link saiu da app em 10/11/2026 (E2b).

  // ── Livro de Reclamações Eletrónico (DL 156/2005, art. 5.º-B) ─────────
  static const String livroReclamacoesUrl =
      'https://www.livroreclamacoes.pt/Inicio/';

  // ── Documentos legais (site institucional) ─────────────────────────────
  static const String termosUrl = 'https://boraguarda.com/termos';
  static const String privacidadeUrl = 'https://boraguarda.com/privacidade';
}
