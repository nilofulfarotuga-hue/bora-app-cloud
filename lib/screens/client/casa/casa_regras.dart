// CASA — regras puras do lado do cliente (31/10/2026, missão casa-manutencao).
//
// Vivem fora dos ecrãs de propósito (mesmo princípio do CarwashFormCheck e do
// falha_de_acao.dart): são lógica pura, por isso os testes chegam-lhes sem
// montar UI nem rede. Os ecrãs só traduzem o resultado em widgets.
//
// NADA aqui calcula dinheiro a sério: o total que se mostra no assistente é só
// indicativo — o servidor (casa_criar_pedido / casa_aceitar_orcamento) recalcula
// sempre e é a única fonte de verdade.

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../l10n/tr.dart';
import '../../../models/casa_models.dart';
import '../../../utils/hora_lisboa.dart';

// ── preço e quantidade ──────────────────────────────────────────────────────

/// Total indicativo de um serviço de preço fixo ou à hora. `null` no orçamento
/// (o preço vem dos profissionais) ou quando o servidor não mandou preço.
int? casaTotalEstimadoCents(CasaServico servico, double quantidade) {
  final preco = servico.precoCents;
  if (servico.pedeOrcamento || preco == null) return null;
  return (preco * quantidade).round();
}

/// "desde 25,00 €" / "desde 20,00 € por hora" / "Pedir orçamento — grátis…".
/// O número vem SEMPRE do servidor (preco_cents); nunca está escrito no código.
String casaTextoPreco(CasaServico servico, {required int quoteMaxPros}) {
  if (servico.pedeOrcamento) {
    return 'Pedir orçamento — grátis, até {0} profissionais respondem'.trArgs([quoteMaxPros]);
  }
  final preco = servico.precoCents;
  if (preco == null) return 'Preço a confirmar'.tr;
  final euros = casaEuro(preco);
  if (servico.modo == CasaModo.hora || servico.unidade == 'hora') {
    return 'desde {0} por hora'.trArgs([euros]);
  }
  if (servico.unidade == 'movel') {
    return 'desde {0} por móvel'.trArgs([euros]);
  }
  return 'desde {0}'.trArgs([euros]);
}

/// Passo do botão de mais/menos: meia hora quando o catálogo usa meias.
double casaPassoQuantidade(CasaServico servico) =>
    (servico.minQuantidade % 1 != 0 || servico.maxQuantidade % 1 != 0)
        ? 0.5
        : 1;

String _numero(double q) => q % 1 == 0
    ? q.toInt().toString()
    : q.toStringAsFixed(1).replaceAll('.', ',');

/// Pergunta por cima do botão de mais/menos.
String casaRotuloQuantidade(CasaServico servico) {
  if (servico.modo == CasaModo.hora || servico.unidade == 'hora') {
    return 'Quantas horas?'.tr;
  }
  if (servico.unidade == 'movel') return 'Quantos móveis?'.tr;
  return 'Quantidade'.tr;
}

/// "2 h", "3 móveis", "× 2".
String casaQuantidadeTexto(CasaServico servico, double q) {
  final n = _numero(q);
  if (servico.modo == CasaModo.hora || servico.unidade == 'hora') {
    return '{0} h'.trArgs([n]);
  }
  if (servico.unidade == 'movel') {
    return q == 1 ? '1 móvel'.tr : '{0} móveis'.trArgs([n]);
  }
  return '× {0}'.trArgs([n]);
}

/// "≈ 1 h 30 min".
String casaDuracaoTexto(int minutos) {
  if (minutos <= 0) return '';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  if (h == 0) return '≈ {0} min'.trArgs([m]);
  if (m == 0) return '≈ {0} h'.trArgs([h]);
  return '≈ {0} h {1} min'.trArgs([h, m]);
}

/// Dia e hora em Lisboa (nunca a hora do telemóvel): "31/10/2026 às 14:30".
String casaQuandoTexto(DateTime instante) {
  final d = paredeLisboa(instante);
  String two(int n) => n.toString().padLeft(2, '0');
  return '{0}/{1}/{2} às {3}:{4}'.trArgs([
    two(d.day),
    two(d.month),
    d.year,
    two(d.hour),
    two(d.minute),
  ]);
}

