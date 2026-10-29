import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/restaurant_model.dart';
import '../services/definicoes_publicas.dart';

/// Quais filtros rápidos o admin deixou ligados (`platform_settings.
/// discovery_filters`, ecrã "Filtros de Descoberta" do painel). 29/10/2026:
/// "Aberto agora" já existia na configuração; "Ir buscar" e "Entrega grátis"
/// entraram agora, desligados por defeito.
class ConfigFiltrosLojas {
  const ConfigFiltrosLojas({
    this.abertoAgora = false,
    this.irBuscar = false,
    this.entregaGratis = false,
  });

  final bool abertoAgora;
  final bool irBuscar;
  final bool entregaGratis;

  bool get algumLigado => abertoAgora || irBuscar || entregaGratis;

  static const ConfigFiltrosLojas desligada = ConfigFiltrosLojas();

  factory ConfigFiltrosLojas.fromJson(Object? bruto) {
    if (bruto is! Map) return desligada;
    bool b(String k) => bruto[k] == true;
    return ConfigFiltrosLojas(
      abertoAgora: b('open_now_enabled'),
      irBuscar: b('takeaway_enabled'),
      entregaGratis: b('free_delivery_enabled'),
    );
  }

  /// Lê a configuração do servidor. Nunca lança: sem leitura, nenhum filtro.
  static Future<ConfigFiltrosLojas> carregar() async {
    try {
      final m = await lerDefinicoesPublicas(const ['discovery_filters']);
      return ConfigFiltrosLojas.fromJson(m['discovery_filters']);
    } catch (e) {
      debugPrint('[ConfigFiltrosLojas] $e');
      return desligada;
    }
  }
}

/// Os chips que a pessoa tem ativos neste momento.
class FiltrosAtivos {
  const FiltrosAtivos({
    this.abertoAgora = false,
    this.irBuscar = false,
    this.entregaGratis = false,
  });

  final bool abertoAgora;
  final bool irBuscar;
  final bool entregaGratis;

  bool get algum => abertoAgora || irBuscar || entregaGratis;

  FiltrosAtivos copyWith({bool? abertoAgora, bool? irBuscar, bool? entregaGratis}) =>
      FiltrosAtivos(
        abertoAgora: abertoAgora ?? this.abertoAgora,
        irBuscar: irBuscar ?? this.irBuscar,
        entregaGratis: entregaGratis ?? this.entregaGratis,
      );
}

/// Ids das lojas com entrega grátis configurada
/// (`restaurants.free_delivery_min_cents` preenchido). Uma só leitura por
/// sessão do ecrã; sem leitura devolve vazio (o filtro fica sem resultados em
/// vez de mentir).
Future<Set<String>> carregarLojasComEntregaGratis() async {
  try {
    final linhas = await Supabase.instance.client
        .from('restaurants')
        .select('id')
        .not('free_delivery_min_cents', 'is', null);
    return {for (final l in (linhas as List)) (l as Map)['id'].toString()};
  } catch (e) {
    debugPrint('[FiltrosLojas] entrega grátis: $e');
    return <String>{};
  }
}

/// Aplica os chips. Só olha para os filtros que o admin deixou ligados: um
/// chip ativo cujo interruptor foi desligado entretanto não filtra nada.
List<RestaurantModel> aplicarFiltrosRapidos(
  List<RestaurantModel> lojas, {
  required FiltrosAtivos ativos,
  required ConfigFiltrosLojas config,
  Set<String> comEntregaGratis = const <String>{},
  DateTime? agora,
}) {
  final aberto = ativos.abertoAgora && config.abertoAgora;
  final buscar = ativos.irBuscar && config.irBuscar;
  final gratis = ativos.entregaGratis && config.entregaGratis;
  if (!aberto && !buscar && !gratis) return lojas;
  return lojas.where((l) {
    if (aberto && !l.isOpenNow(agora)) return false;
    if (buscar && !l.takeawayEnabled) return false;
    if (gratis && !comEntregaGratis.contains(l.id)) return false;
    return true;
  }).toList();
}

/// A fila de chips por baixo da pesquisa. Verde #16A34A quando ativo, contorno
/// cinzento quando não; nunca laranja. Cada chip tem pelo menos 44 px de altura.
class FiltrosRapidosLojas extends StatelessWidget {
  const FiltrosRapidosLojas({
    super.key,
    required this.config,
    required this.ativos,
    required this.onChanged,
  });

  final ConfigFiltrosLojas config;
  final FiltrosAtivos ativos;
  final ValueChanged<FiltrosAtivos> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!config.algumLigado) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView(
        key: const Key('filtros_rapidos_lojas'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg, vertical: Spacing.xs),
        children: [
          if (config.abertoAgora)
            _Chip(
              chave: const Key('filtro_aberto_agora'),
              texto: 'Aberto agora'.tr,
              ativo: ativos.abertoAgora,
              onTap: () =>
                  onChanged(ativos.copyWith(abertoAgora: !ativos.abertoAgora)),
            ),
          if (config.irBuscar)
            _Chip(
              chave: const Key('filtro_ir_buscar'),
              texto: 'Ir buscar'.tr,
              ativo: ativos.irBuscar,
              onTap: () => onChanged(ativos.copyWith(irBuscar: !ativos.irBuscar)),
            ),
          if (config.entregaGratis)
            _Chip(
              chave: const Key('filtro_entrega_gratis'),
              texto: 'Entrega grátis'.tr,
              ativo: ativos.entregaGratis,
              onTap: () => onChanged(
                  ativos.copyWith(entregaGratis: !ativos.entregaGratis)),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.chave,
    required this.texto,
    required this.ativo,
    required this.onTap,
  });

  final Key chave;
  final String texto;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: Semantics(
        button: true,
        selected: ativo,
        label: texto,
        child: InkWell(
          key: chave,
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: ativo ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: ativo ? AppColors.primary : AppColors.divider),
            ),
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ativo ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
