import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/provider_service_model.dart';
import '../../../models/service_provider_model.dart';
import '../../../stores/services_store.dart';
import '../../../widgets/bora/bora_accent_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'booking_flow_screen.dart';

/// Vertical Serviços — detalhe de uma barbearia.
/// Hero, nome, rating, descrição, morada, lista de serviços (preço+duração),
/// CTA "Marcar" → fluxo de marcação.
class ProviderDetailScreen extends StatefulWidget {
  const ProviderDetailScreen({super.key, required this.provider});

  final ServiceProviderModel provider;

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  late Future<List<ProviderServiceModel>> _servicesFuture;

  @override
  void initState() {
    super.initState();
    _servicesFuture =
        context.read<ServicesStore>().fetchServices(widget.provider.id);
  }

  void _startBooking({ProviderServiceModel? preselected}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(
          provider: widget.provider,
          preselectedService: preselected,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: p.name),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Spacing.xxxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero(p),
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (p.ratingsCount > 0) ...[
                            const SizedBox(height: Spacing.sm),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 18, color: AppColors.warning),
                                const SizedBox(width: Spacing.xxs),
                                Text(
                                  '${p.avgRating.toStringAsFixed(1)} · ${p.ratingsCount} avaliações',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (p.address != null && p.address!.isNotEmpty) ...[
                            const SizedBox(height: Spacing.sm),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 16, color: AppColors.textSubtle),
                                const SizedBox(width: Spacing.xs),
                                Expanded(
                                  child: Text(
                                    p.address!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (p.description != null &&
                              p.description!.isNotEmpty) ...[
                            const SizedBox(height: Spacing.lg),
                            Text(
                              p.description!,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: Spacing.xl),
                          const Text(
                            'Serviços',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          _servicesList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // CTA laranja único do ecrã (regra 1 laranja/ecrã).
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
              child: BoraAccentButton(
                label: 'Marcar',
                icon: Icons.event_available,
                onPressed: () => _startBooking(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(ServiceProviderModel p) {
    final url = (p.heroImageUrl != null && p.heroImageUrl!.isNotEmpty)
        ? p.heroImageUrl!
        : (p.photoUrl ?? '');
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _heroFallback(),
              loadingBuilder: (_, child, prog) =>
                  prog == null ? child : _heroFallback(),
            )
          : _heroFallback(),
    );
  }

  Widget _heroFallback() => Container(
        decoration: const BoxDecoration(gradient: AppColors.tileReserveTable),
        alignment: Alignment.center,
        child: const Icon(Icons.content_cut, color: Colors.white, size: 48),
      );

  Widget _servicesList() {
    return FutureBuilder<List<ProviderServiceModel>>(
      future: _servicesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text(
            snap.error.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: AppColors.error),
          );
        }
        final services = snap.data ?? const [];
        if (services.isEmpty) {
          return const Text(
            'Este prestador ainda não tem serviços.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return Column(
          children: [
            for (final s in services) ...[
              _ServiceTile(service: s, onTap: () => _startBooking(preselected: s)),
              if (s != services.last) const SizedBox(height: Spacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap});

  final ProviderServiceModel service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (service.description != null &&
                      service.description!.isNotEmpty) ...[
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      service.description!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: Spacing.xs),
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          size: 14, color: AppColors.textSubtle),
                      const SizedBox(width: Spacing.xxs),
                      Text(
                        service.durationLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSubtle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            Text(
              service.priceLabel,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
