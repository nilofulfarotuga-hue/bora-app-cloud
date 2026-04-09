import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_service_type.dart';
import '../stores/order_store.dart';

class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final completedOrders = context.watch<OrderStore>().completedOrders;
    final totalEarnings = completedOrders.fold<double>(
      0,
      (sum, order) => sum + order.driverEarnings,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ganhos"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryCard(totalEarnings: totalEarnings, totalOrders: completedOrders.length),
            const SizedBox(height: 8),
            const _LedgerBalanceCard(),
            const SizedBox(height: 16),
            const Text(
              "Histórico de entregas",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: completedOrders.isEmpty
                  ? const Center(
                      child: Text("Nenhuma entrega concluída ainda."),
                    )
                  : ListView.separated(
                      itemCount: completedOrders.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        final order = completedOrders[index];
                        return _EarningTile(
                          title: order.serviceType.label,
                          subtitle: order.vendorName ?? order.dropoffAddress ?? "Entrega",
                          amount: order.driverEarnings,
                          distanceKm: order.distanceKm,
                          createdAt: order.createdAt,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalEarnings,
    required this.totalOrders,
  });

  final double totalEarnings;
  final int totalOrders;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Total ganho",
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "€${totalEarnings.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  "Entregas",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  "$totalOrders",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EarningTile extends StatelessWidget {
  const _EarningTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.distanceKm,
    required this.createdAt,
  });

  final String title;
  final String? subtitle;
  final double amount;
  final double distanceKm;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) Text(subtitle!),
          Text(
            "${distanceKm.toStringAsFixed(1)} km • ${_formatDate(createdAt)}",
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
      trailing: Text(
        "+€${amount.toStringAsFixed(2)}",
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.green,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}";
  }
}

class _LedgerBalanceCard extends StatefulWidget {
  const _LedgerBalanceCard();

  @override
  State<_LedgerBalanceCard> createState() => _LedgerBalanceCardState();
}

class _LedgerBalanceCardState extends State<_LedgerBalanceCard> {
  double? _balance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('user_balance_snapshots')
          .select('balance')
          .eq('user_id', uid)
          .eq('user_type', 'driver')
          .maybeSingle();
      setState(() {
        _balance = row == null ? null : (row['balance'] as num?)?.toDouble();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _balance == null) return const SizedBox.shrink();
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saldo confirmado',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Text(
                  '€${_balance!.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
