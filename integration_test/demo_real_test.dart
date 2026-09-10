// Capturas da App Store e vídeo do revisor — a partir da APP REAL.
//
// PORQUE ESTE FICHEIRO EXISTE (cicatriz de 2026-09-08)
// O arnês anterior (`capturas_loja_test.dart` + `lib/screens/capturas/`)
// desenhava sete ecrãs bonitos com dados **inventados**: uma "Mercado da
// Guarda" que não existe, uma "Barbearia Central" que não existe, açaí a €4,50
// quando a Goola Açaí só tem Big Bowl a €11,55 e Goola Bowl a €9,22, e uma
// "Lavagem + Cera €20" que nunca existiu. Auditado contra a produção: as
// **sete** falharam. Mostrar isso à Apple é reprovação por metadados enganosos
// (2.3.1) e por o revisor não encontrar na app o que viu nas imagens (2.3.3).
//
// REGRA, sem excepção: nenhuma captura e nenhum vídeo mostra loja, serviço,
// produto ou preço que não exista mesmo no banco de produção. Por isso este
// teste não desenha nada — abre a app a sério, liga-se ao servidor e fotografa
// o que lá está.
//
// DUAS COISAS DIFERENTES, E O NOME DO FICHEIRO DIZ QUAL (decisão do Danilo,
// 2026-09-08):
//
//   `NN-loja-*`   CAPTURAS DA LOJA — são publicidade **pública**. Não podem ter
//                 em destaque nomes nem logótipos das lojas onde a Bora só
//                 compra (Continente, Auchan, Pingo Doce, Lidl, Mercadona,
//                 Intermarché, McDonald's, Burger King, KFC, Pizza Hut, Worten,
//                 Wells, Leroy Merlin, Kiwoko, Zippy). Para isso o interruptor
//                 `ios_hide_nonpartner_logos` está LIGADO em `platform_settings`
//                 desde 2026-09-08: a lista de mercados passa a mostrar a loja
//                 por nome em texto e ícone de categoria, sem logótipo.
//
//   `NN-video-*`  PERCURSO DO VÍDEO DO REVISOR — é **privado**, vai para uma
//                 página não listada, e pode mostrar tudo, incluindo o
//                 supermercado real, porque tem de provar uma compra a sério.
//
//   `zz-*`        diagnóstico. Nunca entra no vídeo nem na loja (o ecrã de
//                 credenciais, por exemplo).
//
// PARCEIROS QUE PODEM APARECER COMO QUEM JÁ VENDE (confirmado no banco a
// 2026-09-08): Goola Açaí, Sabores do Brasil - Keli Barbosa, Barbearia Ouro e
// Prata. O Mr Kebab e a Sabores de Casa Açaí têm `coming_soon = true` — a app
// desenha-lhes o selo "Em breve" sozinha, e é assim que têm de aparecer.
//
// PORQUE NÃO HÁ UM ÚNICO `pumpAndSettle`
// `app.main()` traz Supabase, Firebase, realtime e `Timer.periodic` a andar.
// Com isso o `pumpAndSettle` **nunca** assenta: na corrida 34163172748 deu
// +0 -7, o binding ficava com frame pendente e o primeiro teste envenenava os
// seguintes. Aqui bombeia-se em passos curtos deixando o relógio real correr
// (`runAsync`), e espera-se por um `Finder` com prazo.
//
// A ENCOMENDA A SÉRIO ESTÁ ATRÁS DE UM INTERRUPTOR
// `--dart-define=FAZER_ENCOMENDA_REAL=true`. E não chama ninguém real: o
// gatilho BEFORE INSERT `a_trg_pedido_demo_caixa_fechada` em `orders`
// (confirmado ligado a 2026-09-08) faz as encomendas das contas demo nascerem
// já em `driverAccepted` no estafeta demo, sem passarem por `callingDriver`.
// É essa caixa fechada que sustenta a frase das notas ao revisor: "orders
// placed from the demo account are never dispatched to real couriers".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bora_app/main.dart' as app;
import 'package:bora_app/services/notification_service.dart';

