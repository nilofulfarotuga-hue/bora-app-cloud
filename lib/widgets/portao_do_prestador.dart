import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../screens/cleaner/cleaner_home_screen.dart';
import '../screens/washer/washer_home_screen.dart';
import '../services/role_switch_helper.dart';
import '../services/roles_service.dart';
import '../stores/session_store.dart';
import 'profile_switcher_button.dart';

/// PORTÃO POR PAPEL — a entrada de quem trabalha no Bora.
///
/// O `_RootNavigator` mostra-o a TODOS os que entram pela porta do estafeta.
/// Em vez de prender a pessoa em "em análise" por causa do perfil de estafeta,
/// vê que papéis tem aprovados e abre o ecrã de trabalho certo. Sem nenhum,
/// mostra [semOutroPapel] — o comportamento de sempre.
///
/// [09/10/2026 · Mayra] Com vários papéis aprovados entra-se, por esta ordem:
/// no papel com trabalho à espera (oferta viva, trabalho de hoje; estafeta
/// ligado ou com entrega em curso), no ÚLTIMO MODO usado (guardado no
/// `SessionStore`), e só depois na ordem de sempre. Para o estafeta aprovado o
/// portão abre JÁ no modo guardado (sem roda) e só muda depois de ler o
/// servidor se outro papel tiver trabalho à espera — ou se o modo guardado já
/// não estiver aprovado. "Mudar de modo" grava o modo e o portão segue-o.
///
/// Relê ao voltar à app: quem é aprovado com a app em segundo plano entra
/// sem ter de sair e voltar a entrar.
class PortaoDoPrestador extends StatefulWidget {
  const PortaoDoPrestador({
    super.key,
    required this.semOutroPapel,
    this.estafetaAprovado = false,
  });

  /// O ecrã do estafeta (aprovado, ou com o seu próprio "em análise" / a
  /// candidatura por acabar).
  final Widget semOutroPapel;

  /// O perfil de estafeta está aprovado (o AuthStore já o sabe).
  final bool estafetaAprovado;

  @override
  State<PortaoDoPrestador> createState() => _PortaoDoPrestadorState();
}