// ── pagamento ───────────────────────────────────────────────────────────────

/// Decisão 3 do Danilo (30/10): dinheiro em mão só até max_cash_cents.
bool casaDinheiroPermitido(int totalCents, int maxCashCents) =>
    totalCents <= maxCashCents;

class CasaMetodoPagamento {
  const CasaMetodoPagamento({
    required this.codigo,
    required this.rotulo,
    required this.disponivel,
  });

  /// cash | card | mbway (os valores que o servidor aceita).
  final String codigo;
  final String rotulo;
  final bool disponivel;
}

/// Os três métodos, pela ordem do ecrã, com o que está ou não disponível.
/// Cartão e MB Way ficam "brevemente" enquanto `casa_config().pagamento_cartao`
/// for false (nesta fase é sempre false — só proposta em docs/propostas).
List<CasaMetodoPagamento> casaMetodosPagamento({
  required int totalCents,
  required CasaConfig config,
  bool cartaoNestaPlataforma = !kIsWeb,
}) {
  final dinheiro = casaDinheiroPermitido(totalCents, config.maxCashCents);
  final cartao = config.pagamentoCartao;
  return [
    CasaMetodoPagamento(
      codigo: 'cash',
      rotulo: dinheiro
          ? 'Dinheiro (no local)'.tr
          : 'Dinheiro — só até {0}'.trArgs([casaEuro(config.maxCashCents)]),
      disponivel: dinheiro,
    ),
    CasaMetodoPagamento(
      codigo: 'card',
      // O cartão (folha da Stripe) só existe na app do telemóvel; na web fica o MB Way (m11).
      rotulo: !cartao
          ? 'Cartão — brevemente'.tr
          : cartaoNestaPlataforma
              ? 'Cartão'.tr
              : 'Cartão — só na app do telemóvel'.tr,
      disponivel: cartao && cartaoNestaPlataforma,
    ),
    CasaMetodoPagamento(
      codigo: 'mbway',
      rotulo: cartao ? 'MB Way'.tr : 'MB Way — brevemente'.tr,
      disponivel: cartao,
    ),
  ];
}

/// Primeiro método disponível (o que o ecrã escolhe sozinho), ou null.
String? casaMetodoPorDefeito({
  required int totalCents,
  required CasaConfig config,
}) {
  for (final m in casaMetodosPagamento(totalCents: totalCents, config: config)) {
    if (m.disponivel) return m.codigo;
  }
  return null;
}

/// Frase que explica porque é que o dinheiro não aparece.
String casaExplicacaoDinheiro(CasaConfig config) {
  final limite = casaEuro(config.maxCashCents);
  if (config.pagamentoCartao) {
    return 'Acima de {0} só cartão ou MB Way.'.trArgs([limite]);
  }
  return 'Acima de {0} só cartão ou MB Way, que chegam brevemente. Por agora, reduz a quantidade ou divide em dois pedidos.'.trArgs([limite]);
}

/// Porque é que um método de pagamento está cinzento (PADRAO_BORA 1.2 — o
/// toque nunca fica mudo). A Casa não tem carteira: só dinheiro, cartão e
/// MB Way, e estes dois só quando `pagamento_cartao` estiver ligado.
String casaPorqueIndisponivel(
  String codigo, {
  required int totalCents,
  required CasaConfig config,
}) {
  final dinheiro = casaDinheiroPermitido(totalCents, config.maxCashCents);
  // Cartão ligado mas cinzento = estamos na web (a folha do cartão só existe na app do telemóvel).
  if (codigo == 'card' && config.pagamentoCartao) {
    return 'O cartão só dá na app do telemóvel. Aqui, paga com MB Way.'.tr;
  }
  if (codigo == 'cash' || !dinheiro) return casaExplicacaoDinheiro(config);
  return 'Cartão e MB Way chegam brevemente. Por agora, paga em dinheiro.'.tr;
}

/// "Aceite e pago" — decisão 4: cartão/MB Way = pagamento retido; dinheiro =
/// trabalho confirmado (paga-se em mão, não há pré-pagamento).
bool casaPedidoPago(CasaPedido p) {
  if (p.paymentMethod == 'cash') return p.estado == CasaEstado.confirmado;
  return p.paymentStatus == 'held' || p.paymentStatus == 'released';
}

