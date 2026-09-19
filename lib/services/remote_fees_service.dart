import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// TAXA DE SERVIÇO DAS LOJAS SEM CONTRATO (2026-09-08).
///
/// Decisão do Danilo a 08/09: a taxa fixa do não-parceiro desceu de **2,50 €**
/// para **0,99 €** (a diferença passou para dentro do preço dos produtos, +6%).
/// O servidor já cobra 0,99 € — `platform_settings.non_partner_service_fee_cents`
/// e a função `quote_order_pricing`/`pricing_calculate` foram actualizadas nesse
/// dia. A app, porém, continuava a mostrar 2,50 € porque o número vive numa
/// constante dentro de `lib/services/pricing_service.dart`, que é **zona
/// protegida** (a Trava proíbe editá-lo).
///
/// Este serviço é o caminho de fuga aprovado: lê o valor do servidor e os ecrãs
/// do cliente passam a mostrá-lo. `pricing_service.dart` fica intocado — a
/// constante `_nonPartnerPurchaseFee = 2.5` continua lá e continua a ser a base
/// do cálculo, mas deixa de ser o que o cliente vê. Isso é **dívida técnica
/// assumida**: quando a Trava permitir, a constante deve passar a ler daqui.
///
/// ## Duas chaves, não uma
///
/// * `non_partner_service_fee_cents` — o que se cobra hoje (99).
/// * `non_partner_service_fee_strikethrough_cents` — o valor antigo (250), que
///   os ecrãs mostram **riscado** ao lado do actual, ao estilo da Uber e da
///   Glovo. Pôr 0 (ou apagar) faz o risco desaparecer sem tocar em código.
///
/// ## Regras de casa
///
/// * Nunca deita a app abaixo: toda a leitura é `try/catch` e os getters
///   síncronos não lançam.
/// * Sem leitura, ficam os valores de recurso (0,99 € e 2,50 € riscado) — os
///   mesmos que estão hoje no servidor, por isso o pior caso continua certo.
/// * `platform_settings` tem RLS de leitura **só para autenticados**: sem
///   sessão a resposta é `HTTP 200` com `[]`, sem erro nenhum. Uma lista vazia
///   NÃO marca como carregado — volta a tentar-se depois de entrar. (Mesma
///   cicatriz do interruptor 5.2.1 em `lib/config/ios_launch_flags.dart`.)
@immutable
class TaxaServicoNaoParceiro {
  const TaxaServicoNaoParceiro({
    required this.atualCents,
    required this.riscoCents,
  });

  /// Cêntimos cobrados hoje ao cliente.
  final int atualCents;

  /// Cêntimos do valor antigo, para mostrar riscado. 0 = não mostrar risco.
  final int riscoCents;

  double get atualEur => atualCents / 100;

  /// Valor a riscar, em euros — `null` quando não há risco a mostrar.
  ///
  /// Só se risca quando o valor antigo é MAIOR que o actual: riscar um valor
  /// igual ou menor não é uma descida, é ruído (e num caso seria mentira).
  double? get riscoEur => riscoCents > atualCents ? riscoCents / 100 : null;
}

/// Lê do servidor as taxas que a app mostra ao cliente e guarda-as em memória
/// durante a sessão. Uma leitura por sessão; repetir não custa nada.
class RemoteFeesService {
  RemoteFeesService._();

  static const String kAtual = 'non_partner_service_fee_cents';
  static const String kRisco = 'non_partner_service_fee_strikethrough_cents';

  /// Valores de recurso — iguais ao que está no servidor a 2026-09-08.
  static const int fallbackAtualCents = 99;
  static const int fallbackRiscoCents = 250;

  static TaxaServicoNaoParceiro _taxa = const TaxaServicoNaoParceiro(
    atualCents: fallbackAtualCents,
    riscoCents: fallbackRiscoCents,
  );
  static bool _carregado = false;

  /// A taxa em vigor (lida do servidor, ou a de recurso).
  static TaxaServicoNaoParceiro get taxaServicoNaoParceiro => _taxa;

  /// Atalho: a taxa actual em euros.
  static double get taxaServicoNaoParceiroEur => _taxa.atualEur;

  /// Atalho: o valor riscado em euros, ou `null` quando não há risco.
  static double? get taxaServicoNaoParceiroRiscadaEur => _taxa.riscoEur;

  /// `true` quando os valores vieram mesmo do servidor. Só para diagnóstico.
  static bool get carregadoDoServidor => _carregado;

  /// Lê as duas chaves. Idempotente. Nunca lança.
  static Future<void> carregar({bool forcar = false}) async {
    if (_carregado && !forcar) return;
    try {
      final linhas = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', const [kAtual, kRisco]);

      final lista = (linhas as List).cast<Map<String, dynamic>>();
      if (lista.isEmpty) {
        // Sem sessão (RLS) ou chaves apagadas — não se marca como carregado
        // para se tentar outra vez depois de entrar.
        debugPrint('[RemoteFees] ainda não é legível (sem sessão?) — '
            'fica ${_taxa.atualCents}c / risco ${_taxa.riscoCents}c.');
        return;
      }

      final valores = <String, dynamic>{
        for (final l in lista) l['key'] as String: l['value'],
      };

      _taxa = TaxaServicoNaoParceiro(
        atualCents: _comoCents(valores[kAtual], fallbackAtualCents),
        riscoCents: _comoCents(valores[kRisco], 0),
      );
      _carregado = true;
      debugPrint('[RemoteFees] taxa não-parceiro: ${_taxa.atualCents}c '
          '(riscado ${_taxa.riscoCents}c)');
    } catch (e) {
      // Estado seguro: ficam os valores de recurso e tenta-se outra vez.
      debugPrint('[RemoteFees] falhou a ler as taxas: $e');
    }
  }

  /// Usado pelo painel admin depois de gravar, para a app não continuar a
  /// mostrar o valor antigo.
  static void esquecerCache() {
    _carregado = false;
  }

  /// Cêntimos inteiros e não-negativos. Lixo → [seDerErrado].
  static int _comoCents(dynamic v, int seDerErrado) {
    if (v == null) return seDerErrado;
    final n = v is num ? v : num.tryParse('$v');
    if (n == null || n.isNaN || n.isInfinite || n < 0) return seDerErrado;
    return n.round();
  }
}
