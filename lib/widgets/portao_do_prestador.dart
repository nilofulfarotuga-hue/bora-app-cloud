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
/// O `_RootNavigator` só o mostra quando o perfil de estafeta NÃO está
/// aprovado (pendente, recusado ou inexistente). Em vez de prender a pessoa em
/// "em análise" por causa desse perfil, vê se ela tem outro papel aprovado e
/// abre o ecrã de trabalho desse papel. Sem nenhum, mostra [semOutroPapel] —
/// o comportamento de sempre.
///
/// Relê ao voltar à app: quem é aprovado com a app em segundo plano entra
/// sem ter de sair e voltar a entrar.
class PortaoDoPrestador extends StatefulWidget {
  const PortaoDoPrestador({super.key, required this.semOutroPapel});

  /// O que se mostrava antes de existir este portão (ecrã do estafeta, que
  /// tem o seu próprio "em análise", ou a candidatura por acabar).
  final Widget semOutroPapel;

  @override
  State<PortaoDoPrestador> createState() => _PortaoDoPrestadorState();
}

class _PortaoDoPrestadorState extends State<PortaoDoPrestador>
    with WidgetsBindingObserver {
  EntradaDoPrestador? _entrada; // null = ainda a ler

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _ler() async {
    final auth = context.read<AuthStore>();
    // O estado do estafeta refresca-se aqui também: se entretanto foi
    // aprovado, o AuthStore avisa e o `_RootNavigator` tira este portão.
    //
    // Com limite de tempo: sem rede, ninguém fica preso na roda — cai no
    // ecrã de sempre, que tem os seus próprios botões.
    RolesSummary resumo;
    try {
      final resultados = await Future.wait<Object>([
        auth.refreshApprovalStatus(),
        RolesService.mySummary(),
      ]).timeout(const Duration(seconds: 8));
      resumo = resultados[1] as RolesSummary;
    } catch (_) {
      resumo = RolesSummary.empty();
    }
    if (!mounted) return;
    final nova = entradaDoPrestador(resumo);
    // Uma releitura falhada (ao voltar à app sem rede) não tira ninguém do
    // ecrã de trabalho em que já estava.
    if (_entrada != null && nova == EntradaDoPrestador.nenhuma) return;
    setState(() => _entrada = nova);
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
