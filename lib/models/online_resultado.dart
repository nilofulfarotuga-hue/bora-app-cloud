import '../utils/mensagem_online_recusado.dart';

/// [B4 · 01/11/2026] O que aconteceu quando o estafeta tocou no botão Online.
///
/// Antes `toggleAvailability` devolvia só `bool` e a gravação no servidor
/// corria em segundo plano a engolir o erro: o botão ficava verde mesmo com o
/// servidor a recusar (conta por aprovar). Agora o ecrã recebe o motivo e a
/// frase a mostrar.
class OnlineResultado {
  const OnlineResultado({
    required this.ok,
    this.codigo,
    this.mensagem,
    this.motivos = const <String>[],
    this.semRespostaDoServidor = false,
  });

  /// Ficou como se pediu.
  const OnlineResultado.ok()
      : ok = true,
        codigo = CodigoOnline.ok,
        mensagem = null,
        motivos = const <String>[],
        semRespostaDoServidor = false;

  /// A pergunta ao servidor falhou (rede/tempo): deixa seguir. O travão
  /// verdadeiro é o gatilho `trg_online_so_aprovado` na gravação.
  const OnlineResultado.semResposta()
      : ok = true,
        codigo = null,
        mensagem = null,
        motivos = const <String>[],
        semRespostaDoServidor = true;

  /// Recusado, com a frase única de [mensagemOnlineRecusado].
  factory OnlineResultado.recusado(
    String codigo, {
    String? mensagemServidor,
    List<String> motivos = const <String>[],
  }) =>
      OnlineResultado(
        ok: false,
        codigo: codigo,
        mensagem:
            mensagemOnlineRecusado(codigo, mensagemServidor: mensagemServidor),
        motivos: motivos,
      );

  /// Lê a resposta de `prestador_pode_ficar_online()`:
  /// `{ok, codigo, mensagem, faltas?, motivos?}`.
  factory OnlineResultado.daResposta(dynamic res) {
    if (res is! Map) return const OnlineResultado.semResposta();
    if (res['ok'] != false) return const OnlineResultado.ok();
    final codigo = (res['codigo'] ?? '').toString();
    final motivos = (res['motivos'] is List ? res['motivos'] as List : const [])
        .map((m) => m is Map
            ? (m['rotulo'] ?? m['codigo'] ?? '').toString()
            : m.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    return OnlineResultado.recusado(
      codigo.isEmpty ? CodigoOnline.naoConfirmado : codigo,
      mensagemServidor: res['mensagem']?.toString(),
      motivos: motivos,
    );
  }

  /// Lê o erro do gatilho do servidor (`"CONTA_NAO_APROVADA: …"`). Um erro sem
  /// código conhecido fica como [CodigoOnline.naoConfirmado].
  factory OnlineResultado.doErro(Object erro) {
    final texto = erro.toString();
    final codigo = codigoOnlineNoErro(texto);
    if (codigo == null) {
      return OnlineResultado.recusado(CodigoOnline.naoConfirmado);
    }
    return OnlineResultado.recusado(
      codigo,
      mensagemServidor: mensagemDoServidorNoErro(texto, codigo),
    );
  }

  final bool ok;
  final String? codigo;

  /// Frase PT-PT para mostrar (null quando [ok]).
  final String? mensagem;

  /// TVDE: os motivos (rótulos) que o servidor deu.
  final List<String> motivos;

  /// [ok] só porque não houve resposta (falha aberta).
  final bool semRespostaDoServidor;

  /// Recusa por causa da conta (por aprovar, recusada, bloqueada, apagada).
  bool get recusaDaConta => !ok && CodigoOnline.daConta.contains(codigo);

  @override
  String toString() => 'OnlineResultado(ok=$ok, codigo=$codigo)';
}
