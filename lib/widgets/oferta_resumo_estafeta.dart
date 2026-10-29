import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../services/interruptores_app.dart';
import '../utils/favor_passos.dart';

/// Quantas paragens tem a oferta: recolha + entrega numa entrega normal; num
/// favor, os passos da rota (casa da cliente, local do favor, entrega).
int paragensDaOferta(OrderModel o) {
  if (o.serviceType == OrderServiceType.errand) {
    final n = FavorRota.de(o)?.passos.length ?? 0;
    if (n > 0) return n;
  }
  return 2;
}

/// "1 paragem" / "3 paragens".
String textoParagens(int n) => n == 1 ? '1 paragem' : '$n paragens';

/// Quilómetros da oferta: estafeta→loja + loja→cliente quando as duas pernas
/// se sabem; senão a distância do pedido; `null` quando nada se sabe.
double? kmTotalDaOferta(OrderModel o, LatLng? estafeta) {
  const d = Distance(roundResult: false);
  final recolha = o.pickupLocation;
  final entrega = o.destination;
  if (recolha != null && entrega != null) {
    final entre = d.as(LengthUnit.Kilometer, recolha, entrega);
    final ate = estafeta == null
        ? 0.0
        : d.as(LengthUnit.Kilometer, estafeta, recolha);
    return ate + entre;
  }
  return o.distanceKm > 0 ? o.distanceKm : null;
}

String _eur(double v) => '€${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// O que o estafeta lê ANTES de aceitar: quanto ganha, quantos quilómetros faz
/// e quantas paragens tem (adendo 4 · item 3, 29/10/2026). Só leitura: os
/// números vêm do pedido (o ganho é o que o servidor já gravou).
///
/// [ganho] `null` = o servidor ainda não disse (pedido adicional): mostra
/// "Ganho a confirmar" em vez de inventar um número.
///
/// Interruptor `feature_oferta_ganho_visivel` no painel admin.
class OfertaResumoEstafeta extends StatefulWidget {
  const OfertaResumoEstafeta({
    super.key,
    required this.order,
    required this.ganho,
    this.driverLocation,
  });

  final OrderModel order;
  final double? ganho;
  final LatLng? driverLocation;

  @override
  State<OfertaResumoEstafeta> createState() => _OfertaResumoEstafetaState();
}

class _OfertaResumoEstafetaState extends State<OfertaResumoEstafeta> {
  bool _ligado = true;

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance
        .ligado(InterruptoresApp.ofertaGanhoVisivel)
        .then((v) {
      if (mounted && v != _ligado) setState(() => _ligado = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    final km = kmTotalDaOferta(widget.order, widget.driverLocation);
    final paragens = paragensDaOferta(widget.order);
    final ganho = widget.ganho;
    return Container(
      key: const Key('oferta_resumo_estafeta'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          _Dado(
            chave: const Key('oferta_ganho'),
            icone: Icons.payments_outlined,
            texto: ganho != null
                ? 'Ganhas ${_eur(ganho)}'
                : 'Ganho a confirmar',
            forte: true,
          ),
          if (km != null)
            _Dado(
              chave: const Key('oferta_km'),
              icone: Icons.route_outlined,
              texto:
                  '${km.toStringAsFixed(1).replaceAll('.', ',')} km no total',
            ),
          _Dado(
            chave: const Key('oferta_paragens'),
            icone: Icons.pin_drop_outlined,
            texto: textoParagens(paragens),
          ),
        ],
      ),
    );
  }
}

class _Dado extends StatelessWidget {
  const _Dado({
    required this.chave,
    required this.icone,
    required this.texto,
    this.forte = false,
  });

  final Key chave;
  final IconData icone;
  final String texto;
  final bool forte;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: chave,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          texto,
          style: TextStyle(
            fontSize: 16,
            fontWeight: forte ? FontWeight.w800 : FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
