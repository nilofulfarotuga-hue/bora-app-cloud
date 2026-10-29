import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_spacing.dart';


import '../../l10n/tr.dart';
import '../../stores/cart_store.dart';
import 'loja_fechada.dart';
/// Widgets partilhados do estado "Em breve" (`coming_soon`).
///
/// A loja/parceiro continua visível, clicável e navegável — só não aceita
/// pedidos nem marcações. O bloqueio a sério vive no servidor
/// (`STORE_COMING_SOON`); isto é a camada de UI do cliente (PT-PT).
///
/// Laranja da marca `#F97316` fixo aqui de propósito: é um selo de estado,
/// não muda com o tema.
const Color kComingSoonOrange = Color(0xFFF97316);

/// Mensagem única usada em todos os bloqueios do cliente.
///
/// Getter (e não `const`) para passar pelo `.tr` (29/10/2026): em inglês
/// aparecia em português. O texto PT é o mesmo de sempre.
String get kComingSoonBlockedMessage =>
    'Esta loja ainda não está a aceitar pedidos.'.tr;

/// A mesma recusa, mas para quem tenta RESERVAR MESA (29/10/2026): ninguém
/// "faz um pedido" numa reserva, por isso o aviso diz reservas.
String get kComingSoonReservationBlockedMessage =>
    'Esta loja ainda não está a aceitar reservas.'.tr;

/// Selo compacto "Em breve" para o canto de um card de loja/parceiro.
class ComingSoonChip extends StatelessWidget {
  const ComingSoonChip({super.key, this.dense = false});

  /// Versão ainda mais pequena, para cards com pouco espaço.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: kComingSoonOrange,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Text(
        'Em breve'.tr,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Banner fixo no topo da ficha da loja/parceiro, por baixo do cabeçalho.
class ComingSoonBanner extends StatelessWidget {
  const ComingSoonBanner({super.key, required this.text});

  /// Texto de `coming_soon_text` (o chamador já aplica o fallback
  /// `comingSoonLabel`).
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      color: kComingSoonOrange,
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: Colors.white),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mostra a mensagem única de bloqueio "Em breve".
///
/// [reserva]: `true` quando o cliente tentava reservar mesa — o aviso diz
/// "reservas" em vez de "pedidos". As entregas e compras não passam nada.
void showComingSoonBlockedSnackBar(BuildContext context,
    {bool reserva = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(reserva
            ? kComingSoonReservationBlockedMessage
            : kComingSoonBlockedMessage),
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Selo compacto "Fechada" para o canto de um card de loja.
///
/// Diferente do "Em breve" de propósito: a loja já trabalha connosco, só está
/// fora de horário. Vermelho discreto, não o laranja da marca.
class LojaFechadaChip extends StatelessWidget {
  const LojaFechadaChip({super.key, required this.texto, this.dense = false});

  /// Vem de `RestaurantModel.statusLabel()` — ex.: "Fechada, abre às 10h00".
  final String texto;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: const Color(0xFFDC2626).withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFB91C1C),
          height: 1.2,
        ),
      ),
    );
  }
}

/// Mensagem única de bloqueio por loja fechada.
///
/// Diz a hora a que abre e (26/10, item 4) oferece "Ver lojas abertas
/// parecidas" — da mesma secção, abertas agora. NÃO promete agendamento nem
/// "avisar quando abrir": isso ainda não existe.
///
/// [lojaId]: a loja que o cliente está a VER (26/10, adendo A3). Sem ele usa-se
/// a do carrinho — que no "Pedir de novo" ainda é a loja anterior.
void showLojaFechadaSnackBar(BuildContext context, String aviso, {String? lojaId}) {
  if (lojaId == null) {
    try {
      lojaId = context.read<CartStore>().vendorRestaurantId;
    } catch (_) {
      lojaId = null; // fora da árvore do Provider (testes): só o aviso
    }
  }
  final id = lojaId;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(aviso),
        duration: const Duration(seconds: 6),
        action: id == null
            ? null
            : SnackBarAction(
                label: 'Ver lojas abertas parecidas'.tr,
                onPressed: () {
                  if (context.mounted) mostrarLojasAbertasParecidas(context, id);
                },
              ),
      ),
    );
}
