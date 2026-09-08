// Capturas da App Store e vídeo do revisor — a partir da APP REAL.
//
// PORQUE ESTE FICHEIRO EXISTE (cicatriz de 2026-09-08)
// O arnês anterior (`capturas_loja_test.dart` + `lib/screens/capturas/`)
// desenhava sete ecrãs bonitos com dados **inventados**: uma "Mercado da
// Guarda" que não existe, uma "Barbearia Central" que não existe, açaí a €4,50
// quando a Goola Açaí só tem Big Bowl a €11,55 e Goola Bowl a €9,22, limpeza a
// €25/hora quando o preço real é por tipologia, e uma "Lavagem + Cera €20" que
// nunca existiu. Auditado contra a produção: as **sete** falharam. Mostrar isso
// à Apple é reprovação por metadados enganosos (2.3.1) e por o revisor não
// encontrar na app o que viu nas imagens (2.3.3). O arnês foi apagado.
//
// REGRA, sem excepção: nenhuma captura e nenhum vídeo mostra loja, serviço,
// produto ou preço que não exista mesmo no banco de produção. Por isso este
// teste não desenha nada — abre a app a sério, liga-se ao servidor e fotografa
// o que lá está.
//
// PORQUE NÃO HÁ UM ÚNICO `pumpAndSettle`
// `app.main()` traz Supabase, Firebase, realtime e `Timer.periodic` a andar.
// Com isso o `pumpAndSettle` **nunca** assenta: na corrida 34163172748 deu
// +0 -7, o binding ficava com frame pendente e o primeiro teste envenenava os
// seguintes. Aqui bombeia-se em passos curtos deixando o relógio real correr
// (`runAsync`), e espera-se por um `Finder` com prazo. Nunca se espera pelo
// "fim" de coisa nenhuma, porque não há fim.
//
// O QUE ESTE TESTE PRODUZ
//   · PNGs 1320×2868 em `artefactos/capturas/` (o simulador é o maior iPhone)
//   · imagem parada e legível para o `xcrun simctl recordVideo` do workflow,
//     que é a matéria-prima do vídeo de 60–120 s das notas ao revisor.
//
// A ENCOMENDA A SÉRIO ESTÁ ATRÁS DE UM INTERRUPTOR
// `--dart-define=FAZER_ENCOMENDA_REAL=true`. Desligado, o percurso vai até ao
// ecrã de pagamento e pára. Ligado, confirma em DINHEIRO.
//
// E NÃO CHAMA NINGUÉM REAL: o gatilho BEFORE INSERT
// `a_trg_pedido_demo_caixa_fechada` em `orders` (confirmado ligado a
// 2026-09-08) apanha `demo@bora.app`, `demo.cliente@bora.app` e
// `demo.apagar@bora.app` e força `is_test_order`, dinheiro, e nasce já em
// `driverAccepted` atribuída ao estafeta demo. Nunca passa por
// `callingDriver`, por isso o dispatch — que corre de 15 em 15 s — nunca a
// oferece a um estafeta real. É esta caixa fechada que sustenta a frase das
// notas ao revisor: "orders placed from the demo account are never dispatched
// to real couriers". Se o gatilho for desligado, a frase deixa de ser verdade.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bora_app/main.dart' as app;

/// Credenciais da conta de demonstração. Já são públicas de propósito — estão
/// em `ios/NOTAS-AO-REVISOR.md`, que é o que se entrega à Apple.
const String _email =
    String.fromEnvironment('DEMO_EMAIL', defaultValue: 'demo@bora.app');
const String _senha =
    String.fromEnvironment('DEMO_PASSWORD', defaultValue: 'BoraDemo2026!');

/// Segundos que cada ecrã fica parado depois da fotografia, só para o gravador
/// de vídeo apanhar a imagem legível. Não afecta a captura em si.
const int _pausa = int.fromEnvironment('SEGUNDOS_POR_ECRA', defaultValue: 6);

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
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
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
  await _binding.takeScreenshot('falha-$oQue');
  fail('não apareceu: $oQue');
}

/// Toca no primeiro [f], arrastando-o para a vista se estiver fora do ecrã.
///
/// `tap` num widget fora do ecrã não bate em nada e, com `warnIfMissed: false`,
/// falha em silêncio — o teste seguiria a fingir que carregou. A página da loja
/// empilha carrosséis por categoria (o Continente tem dezenas), por isso o
/// botão de adicionar está quase sempre a meio da lista.
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

