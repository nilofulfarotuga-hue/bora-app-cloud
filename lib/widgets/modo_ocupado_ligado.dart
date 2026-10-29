import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../services/interruptores_app.dart';

/// Entrega ao [builder] se o MODO OCUPADO do parceiro está ligado no painel admin
/// (`platform_settings.partner_busy_mode_enabled`, C6 · 29/10/2026).
///
/// Começa em `false` e só passa a `true` se o servidor o disser, por isso com o
/// interruptor desligado (o estado de fábrica) — ou sem rede — o ecrã desenha
/// exatamente o que desenhava antes. A leitura vem da cache de 2 minutos do
/// [InterruptoresApp] (a mesma ida ao servidor dos outros interruptores).
class ModoOcupadoLigado extends StatefulWidget {
  const ModoOcupadoLigado({super.key, required this.builder});

  final Widget Function(BuildContext context, bool ligado) builder;

  @override
  State<ModoOcupadoLigado> createState() => _ModoOcupadoLigadoState();
}

class _ModoOcupadoLigadoState extends State<ModoOcupadoLigado> {
  bool _ligado = false;

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance
        .ligado(InterruptoresApp.modoOcupadoParceiro)
        .then((v) {
      if (mounted && v != _ligado) setState(() => _ligado = v);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ligado);
}

/// O aviso que o cliente vê quando a loja está em modo ocupado.
class AvisoTempoMaior extends StatelessWidget {
  const AvisoTempoMaior({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('aviso_tempo_maior'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.hourglass_top, size: 16, color: Colors.amber.shade900),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Tempo maior do que o normal: a loja está com muitos pedidos.'.tr,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade900,
            ),
          ),
        ),
      ],
    );
  }
}
