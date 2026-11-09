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
    this.faltas = const <String>[],
    this.semRespostaDoServidor = false,
  });

  /// Ficou como se pediu.
  const OnlineResultado.ok()
      : ok = true,
        codigo = CodigoOnline.ok,
        mensagem = null,
        motivos = const <String>[],
        faltas = const <String>[],
        semRespostaDoServidor = false;

  /// A pergunta ao servidor falhou (rede/tempo): deixa seguir. O travão
  /// verdadeiro é o gatilho `trg_online_so_aprovado` na gravação.
  const OnlineResultado.semResposta()
      : ok = true,
        codigo = null,
        mensagem = null,
        motivos = const <String>[],
        faltas = const <String>[],
        semRespostaDoServidor = true;

  /// Recusado, com a frase única de [mensagemOnlineRecusado].
  factory OnlineResultado.recusado(
    String codigo, {
    String? mensagemServidor,
    List<String> motivos = const <String>[],
    List<String> faltas = const <String>[],
  }) =>
      OnlineResultado(
        ok: false,
        codigo: codigo,
        mensagem:
            mensagemOnlineRecusado(codigo, mensagemServidor: mensagemServidor),
        motivos: motivos,
        faltas: faltas,
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
    // Missão m2 (08/11/2026): o servidor já mandava o que falta à candidatura
    // (`faltas`, do robô dos documentos) e a app deitava fora.
    final faltas = (res['faltas'] is List ? res['faltas'] as List : const [])
        .map((f) => f.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return OnlineResultado.recusado(
      codigo.isEmpty ? CodigoOnline.naoConfirmado : codigo,
      mensagemServidor: res['mensagem']?.toString(),
      motivos: motivos,
      faltas: faltas,
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

  /// Conta por aprovar: o que ainda falta enviar (`faltas` do servidor).
  final List<String> faltas;

  /// A frase a mostrar, já com "Falta enviar: …" quando o servidor o disse.
  String? get mensagemComFaltas {
    final m = mensagem;
    if (faltas.isEmpty) return m;
    final lista = faltas.length == 1
        ? faltas.first
        : '${faltas.sublist(0, faltas.length - 1).join(', ')} e ${faltas.last}';
    return '${m ?? ''} Falta enviar: $lista.'.trim();
  }

  /// [ok] só porque não houve resposta (falha aberta).
  final bool semRespostaDoServidor;

  /// Recusa por causa da conta (por aprovar, recusada, bloqueada, apagada).
  bool get recusaDaConta => !ok && CodigoOnline.daConta.contains(codigo);

  @override
  String toString() => 'OnlineResultado(ok=$ok, codigo=$codigo)';
}
