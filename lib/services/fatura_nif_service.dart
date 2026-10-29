import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Chamada a uma função do servidor (`rpc`). Fica injetável para os testes
/// não precisarem de Supabase.
typedef ChamadaRpc = Future<dynamic> Function(
    String funcao, Map<String, dynamic> parametros);

Future<dynamic> _rpcSupabase(String funcao, Map<String, dynamic> parametros) =>
    Supabase.instance.client.rpc(funcao, params: parametros);

/// NIF e nome para a fatura (do perfil do cliente ou de um pedido).
@immutable
class DadosFatura {
  const DadosFatura({required this.nif, this.nome});

  final String nif;
  final String? nome;

  /// `{nif, nome}` do servidor → [DadosFatura]. Sem NIF devolve `null`.
  static DadosFatura? deMapa(dynamic m) {
    if (m is! Map) return null;
    final nif = (m['nif'] ?? '').toString().trim();
    if (nif.isEmpty) return null;
    final nome = (m['nome'] ?? '').toString().trim();
    return DadosFatura(nif: nif, nome: nome.isEmpty ? null : nome);
  }
}

/// Porque é que o NIF ainda não ficou no pedido.
enum MotivoFaturaPendente {
  /// Falhou a ligação (as 3 tentativas): vale a pena "tentar de novo".
  rede,

  /// O servidor recusou de vez (o pedido já saiu da loja, ou o NIF não vale).
  recusado,
}

/// Um pedido de fatura que ainda não ficou registado no servidor.
@immutable
class FaturaPendente {
  const FaturaPendente({
    required this.orderId,
    required this.nif,
    this.nome,
    required this.motivo,
  });

  final String orderId;
  final String nif;
  final String? nome;
  final MotivoFaturaPendente motivo;
}

/// FATURA COM NIF (28/10/2026) — o lado do cliente.
///
/// O NIF é SEMPRE opcional e **nunca trava nem atrasa o pedido**: só se chama
/// o servidor depois de o pedido ter id real, em segundo plano, com 3
/// tentativas e uma espera curta. Se mesmo assim falhar, o pedido fica na lista
/// de pendentes e o ecrã de acompanhamento mostra o aviso com "tentar de novo".
///
/// Funções do servidor (todas `SECURITY DEFINER`, só `authenticated`):
/// `client_billing_get()`, `client_billing_save(p_nif, p_nome)` e
/// `client_set_order_invoice(p_order_id, p_nif, p_nome, p_guardar)`.
class FaturaNifService extends ChangeNotifier {
  FaturaNifService({
    ChamadaRpc? rpc,
    this.espera = const Duration(milliseconds: 700),
    this.tentativas = 3,
    Future<DadosFatura?> Function(String orderId)? lerPedido,
  })  : _rpc = rpc ?? _rpcSupabase,
        _lerPedido = lerPedido;

  /// A instância da app.
  static final FaturaNifService instance = FaturaNifService();

  final ChamadaRpc _rpc;
  final Future<DadosFatura?> Function(String orderId)? _lerPedido;

  /// Espera entre tentativas (cresce: 1×, 2×…).
  final Duration espera;
  final int tentativas;

  final Map<String, FaturaPendente> _pendentes = {};

  /// O pedido tem NIF por registar?
  FaturaPendente? pendenteDe(String orderId) => _pendentes[orderId];

  // ── Perfil de faturação do cliente ────────────────────────────────────────

  /// O NIF guardado do cliente, ou `null` se não tem. Lança se a ligação falhar.
  Future<DadosFatura?> lerPerfil() async =>
      DadosFatura.deMapa(await _rpc('client_billing_get', const {}));

  /// Guarda (ou muda) o NIF e o nome. Lança com `NIF_INVALIDO` se não valer.
  Future<void> guardarPerfil(String nif, String? nome) async {
    await _rpc('client_billing_save', {'p_nif': nif, 'p_nome': nome});
  }

  /// Apaga o NIF guardado (NIF vazio = apagar, no servidor).
  Future<void> apagarPerfil() => guardarPerfil('', null);

  // ── Fatura de um pedido ───────────────────────────────────────────────────

  /// O pedido de fatura registado para [orderId], ou `null`.
  Future<DadosFatura?> lerDoPedido(String orderId) async {
    final f = _lerPedido;
    if (f != null) return f(orderId);
    final r = await Supabase.instance.client
        .from('order_invoice_requests')
        .select('nif, nome')
        .eq('order_id', orderId)
        .maybeSingle();
    return DadosFatura.deMapa(r);
  }

  /// Chamar logo que o pedido tem id real. Não espera, nunca lança.
  void pedirEmSegundoPlano(String orderId, {required String nif, String? nome}) {
    unawaited(pedir(orderId, nif: nif, nome: nome));
  }

  /// Regista o NIF no pedido (3 tentativas). `true` = ficou registado.
  /// Nunca lança: o que falhar fica em [pendenteDe].
  Future<bool> pedir(String orderId,
      {required String nif, String? nome}) async {
    final motivo = await _tentar(orderId, nif, nome);
    if (motivo == null) {
      if (_pendentes.remove(orderId) != null) notifyListeners();
      return true;
    }
    _pendentes[orderId] = FaturaPendente(
        orderId: orderId, nif: nif, nome: nome, motivo: motivo);
    notifyListeners();
    return false;
  }

  /// "Tentar de novo" do acompanhamento.
  Future<bool> tentarDeNovo(String orderId) async {
    final p = _pendentes[orderId];
    if (p == null) return true;
    return pedir(orderId, nif: p.nif, nome: p.nome);
  }

  Future<MotivoFaturaPendente?> _tentar(
      String orderId, String nif, String? nome) async {
    for (var i = 1; i <= tentativas; i++) {
      try {
        await _rpc('client_set_order_invoice', {
          'p_order_id': orderId,
          'p_nif': nif,
          'p_nome': nome,
          'p_guardar': true,
        });
        return null;
      } catch (e) {
        final t = e.toString();
        // Recusas de vez: repetir não adianta.
        if (t.contains('TARDE_DEMAIS') ||
            t.contains('PEDIDO_NAO_E_TEU') ||
            t.contains('NIF_INVALIDO')) {
          debugPrint('[FaturaNif] recusado ($orderId): $t');
          return MotivoFaturaPendente.recusado;
        }
        debugPrint('[FaturaNif] tentativa $i/$tentativas falhou ($orderId): $t');
        if (i < tentativas && espera > Duration.zero) {
          await Future<void>.delayed(espera * i);
        }
      }
    }
    return MotivoFaturaPendente.rede;
  }
}
