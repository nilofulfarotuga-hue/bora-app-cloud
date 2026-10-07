// lib/widgets/web_push_card.dart
//
// [Web 07/10/2026] Cartão "Ativar notificações" do CLIENTE e do PARCEIRO no
// navegador. Até aqui só o estafeta registava token FCM na web
// (`DriverWebCards` → `DriverStore.registarPushAposToque`); o cliente nunca
// sabia que o pedido ia a caminho com a Bora fechada e o parceiro só via os
// pedidos novos com o painel à frente.
//
// O navegador só concede a permissão a partir de um gesto — por isso é um
// botão, nunca no arranque. No toque: `FirebaseMessaging.requestPermission()`
// → `PushTokenService.registerForRole(role)` → RPC `register_push_token`, que
// escreve no MESMO sítio do estafeta para o seu papel: `client_push_tokens`
// (cliente) e `partner_push_tokens` (parceiro), `platform='web'`. É daí que as
// Edge `notify-client` e `notify-partner` lêem os destinos. A notificação em
// segundo plano nasce no `web/firebase-messaging-sw.js`, que abre o destino
// pelo tipo do aviso.
//
// Só existe na web (fora dela devolve nada); desaparece quando a permissão
// está dada; "Agora não" esconde-o até à próxima abertura da página.
// PT-PT com `.tr` (o cliente tem alternador PT/EN).
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../services/push_token_service.dart';
import '../services/web_presence.dart';

class WebPushCard extends StatefulWidget {
  const WebPushCard({
    super.key,
    required this.role,
    this.ativar,
    this.permissaoInicial,
    this.forcarVisivel = false,
  });

  /// 'client' ou 'partner'.
  final String role;

  /// O que o botão faz; devolve a permissão resultante
  /// ('granted' | 'denied' | 'default'). Por omissão pede ao navegador e
  /// regista o token. Os testes injectam.
  final Future<String?> Function()? ativar;

  /// Permissão inicial; por omissão lê-se do navegador. Os testes injectam.
  final String? permissaoInicial;

  /// Testes: desenha mesmo fora da web.
  final bool forcarVisivel;

  /// Papéis que este cartão serve. O estafeta tem o seu (`DriverWebCards`).
  static const Set<String> papeis = {'client', 'partner'};

  static const String textoBotao = 'Ativar notificações';

  /// "Agora não" vale até à próxima abertura da página (por papel).
  static final Set<String> _dispensados = <String>{};

  @visibleForTesting
  static void limparDispensas() => _dispensados.clear();

  @override
  State<WebPushCard> createState() => _WebPushCardState();
}

class _WebPushCardState extends State<WebPushCard> {
  String? _permissao;
  bool _aAtivar = false;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    _permissao = widget.permissaoInicial ??
        (kIsWeb ? WebPresence.instance.notificationPermission : null);
  }

  bool get _visivel {
    if (!WebPushCard.papeis.contains(widget.role)) return false;
    if (WebPushCard._dispensados.contains(widget.role)) return false;
    if (_permissao == 'granted') return false;
    if (widget.forcarVisivel) return true;
    if (!kIsWeb) return false;
    // Sem config Firebase na web não há token possível — não se promete nada.
    return WebPresence.instance.firebaseConfig != null;
  }

  /// Pede a permissão a partir do toque e regista o token no papel certo.
  Future<String?> _ativarPorOmissao() async {
    try {
      final s = await FirebaseMessaging.instance.requestPermission();
      if (s.authorizationStatus == AuthorizationStatus.denied) return 'denied';
    } catch (e) {
      debugPrint('[WebPushCard] requestPermission: $e');
    }
    await PushTokenService.registerForRole(widget.role);
    return WebPresence.instance.notificationPermission;
  }

  Future<void> _ativar() async {
    if (_aAtivar) return;
    setState(() {
      _aAtivar = true;
      _falhou = false;
    });
    String? nova;
    try {
      nova = await (widget.ativar ?? _ativarPorOmissao)()
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('[WebPushCard] ativar: $e');
    }
    if (!mounted) return;
    setState(() {
      _aAtivar = false;
      _permissao = nova ?? _permissao;
      _falhou = _permissao != 'granted';
    });
  }

  void _dispensar() {
    WebPushCard._dispensados.add(widget.role);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_visivel) return const SizedBox.shrink();

    final cliente = widget.role == 'client';
    final bloqueado = _permissao == 'denied';
    final wp = WebPresence.instance;
    final iphoneSemInstalar = kIsWeb && wp.isIosBrowser && !wp.isStandalone;

    final titulo = cliente
        ? 'Recebe avisos do teu pedido'.tr
        : 'Recebe os pedidos novos'.tr;
    final texto = cliente
        ? 'Ativa as notificações para saberes quando o pedido está a caminho, mesmo com a Bora fechada.'
            .tr
        : 'Ativa as notificações para o navegador avisar quando entra um pedido, mesmo com o painel fechado.'
            .tr;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: Key('web_push_card_${widget.role}'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bloqueado ? const Color(0xFFFEF2F2) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: bloqueado ? const Color(0xFFFECACA) : const Color(0xFFE5E7EB),
          ),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  bloqueado
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  color: bloqueado ? const Color(0xFFB91C1C) : AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                IconButton(
                  key: const Key('web_push_card_agora_nao'),
                  tooltip: 'Agora não'.tr,
                  visualDensity: VisualDensity.compact,
                  onPressed: _dispensar,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (bloqueado)
              Text(
                'As notificações estão bloqueadas neste navegador. Ativa-as nas definições do site e volta a abrir a Bora.'
                    .tr,
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade900),
              )
            else ...[
              Text(texto,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSubtle)),
              if (iphoneSemInstalar) ...[
                const SizedBox(height: 4),
                Text(
                  'No iPhone só funciona com a Bora instalada no ecrã principal.'
                      .tr,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSubtle),
                ),
              ],
              if (_falhou) ...[
                const SizedBox(height: 4),
                Text(
                  'Não ficou ativo. Tenta de novo ou verifica as permissões do navegador.'
                      .tr,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: Key('btn_web_push_${widget.role}'),
                  onPressed: _aAtivar ? null : _ativar,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  child: Text(
                    _aAtivar ? 'A ativar…'.tr : WebPushCard.textoBotao.tr,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
