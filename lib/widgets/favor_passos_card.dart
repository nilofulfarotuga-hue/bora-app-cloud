// Cartão "para onde vou" do Favor, no estafeta (08/10/2026, pedido real
// 74dd4ecc e pedido do Danilo).
//
// Em cada passo, em letra grande: o nome do sítio ("Casa da cliente —
// Cristina", "Farmácia Tavares", "Entrega à cliente — Cristina"), a morada
// completa, a distância desde o estafeta e o botão "Navegar" para ESSE passo.
// O passo atual vem do servidor (`orders.errand_passo`); ao confirmar um
// passo na folha do favor, o cartão, o mapa e o "Navegar" passam sozinhos
// para o seguinte.
//
// Farmácia: a foto da receita aparece GRANDE no passo do favor, com zoom ao
// tocar, e a frase do que mostrar ao balcão.
//
// Nunca mostra `pickupAddress` (num favor é texto herdado de outro carrinho).
// [compacto] = versão para a oferta, antes de aceitar: a rota toda, sem
// botões de ação.
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../services/navigation_service.dart';
import '../utils/favor_passos.dart';
import 'folha_favor.dart';
import 'private_bucket_image.dart';

const _corFavor = Color(0xFF14B8A6);
const _corFavorEscura = Color(0xFF0F766E);

class FavorPassosCard extends StatelessWidget {
  const FavorPassosCard({
    super.key,
    required this.order,
    this.posicaoEstafeta,
    this.compacto = false,
    this.mostrarBotaoFolha = true,
  });

  final OrderModel order;
  final LatLng? posicaoEstafeta;

  /// Versão curta para a oferta (antes de aceitar).
  final bool compacto;

  /// Mostra o botão "Tratar do favor" (abre a folha da recolha/talão/entrega).
  final bool mostrarBotaoFolha;

