/// [Fix botão preso 2026-08-20] Tradução das falhas de QUALQUER botão de acção
/// para português simples, e decisão de sair (ou não) do ecrã.
///
/// Nasceu no ecrã de corrida do motorista (`tvde_driver_action_error.dart`) e
/// foi renomeado quando passou a servir também o estafeta do delivery, a
/// limpeza, as marcações e as reservas — deixou de ser só do TVDE.
///
/// Vive fora dos ecrãs por dois motivos:
///  1. É lógica pura — não precisa de Flutter, logo é testável de verdade
///     (o mesmo princípio do `TvdeFareView`).
///  2. Enterrada como método privado de um ecrã, nenhum teste lhe chegava.
///
/// Regra da casa: quem lê isto está a trabalhar — muitas vezes ao volante.
/// Nada de nomes de excepções, códigos SQL ou `PostgrestException(...)`. A
/// frase diz o que aconteceu e o que fazer a seguir.
///
/// **As marcas não foram inventadas.** Saíram de um varrimento ao código das
/// funções em produção a 2026-08-20 (`RAISE EXCEPTION '<marca>'`), com a
/// contagem de funções que as levantam:
/// ```
/// not_authenticated 19 · ride_not_found 15 · reservation_not_found 8
/// auth_required 7 · booking_not_found 6 · not_ride_driver 6
/// appointment_not_found 5 · booking_not_yours 4 · invalid_status 3
/// offer_no_longer_valid 3 · not_ride_client 2 · not_ride_owner 2
/// not_your_appointment 2 · not_your_reservation 2 · ride_already_taken 2
/// ```
/// E confirmadas ao vivo contra a produção:
/// ```
/// select public.tvde_driver_arrived('00000000-0000-0000-0000-000000000000');
/// ERROR:  P0001: ride_not_found
/// ```
library;

import 'dart:async';

/// O que está a ser tratado quando a acção falha. Serve só para a frase sair
/// natural em português: *"Esta corrida já não existe"* vs *"Este pedido já
/// não existe"*. É obrigatório de propósito — um valor por omissão faria um
/// ecrã de entregas dizer "corrida" sem ninguém dar por isso.
enum TrabalhoEmCurso {
  corrida, // TVDE
  pedido, // delivery
  limpeza,
  marcacao, // serviços / barbearias
  reserva,
  lavagem, // Lavagem Auto
}

extension _Nomes on TrabalhoEmCurso {
  /// "Esta corrida", "Este pedido", …
  String get comMaiuscula => switch (this) {
        TrabalhoEmCurso.corrida => 'Esta corrida',
        TrabalhoEmCurso.pedido => 'Este pedido',
        TrabalhoEmCurso.limpeza => 'Esta limpeza',
        TrabalhoEmCurso.marcacao => 'Esta marcação',
        TrabalhoEmCurso.reserva => 'Esta reserva',
        TrabalhoEmCurso.lavagem => 'Esta lavagem',
      };

  /// "a corrida", "o pedido", … (para o meio de uma frase)
  String get comMinuscula => switch (this) {
        TrabalhoEmCurso.corrida => 'a corrida',
        TrabalhoEmCurso.pedido => 'o pedido',
        TrabalhoEmCurso.limpeza => 'a limpeza',
        TrabalhoEmCurso.marcacao => 'a marcação',
        TrabalhoEmCurso.reserva => 'a reserva',
        TrabalhoEmCurso.lavagem => 'a lavagem',
      };

  /// Concordância: "atribuída" / "atribuído".
  String get atribuido =>
      this == TrabalhoEmCurso.pedido ? 'atribuído' : 'atribuída';
}

/// Marcas que o servidor levanta quando a coisa simplesmente já não existe.
const _naoExiste = <String>[
  'ride_not_found',
  'reservation_not_found',
  'booking_not_found',
  'appointment_not_found',
  'provider_not_found',
];