// ── estados ─────────────────────────────────────────────────────────────────

/// O mesmo texto de [CasaEstado.textoPt], mas com tradução para inglês (o
/// gerador do dicionário só vê frases escritas no código com `.tr`).
String casaEstadoTr(CasaEstado e) => switch (e) {
      CasaEstado.aguardaPagamento => 'À espera do pagamento'.tr,
      CasaEstado.procura => 'À procura de profissional'.tr,
      CasaEstado.orcamentos => 'À espera de orçamentos'.tr,
      CasaEstado.aceite => 'Confirmado'.tr,
      CasaEstado.aCaminho => 'Profissional a caminho'.tr,
      CasaEstado.chegou => 'Profissional chegou'.tr,
      CasaEstado.emCurso => 'Trabalho em curso'.tr,
      CasaEstado.concluido => 'Concluído — confirma'.tr,
      CasaEstado.confirmado => 'Concluído'.tr,
      CasaEstado.disputa => 'Pedido para refazer'.tr,
      CasaEstado.cancelado => 'Cancelado'.tr,
      CasaEstado.expirado => 'Sem profissional disponível'.tr,
    };

/// Passos da linha do tempo. O orçamento começa à espera de orçamentos; o preço
/// fixo começa à procura de profissional.
List<CasaEstado> casaPassosDaLinha(CasaModo modo) => [
      modo == CasaModo.orcamento ? CasaEstado.orcamentos : CasaEstado.procura,
      CasaEstado.aceite,
      CasaEstado.aCaminho,
      CasaEstado.chegou,
      CasaEstado.emCurso,
      CasaEstado.concluido,
      CasaEstado.confirmado,
    ];

/// Rótulo curto de cada passo da linha do tempo.
String casaRotuloPasso(CasaEstado e) => switch (e) {
      CasaEstado.procura => 'À procura de profissional'.tr,
      CasaEstado.orcamentos => 'À espera de orçamentos'.tr,
      CasaEstado.aceite => 'Profissional confirmado'.tr,
      CasaEstado.aCaminho => 'A caminho'.tr,
      CasaEstado.chegou => 'Chegou'.tr,
      CasaEstado.emCurso => 'Trabalho em curso'.tr,
      CasaEstado.concluido => 'Trabalho concluído'.tr,
      CasaEstado.confirmado => 'Confirmado por ti'.tr,
      _ => casaEstadoTr(e),
    };

/// Onde o pedido está na linha do tempo. -1 = fora da linha (cancelado ou
/// expirado: o ecrã mostra uma faixa em vez da linha).
int casaIndiceNaLinha(CasaEstado e, List<CasaEstado> passos) {
  if (e == CasaEstado.cancelado || e == CasaEstado.expirado) return -1;
  if (e == CasaEstado.aguardaPagamento) return 0;
  if (e == CasaEstado.disputa) return passos.indexOf(CasaEstado.concluido);
  final i = passos.indexOf(e);
  return i < 0 ? 0 : i;
}

/// Selos do profissional, em texto para o cliente.
String casaSeloTr(String selo) => switch (selo) {
      'documentos_verificados' => 'Documentos verificados'.tr,
      'seguro' => 'Com seguro'.tr,
      'dgeg' => 'Certificado DGEG'.tr,
      'impic' => 'Certificado IMPIC'.tr,
      _ => selo,
    };

// ── o que o cliente pode fazer em cada estado ───────────────────────────────

/// Um orçamento ainda se pode aceitar: enviado e dentro da validade (o servidor
/// recusa os expirados com `orcamento_expirado`).
bool casaOrcamentoAceitavel(CasaOrcamento o, DateTime agora) {
  final expira = o.expiraEm;
  return o.aberto && (expira == null || agora.isBefore(expira));
}


/// Que botões aparecem no acompanhamento. Uma regra só, testada em
/// `test/casa_cliente_regras_test.dart`. O servidor volta a verificar tudo.
class CasaAcoesCliente {
  const CasaAcoesCliente({
    this.aceitarOrcamentos = false,
    this.responderExtras = false,
    this.confirmarConclusao = false,
    this.avaliar = false,
    this.refazer = false,
    this.cancelar = false,
    this.contactar = false,
    this.adicionarFotos = false,
  });

