import '../models/driver_model.dart' show DriverStatus;

/// [B4 · 01/11/2026] Estafeta não aprovado não fica online.
///
/// UMA porta só para a frase que o estafeta lê quando o servidor não o deixa
/// ficar online — a mesma no ecrã das entregas e no ecrã TVDE (PT-PT).
///
/// Os códigos vêm de `prestador_pode_ficar_online()` (pergunta antes de
/// ligar) e do gatilho `trg_online_so_aprovado` em `drivers`, que levanta
/// `"<CODIGO>: <mensagem>"` quando alguém tenta pôr `is_online=true` sem
/// aprovação.
class CodigoOnline {
  CodigoOnline._();

  // Do servidor.
  static const ok = 'OK';
  static const semConta = 'SEM_CONTA';
  static const contaApagada = 'CONTA_APAGADA';
  static const contaBloqueada = 'CONTA_BLOQUEADA';
  static const contaRecusada = 'CONTA_RECUSADA';
  static const contaNaoAprovada = 'CONTA_NAO_APROVADA';
  static const tvdeBloqueado = 'TVDE_BLOQUEADO';

  /// Gatilhos TVDE em `drivers` (fn_motorista_doc_expirado_online,
  /// fn_tvde_conformidade_online): "DOCUMENTO_EXPIRADO: …", "LIMITE_HORAS: …".
  static const documentoExpirado = 'DOCUMENTO_EXPIRADO';
  static const limiteHoras = 'LIMITE_HORAS';

  // Da app.
  /// Ir offline com pedidos/corrida em curso (cada ecrã diz a sua frase).
  static const pedidosAtivos = 'PEDIDOS_ATIVOS';

  /// Já há um pedido para ficar online a meio (dois toques seguidos).
  static const emCurso = 'EM_CURSO';

  /// Sem resposta do servidor ao gravar: não se fica online "às escuras".
  static const semLigacao = 'SEM_LIGACAO';

  /// O servidor respondeu mas a linha não ficou online.
  static const naoConfirmado = 'NAO_CONFIRMADO';

  /// Códigos do servidor que se podem encontrar no texto de um erro.
  static const doServidor = <String>[
    contaNaoAprovada,
    contaRecusada,
    contaBloqueada,
    contaApagada,
    semConta,
    tvdeBloqueado,
    documentoExpirado,
    limiteHoras,
  ];

  /// Recusas por causa da CONTA (não da rede nem da conformidade TVDE): o ecrã
  /// volta a ler o estado de aprovação para mostrar o portão certo.
  static const daConta = <String>{
    contaNaoAprovada,
    contaRecusada,
    contaBloqueada,
    contaApagada,
    semConta,
  };
}

/// Frase única (PT-PT) para quando o servidor não deixa ficar online.
String mensagemOnlineRecusado(String? codigo, {String? mensagemServidor}) {
  final aparada = mensagemServidor?.trim() ?? '';
  // null quando o servidor não mandou texto (ou só espaços).
  final String? doServidor = aparada.isEmpty ? null : aparada;
  switch (codigo) {
    case CodigoOnline.contaNaoAprovada:
      return 'A tua conta ainda não está aprovada. Quando for aprovada '
          'recebes um aviso e podes ficar online.';
    case CodigoOnline.contaRecusada:
      return 'A tua candidatura não foi aprovada. Fala com o suporte da Bora.';
    case CodigoOnline.contaBloqueada:
      return 'A tua conta está bloqueada. Fala com o suporte da Bora.';
    case CodigoOnline.tvdeBloqueado:
      return doServidor ??
          'Não podes ficar online: falta resolver a conformidade TVDE.';
    case CodigoOnline.documentoExpirado:
      return 'Não podes ficar online: há um documento fora da validade '
          '(${doServidor ?? 'ver a Ficha legal'}). Atualiza a validade na '
          'Ficha legal para voltares a ficar online.';
    case CodigoOnline.limiteHoras:
      return doServidor != null
          ? 'Não podes ficar online: ${doServidor[0].toLowerCase()}${doServidor.substring(1)}.'
          : 'Não podes ficar online: atingiste o limite legal de horas de '
              'serviço nas últimas 24 horas.';
    case CodigoOnline.pedidosAtivos:
      return 'Tens pedidos activos. Conclui-os antes de ficar offline.';
    case CodigoOnline.semLigacao:
      return 'Não conseguimos confirmar com o servidor. Não ficaste online — '
          'verifica a ligação e tenta outra vez.';
    default:
      return doServidor ?? 'Não foi possível ficar online. Tenta outra vez.';
  }
}

/// Encontra o código de recusa num texto de erro do servidor (ex.: a
/// `PostgrestException` do gatilho: `"CONTA_NAO_APROVADA: A tua conta…"`).
/// Devolve `null` quando o texto não traz nenhum.
String? codigoOnlineNoErro(String texto) {
  for (final c in CodigoOnline.doServidor) {
    if (texto.contains(c)) return c;
  }
  return null;
}

/// A mensagem que o servidor pôs depois de `"<CODIGO>:"` (primeira linha).
String? mensagemDoServidorNoErro(String texto, String codigo) {
  final i = texto.indexOf('$codigo:');
  if (i < 0) return null;
  final resto = texto.substring(i + codigo.length + 1).split('\n').first;
  // A PostgrestException acrescenta ", code: P0001, …" ao toString().
  final corte = resto.indexOf(', code:');
  final limpo = (corte >= 0 ? resto.substring(0, corte) : resto).trim();
  return limpo.isEmpty ? null : limpo;
}

/// [O4 · 01/11/2026] O interruptor Online (`driver_online_toggle`) só existe
/// para quem está APROVADO. Pendente ou recusado vê o ecrã de espera — nunca
/// um botão que o servidor depois recusa.
bool mostraInterruptorOnline(DriverStatus estado) =>
    estado == DriverStatus.approved;