/// Credenciais da conta de demonstração. Já são públicas de propósito — estão
/// em `ios/NOTAS-AO-REVISOR.md`, que é o que se entrega à Apple.
const String _email =
    String.fromEnvironment('DEMO_EMAIL', defaultValue: 'demo@bora.app');
const String _senha =
    String.fromEnvironment('DEMO_PASSWORD', defaultValue: 'BoraDemo2026!');

/// Conta demo do estafeta. Confirmada contra o servidor a 2026-09-08:
/// `grant_type=password` devolve HTTP 200 com `bora_role: driver`.
const String _emailEstafeta = String.fromEnvironment(
    'DEMO_EMAIL_ESTAFETA', defaultValue: 'demo-estafeta@bora.app');

/// Segundos que cada ecrã fica parado depois de fotografado, só para o gravador
/// de vídeo apanhar a imagem legível. Não afecta a captura em si.
const int _pausa = int.fromEnvironment('SEGUNDOS_POR_ECRA', defaultValue: 9);

const bool _fazerEncomenda =
    bool.fromEnvironment('FAZER_ENCOMENDA_REAL', defaultValue: false);

late IntegrationTestWidgetsFlutterBinding _binding;

/// Deixa o relógio REAL andar [segundos] enquanto produz frames.
///
/// `tester.pump` sozinho não deixa a rede responder (o tempo do teste é
/// virtual); `runAsync` com um `Future.delayed` deixa. É a única forma de um
/// widget que depende do Supabase chegar a aparecer.
Future<void> _bombear(WidgetTester t, {double segundos = 1.0}) async {
  const passo = Duration(milliseconds: 200);
  for (int i = 0; i < (segundos * 5).round(); i++) {
    await t.pump(passo);
    await t.runAsync(() => Future<void>.delayed(passo));
  }
}

