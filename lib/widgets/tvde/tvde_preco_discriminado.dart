import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Preço discriminado ANTES de pedir — Lei 45/2018, art. 15.º (versão da
/// Lei 59/2026).
///
/// Recebe o mapa devolvido por `tvde_fare_breakdown` e mostra, colapsado por
/// defeito ("Ver como é calculado"): tarifa base, km extra × preço/km, preço
/// por tempo (0 €), tarifa dinâmica (nenhuma), taxa de intermediação em % e em
/// €, IVA (só quando o servidor o discrimina), total e a nota. É só
/// informação: não calcula preço nenhum — os valores vêm todos do servidor.
class TvdePrecoDiscriminado extends StatefulWidget {
  const TvdePrecoDiscriminado({
    super.key,
    required this.dados,
    this.inicialmenteAberto = false,
  });

  final Map<String, dynamic> dados;

  /// Para testes e ecrãs onde o detalhe deve nascer aberto.
  final bool inicialmenteAberto;

  @override
  State<TvdePrecoDiscriminado> createState() => _TvdePrecoDiscriminadoState();
}

String _eur(num? cents) => '€${((cents ?? 0) / 100).toStringAsFixed(2)}';

/// 10 → "10", 12.5 → "12.5".
String _pct(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _TvdePrecoDiscriminadoState extends State<TvdePrecoDiscriminado> {
  late bool _aberto = widget.inicialmenteAberto;

  @override
  Widget build(BuildContext context) {
    final d = widget.dados;
    final combinada = d['tarifa_combinada'] == true;
    final base = d['tarifa_base_cents'] as num?;
    final kmIncl = d['km_incluidos'] as num?;
    final kmExtra = (d['km_extra'] as num?) ?? 0;
    final precoKm = (d['preco_km_extra_cents'] as num?) ?? 0;
    final precoMin = (d['preco_por_minuto_cents'] as num?) ?? 0;
    final fator = (d['fator_dinamico'] as num?) ?? 1;
    final interm = d['intermediacao_cents'] as num?;
    final intermPct = d['intermediacao_pct'] as num?;
    final ivaPct = d['iva_pct'] as num?;
    final ivaCents = d['iva_cents'] as num?;
    final total = d['total_cents'] as num?;
    final nota = d['nota'] as String?;

    return Container(
      key: const Key('tvde_preco_discriminado'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('tvde_preco_discriminado_abrir'),
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () => setState(() => _aberto = !_aberto),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.calculate_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: Spacing.sm),
                  const Expanded(
                    child: Text('Ver como é calculado',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  Icon(_aberto ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSubtle),
                ],
              ),
            ),
          ),
          if (_aberto)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, 0, Spacing.md, Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (combinada)
                    _Linha(
                      key: const Key('tvde_preco_combinado'),
                      rotulo: 'Preço combinado para ti',
                      valor: _eur(total),
                    )
                  else ...[
                    _Linha(
                      key: const Key('tvde_preco_base'),
                      rotulo: kmIncl != null
                          ? 'Tarifa base (até ${_pct(kmIncl)} km)'
                          : 'Tarifa base',
                      valor: _eur(base),
                    ),
                    _Linha(
                      key: const Key('tvde_preco_km_extra'),
                      rotulo:
                          'Km extra: ${_pct(kmExtra)} × ${_eur(precoKm)}/km',
                      valor: _eur(kmExtra * precoKm),
                    ),
                  ],
                  _Linha(
                    key: const Key('tvde_preco_tempo'),
                    rotulo: 'Preço por tempo',
                    detalhe: precoMin == 0
                        ? 'o preço não depende do tempo'
                        : '${_eur(precoMin)}/min',
                    valor: _eur(0),
                  ),
                  _Linha(
                    key: const Key('tvde_preco_dinamica'),
                    rotulo: 'Tarifa dinâmica',
                    valor: fator == 1 ? 'sem tarifa dinâmica' : '× $fator',
                  ),
                  if (interm != null)
                    _Linha(
                      key: const Key('tvde_preco_intermediacao'),
                      rotulo: intermPct != null
                          ? 'Taxa de intermediação (${_pct(intermPct)} %)'
                          : 'Taxa de intermediação',
                      detalhe: 'incluída no total',
                      valor: _eur(interm),
                    ),
                  if (ivaPct != null)
                    _Linha(
                      key: const Key('tvde_preco_iva'),
                      rotulo: 'IVA incluído (${_pct(ivaPct)} %)',
                      valor: _eur(ivaCents),
                    ),
                  const Divider(height: Spacing.lg),
                  _Linha(
                    key: const Key('tvde_preco_total'),
                    rotulo: 'Total estimado',
                    valor: _eur(total),
                    forte: true,
                  ),
                  if (nota != null && nota.isNotEmpty) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(nota,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSubtle)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    super.key,
    required this.rotulo,
    required this.valor,
    this.detalhe,
    this.forte = false,
  });

  final String rotulo;
  final String valor;
  final String? detalhe;
  final bool forte;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: forte ? 15 : 13,
      fontWeight: forte ? FontWeight.w800 : FontWeight.w500,
      color: AppColors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: estilo),
                if (detalhe != null)
                  Text(detalhe!,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSubtle)),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(valor, style: estilo),
        ],
      ),
    );
  }
}
