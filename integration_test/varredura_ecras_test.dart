// VARREDURA DE ECRÃS — o teste que devia ter existido antes (2026-09-10).
//
// PORQUE EXISTE. Num só dia o Danilo encontrou TRÊS crashes num iPhone real
// que nenhum teste nosso via, e todos por duas causas nativas:
//
//   * a chave do Google Maps chegava VAZIA ao IPA, e o SDK aborta o processo
//     ao criar o primeiro mapa. Dez ecrãs da app montam mapa. Todos mortos.
//   * o `Info.plist` não declarava `NSFaceIDUsageDescription`, e o iOS mata a
//     app quando se pede biometria sem essa chave.
//
// Ordem do Danilo, definitiva: *"quem prova a app és tu. Build com autoteste
// vermelho não sai. Sem exceção."*
//
// COMO ISTO APANHA UM CRASH. Se a app morrer, o `flutter drive` perde o
// serviço e a corrida falha sozinha — mas sem dizer ONDE. Por isso cada passo
// ANUNCIA-SE antes de acontecer: a última linha `[varredura]` do log nomeia
// sempre o ecrã que matou a app. Foi exactamente isso que faltou hoje.
//
// O que este teste NÃO apanha: biometria (o simulador não tem nenhuma
// inscrita). Essa fica coberta por `test/ios_info_plist_test.dart`, que é
// estático e corre antes de haver build.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bora_app/main.dart' as app;
import 'package:bora_app/services/notification_service.dart';

late IntegrationTestWidgetsFlutterBinding _binding;

const String _emailCliente =
    String.fromEnvironment('DEMO_EMAIL', defaultValue: 'demo@bora.app');
const String _senha =
    String.fromEnvironment('DEMO_PASSWORD', defaultValue: 'BoraDemo2026!');
const String _emailEstafeta = String.fromEnvironment('DEMO_EMAIL_ESTAFETA',
    defaultValue: 'demo-estafeta@bora.app');
const String _emailParceiro = String.fromEnvironment('DEMO_EMAIL_PARCEIRO',
    defaultValue: 'demo-parceiro@bora.app');

/// Os mosaicos do ecrã inicial do cliente, tal como aparecem escritos.
/// Vêm de `client_home_screen.dart`. Um mosaico novo acrescenta-se aqui —
/// e é de propósito que dá trabalho: um ecrã que ninguém varre é um ecrã que
/// pode ir para a Apple partido.
const List<String> _mosaicos = [
  'Restaurantes',
  'Supermercados',
  'Farmácia',
  'Lojas',
  'Enviar\nEncomenda',
  'Levar\nCompras',
  'Favores',
  'Reservar\nMesa',
  'Beleza',
  'Limpeza',
  'Bora\nMotorista',
  'Festas',
  'Sobremesas',
  'Lavagem Auto',
];

/// Separadores de fundo do cliente, além do Início.
/// Rótulos lidos de `bora_bottom_nav_v2.dart` — no singular.
const List<String> _separadoresCliente = ['Entrega', 'Reserva', 'Perfil'];

void _diz(String m) => debugPrint('[varredura] $m');

Future<void> _bombear(WidgetTester t, {double segundos = 1.0}) async {
  const passo = Duration(milliseconds: 200);
  for (int i = 0; i < (segundos * 5).round(); i++) {
    await t.pump(passo);
    await t.runAsync(() => Future<void>.delayed(passo));
  }
}

Future<bool> _esperar(WidgetTester t, Finder f, {double segundos = 30}) async {
  for (int i = 0; i < (segundos * 5).round(); i++) {
    if (f.evaluate().isNotEmpty) return true;
    await t.pump(const Duration(milliseconds: 200));
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
  return false;
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  try {
    await t.ensureVisible(f.first);
    await _bombear(t, segundos: 0.5);
  } catch (_) {/* não está num Scrollable */}
  await t.tap(f.first, warnIfMissed: false);
  await _bombear(t, segundos: 1.5);
}

Future<void> _rolarAte(WidgetTester t, Finder f, {int vezes = 6}) async {
  for (int i = 0; i < vezes; i++) {
    if (f.evaluate().isNotEmpty) return;
    final rolavel = find.byType(Scrollable);
    if (rolavel.evaluate().isEmpty) return;
    try {
      await t.drag(rolavel.first, const Offset(0, -500), warnIfMissed: false);
    } catch (_) {
      return;
    }
    await _bombear(t, segundos: 1.0);
  }
}

/// Volta UM ecrã atrás sem tocar às cegas. CICATRIZ (corrida 87, e antes
/// dela a corrida 34440774329 do arnês): `find.byTooltip('Back')` sem guarda
/// dá "Bad state: No element" e mata o teste inteiro num ecrã que nem
/// sequer tinha seta.
Future<void> _voltar(WidgetTester t) async {
  final nav = NotificationService.navigatorKey.currentState;
  if (nav != null && nav.canPop()) {
    nav.pop();
  } else {
    final seta = find.byIcon(Icons.arrow_back);
    if (seta.evaluate().isNotEmpty) await _tocar(t, seta.first);
  }
  await _bombear(t, segundos: 2);
}

Future<void> _voltarAoInicio(WidgetTester t) async {
  NotificationService.navigatorKey.currentState
      ?.popUntil((rota) => rota.isFirst);
  await _bombear(t, segundos: 2.5);
}

/// Quantos textos com conteúdo estão no ecrã. É a medida de "não está vazio".
int _quantoTexto() {
  var n = 0;
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
    if (s.isNotEmpty) n++;
  }
  return n;
}