/// Espera até [f] aparecer, ou devolve `false` ao fim de [segundos].
Future<bool> _esperar(WidgetTester t, Finder f, {double segundos = 30}) async {
  for (int i = 0; i < (segundos * 5).round(); i++) {
    if (f.evaluate().isNotEmpty) return true;
    await t.pump(const Duration(milliseconds: 200));
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
  return false;
}

/// Espera e falha com uma fotografia do que estava no ecrã.
///
/// Sem isto, uma falha de percurso só diz "não encontrei o widget" e obriga a
/// adivinhar. Com isto vem uma imagem do ecrã onde encalhou.
Future<void> _exigir(WidgetTester t, Finder f, String oQue,
    {double segundos = 30}) async {
  if (await _esperar(t, f, segundos: segundos)) return;
  await _binding.takeScreenshot('zz-falha-$oQue');
  fail('não apareceu: $oQue');
}

/// Toca no primeiro [f], arrastando-o para a vista se estiver fora do ecrã.
///
/// `tap` num widget fora do ecrã não bate em nada e, com `warnIfMissed: false`,
/// falha em silêncio — o teste seguiria a fingir que carregou. A página da loja
/// empilha carrosséis por categoria (o Continente tem dezenas), por isso o
/// alvo está quase sempre a meio da lista.
Future<void> _tocar(WidgetTester t, Finder f) async {
  try {
    await t.ensureVisible(f.first);
    await _bombear(t, segundos: 0.6);
  } catch (_) {
    // Não está dentro de nenhum `Scrollable` — segue-se e toca-se na mesma.
  }
  await t.tap(f.first, warnIfMissed: false);
  await _bombear(t, segundos: 1.5);
}

/// Rola a página para baixo até [f] existir na árvore, ou [vezes] tentativas.
///
/// Numa lista preguiçosa, o que está fora do ecrã não está construído — e um
/// `Finder` não encontra o que não existe. Rolar é o que faz o Flutter
/// construir o pedaço seguinte.
Future<void> _rolarAteAparecer(WidgetTester t, Finder f,
    {int vezes = 6}) async {
  for (int i = 0; i < vezes; i++) {
    if (f.evaluate().isNotEmpty) return;
    final rolavel = find.byType(Scrollable);
    if (rolavel.evaluate().isEmpty) return;
    try {
      await t.drag(rolavel.first, const Offset(0, -600),
          warnIfMissed: false);
    } catch (_) {
      return;
    }
    await _bombear(t, segundos: 1.2);
  }
}

Future<void> _foto(WidgetTester t, String nome) async {
  await _bombear(t, segundos: 1.5);
  await _binding.takeScreenshot(nome);
  // Só para o gravador: a captura já está feita.
  await _bombear(t, segundos: _pausa.toDouble());
}

Finder _id(String identificador) =>
    find.bySemanticsIdentifier(identificador);

/// Fecha tudo o que estiver empilhado e volta ao início.
///
/// Usa o `navigatorKey` que a app já expõe em vez de carregar em "voltar" N
/// vezes: depois de uma encomenda a pilha tem meia dúzia de ecrãs e contar
/// setas é adivinhar.
Future<void> _voltarAoInicio(WidgetTester t) async {
  NotificationService.navigatorKey.currentState
      ?.popUntil((rota) => rota.isFirst);
  await _bombear(t, segundos: 3);
}

/// Sai da conta e volta ao ecrã dos três perfis.
///
/// Não há atalho: `logout` deixa o papel escolhido, por isso o
/// `_RootNavigator` cai no ecrã de entrar do cliente e não no dos perfis. O
/// caminho é o que uma pessoa faria — Perfil, Terminar sessão, e depois o
/// "← Voltar à escolha de perfil" que o ecrã de entrar tem no fundo.
Future<bool> _sairEVoltarAosPerfis(WidgetTester t) async {
  if (!await _esperar(t, find.text('Perfil'), segundos: 20)) return false;
  await _tocar(t, find.text('Perfil'));
  final sair = find.text('Terminar sessão');
  if (!await _esperar(t, sair, segundos: 25)) return false;
  await _tocar(t, sair);
  await _bombear(t, segundos: 3);
  final voltar = find.textContaining('escolha de perfil');
  if (!await _esperar(t, voltar, segundos: 25)) return false;
  await _tocar(t, voltar);
  await _bombear(t, segundos: 2);
  return true;
}

/// Fecha a folha de consentimento que a app abre por cima de tudo.
///
/// CICATRIZ (corrida 34214041704): a app abre com a folha "Privacidade e
/// Cookies" e um véu escuro por trás. O toque em "Sou Cliente" bateu no véu e
/// não fez nada — e como `tap` leva `warnIfMissed: false`, falhou em silêncio.
/// Só se percebeu ao comparar as duas capturas: `00-video-perfis.png` e
/// `zz-falha-campo-email.png` saíram com o **mesmo MD5**, ou seja o ecrã nunca
/// mudou.
///
/// Escolhe-se **"Rejeitar"**, a opção mais contida: nada do que a demonstração
/// precisa depende de consentimento — as lojas vêm do servidor, a morada vem da
/// morada guardada e não do GPS, e o pagamento é em dinheiro. Correr assim tem
/// a vantagem de provar que a app funciona com o consentimento recusado.
Future<void> _fecharConsentimento(WidgetTester t) async {
  final rejeitar = find.text('Rejeitar');
  if (await _esperar(t, rejeitar, segundos: 25)) {
    await _binding.takeScreenshot('zz-consentimento');
    await _tocar(t, rejeitar);
    await _bombear(t, segundos: 2.5);
  }
}

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('percorre a app real e fotografa o que existe mesmo',
      (WidgetTester t) async {
    // LIGAR A ACESSIBILIDADE ANTES DE TUDO.
    //
    // Metade dos passos deste arnês procura por `bySemanticsIdentifier`
    // (`fld_email`, `btn_entrar`, `cartao_loja`, `btn_add_carrinho`…), e esses
    // localizadores só encontram alguma coisa se a árvore de semântica estiver
    // a ser construída. Sem isto o Flutter não a constrói e os localizadores
    // devolvem vazio — o teste falharia a dizer "não apareceu: campo-email"
    // com o campo mesmo à frente. É a mesma cicatriz que já tinha mordido nas
    // provas da web.
    final SemanticsHandle semantica = t.ensureSemantics();

    // GUARDAR O `ErrorWidget.builder` ANTES DE `app.main()`.
    //
    // CICATRIZ (corrida 34326104105): o percurso correu inteiro, as sete
    // capturas sairam, e o teste falhou na ARRUMACAO com "The value of
    // ErrorWidget.builder was changed by the test". A app define o seu proprio
    // ecra de erro dentro do `main()`, e o `flutter_test` verifica no fim que
    // ninguem mexeu nesse construtor. Resultado: job A vermelho por ruido de
    // arrumacao, e o job do IPA saltado por `needs: simulador` -- 25 minutos de
    // corrida boa deitados fora por uma linha que nao tem nada a ver com a app.
    final ErrorWidgetBuilder construtorDeErroOriginal = ErrorWidget.builder;

    await app.main();
    await _bombear(t, segundos: 6);

    await _fecharConsentimento(t);

    // ── Entrar como cliente ───────────────────────────────────────────────
    // Pode já haver sessão aberta de uma corrida anterior; nesse caso o ecrã
    // de papéis não aparece e salta-se o login.
    final portaCliente = find.text('Sou Cliente');
    if (await _esperar(t, portaCliente, segundos: 20)) {
      await _foto(t, '00-video-perfis');
      await _tocar(t, portaCliente);

      await _exigir(t, _id('fld_email'), 'campo-email');
      await t.enterText(_id('fld_email').first, _email);
      await _bombear(t, segundos: 0.6);
      await t.enterText(_id('fld_password').first, _senha);
      await _bombear(t, segundos: 0.6);
      // `zz-`: o ecrã das credenciais não entra no vídeo nem na loja.
      await _binding.takeScreenshot('zz-login');
      await _tocar(t, _id('btn_entrar'));
    }

    // ── "Falta o seu contacto", se ainda aparecer ─────────────────────────
    //
    // CICATRIZ (corrida 34217347355): entrar correu bem, e logo a seguir a app
    // pôs à frente o ecrã "Os seus contactos — Falta o seu contacto", a pedir
    // nome e telemóvel. A conta demo tinha nome mas **não tinha telemóvel**, e
    // o teste ficou 60 s à espera de "Supermercados" atrás desse ecrã.
    //
    // O telemóvel da conta demo já foi preenchido no banco, por isso isto
    // normalmente não aparece — e é bom que não apareça, porque o revisor da
    // Apple entrava com a mesma conta e batia no mesmo ecrã. Fica aqui como
    // rede: se aparecer, carrega-se em "Agora não" e segue-se.
    final agoraNao = find.text('Agora não');
    if (await _esperar(t, agoraNao, segundos: 8)) {
      await _binding.takeScreenshot('zz-falta-contacto');
      await _tocar(t, agoraNao);
      await _bombear(t, segundos: 2);
    }

    // ── Início: as categorias reais. Zero marcas de terceiros. ────────────
    await _exigir(t, find.text('Supermercados'), 'ecra-inicial', segundos: 60);
    await _foto(t, '01-loja-categorias');

    // ── Mercados: nomes em texto, sem logótipo (interruptor 5.2.1 ligado) ──
    await _tocar(t, find.text('Supermercados'));
    await _exigir(t, _id('cartao_loja'), 'lista-de-supermercados',
        segundos: 45);
    await _bombear(t, segundos: 3);
    await _foto(t, '02-loja-mercados');

    // ── A partir daqui é matéria do VÍDEO (privado): a compra a sério ─────
    // A primeira loja da lista, seja ela qual for — não se crava nome nenhum,
    // porque o que está à venda hoje é o que manda.
    // ABRIR A LOJA — e saber POR QUE nao abre, quando nao abre.
    //
    // CICATRIZ 1 (corrida 34279643078): tocava-se e seguia-se sem confirmar.
    // CICATRIZ 2 (corrida 34285079216): ja se confirmava, mas a mensagem
    // continuava a mentir. Dizia "confirmar que a loja tem produtos" quando o
    // que se passava era outra coisa: `openRetailBusiness` tem um portao de
    // horario e faz `return` com um aviso quando `isOpenNow()` e' falso. O CI
    // corre com relogio UTC, o passo das capturas caiu perto das 23h, e os
    // supermercados da Guarda fecham as 20h-22h. Nenhum abria, e o teste
    // acusava a loja de nao ter produtos.
    //
    // Agora tenta-se loja a loja, e se nenhuma abrir diz-se a HORA — que e' a
    // causa provavel, e a unica que se resolve mudando quando a corrida anda.
    final agora = DateTime.now();
    final horaDoSimulador =
        '${agora.hour.toString().padLeft(2, '0')}:'
        '${agora.minute.toString().padLeft(2, '0')}';
    final quantasLojas = _id('cartao_loja').evaluate().length;
    debugPrint('[arnes] $quantasLojas cartoes de loja, sao $horaDoSimulador '
        'no simulador');

    bool abriu = false;
    for (int n = 0; n < quantasLojas && n < 6; n++) {
      await _tocar(t, _id('cartao_loja').at(n));
      await _bombear(t, segundos: 4);
      if (await _esperar(t, _id('btn_add_carrinho'), segundos: 6)) {
        abriu = true;
        debugPrint('[arnes] abriu a loja numero $n');
        break;
      }
      await _rolarAteAparecer(t, _id('btn_add_carrinho'), vezes: 3);
      if (await _esperar(t, _id('btn_add_carrinho'), segundos: 4)) {
        abriu = true;
        debugPrint('[arnes] abriu a loja numero $n (depois de rolar)');
        break;
      }
      debugPrint('[arnes] a loja numero $n nao abriu — provavelmente fechada');
      // Se tiver entrado nalgum ecra, volta para a lista antes de tentar outra.
      if (_id('cartao_loja').evaluate().isEmpty) {
        // CICATRIZ (corrida 34440774329): `_tocar` faz `f.first`, e um
        // `byTooltip('Back')` que nao existe rebenta com "Bad state: No
        // element" — o teste morria ali em vez de chegar a mensagem util
        // sobre o horario. Toca-se so se houver mesmo botao.
        final voltar = find.byTooltip('Back');
        if (voltar.evaluate().isNotEmpty) {
          await _tocar(t, voltar);
          await _bombear(t, segundos: 2);
        }
      }
    }
    await _foto(t, '03-video-loja');

    if (!abriu) {
      await _binding.takeScreenshot('zz-falha-nenhuma-loja-abriu');
      fail('nenhuma das $quantasLojas lojas abriu, e sao $horaDoSimulador no '
          'simulador (UTC). `openRetailBusiness` bloqueia a entrada fora do '
          'horario da loja: os supermercados da Guarda fecham entre as 20h e '
          'as 22h. Correr o arnes em horario de loja.');
    }

    // A página da loja abre na grelha "Comprar por categoria"; os carrosséis de
    // produtos, que são onde vive o `btn_add_carrinho`, ficam mais abaixo.
    //
    // CICATRIZ (corrida 34220474584): sem rolar, o localizador não encontrava
    // nada e o teste dizia "a loja não tem produtos à venda" — mentira. A lista
    // é preguiçosa, por isso o que está fora do ecrã **nem sequer está
    // construído**, e um `Finder` não encontra o que não existe na árvore. A
    // prova de que nada se tinha mexido: `03-video-loja.png` e
    // `zz-falha-sem-botao-adicionar.png` saíram com o mesmo tamanho exacto.
    final botaoAdicionar = _id('btn_add_carrinho');
    await _foto(t, '04-video-produtos');
    await _tocar(t, botaoAdicionar);
    await _bombear(t, segundos: 2.5);

    // O "+" do cartão não põe o artigo no carrinho: abre a FICHA DO PRODUTO,
    // com foto, quantidade e o seu próprio botão em baixo — medido na corrida
    // 34225343416, que encalhou na "Uva Branca sem Grainha Auchan 500 g, €3,65"
    // à espera de um "Ver carrinho" que nunca podia aparecer, porque o carrinho
    // continuava vazio. Aqui carrega-se no botão da ficha, se ele estiver lá.
    final adicionarNaFicha = find.textContaining('Adicionar ao carrinho');
    if (await _esperar(t, adicionarNaFicha, segundos: 12)) {
      await _foto(t, '05-loja-produto');
      await _tocar(t, adicionarNaFicha);
      await _bombear(t, segundos: 3);
    }

    // ── Carrinho e pagamento: já não há marca de terceiros à vista ────────
    // O botão flutuante da loja é "Ver carrinho · €12,34" — o total muda a cada
    // corrida, por isso procura-se por pedaço de texto e nunca pela frase toda.
    final verCarrinho = find.textContaining('Ver carrinho');
    await _exigir(t, verCarrinho, 'botao-ver-carrinho', segundos: 20);
    await _tocar(t, verCarrinho);

    final finalizar = find.text('Finalizar pedido');
    await _exigir(t, finalizar, 'ecra-do-carrinho', segundos: 25);
    await _foto(t, '06-loja-carrinho');
    await _tocar(t, finalizar);

    await _exigir(t, find.text('Confirmar pagamento'), 'ecra-de-pagamento',
        segundos: 45);
    final dinheiro = find.text('Dinheiro');
    if (await _esperar(t, dinheiro, segundos: 10)) {
      await _tocar(t, dinheiro);
    }
    await _foto(t, '07-loja-pagamento');

    if (_fazerEncomenda) {
      await _tocar(t, find.text('Confirmar pagamento'));
      await _bombear(t, segundos: 12);
      await _foto(t, '08-loja-acompanhar');

      // DENUNCIAR, BLOQUEAR E APAGAR CONTA — a Apple pediu isto por escrito
      // ao recusar (2026-09-10): "Any user-generated content, including the
      // required content reporting and blocking mechanisms" e os fluxos de
      // conta.
      //
      // CICATRIZ (corrida 34458003332): procurava-se o icone do chat logo
      // apos confirmar o pagamento, e nao havia nenhum. Depois de confirmar, a
      // app fica na LISTA de pedidos; os botoes de conversa vivem no DETALHE.
      // O bloco inteiro era saltado em silencio, sem uma linha no log.
      //
      // Tudo protegido: se algum passo nao aparecer, segue-se sem falhar.
      try {
        final cartaoPedido = find.textContaining('#');
        if (cartaoPedido.evaluate().isNotEmpty) {
          await _tocar(t, cartaoPedido.first);
          await _bombear(t, segundos: 6);
          await _foto(t, '13-video-detalhe-pedido');

          // CICATRIZ (corrida 34463405491): procurava-se "Falar com o
          // Estafeta", que e' o rotulo do ecra de ACOMPANHAMENTO. Tocar no
          // cartao abre o ecra de DETALHE, onde o acesso a conversa e' um
          // botao "Chat" dentro do cartao "O teu estafeta" -- e esse cartao
          // fica abaixo da dobra, por isso tem de se ROLAR ate la.
          final cartaoEstafeta = find.text('O teu estafeta');
          await _rolarAteAparecer(t, cartaoEstafeta, vezes: 8);
          final botaoChat = find.text('Chat');
          await _rolarAteAparecer(t, botaoChat, vezes: 4);
          if (await _esperar(t, botaoChat, segundos: 12)) {
            await _tocar(t, botaoChat.first);
            await _bombear(t, segundos: 5);
            final bandeira = find.byIcon(Icons.flag_outlined);
            if (await _esperar(t, bandeira, segundos: 15)) {
              await _foto(t, '14-video-conversa');
              await _tocar(t, bandeira);
              await _bombear(t, segundos: 3);
              await _foto(t, '15-video-denunciar-bloquear');
              final bloquear = find.textContaining('Bloquear esta pessoa');
              if (bloquear.evaluate().isNotEmpty) {
                await _tocar(t, bloquear);
                await _bombear(t, segundos: 5);
                await _foto(t, '16-video-bloqueada');
                // Repoe-se, para a conta de demonstracao ficar como estava.
                final outraVez = find.byIcon(Icons.flag_outlined);
                if (outraVez.evaluate().isNotEmpty) {
                  await _tocar(t, outraVez);
                  await _bombear(t, segundos: 3);
                  final desbloquear =
                      find.textContaining('Desbloquear esta pessoa');
                  if (desbloquear.evaluate().isNotEmpty) {
                    await _tocar(t, desbloquear);
                    await _bombear(t, segundos: 4);
                  }
                }
              }
            } else {
              debugPrint('[arnes] a conversa nao abriu');
              await _binding.takeScreenshot('zz-falha-conversa');
            }
          } else {
            debugPrint('[arnes] sem botao "Chat" no detalhe do pedido');
            await _binding.takeScreenshot('zz-falha-sem-botao-chat');
          }
        } else {
          debugPrint('[arnes] nao achei o cartao do pedido na lista');
        }
        await _voltarAoInicio(t);
      } catch (e) {
        debugPrint('[arnes] denuncia/bloqueio nao deu: $e');
        await _binding.takeScreenshot('zz-falha-bloqueio');
      }

      // APAGAR CONTA — pedido pela Apple (5.1.1(v)). Mostra-se o caminho e o
      // aviso, e CANCELA-SE: apagar a conta de navegacao a meio da corrida
      // deixava o revisor sem por onde entrar. Para apagar a serio existe
      // `demo.apagar@bora.app`, dito nas notas ao revisor.
      try {
        final perfil = find.text('Perfil');
        if (perfil.evaluate().isNotEmpty) {
          await _tocar(t, perfil);
          await _bombear(t, segundos: 4);
          final apagar = find.text('Apagar conta');
          await _rolarAteAparecer(t, apagar, vezes: 8);
          if (await _esperar(t, apagar, segundos: 10)) {
            await _foto(t, '17-video-apagar-conta');
            await _tocar(t, apagar);
            await _bombear(t, segundos: 4);
            await _foto(t, '18-video-apagar-aviso');
            for (final sair in ['Cancelar', 'Agora não', 'Voltar']) {
              final b = find.text(sair);
              if (b.evaluate().isNotEmpty) {
                await _tocar(t, b);
                break;
              }
            }
            await _bombear(t, segundos: 3);
          } else {
            debugPrint('[arnes] nao achei "Apagar conta" no perfil');
            await _binding.takeScreenshot('zz-falha-apagar-conta');
          }
        }
        await _voltarAoInicio(t);
      } catch (e) {
        debugPrint('[arnes] o fluxo de apagar conta nao deu: $e');
        await _binding.takeScreenshot('zz-falha-apagar-conta');
      }

      // Arrumação, não segurança — a caixa fechada já garante que ninguém real
      // é chamado. É só para não deixar pedidos de demonstração abertos. Se o
      // botão não estiver disponível neste estado, segue-se sem drama.
      final cancelar = _id('btn_cancelar_pedido');
      if (await _esperar(t, cancelar, segundos: 20)) {
        await _tocar(t, cancelar);
        await _bombear(t, segundos: 4);
      }
    }

    // ── Parceiros de marca própria: é o que pode ir para a loja ───────────
    // A Goola Açaí é parceira, está online e NÃO está `coming_soon` — vende
    // hoje. Chega-se lá pela pesquisa, para não fotografar a lista de
    // restaurantes, que é dominada por cadeias de terceiros.
    await _voltarAoInicio(t);
    if (await _esperar(t, find.text('Restaurantes'), segundos: 25)) {
      await _tocar(t, find.text('Restaurantes'));
      if (await _esperar(t, find.byType(TextField), segundos: 25)) {
        await t.enterText(find.byType(TextField).first, 'Goola');
        await _bombear(t, segundos: 3);
        if (await _esperar(t, _id('cartao_restaurante'), segundos: 15)) {
          await _tocar(t, _id('cartao_restaurante'));

          // "Carrinho activo": vimos da Auchan com um artigo no cesto, e a app
          // pergunta se se cancela para começar outro pedido. Medido na corrida
          // 34229774614, onde a captura `09-loja-acai` saiu a fotografar o
          // diálogo em vez da loja. Responde-se que sim e segue-se.
          final novoPedido = find.text('Sim, novo pedido');
          if (await _esperar(t, novoPedido, segundos: 8)) {
            await _tocar(t, novoPedido);
            await _bombear(t, segundos: 4);
          }
          await _bombear(t, segundos: 5);
          await _foto(t, '09-loja-acai');
        } else {
          await _binding.takeScreenshot('zz-falha-goola');
        }
      }
    }

    // A Barbearia Ouro e Prata tem 8 serviços activos e não está `coming_soon`.
    await _voltarAoInicio(t);
    if (await _esperar(t, find.text('Beleza'), segundos: 25)) {
      await _tocar(t, find.text('Beleza'));
      if (await _esperar(t, _id('cartao_servico'), segundos: 30)) {
        await _tocar(t, _id('cartao_servico'));
        await _bombear(t, segundos: 5);
        await _foto(t, '10-loja-barbearia');
      } else {
        await _binding.takeScreenshot('zz-falha-barbearia');
      }
    }

    // ── O lado do estafeta: mapa e localização em segundo plano ───────────
    //
    // Fica no FIM de propósito. Tudo o que vem daqui para baixo é prova
    // extra; se falhar, as capturas da loja já estão gravadas em disco e não
    // se perde a corrida por causa disto.
    //
    // O mapa importa: até 2026-09-07 aparecia vazio no iPhone porque o
    // `AppDelegate` nunca chamava `GMSServices.provideAPIKey`. Ver esse ecrã
    // desenhado é a prova de que a correcção pegou no aparelho.
    await _voltarAoInicio(t);
    if (await _sairEVoltarAosPerfis(t)) {
      final portaEstafeta = find.text('Sou Estafeta');
      if (await _esperar(t, portaEstafeta, segundos: 20)) {
        await _tocar(t, portaEstafeta);
        if (await _esperar(t, _id('fld_email'), segundos: 25)) {
          await t.enterText(_id('fld_email').first, _emailEstafeta);
          await _bombear(t, segundos: 0.6);
          await t.enterText(_id('fld_password').first, _senha);
          await _bombear(t, segundos: 0.6);
          await _tocar(t, _id('btn_entrar_driver'));

          // O ecrã do estafeta abre com o mapa. Fotografa-se antes de ligar,
          // para se ver que o mapa desenha mesmo.
          if (await _esperar(t, _id('btn_toggle_online'), segundos: 60)) {
            await _foto(t, '11-video-estafeta-mapa');
            await _tocar(t, _id('btn_toggle_online'));
            await _bombear(t, segundos: 6);
            await _foto(t, '12-video-estafeta-online');
          } else {
            await _binding.takeScreenshot('zz-falha-estafeta');
          }
        }
      }
    }

    // Repor o que a app mudou, senao o `flutter_test` reprova na arrumacao.
    ErrorWidget.builder = construtorDeErroOriginal;
    semantica.dispose();
  }, timeout: const Timeout(Duration(minutes: 45)));
}