class _PortaoDoPrestadorState extends State<PortaoDoPrestador>
    with WidgetsBindingObserver {
  EntradaDoPrestador? _entrada; // null = ainda a ler
  RolesSummary? _resumo;
  bool _decidido = false;
  String? _modoVisto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final modo = context.read<SessionStore>().ultimoModoTrabalho;
    _modoVisto = modo;
    // Estafeta aprovado e último modo = estafeta (ou nenhum): abre JÁ o ecrã
    // do estafeta, sem roda — exatamente como antes. Com outro modo guardado
    // espera pela leitura do servidor: um estafeta ligado ou com entrega nunca
    // abre noutro ecrã, e se a leitura falhar cai no do estafeta (revisão 09/10).
    if (widget.estafetaAprovado &&
        (modo == null || modo == 'estafeta')) {
      _entrada = EntradaDoPrestador.estafeta;
    }
    _ler();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ler();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Mudar de modo" → Estafeta grava o modo no SessionStore: o portão volta
    // ao ecrã do estafeta. SÓ nessa direção: limpeza e lavagem abrem POR CIMA
    // (ver ProfileSwitcherButton), nunca desmontando o ecrã do estafeta — que
    // é onde vivem o batimento, o GPS e o cartão das ofertas de entrega.
    final modo = Provider.of<SessionStore>(context).ultimoModoTrabalho;
    if (modo == _modoVisto) return;
    _modoVisto = modo;
    final pedida = entradaDoModo(modo);
    if (pedida != EntradaDoPrestador.estafeta || pedida == _entrada) return;
    if (_papelAprovado(pedida!)) _entrada = pedida;
  }

  bool _papelAprovado(EntradaDoPrestador e) {
    final r = _resumo;
    return switch (e) {
      EntradaDoPrestador.estafeta =>
        widget.estafetaAprovado || (r?.driverApproved ?? false),
      EntradaDoPrestador.limpeza => r?.cleanerApproved ?? false,
      EntradaDoPrestador.lavagem => r?.washerApproved ?? false,
      EntradaDoPrestador.nenhuma => false,
    };
  }

  Future<void> _ler() async {
    final auth = context.read<AuthStore>();
    final session = context.read<SessionStore>();
    // O estado do estafeta refresca-se aqui também: se entretanto foi
    // aprovado, o AuthStore avisa e o `_RootNavigator` reconstrói o portão.
    //
    // Com limite de tempo: sem rede, ninguém fica preso na roda — cai no
    // ecrã de sempre, que tem os seus próprios botões.
    RolesSummary resumo;
    TrabalhoPendente pendente;
    try {
      final resultados = await Future.wait<Object>([
        auth.refreshApprovalStatus(),
        RolesService.mySummary(),
        RolesService.myTrabalhoPendente(),
      ]).timeout(const Duration(seconds: 8));
      resumo = resultados[1] as RolesSummary;
      pendente = resultados[2] as TrabalhoPendente;
    } catch (_) {
      resumo = RolesSummary.empty();
      pendente = TrabalhoPendente.nenhum;
    }
    if (!mounted) return;
    final leituraFalhou = !resumo.temAlgumPapel;
    if (!leituraFalhou) _resumo = resumo;
    final nova = entradaDoPrestador(resumo,
        ultimoModo: session.ultimoModoTrabalho, pendente: pendente);

    final atual = _entrada;
    EntradaDoPrestador? escolhida;
    if (!_decidido) {
      // Primeira leitura: decide. Uma leitura falhada não tira o estafeta
      // aprovado do ecrã que já está a ver.
      if (leituraFalhou && atual != null) {
        escolhida = atual;
      } else {
        escolhida = nova;
      }
      _decidido = !leituraFalhou;
    } else if (atual == null ||
        atual == EntradaDoPrestador.nenhuma ||
        (!leituraFalhou && !_papelAprovado(atual))) {
      // Depois: só se muda quando o ecrã atual deixou de ser válido.
      escolhida = leituraFalhou ? atual : nova;
    } else {
      escolhida = atual;
    }
    if (escolhida != _entrada) setState(() => _entrada = escolhida);
    final modo = escolhida == null ? null : modoDaEntrada(escolhida);
    if (modo != null) {
      _modoVisto = modo;
      await session.setUltimoModoTrabalho(modo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_entrada) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      EntradaDoPrestador.limpeza => const CleanerHomeScreen(comoEntrada: true),
      EntradaDoPrestador.lavagem => const WasherHomeScreen(comoEntrada: true),
      _ => widget.semOutroPapel,
    };
  }
}

/// Os botões da barra quando o ecrã da limpeza ou da lavagem é a ENTRADA da
/// pessoa (e não um ecrã aberto por cima do do estafeta): sem eles não havia
/// como sair, nem como ir fazer pedidos como cliente.
///
/// [03/10 · Mayra] Os dois ícones sem texto ("trabalhar noutra coisa" e
/// "fazer pedidos como cliente") deram lugar ao botão "Mudar de modo", que
/// lista TODOS os papéis da pessoa. Quem só tem um papel continua a ter o
/// atalho para cliente.
List<Widget> acoesDaEntradaDoPrestador(BuildContext context,
        {String? modoAtual}) =>
    [
      ProfileSwitcherButton(modoAtual: modoAtual, comTexto: true),
      IconButton(
        icon: const Icon(Icons.shopping_bag_outlined),
        tooltip: 'Fazer pedidos como cliente',
        onPressed: () async {
          final ok = await activateRole(context, UserRole.client);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Não foi possível abrir o teu perfil de '
                    'cliente. Tenta de novo.')));
          }
        },
      ),
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Terminar sessão',
        onPressed: () async {
          context.read<AuthStore>().logout();
          await context.read<SessionStore>().clearRole();
        },
      ),
    ];
