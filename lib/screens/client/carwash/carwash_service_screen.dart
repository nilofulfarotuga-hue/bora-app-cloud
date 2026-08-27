import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/carwash_models.dart';
import '../../../stores/carwash_store.dart';
import 'carwash_request_screen.dart';
import 'carwash_tracking_screen.dart';

/// LAVAGEM AUTO — passo 1: escolher o serviço.
/// Dois cartões grandes com o preço final. Sem taxas por cima.
class CarwashServiceScreen extends StatefulWidget {
  const CarwashServiceScreen({super.key});

  @override
  State<CarwashServiceScreen> createState() => _CarwashServiceScreenState();
}

class _CarwashServiceScreenState extends State<CarwashServiceScreen> {
  Map<CarwashServiceType, CarwashQuote> _quotes = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<CarwashStore>();
    await store.refreshSettings();
    await store.loadMyBookings();
    final q = await store.quoteAll();
    if (!mounted) return;
    setState(() {
      _quotes = q;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CarwashStore>();
    final ativos = store.activeBookings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lavagem Auto'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(Spacing.lg),
                children: [
                  if (ativos.isNotEmpty) ...[
                    _AtivoCard(booking: ativos.first),
                    const SizedBox(height: Spacing.xl),
                  ],
                  const Text(
                    'Vamos buscar o carro e entregamos lavado.',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  const Text(
                    'Escolha o serviço. O preço já inclui a recolha e a entrega.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: Spacing.lg),
                  for (final t in store.availableServices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: _ServicoCard(
                        type: t,
                        quote: _quotes[t],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CarwashRequestScreen(
                              serviceType: t,
                              quote: _quotes[t],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: Spacing.lg),
                  if (store.pastBookings.isNotEmpty) ...[
                    const Text('Lavagens anteriores',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: Spacing.sm),
                    for (final b in store.pastBookings.take(5))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.local_car_wash,
                            color: AppColors.textSubtle),
                        title: Text('${b.serviceType.label} · ${b.plate}'),
                        subtitle: Text(
                          '${b.status.clientLabel} · '
                          '${b.totalEur.toStringAsFixed(2)} €',
                        ),
                        onTap: () {
                          context.read<CarwashStore>().trackBooking(b);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CarwashTrackingScreen()),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ServicoCard extends StatelessWidget {
  const _ServicoCard({required this.type, required this.quote, required this.onTap});

  final CarwashServiceType type;
  final CarwashQuote? quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preco = quote == null
        ? '—'
        : '${quote!.totalEur.toStringAsFixed(0)} €';
    return InkWell(
      onTap: quote == null ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    type.label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  preco,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              type.description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            if (quote != null) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 15, color: AppColors.textSubtle),
                  const SizedBox(width: 4),
                  Text('cerca de ${quote!.durationMin} min',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSubtle)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AtivoCard extends StatelessWidget {
  const _AtivoCard({required this.booking});
  final CarwashBooking booking;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        context.read<CarwashStore>().trackBooking(booking);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CarwashTrackingScreen()),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.primaryWash,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_car_wash, color: AppColors.primary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.status.clientLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  Text('${booking.serviceType.label} · ${booking.plate}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}
