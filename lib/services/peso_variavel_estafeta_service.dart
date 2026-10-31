// Peso variável — o estafeta escreve o valor da balança (31/10/2026).
//
// Regra do Danilo (26/10, "Autorizo" 10:16; business_rules §59): nos mercados
// não-parceiros os produtos ao quilo (`products.variable_weight`) mudam de
// preço na balança. O estafeta toca no preço da linha e escreve o TOTAL da
// etiqueta dessa linha (ex.: as 4 bananas juntas). O servidor
// (`estafeta_ajustar_peso`) recusa fora do limite (±30 %), calcula o preço novo
// ao cliente com a mesma margem, grava em `order_weight_adjustments` e avisa o
// cliente. O talão (`finalizar_talao_nao_parceiro`) aplica a diferença
// sozinho. A app não escreve nenhuma coluna financeira.
//
// Cicatriz (31/10, pedido 48669acf, Continente): a melancia saiu 9,06 € na
// balança e estava na app a 7,14 €; o estafeta não tinha onde pôr o valor.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Um ajuste já gravado (ou acabado de gravar) para uma linha do pedido.
class AjustePesoEstafeta {
  const AjustePesoEstafeta({
    required this.productId,
    required this.estimadoCaixaCents,
    required this.realCaixaCents,
    required this.estimadoClienteCents,
    required this.novoClienteCents,
  });

  final String productId;
  final int estimadoCaixaCents;
  final int realCaixaCents;
  final int estimadoClienteCents;
  final int novoClienteCents;

  /// Diferença do lado do cliente (positivo = paga mais).
  int get diferencaClienteCents => novoClienteCents - estimadoClienteCents;

  /// Linha de `order_weight_adjustments`.
  static AjustePesoEstafeta? daTabela(Map<String, dynamic> m) {
    final id = m['product_id'];
    if (id is! String || id.isEmpty) return null;
    return AjustePesoEstafeta(
      productId: id,
      estimadoCaixaCents: _int(m['est_base_cents']),
      realCaixaCents: _int(m['real_base_cents']),
      estimadoClienteCents: _int(m['est_client_cents']),
      novoClienteCents: _int(m['new_client_cents']),
    );
  }

  /// Resposta ok de `estafeta_ajustar_peso`.
  static AjustePesoEstafeta daResposta(
      String productId, Map<String, dynamic> m) {
    return AjustePesoEstafeta(
      productId: productId,
      estimadoCaixaCents: _int(m['estimado_caixa_cents']),
      realCaixaCents: _int(m['real_caixa_cents']),
      estimadoClienteCents: _int(m['estimado_cliente_cents']),
      novoClienteCents: _int(m['novo_cliente_cents']),
    );
  }

  static int _int(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
}

class PesoVariavelResultado {
  const PesoVariavelResultado._({
    required this.ok,
    this.ajuste,
    this.codigo,
    this.mensagem,
    this.minimoCents,
    this.maximoCents,
  });

  factory PesoVariavelResultado.sucesso(AjustePesoEstafeta ajuste) =>
      PesoVariavelResultado._(ok: true, ajuste: ajuste);

  factory PesoVariavelResultado.erro(
    String codigo, {
    int? minimoCents,
    int? maximoCents,
  }) =>
      PesoVariavelResultado._(
        ok: false,
        codigo: codigo,
        minimoCents: minimoCents,
        maximoCents: maximoCents,
        mensagem: PesoVariavelEstafetaService.mensagemErro(codigo,
            minimoCents: minimoCents, maximoCents: maximoCents),
      );

  final bool ok;
  final AjustePesoEstafeta? ajuste;

  /// Código do servidor (ex.: fora_do_limite) ou `sem_rede`.
  final String? codigo;

  /// Texto PT-PT pronto para o ecrã.
  final String? mensagem;
  final int? minimoCents;
  final int? maximoCents;
}

class PesoVariavelEstafetaService {
  static const rpcAjustar = 'estafeta_ajustar_peso';

  /// Limite que a folha mostra antes do primeiro envio. Quem manda é o
  /// servidor (`weight_adjust_max_pct`); se recusar, a folha passa a mostrar o
  /// intervalo que ele devolveu.
  static const int limitePctPrevisto = 30;

  /// Intervalo aceite (mínimo, máximo) em cêntimos, com a mesma conta do
  /// servidor (CEIL do mínimo, FLOOR do máximo), sem vírgula flutuante.
  static (int, int) intervalo(int estimadoCents,
      {int pct = limitePctPrevisto}) {
    final minimo = (estimadoCents * (100 - pct) + 99) ~/ 100;
    final maximo = (estimadoCents * (100 + pct)) ~/ 100;
    return (minimo, maximo);
  }