  final bool aceitarOrcamentos;
  final bool responderExtras;
  final bool confirmarConclusao;
  final bool avaliar;
  final bool refazer;
  final bool cancelar;
  final bool contactar;
  final bool adicionarFotos;

  factory CasaAcoesCliente.de(
    CasaPedido p, {
    required DateTime agora,
    int maxFotos = 5,
  }) {
    final e = p.estado;
    final garantia = p.garantiaAte;
    return CasaAcoesCliente(
      aceitarOrcamentos: e == CasaEstado.orcamentos &&
          p.orcamentos.any((o) => casaOrcamentoAceitavel(o, agora)),
      // Mesmos estados que o servidor (casa_responder_extra).
      responderExtras: const {
            CasaEstado.aceite,
            CasaEstado.aCaminho,
            CasaEstado.chegou,
            CasaEstado.emCurso,
          }.contains(e) &&
          p.extrasPorResponder.isNotEmpty,
      confirmarConclusao: e == CasaEstado.concluido,
      // Avaliação só de quem pagou, e uma vez.
      avaliar: e == CasaEstado.confirmado &&
          p.ratingCliente == null &&
          casaPedidoPago(p),
      // Garantia: antes de confirmar, ou depois até garantia_ate.
      refazer: p.refazerPedidoEm == null &&
          (e == CasaEstado.concluido ||
              (e == CasaEstado.confirmado &&
                  garantia != null &&
                  agora.isBefore(garantia))),
      // Mesmos estados que o servidor (casa_cancelar); o custo vem sempre da
      // simulação antes de confirmar.
      cancelar: const {
        CasaEstado.aguardaPagamento,
        CasaEstado.procura,
        CasaEstado.orcamentos,
        CasaEstado.aceite,
        CasaEstado.aCaminho,
        CasaEstado.chegou,
      }.contains(e),
      // Decisão 4: chat e telefone só depois de aceite e pago (o servidor diz).
      contactar: p.podeContactar &&
          p.profissional != null &&
          e != CasaEstado.cancelado &&
          e != CasaEstado.expirado,
      adicionarFotos: const {
            CasaEstado.aguardaPagamento,
            CasaEstado.procura,
            CasaEstado.orcamentos,
            CasaEstado.aceite,
          }.contains(e) &&
          p.fotosDe('problema').length < maxFotos,
    );
  }
}

// ── validação do assistente ─────────────────────────────────────────────────

enum CasaCampo { pergunta, quantidade, descricao, data, rua, cidade, pagamento }

/// O primeiro campo que falta, com a frase a dizer ao cliente. O ecrã rola até
/// ao campo e mostra a frase — o botão nunca falha calado.
class CasaFalta {
  const CasaFalta(this.campo, this.mensagem, {this.perguntaId});

  final CasaCampo campo;
  final String mensagem;

  /// Só quando [campo] é [CasaCampo.pergunta].
  final String? perguntaId;
}

/// Passo 1 — o serviço. As perguntas de escolha são obrigatórias; no
/// orçamento é preciso dizer o que há a fazer (é com isso que se orça).
CasaFalta? casaFaltaNoServico({
  required CasaServico servico,
  required Map<String, String> respostas,
  required double quantidade,
  required String descricao,
}) {
  for (final p in servico.perguntas) {
    // Material (ordem do Danilo, 09/11): só se pede com "Sim, já tenho tudo",
    // mesmo que o painel um dia acrescente outra opção à pergunta.
    if (p.id == kCasaPerguntaMaterial &&
        (respostas[p.id] ?? '').trim() != kCasaMaterialSim) {
      return CasaFalta(
        CasaCampo.pergunta,
        'Para pedir, confirma que já tens todo o material: o profissional leva só as ferramentas.'.tr,
        perguntaId: p.id,
      );
    }
    if (p.escolha && (respostas[p.id] ?? '').trim().isEmpty) {
      return CasaFalta(
        CasaCampo.pergunta,
        'Falta responder: {0}'.trArgs([p.texto]),
        perguntaId: p.id,
      );
    }
  }
  if (!servico.pedeOrcamento &&
      (quantidade < servico.minQuantidade ||
          quantidade > servico.maxQuantidade)) {
    return CasaFalta(
      CasaCampo.quantidade,
      'Escolhe uma quantidade entre {0} e {1}.'.trArgs(
          [_numero(servico.minQuantidade), _numero(servico.maxQuantidade)]),
    );
  }
  if (servico.pedeOrcamento) {
    final escrito = [
      descricao,
      for (final p in servico.perguntas)
        if (!p.escolha) respostas[p.id] ?? '',
    ].join(' ').trim();
    if (escrito.length < 10) {
      return CasaFalta(
        CasaCampo.descricao,
        'Conta em poucas palavras o que é preciso fazer — ajuda os profissionais a dar o preço certo.'.tr,
      );
    }
  }
  return null;
}

