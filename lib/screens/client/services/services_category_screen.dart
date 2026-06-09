import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/service_provider_model.dart';
import '../../../stores/services_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'provider_detail_screen.dart';

/// Vertical Serviços — lista de barbearias (prestadores aprovados + online).
/// Cards com foto/nome/rating/morada → ProviderDetailScreen.
class ServicesCategoryScreen extends StatefulWidget {
  const ServicesCategoryScreen({super.key});

  @override
  State<ServicesCategoryScreen> createState() => _ServicesCategoryScreenState();
}

class _ServicesCategoryScreenState extends State<ServicesCategoryScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('[SERVICOS] initState mount (build 271)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ServicesStore>().fetchProviders();
    });
  }

  Future<void> _refresh() => context.read<ServicesStore>().fetchProviders();

  void _openProvider(ServiceProviderModel p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProviderDetailScreen(provider: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Serviços'),
      body: SafeArea(
        child: Consumer<ServicesStore>(
          builder: (context, store, _) {
            debugPrint('[SERVICOS] build providers=${store.providers.length} '
                'loading=${store.loadingProviders} err=${store.providersError}');
            if (store.loadingProviders && store.providers.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (store.providersError != null && store.providers.isEmpty) {
              return _ErrorState(message: store.providersError!, onRetry: _refresh);
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: store.providers.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxxl),
                      itemCount: store.providers.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Spacing.md),
                      itemBuilder: (_, i) => _ProviderCard(
                        provider: store.providers[i],
                        onTap: () => _openProvider(store.providers[i]),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _emptyState() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.content_cut, size: 56, color: AppColors.textSubtle),
                  SizedBox(height: Spacing.lg),
                  Text(
                    'Ainda não há serviços disponíveis\nVolta em breve!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.onTap});

  final ServiceProviderModel provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photo = provider.photoUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: (photo != null && photo.isNotEmpty)
                  ? Image.network(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _PhotoFallback(),
                      loadingBuilder: (_, child, prog) =>
                          prog == null ? child : const _PhotoFallback(),
                    )
                  : const _PhotoFallback(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      provider.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (provider.ratingsCount > 0) ...[
                      const SizedBox(height: Spacing.xs),
                      _RatingRow(
                        avg: provider.avgRating,
                        count: provider.ratingsCount,
                      ),
                    ],
                    if (provider.address != null &&
                        provider.address!.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xs),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 14, color: AppColors.textSubtle),
                          const SizedBox(width: Spacing.xs),
                          Expanded(
                            child: Text(
                              provider.address!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: Spacing.sm),
              child: Icon(Icons.chevron_right, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.avg, required this.count});
  final double avg;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 16, color: AppColors.warning),
        const SizedBox(width: Spacing.xxs),
        Text(
          avg.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Text(
          '($count)',
          style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
        ),
      ],
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.content_cut, color: AppColors.primary, size: 28),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: Spacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.lg),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
