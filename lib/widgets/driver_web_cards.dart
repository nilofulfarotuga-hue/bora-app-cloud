// lib/widgets/driver_web_cards.dart
//
// [Estafeta web 2026-09-16] Cartões que só existem no NAVEGADOR, por cima do
// cartão "Estás offline / À espera de pedidos" do ecrã do estafeta:
//
//  1. iPhone no navegador: aviso fixo e curto — "Para receberes pedidos
//     sempre, mantém o ecrã ligado e a Bora aberta." (o iOS suspende a página
//     ao bloquear; sem isto o estafeta acha que está a receber e não está).
//  2. Instalar a Bora no ecrã principal (PWA): explicação curta com imagem
//     (desenhada em widgets — sem ficheiro novo), passos do Safari/Chrome.
//     Fecha-se e fica fechado (SharedPreferences).
//  3. Ativar notificações: um toque pede a permissão do navegador e regista
//     o token web. No iPhone só funciona com a Bora no ecrã principal
//     (iOS 16.4 ou mais) — e a página diz isso.
//
// Tudo em PT-PT (app do estafeta).
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import '../services/web_presence.dart';

class DriverWebCards extends StatefulWidget {
  const DriverWebCards({
    super.key,
    required this.isOnline,
    required this.onAtivarNotificacoes,
  });

  final bool isOnline;
  final Future<void> Function() onAtivarNotificacoes;

  @override
  State<DriverWebCards> createState() => _DriverWebCardsState();
}

class _DriverWebCardsState extends State<DriverWebCards> {
  static const _kInstalarFechado = 'bora_web.instalar_fechado';
  bool _instalarFechado = true; // até ler as prefs não mostra (evita salto)
  bool _aAtivar = false;

  @override
  void initState() {
    super.initState();
    // Regra dos gémeos: o index.html tem um banner HTML com o mesmo convite
    // (para todos os papéis). No ecrã do estafeta manda este cartão — o
    // HTML esconde-se enquanto aqui estivermos; fechar um fecha os dois.
    WebPresence.instance.hideNativeIosBanner();
    _lerPrefs();
  }

  Future<void> _lerPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _instalarFechado =
          (prefs.getBool(_kInstalarFechado) ?? false) ||
              WebPresence.instance.iosBannerDismissed);
    } catch (_) {
      if (mounted) {
        setState(() => _instalarFechado = WebPresence.instance.iosBannerDismissed);
      }
    }
  }

  Future<void> _fecharInstalar() async {
    setState(() => _instalarFechado = true);
    WebPresence.instance.hideNativeIosBanner(remember: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kInstalarFechado, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final wp = WebPresence.instance;
    if (!wp.isWeb) return const SizedBox.shrink();

    final ios = wp.isIosBrowser;
    final android = wp.isAndroidBrowser;
    final instalada = wp.isStandalone;
    final temFirebase = wp.firebaseConfig != null;
    final permissao = wp.notificationPermission;
    final notifAtivas = permissao == 'granted';

    final cards = <Widget>[];

    // 1. Aviso fixo do iPhone no navegador.
    if (ios) {
      cards.add(_Card(
        cor: const Color(0xFFFFF7ED),
        borda: const Color(0xFFFED7AA),
        child: Row(
          children: [
            const Icon(Icons.phone_iphone, color: Color(0xFFC2410C)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Para receberes pedidos sempre, mantém o ecrã ligado e a Bora aberta.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.brown.shade900,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    // 2. Instalar no ecrã principal (iPhone e Android, só quando não instalada).
    if ((ios || android) && !instalada && !_instalarFechado) {
      cards.add(_Card(
        cor: Colors.white,
        borda: const Color(0xFFE5E7EB),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_to_home_screen, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Instala a Bora no ecrã principal',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  visualDensity: VisualDensity.compact,
                  onPressed: _fecharInstalar,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              ios
                  ? 'Abre como app, fica no ecrã inicial e é a única forma de '
                      'receberes notificações no iPhone (iOS 16.4 ou mais).'
                  : 'Abre como app e fica no ecrã inicial, com notificações.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            if (ios) const _PassosIphone() else const _PassosAndroid(),
          ],
        ),
      ));
    }

    // 3. Ativar notificações.
    if (temFirebase && !notifAtivas && permissao != 'denied') {
      final bloqueadoNoIphone = ios && !instalada;
      cards.add(_Card(
        cor: Colors.white,
        borda: const Color(0xFFE5E7EB),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                bloqueadoNoIphone
                    ? 'No iPhone as notificações só funcionam com a Bora no ecrã principal.'
                    : 'Ativa as notificações para saberes dos pedidos mesmo com a página em segundo plano.',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (bloqueadoNoIphone || _aAtivar)
                  ? null
                  : () async {
                      setState(() => _aAtivar = true);
                      try {
                        await widget.onAtivarNotificacoes();
                      } finally {
                        if (mounted) setState(() => _aAtivar = false);
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(_aAtivar ? 'A ativar…' : 'Ativar notificações',
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ));
    } else if (permissao == 'denied' && temFirebase) {
      cards.add(_Card(
        cor: const Color(0xFFFEF2F2),
        borda: const Color(0xFFFECACA),
        child: Row(
          children: [
            const Icon(Icons.notifications_off_outlined, color: Color(0xFFB91C1C)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'As notificações estão bloqueadas neste navegador. Permite-as nas definições do site para saberes dos pedidos.',
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade900),
              ),
            ),
          ],
        ),
      ));
    }

    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in cards) ...[c, const SizedBox(height: 8)],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.cor, required this.borda});
  final Widget child;
  final Color cor;
  final Color borda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borda),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

/// "Imagem" dos passos do Safari desenhada em widgets: o botão Partilhar
/// (quadrado com seta) e a opção "Adicionar ao ecrã principal" (quadrado com +).
class _PassosIphone extends StatelessWidget {
  const _PassosIphone();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Passo(
          numero: '1',
          icone: CupertinoIcons.share,
          texto: 'Toca em Partilhar\n(em baixo, no Safari)',
        ),
        SizedBox(width: 8),
        _Passo(
          numero: '2',
          icone: CupertinoIcons.plus_app,
          texto: 'Escolhe "Adicionar ao\necrã principal"',
        ),
        SizedBox(width: 8),
        _Passo(
          numero: '3',
          icone: Icons.check_circle_outline,
          texto: 'Abre a Bora pelo\nícone novo',
        ),
      ],
    );
  }
}

class _PassosAndroid extends StatelessWidget {
  const _PassosAndroid();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Passo(
          numero: '1',
          icone: Icons.more_vert,
          texto: 'Toca no menu ⋮\n(em cima, no Chrome)',
        ),
        SizedBox(width: 8),
        _Passo(
          numero: '2',
          icone: Icons.add_to_home_screen,
          texto: '"Adicionar ao ecrã\nprincipal" / "Instalar"',
        ),
        SizedBox(width: 8),
        _Passo(
          numero: '3',
          icone: Icons.check_circle_outline,
          texto: 'Abre a Bora pelo\nícone novo',
        ),
      ],
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({required this.numero, required this.icone, required this.texto});
  final String numero;
  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Stack(
              children: [
                Center(child: Icon(icone, color: AppColors.primary, size: 24)),
                Positioned(
                  left: 2,
                  top: 2,
                  child: CircleAvatar(
                    radius: 7,
                    backgroundColor: AppColors.primary,
                    child: Text(numero,
                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.2),
          ),
        ],
      ),
    );
  }
}