/// Marcas de "existe, mas já não é teu".
const _naoEhTeu = <String>[
  'not_ride_driver',
  'not_ride_client',
  'not_ride_owner',
  'booking_not_yours',
  'not_your_appointment',
  'not_your_reservation',
  'not_authorized',
  'forbidden',
];

/// Marcas de "outra pessoa ficou com isto / a oferta expirou".
const _jaFoiTirado = <String>[
  'ride_already_taken',
  'offer_no_longer_valid',
  'offer_not_yours_or_expired',
];

/// Marcas de sessão perdida.
const _semSessao = <String>[
  'not_authenticated',
  'auth_required',
];

/// Marcas de "o estado mudou por baixo de ti".
const _estadoErrado = <String>[
  'invalid_status',
  'booking_not_active',
  'booking_not_finished',
  'cannot_cancel',
  'cancellation_not_allowed_reschedule_only',
];

/// Marcas de rede em baixo.
const _semRede = <String>[
  'SocketException',
  'Failed host lookup',
  'ClientException',
  'Connection closed',
  'Connection refused',
];

bool _tem(String txt, List<String> marcas) =>
    marcas.any((m) => txt.contains(m));

/// Frase a mostrar quando uma acção falha.
String mensagemDeFalhaDeAcao(
  Object erro, {
  required TrabalhoEmCurso trabalho,
}) {
  if (erro is JaFicouCriado) return erro.mensagem;

  if (erro is TimeoutException) {
    return 'O servidor demorou demasiado a responder. Fui verificar como está '
        '${trabalho.comMinuscula} — se continuar igual, tenta outra vez.';
  }

  final txt = erro.toString();

  if (_tem(txt, _naoExiste)) {
    return '${trabalho.comMaiuscula} já não existe.';
  }
  if (_tem(txt, _naoEhTeu)) {
    return '${trabalho.comMaiuscula} já não está ${trabalho.atribuido} a ti.';
  }
  if (_tem(txt, _jaFoiTirado)) {
    return 'Já não está disponível — outra pessoa chegou primeiro.';
  }
  if (_tem(txt, _semSessao)) {
    return 'A tua sessão terminou. Entra outra vez para continuar.';
  }
  if (_tem(txt, _estadoErrado)) {
    return '${trabalho.comMaiuscula} já não está nesse estado. Atualiza para '
        'veres como está agora.';
  }
  if (_tem(txt, _semRede)) {
    return 'Sem ligação à internet. Verifica a rede e tenta outra vez.';
  }

  return 'Não consegui concluir. Verifica ${trabalho.comMinuscula} e tenta '
      'outra vez.';
}

/// `true` quando a falha significa que já não há nada para fazer neste ecrã —
/// o ecrã deve sair em vez de deixar a pessoa presa.
///
/// Rede e timeout NÃO fecham o ecrã de propósito: aí não sabemos o que se
/// passou, e a acção até pode ter-se aplicado.
bool falhaFechaOEcra(Object erro) {
  if (erro is JaFicouCriado) return false; // é sucesso, não falha
  if (erro is TimeoutException) return false;
  final txt = erro.toString();
  return _tem(txt, _naoExiste) ||
      _tem(txt, _naoEhTeu) ||
      _tem(txt, _jaFoiTirado);
}

/// Tecto de espera de QUALQUER acção com botão, em toda a app.
///
/// Sem isto, uma chamada que nunca responde (rede fraca, servidor pendurado)
/// deixa o `finally` por correr e o botão fica a girar para sempre — foi
/// exactamente o defeito de 2026-08-20 no ecrã de corrida do motorista.
const Duration kAcaoTimeout = Duration(seconds: 12);

// ───────────────────────────────────────────────────────────────────────────
// AÇÕES QUE CRIAM ALGO
// ───────────────────────────────────────────────────────────────────────────