  /// "1,20 €".
  static String euros(int cents) {
    final negativo = cents < 0;
    final c = cents.abs();
    final txt = '${c ~/ 100},${(c % 100).toString().padLeft(2, '0')} €';
    return negativo ? '-$txt' : txt;
  }

  static String mensagemErro(String codigo,
      {int? minimoCents, int? maximoCents}) {
    switch (codigo) {
      case 'fora_do_limite':
        final faixa = (minimoCents != null && maximoCents != null)
            ? ' Aceite: ${euros(minimoCents)} a ${euros(maximoCents)}.'
            : '';
        return 'Diferença grande. Pesa outra vez (tira ou põe uma peça) '
            'ou marca "Não há".$faixa';
      case 'valor_invalido':
        return 'Escreve o valor da etiqueta em euros (ex.: 1,20).';
      case 'compra_ja_fechada':
        return 'A compra deste pedido já foi fechada: já não dá para mudar o '
            'peso.';
      case 'desligado':
        return 'O ajuste de peso está desligado de momento. Compra ao preço '
            'da app e avisa o suporte.';
      case 'produto_sem_peso_variavel':
        return 'Este produto não se vende ao quilo.';
      case 'produto_fora_do_pedido':
        return 'Este produto já não está no pedido. Atualiza a lista.';
      case 'loja_parceira':
        return 'Nas lojas parceiras o preço não se muda aqui.';
      case 'tipo_de_pedido':
        return 'Este tipo de pedido não tem ajuste de peso.';
      case 'preco_estimado_invalido':
        return 'O preço previsto deste produto está errado. Avisa o suporte.';
      case 'NOT_ASSIGNED_DRIVER':
        return 'Este pedido não está atribuído a ti.';
      case 'UNAUTHENTICATED':
        return 'Sessão expirada. Inicia sessão de novo.';
      case 'sem_rede':
        return 'Sem ligação. Verifica a internet e toca outra vez em '
            '"Confirmar".';
      default:
        return 'Não foi possível guardar o peso. Tenta outra vez.\n'
            'Código: $codigo';
    }
  }

  /// Ajustes já gravados neste pedido (para repor o estado ao reabrir a
  /// lista). Best-effort: sem rede devolve vazio.
  static Future<Map<String, AjustePesoEstafeta>> ajustesDoPedido(
      String orderId) async {
    try {
      final rows = await Supabase.instance.client
          .from('order_weight_adjustments')
          .select(
              'product_id, est_base_cents, real_base_cents, est_client_cents, new_client_cents')
          .eq('order_id', orderId);
      final out = <String, AjustePesoEstafeta>{};
      for (final r in rows as List) {
        final a = AjustePesoEstafeta.daTabela(Map<String, dynamic>.from(r as Map));
        if (a != null) out[a.productId] = a;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Grava o valor da balança. Nunca lança.
  static Future<PesoVariavelResultado> ajustar({
    required String orderId,
    required String productId,
    required int realCaixaCents,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc(rpcAjustar, params: {
        'p_order_id': orderId,
        'p_product_id': productId,
        'p_real_base_cents': realCaixaCents,
      });
      final m = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      return lerResposta(productId, m);
    } on PostgrestException catch (e) {
      return PesoVariavelResultado.erro(_codigoDaExcecao(e.message));
    } catch (e) {
      final txt = e.toString();
      final semRede = txt.contains('SocketException') ||
          txt.contains('ClientException') ||
          txt.contains('Failed host lookup') ||
          txt.contains('TimeoutException');
      return PesoVariavelResultado.erro(
          semRede ? 'sem_rede' : _codigoDaExcecao(txt));
    }
  }

  /// Lê a resposta da RPC (pura, testável).
  static PesoVariavelResultado lerResposta(
      String productId, Map<String, dynamic> m) {
    if (m['ok'] == true) {
      return PesoVariavelResultado.sucesso(
          AjustePesoEstafeta.daResposta(productId, m));
    }
    final codigo = (m['erro'] ?? m['error'] ?? 'resposta_invalida').toString();
    int? cents(Object? v) => v is num ? v.round() : null;
    return PesoVariavelResultado.erro(codigo,
        minimoCents: cents(m['minimo_cents']),
        maximoCents: cents(m['maximo_cents']));
  }

  static String _codigoDaExcecao(String texto) {
    final m = RegExp(r'\b([A-Z][A-Z0-9_]{3,})\b').firstMatch(texto);
    return m?.group(1) ?? 'erro_desconhecido';
  }
}