/// Falha se o ecrã veio vazio ou com o ecrã vermelho de erro do Flutter.
Future<void> _exigirEcraVivo(WidgetTester t, String oQue,
    {int minimoDeTextos = 3}) async {
  if (find.byType(ErrorWidget).evaluate().isNotEmpty) {
    await _binding.takeScreenshot('zz-erro-$oQue');
    fail('ECRÃ DE ERRO em "$oQue" — o Flutter mostrou o ecrã vermelho.');
  }
  final n = _quantoTexto();
  if (n < minimoDeTextos) {
    await _binding.takeScreenshot('zz-vazio-$oQue');
    fail('ECRÃ VAZIO em "$oQue" — só $n textos com conteúdo '
        '(mínimo $minimoDeTextos).');
  }
  _diz('   ok: "$oQue" com $n textos');
}

/// O acompanhamento do pedido abre-se sozinho quando há pedido com estafeta.
/// É um dos ecrãs com mapa, por isso conta como cobertura — mas tem de se
/// sair dele, senão esconde tudo o resto.
Future<void> _fecharAcompanhamentoSeAberto(WidgetTester t) async {
  final mapa = find.byIcon(Icons.my_location);
  if (!await _esperar(t, mapa, segundos: 12)) return;
  _diz('acompanhamento do pedido abriu sozinho (ecrã COM MAPA) — sobreviveu');
  await _exigirEcraVivo(t, 'acompanhamento-do-pedido', minimoDeTextos: 1);
  final voltar = find.byIcon(Icons.arrow_back);
  if (voltar.evaluate().isNotEmpty) {
    await _tocar(t, voltar.first);
    await _bombear(t, segundos: 2);
  }
}

Future<void> _entrar(WidgetTester t, String email) async {
  _diz('a entrar com $email');
  final campos = find.byType(TextField);
  await _esperar(t, campos, segundos: 30);
  await t.enterText(campos.at(0), email);
  await _bombear(t, segundos: 0.5);
  await t.enterText(campos.at(1), _senha);
  await _bombear(t, segundos: 0.5);
  await _tocar(t, find.text('Entrar'));
  await _bombear(t, segundos: 8);
}

/// Sai da conta corrente. Cada perfil tem a sua porta de saída:
/// cliente = Perfil > "Terminar sessão"; estafeta e parceiro = ícone com
/// tooltip. Devolve `true` se voltou ao ecrã de escolha de perfil.
Future<bool> _sair(WidgetTester t) async {
  _diz('a terminar sessão');
  await _voltarAoInicio(t);

  Future<void> confirmarSePedir() async {
    for (final c in ['Terminar sessão', 'Sair', 'Sim', 'Confirmar']) {
      final b = find.text(c);
      if (b.evaluate().isNotEmpty) {
        await _tocar(t, b.last);
        await _bombear(t, segundos: 4);
        return;
      }
    }
  }

  // Estafeta e parceiro: ícone no topo.
  for (final tip in ['Terminar sessão', 'Sair']) {
    final icone = find.byTooltip(tip);
    if (icone.evaluate().isNotEmpty) {
      await _tocar(t, icone.first);
      await _bombear(t, segundos: 3);
      await confirmarSePedir();
      return _esperar(t, find.text('Sou Cliente'), segundos: 20);
    }
  }

  // Cliente: separador Perfil e botão no fim da página.
  final perfil = find.text('Perfil');
  if (await _esperar(t, perfil, segundos: 10)) {
    await _tocar(t, perfil.last);
    await _bombear(t, segundos: 3);
  }
  final sair = find.text('Terminar sessão');
  await _rolarAte(t, sair, vezes: 10);
  if (await _esperar(t, sair, segundos: 10)) {
    await _tocar(t, sair);
    await _bombear(t, segundos: 4);
    await confirmarSePedir();
  }
  return _esperar(t, find.text('Sou Cliente'), segundos: 20);
}