/// Marcas de guarda que, **numa repetição a seguir a um tecto de tempo**,
/// PROVAM que a primeira chamada já se aplicou.
///
/// Isto não é adivinhação: cada uma foi lida na função em produção a
/// 2026-08-20.
///
/// | RPC | guarda |
/// |---|---|
/// | `tvde_schedule_ride` | `reservation_overlap` (±30 min), `too_many_reservations` |
/// | `tvde_request_ride` | `ride_in_progress` |
/// | `tvde_request_return_ride` | `SELECT … FOR UPDATE` + `credit_not_active` |
/// | `client_book_appointment` | `slot_taken` |
/// | `create_cleaning_booking` | `cleaner_not_available` |
/// | `client_confirm_appointment_payment` | `invalid_status` (idempotente) |
///
/// `tvde_request_plan` e `tvde_create_roundtrip_credit_cash` não precisam de
/// marca nenhuma: são **idempotentes por desenho** — procuram o que já existe
/// e devolvem-no (a segunda tem no próprio código *"Idempotencia INTACTA: vale
/// ja criado devolve-se tal e qual"*). A repetição devolve sucesso normal.
const _provamQueJaFoiCriado = <String>[
  'reservation_overlap',
  'too_many_reservations',
  'ride_in_progress',
  'credit_not_active',
  'slot_taken',
  'cleaner_not_available',
  'invalid_status',
];

/// `true` quando o erro é uma guarda que só podia ter disparado porque a
/// primeira tentativa se aplicou.
///
/// Só faz sentido consultar isto **na repetição**. À primeira, um
/// `reservation_overlap` é o que diz: choque com outra reserva.
bool provaQueJaFoiCriado(Object erro) =>
    _tem(erro.toString(), _provamQueJaFoiCriado);

/// Não é uma falha — é o contrário. A acção **aplicou-se**, só a resposta é
/// que se perdeu pelo caminho.
class JaFicouCriado implements Exception {
  const JaFicouCriado(this.trabalho);

  final TrabalhoEmCurso trabalho;

  String get mensagem => switch (trabalho) {
        TrabalhoEmCurso.reserva =>
          'A reserva já ficou marcada — não marcaste duas. Confirma em '
              '"As minhas reservas".',
        TrabalhoEmCurso.corrida =>
          'A corrida já ficou pedida — não pediste duas. Volta atrás para a '
              'veres.',
        TrabalhoEmCurso.limpeza =>
          'A limpeza já ficou marcada — não marcaste duas. Confirma nas tuas '
              'limpezas.',
        TrabalhoEmCurso.marcacao =>
          'A marcação já ficou feita — não marcaste duas. Confirma nas tuas '
              'marcações.',
        TrabalhoEmCurso.lavagem =>
          'A lavagem já ficou pedida — não pediste duas. Confirma em '
              '"Lavagem Auto".',
        TrabalhoEmCurso.pedido =>
          'O pedido já ficou feito — não fizeste dois. Confirma nos teus '
              'pedidos.',
      };

  @override
  String toString() => mensagem;
}

/// Corre uma acção que **cria** algo, com tecto de tempo seguro.
///
/// O tecto sozinho seria perigoso aqui: se a chamada demora mas **passa** no
/// servidor, dizer "não ficou marcada" leva a pessoa a repetir — e a duplicar.
/// Por isso, ao expirar, isto **não assume falha**: repete uma vez. Se a
/// repetição bater na guarda do servidor, essa guarda é a prova de que a
/// primeira se aplicou → [JaFicouCriado], que os ecrãs tratam como SUCESSO.
///
/// Se a repetição correr bem (RPC idempotente), devolve o resultado normal.
Future<T> criarComTectoSeguro<T>(
  Future<T> Function() chamar, {
  required TrabalhoEmCurso trabalho,
  Duration tecto = kAcaoTimeout,
}) async {
  try {
    return await chamar().timeout(tecto);
  } on TimeoutException {
    try {
      return await chamar().timeout(tecto);
    } catch (e) {
      if (provaQueJaFoiCriado(e)) {
        throw JaFicouCriado(trabalho);
      }
      rethrow;
    }
  }
}