/// Passo 2 — quando e onde.
CasaFalta? casaFaltaNoQuandoOnde({
  required DateTime? quando,
  required DateTime agora,
  required int minLeadHours,
  required String rua,
  required String cidade,
}) {
  if (quando == null) {
    return CasaFalta(CasaCampo.data, 'Escolhe o dia e a hora.'.tr);
  }
  if (quando.isBefore(agora.add(Duration(hours: minLeadHours)))) {
    return CasaFalta(
      CasaCampo.data,
      'Escolhe uma hora com pelo menos {0} h de antecedência.'.trArgs([minLeadHours]),
    );
  }
  if (rua.trim().length < 4) {
    return CasaFalta(CasaCampo.rua, 'Falta a rua e o número.'.tr);
  }
  if (cidade.trim().isEmpty) {
    return CasaFalta(CasaCampo.cidade, 'Falta a localidade.'.tr);
  }
  return null;
}

/// Passo 3 — pagamento (só no preço fixo e à hora; no orçamento escolhe-se ao
/// aceitar o orçamento).
CasaFalta? casaFaltaNoPagamento({
  required CasaServico servico,
  required String? metodo,
  required int totalCents,
  required CasaConfig config,
}) {
  if (servico.pedeOrcamento) return null;
  final metodos = casaMetodosPagamento(totalCents: totalCents, config: config);
  final escolhido = metodos.where((m) => m.codigo == metodo && m.disponivel);
  if (escolhido.isNotEmpty) return null;
  if (!metodos.any((m) => m.disponivel)) {
    return CasaFalta(CasaCampo.pagamento, casaExplicacaoDinheiro(config));
  }
  return CasaFalta(CasaCampo.pagamento, 'Escolhe como queres pagar.'.tr);
}

// ── morada ──────────────────────────────────────────────────────────────────

class CasaMoradaPartida {
  const CasaMoradaPartida({
    required this.rua,
    required this.cidade,
    required this.codigoPostal,
  });

  final String rua;
  final String cidade;
  final String codigoPostal;
}

final RegExp _codigoPostal = RegExp(r'(\d{4}-\d{3})\s*([^,]*)');

/// Parte a linha única da morada automática (Google, pt-PT:
/// "R. Dr. Francisco 12, 6300-690 Guarda, Portugal") nos três campos que a
/// RPC casa_criar_pedido pede. Sem código postal, a última parte é a
/// localidade. Nunca falha: no pior caso fica tudo na rua.
CasaMoradaPartida casaPartirMorada(String linha) {
  var texto = linha.trim();
  texto = texto.replaceAll(RegExp(r',?\s*Portugal\s*$', caseSensitive: false), '');
  final m = _codigoPostal.firstMatch(texto);
  if (m != null) {
    final rua = texto
        .substring(0, m.start)
        .trim()
        .replaceAll(RegExp(r'[,\s]+$'), '');
    return CasaMoradaPartida(
      rua: rua,
      cidade: (m.group(2) ?? '').trim(),
      codigoPostal: m.group(1) ?? '',
    );
  }
  final partes = texto
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (partes.length < 2) {
    return CasaMoradaPartida(rua: texto, cidade: '', codigoPostal: '');
  }
  return CasaMoradaPartida(
    rua: partes.sublist(0, partes.length - 1).join(', '),
    cidade: partes.last,
    codigoPostal: '',
  );
}