/// Abre um ecrã pelo texto que o alcança, prova que veio vivo, regista.
/// Devolve a mensagem da falha, ou `null` se ficou bem.
Future<String?> _abrirEProvar(WidgetTester t, String rotulo,
    {String? alvoTexto, String? alvoTooltip, int minimoDeTextos = 3}) async {
  final alvo = alvoTooltip != null
      ? find.byTooltip(alvoTooltip)
      : find.text(alvoTexto ?? rotulo);
  await _rolarAte(t, alvo, vezes: 8);
  if (alvo.evaluate().isEmpty) {
    _diz('"$rotulo" NÃO ESTÁ no ecrã — saltado (categoria fechada?)');
    return null;
  }
  // Anuncia-se ANTES de tocar: se a app morrer aqui, é esta a última linha
  // do log e sabe-se logo quem foi.
  _diz('a abrir "$rotulo"…');
  await _tocar(t, alvo);
  await _bombear(t, segundos: 5);
  try {
    await _exigirEcraVivo(t, rotulo, minimoDeTextos: minimoDeTextos);
    return null;
  } on TestFailure catch (e) {
    return '$rotulo: ${e.message}';
  }
}

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('varre todos os mosaicos e os três perfis sem a app morrer',
      (t) async {
    final falhados = <String>[];
    final porVarrer = <String>[];

    app.main();
    await _bombear(t, segundos: 12);

    // ── Folha de privacidade ────────────────────────────────────────────
    final aceitar = find.text('Aceitar tudo');
    if (await _esperar(t, aceitar, segundos: 20)) {
      await _tocar(t, aceitar);
      await _bombear(t, segundos: 2);
    }

    // ══ PERFIL 1: CLIENTE ═══════════════════════════════════════════════
    _diz('PERFIL 1 de 3: CLIENTE');
    final souCliente = find.text('Sou Cliente');
    expect(await _esperar(t, souCliente, segundos: 30), isTrue,
        reason: 'o ecrã de escolha de perfil nunca apareceu');
    await _tocar(t, souCliente);
    await _bombear(t, segundos: 3);

    // Ecrãs de entrada que a Apple pediu para ver: registo e recuperação.
    final criar = find.text('Criar conta');
    if (await _esperar(t, criar, segundos: 8)) {
      final r = await _abrirEProvar(t, 'registo-do-cliente',
          alvoTexto: 'Criar conta');
      if (r != null) falhados.add(r);
      await _voltar(t);
    }
    final esqueci = find.text('Esqueci-me da palavra-passe');
    if (await _esperar(t, esqueci, segundos: 8)) {
      final r = await _abrirEProvar(t, 'recuperar-palavra-passe',
          alvoTexto: 'Esqueci-me da palavra-passe', minimoDeTextos: 2);
      if (r != null) falhados.add(r);
      await _voltar(t);
    }

    await _entrar(t, _emailCliente);

    final agoraNao = find.text('Agora não');
    if (await _esperar(t, agoraNao, segundos: 6)) {
      await _tocar(t, agoraNao);
      await _bombear(t, segundos: 2);
    }

    await _fecharAcompanhamentoSeAberto(t);

    expect(await _esperar(t, find.text('Supermercados'), segundos: 60), isTrue,
        reason: 'o ecrã inicial do cliente nunca apareceu');
    await _exigirEcraVivo(t, 'inicio-do-cliente', minimoDeTextos: 6);

    // ── Todos os mosaicos, um a um ──────────────────────────────────────
    for (final mosaico in _mosaicos) {
      await _voltarAoInicio(t);
      final inicio = find.text('Início');
      if (inicio.evaluate().isNotEmpty) await _tocar(t, inicio.last);
      final r = await _abrirEProvar(t, mosaico.replaceAll('\n', ' '),
          alvoTexto: mosaico);
      if (r != null) falhados.add(r);
    }
    await _voltarAoInicio(t);

    // ── Separadores de fundo ────────────────────────────────────────────
    for (final sep in _separadoresCliente) {
      final r = await _abrirEProvar(t, 'separador-$sep',
          alvoTexto: sep, minimoDeTextos: 2);
      if (r != null) falhados.add(r);
    }

    // ── Perfil: o caminho de apagar conta (5.1.1(v)), sem apagar ────────
    final apagar = find.text('Apagar conta');
    await _rolarAte(t, apagar, vezes: 10);
    if (await _esperar(t, apagar, segundos: 8)) {
      _diz('a abrir "Apagar conta" (só o aviso; cancela-se)');
      await _tocar(t, apagar);
      await _bombear(t, segundos: 3);
      try {
        await _exigirEcraVivo(t, 'apagar-conta-aviso', minimoDeTextos: 2);
      } on TestFailure catch (e) {
        falhados.add('apagar-conta: ${e.message}');
      }
      for (final c in ['Cancelar', 'Agora não', 'Não']) {
        final b = find.text(c);
        if (b.evaluate().isNotEmpty) {
          await _tocar(t, b.last);
          break;
        }
      }
      await _bombear(t, segundos: 2);
    } else {
      porVarrer.add('apagar conta (não achei o botão no Perfil)');
    }

    // ══ PERFIL 2: ESTAFETA ══════════════════════════════════════════════
    // O ecrã inicial do estafeta MONTA MAPA à entrada — foi o terceiro
    // crash que o Danilo apanhou na build 63.
    _diz('PERFIL 2 de 3: ESTAFETA (o ecrã inicial monta mapa)');
    if (!await _sair(t)) {
      falhados.add('cliente: não consegui terminar sessão');
    }
    final souEstafeta = find.text('Sou Estafeta');
    if (await _esperar(t, souEstafeta, segundos: 20)) {
      await _tocar(t, souEstafeta);
      await _bombear(t, segundos: 3);
      await _entrar(t, _emailEstafeta);
      await _bombear(t, segundos: 10);
      _diz('   entrou como estafeta — a app não morreu ao montar o mapa');
      try {
        await _exigirEcraVivo(t, 'inicio-do-estafeta', minimoDeTextos: 2);
      } on TestFailure catch (e) {
        falhados.add('estafeta: ${e.message}');
      }
      // Os ecrãs do estafeta alcançam-se por ícone com tooltip (Ganhos,
      // Perfil) ou por rótulo (Definições). Lido de `driver_home_screen.dart`.
      for (final tip in ['Ganhos', 'Perfil']) {
        final r = await _abrirEProvar(t, 'estafeta-$tip',
            alvoTooltip: tip, minimoDeTextos: 2);
        if (r != null) falhados.add(r);
        await _voltarAoInicio(t);
      }
      final r2 = await _abrirEProvar(t, 'estafeta-Definições',
          alvoTexto: 'Definições', minimoDeTextos: 2);
      if (r2 != null) falhados.add(r2);
      await _voltarAoInicio(t);
    } else {
      falhados.add('não cheguei ao botão "Sou Estafeta"');
    }

    // ══ PERFIL 3: PARCEIRO ══════════════════════════════════════════════
    _diz('PERFIL 3 de 3: PARCEIRO');
    if (!await _sair(t)) {
      falhados.add('estafeta: não consegui terminar sessão');
    }
    final souParceiro = find.text('Sou Parceiro');
    if (await _esperar(t, souParceiro, segundos: 20)) {
      await _tocar(t, souParceiro);
      await _bombear(t, segundos: 3);
      await _entrar(t, _emailParceiro);
      await _bombear(t, segundos: 10);
      try {
        await _exigirEcraVivo(t, 'inicio-do-parceiro', minimoDeTextos: 2);
      } on TestFailure catch (e) {
        falhados.add('parceiro: ${e.message}');
      }
      // Rótulos lidos de `partner_dashboard_screen.dart`.
      for (final e in [
        'Gerir produtos',
        'Horários de funcionamento',
        'Ver detalhe de ganhos',
        'Extrato',
        'Reservas Pro',
        'Chamar estafeta',
      ]) {
        final r = await _abrirEProvar(t, 'parceiro-$e',
            alvoTexto: e, minimoDeTextos: 2);
        if (r != null) falhados.add(r);
        await _voltarAoInicio(t);
      }
    } else {
      falhados.add('não cheguei ao botão "Sou Parceiro"');
    }

    _diz('VARREDURA TERMINADA. Falhas: ${falhados.length}. '
        'Por varrer: ${porVarrer.length}');
    for (final f in falhados) {
      _diz('   FALHOU $f');
    }
    for (final p in porVarrer) {
      _diz('   POR VARRER $p');
    }
    expect(falhados, isEmpty,
        reason: 'ecrãs partidos ou vazios:\n${falhados.join('\n')}');
  });
}
