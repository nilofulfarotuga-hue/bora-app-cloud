/// As decisões do checkout web, separadas do `dart:html`.
///
/// Vivem aqui para poderem ser testadas na suite normal (`flutter test`), que
/// corre na VM e nem sequer compila um ficheiro com `dart:html`.
///
/// Não é arrumação por arrumação: o bug de 22/09/2026 **foi uma decisão
/// errada**, não um erro de integração. O código lia `popup.closed` dentro de
/// um `try`, e no `catch` concluía `blocked = false` — "cross-origin, logo está
/// viva". Com a janela bloqueada pelo Safari, `popup` era `null`, a leitura
/// atirava, e a app ficava à espera para sempre de uma janela que nunca
/// existiu. A cliente Priscila Prates viu o ecrã a rodar e foi-se embora.
///
/// Uma decisão que custou uma cliente merece um teste que a prenda.
library;

/// Por onde é que o pagamento vai sair.
enum CaminhoDoCheckout {
  /// Janela pequena à parte; a app Flutter fica viva por trás.
  janelaNova,

  /// A app sai da página. Guarda-se o estado e retoma-se no arranque seguinte.
  mesmoSeparador,
}

/// Escolhe o caminho **antes** de esperar seja pelo que for.
///
/// [janelaAbriu] é `false` quando o `window.open` devolveu `null` **ou**
/// atirou. As duas coisas querem dizer bloqueada — nunca "está viva".
CaminhoDoCheckout escolherCaminhoDoCheckout({
  required bool ehBrowserDeTelemovel,
  required bool janelaAbriu,
}) {
  // No telemóvel nem se tenta: o Safari do iPhone bloqueia o `window.open` que
  // não venha colado a um toque, e entre o toque e o open há a biometria e a
  // chamada à Edge Function.
  if (ehBrowserDeTelemovel) return CaminhoDoCheckout.mesmoSeparador;
  if (!janelaAbriu) return CaminhoDoCheckout.mesmoSeparador;
  return CaminhoDoCheckout.janelaNova;
}

/// O que fazer no próximo tique da vigia.
enum PassoDaEspera {
  /// Continuar à espera — é o caso normal.
  continuar,

  /// A janela abriu mas nunca deu sinal: tratar como bloqueada e ir pelo mesmo
  /// separador.
  tratarComoBloqueada,

  /// O cliente fechou a janela no X.
  cancelar,

  /// Silêncio a mais. Desistir com mensagem clara em vez de rodar para sempre.
  desistirPorSilencio,
}

/// Quanto tempo se espera pelo `pronto` do `pay.html`.
const Duration prazoDoSinal = Duration(milliseconds: 1500);

/// Tecto de silêncio com o cliente ainda a olhar para o formulário. O
/// `pay.html` bate de 10 em 10 s, por isso 90 s sem nada é morte a sério.
const Duration tectoSemSinal = Duration(seconds: 90);

/// Depois do "Pagar" o cliente pode estar no banco a aprovar o 3-D Secure — aí
/// a página sai e o batimento pára. Matar isto aos 90 s seria matar um
/// pagamento a sério.
const Duration tectoAPagar = Duration(minutes: 10);

PassoDaEspera avaliarEspera({
  required bool deuSinal,
  required bool aPagar,
  required bool janelaFechada,
  required Duration desdeAbertura,
  required Duration desdeUltimoSinal,
}) {
  // A ordem importa. "Nunca deu sinal" vem primeiro: uma janela bloqueada pode
  // muito bem parecer fechada, e o caminho certo aí é o mesmo separador, não
  // dizer ao cliente que ele cancelou uma coisa que nunca viu.
  if (!deuSinal) {
    return desdeAbertura > prazoDoSinal
        ? PassoDaEspera.tratarComoBloqueada
        : PassoDaEspera.continuar;
  }

  if (janelaFechada) return PassoDaEspera.cancelar;

  final tecto = aPagar ? tectoAPagar : tectoSemSinal;
  if (desdeUltimoSinal > tecto) return PassoDaEspera.desistirPorSilencio;

  return PassoDaEspera.continuar;
}