Future<void> _foto(WidgetTester t, String nome) async {
  await _bombear(t, segundos: 1.5);
  await _binding.takeScreenshot(nome);
  // Só para o gravador: a captura já está feita.
  await _bombear(t, segundos: _pausa.toDouble());
}

Finder _porIdentificador(String id) => find.bySemanticsIdentifier(id);

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('percorre a app real e fotografa o que existe mesmo',
      (WidgetTester t) async {
    await app.main();
    await _bombear(t, segundos: 6);

    // ── Entrar como cliente ───────────────────────────────────────────────
    // Pode já haver sessão aberta de uma corrida anterior; nesse caso o ecrã
    // de papéis não aparece e salta-se o login.
    final portaCliente = find.text('Sou Cliente');
    if (await _esperar(t, portaCliente, segundos: 20)) {
      await _foto(t, '00-perfis');
      await _tocar(t, portaCliente);

      await _exigir(t, _porIdentificador('fld_email'), 'campo-email');
      await t.enterText(_porIdentificador('fld_email').first, _email);
      await _bombear(t, segundos: 0.6);
      await t.enterText(_porIdentificador('fld_password').first, _senha);
      await _bombear(t, segundos: 0.6);
      await _foto(t, '01-entrar');
      await _tocar(t, _porIdentificador('btn_entrar'));
    }

    // ── Início: as categorias reais ───────────────────────────────────────
    await _exigir(t, find.text('Supermercados'), 'ecra-inicial', segundos: 60);
    await _foto(t, '02-inicio');

    // ── Supermercados: lojas reais da Guarda ──────────────────────────────
    await _tocar(t, find.text('Supermercados'));
    await _exigir(t, find.byType(ListView), 'lista-de-supermercados',
        segundos: 45);
    await _bombear(t, segundos: 4);
    await _foto(t, '03-supermercados');

    // A primeira loja da lista, seja ela qual for — não se crava nome nenhum,
    // porque o que está à venda hoje é o que manda.
    //
    // Pelo identificador, não pelo tipo: o cartão é um `GestureDetector` e não
    // um `InkWell`, e `find.byType(InkWell).first` apanhava um chip da barra de
    // ordenação em vez da loja.
    final primeiraLoja = _porIdentificador('cartao_loja');
    await _exigir(t, primeiraLoja, 'cartao-de-loja');
    await _tocar(t, primeiraLoja);
    await _bombear(t, segundos: 5);
    await _foto(t, '04-loja');

    // ── Produto real e carrinho ───────────────────────────────────────────
    final botaoAdicionar = _porIdentificador('btn_add_carrinho');
    if (await _esperar(t, botaoAdicionar, segundos: 30)) {
      await _foto(t, '05-produtos');
      await _tocar(t, botaoAdicionar);
      await _bombear(t, segundos: 2);
      await _foto(t, '06-adicionado');
    } else {
      await _binding.takeScreenshot('falha-sem-botao-adicionar');
      fail('a loja abriu mas não há nenhum "adicionar ao carrinho" — '
          'confirmar que a loja escolhida tem produtos à venda');
    }

    // ── Carrinho → pagamento ──────────────────────────────────────────────
    // O botão flutuante da loja é "Ver carrinho · €12,34" — o total muda a cada
    // corrida, por isso procura-se por pedaço de texto e nunca pela frase toda.
    final verCarrinho = find.textContaining('Ver carrinho');
    await _exigir(t, verCarrinho, 'botao-ver-carrinho', segundos: 20);
    await _tocar(t, verCarrinho);

    final finalizar = find.text('Finalizar pedido');
    if (await _esperar(t, finalizar, segundos: 20)) {
      await _foto(t, '07-carrinho');
      await _tocar(t, finalizar);

      await _exigir(t, find.text('Confirmar pagamento'), 'ecra-de-pagamento',
          segundos: 45);
      final dinheiro = find.text('Dinheiro');
      if (await _esperar(t, dinheiro, segundos: 10)) {
        await _tocar(t, dinheiro);
      }
      await _foto(t, '08-pagamento');

      if (_fazerEncomenda) {
        await _tocar(t, find.text('Confirmar pagamento'));
        await _bombear(t, segundos: 12);
        await _foto(t, '09-acompanhar');

        // Arrumação, não segurança — a caixa fechada já garante que ninguém
        // real é chamado. É só para não deixar pedidos de demonstração abertos
        // a encher a lista. Se o botão não estiver disponível neste estado,
        // segue-se sem drama.
        final cancelar = _porIdentificador('btn_cancelar_pedido');
        if (await _esperar(t, cancelar, segundos: 20)) {
          await _tocar(t, cancelar);
          await _bombear(t, segundos: 4);
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