  @override
  Widget build(BuildContext context) {
    final rota = FavorRota.de(order);
    if (rota == null) return const SizedBox.shrink();
    return Container(
      key: const Key('favor_passos_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecalho(order: order),
          const SizedBox(height: 6),
          Text(
            rota.resumo,
            key: const Key('favor_rota_resumo'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _corFavorEscura),
          ),
          const SizedBox(height: 10),
          if (compacto)
            for (final p in rota.passos)
              _LinhaPassoCompacta(passo: p, posicao: posicaoEstafeta)
          else ...[
            _Progresso(rota: rota),
            const SizedBox(height: 12),
            _PassoAtual(
              order: order,
              rota: rota,
              posicao: posicaoEstafeta,
            ),
            if (mostrarBotaoFolha) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('btn_tratar_favor'),
                  onPressed: () => FolhaFavor.abrir(context, order),
                  icon: const Icon(Icons.task_alt),
                  label: Text(_rotuloFolha(rota)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _corFavor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _rotuloFolha(FavorRota rota) => switch (rota.atual.tipo) {
        FavorPassoTipo.casa => 'Cheguei — confirmar recolha',
        FavorPassoTipo.favor => 'Tratar do favor',
        FavorPassoTipo.entrega => 'Entrega — ver o que cobrar',
      };
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final desc = order.errandDescription?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          order.errandSpeed == 'express' ? 'FAVOR EXPRESSO' : 'FAVOR',
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: _corFavorEscura),
        ),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(desc,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }
}

/// 1 ● — 2 ○ — 3 ○ com o atual destacado.
class _Progresso extends StatelessWidget {
  const _Progresso({required this.rota});
  final FavorRota rota;

  @override
  Widget build(BuildContext context) {
    final itens = <Widget>[];
    for (var i = 0; i < rota.passos.length; i++) {
      if (i > 0) {
        itens.add(Expanded(
          child: Container(
            height: 2,
            color: i <= rota.indiceAtual ? _corFavor : AppColors.divider,
          ),
        ));
      }
      itens.add(_Bola(
        numero: rota.passos[i].numero,
        feito: i < rota.indiceAtual,
        atual: i == rota.indiceAtual,
      ));
    }
    return Row(children: itens);
  }
}

class _Bola extends StatelessWidget {
  const _Bola({required this.numero, required this.feito, required this.atual});
  final int numero;
  final bool feito;
  final bool atual;

  @override
  Widget build(BuildContext context) {
    final tam = atual ? 34.0 : 26.0;
    return Container(
      width: tam,
      height: tam,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: atual ? _corFavor : (feito ? AppColors.divider : Colors.white),
        border: Border.all(
            color: atual || feito ? _corFavor : AppColors.dividerStrong,
            width: 2),
      ),
      child: feito
          ? const Icon(Icons.check, size: 16, color: _corFavorEscura)
          : Text('$numero',
              style: TextStyle(
                  fontSize: atual ? 16 : 13,
                  fontWeight: FontWeight.w800,
                  color: atual ? Colors.white : AppColors.textSecondary)),
    );
  }
}

class _PassoAtual extends StatelessWidget {
  const _PassoAtual({
    required this.order,
    required this.rota,
    required this.posicao,
  });

  final OrderModel order;
  final FavorRota rota;
  final LatLng? posicao;

  @override
  Widget build(BuildContext context) {
    final p = rota.atual;
    final km = distanciaKm(posicao, p.coords);
    final farmacia = favorEhFarmacia(order);
    final foto = order.errandRequestPhotoUrl?.trim() ?? '';
    return Column(
      key: Key('favor_passo_atual_${p.tipo.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PASSO ${p.numero} DE ${rota.passos.length}',
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 2),
        Text(
          p.nome,
          key: const Key('favor_passo_nome'),
          style: const TextStyle(
              fontSize: 21, fontWeight: FontWeight.w800, height: 1.15),
        ),
        const SizedBox(height: 4),
        Text(
          p.morada.isEmpty ? 'Morada por confirmar — liga à cliente' : p.morada,
          key: const Key('favor_passo_morada'),
          style: const TextStyle(fontSize: 15, height: 1.3),
        ),
        if (km != null) ...[
          const SizedBox(height: 2),
          Text('A ${distanciaTexto(km)} de ti',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],

        // ── Passo 1: casa da cliente ─────────────────────────────────────
        if (p.tipo == FavorPassoTipo.casa) ...[
          const SizedBox(height: 8),
          _Linha(
            icone: Icons.info_outline,
            texto: 'Motivo: ${motivoParagemEmCasa(order.errandHomeStopReason)}',
          ),
          if ((order.errandHomeStopCashCents ?? 0) > 0)
            _Linha(
              icone: Icons.payments_outlined,
              texto:
                  'Recebe €${(order.errandHomeStopCashCents! / 100).toStringAsFixed(2)} em dinheiro da cliente',
              destaque: true,
            ),
        ],

        // ── Passo 2: tratar do favor ─────────────────────────────────────
        if (p.tipo == FavorPassoTipo.favor) ...[
          if (farmacia && foto.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: const Text(
                'Mostra esta foto na farmácia: número da receita e código de acesso e dispensa.',
                key: Key('favor_farmacia_instrucao'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            PrivateBucketImage(
              key: const Key('favor_foto_receita'),
              urlOrPath: foto,
              height: 260,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(12),
              tituloAmpliada: 'Foto da receita',
            ),
            const SizedBox(height: 4),
            const Text('Toca na foto para a ver em ecrã inteiro e ampliar.',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            const Text(
              'Alguns medicamentos controlados podem pedir o teu cartão de cidadão.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else if (farmacia) ...[
            const SizedBox(height: 8),
            const _Linha(
              icone: Icons.warning_amber_rounded,
              texto:
                  'A cliente não mandou foto da receita. Liga-lhe antes de ires à farmácia.',
              destaque: true,
            ),
          ] else if (foto.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Foto da cliente (o que comprar) — toca para ampliar',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            PrivateBucketImage(
              urlOrPath: foto,
              height: 170,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(12),
              tituloAmpliada: 'Foto do pedido',
            ),
          ],
        ],

        // ── Passo 3: entrega ─────────────────────────────────────────────
        if (p.tipo == FavorPassoTipo.entrega)
          Builder(builder: (_) {
            final conta = contaDaEntregaFavor(order);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: conta == null
                  ? const _Linha(
                      icone: Icons.check_circle_outline,
                      texto: 'Já pago na app — não cobres nada.',
                    )
                  : _Linha(
                      icone: conta.devolver
                          ? Icons.currency_exchange
                          : Icons.payments_outlined,
                      texto:
                          '${conta.rotulo}: €${conta.valor.toStringAsFixed(2)}',
                      destaque: true,
                    ),
            );
          }),

        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('btn_navegar_passo'),
            onPressed: (p.coords == null && p.morada.isEmpty)
                ? null
                : () => _navegar(context, p),
            icon: const Icon(Icons.navigation_outlined),
            label: Text('Navegar — ${p.rotuloCurto}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: _corFavorEscura,
              side: const BorderSide(color: _corFavor),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _navegar(BuildContext context, FavorPasso p) {
  if (p.coords != null) {
    return NavigationService.openNavigationOptions(context, p.coords!);
  }
  return NavigationService.openNavigationToAddress(context, p.morada);
}

class _LinhaPassoCompacta extends StatelessWidget {
  const _LinhaPassoCompacta({required this.passo, required this.posicao});
  final FavorPasso passo;
  final LatLng? posicao;

  @override
  Widget build(BuildContext context) {
    final km = distanciaKm(posicao, passo.coords);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Bola(numero: passo.numero, feito: false, atual: false),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(passo.nome,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                if (passo.morada.isNotEmpty)
                  Text(passo.morada,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                if (km != null)
                  Text('A ${distanciaTexto(km)} de ti',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (passo.coords != null || passo.morada.isNotEmpty)
            IconButton(
              tooltip: 'Navegar — ${passo.rotuloCurto}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.navigation_outlined,
                  color: _corFavorEscura),
              onPressed: () => _navegar(context, passo),
            ),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.icone, required this.texto, this.destaque = false});
  final IconData icone;
  final String texto;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone,
              size: 18,
              color: destaque ? _corFavorEscura : AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: destaque ? 15 : 14,
                fontWeight: destaque ? FontWeight.w800 : FontWeight.w500,
                color: destaque ? _corFavorEscura : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
