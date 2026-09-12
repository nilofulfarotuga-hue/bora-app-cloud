import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin/admin_partner_detail_screen.dart';

/// T5.4 — Card no admin_dashboard mostrando parceiros fechados AGORA.
/// Refresh 30s. Click → navega ao detail do parceiro.
class AdminClosedPartnersCard extends StatefulWidget {
  const AdminClosedPartnersCard({super.key});
  @override
  State<AdminClosedPartnersCard> createState() =>
      _AdminClosedPartnersCardState();
}

class _AdminClosedPartnersCardState extends State<AdminClosedPartnersCard> {
  Timer? _timer;
  bool _loading = true;
  List<Map<String, dynamic>> _partners = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await Supabase.instance.client.rpc('admin_partners_closed_now');
      if (!mounted) return;
      final m = (res as Map).cast<String, dynamic>();
      setState(() {
        _partners =
            ((m['partners'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminClosedPartnersCard] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_partners.isEmpty && !_loading) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.orange.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.do_not_disturb_on,
                    color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Parceiros fechados agora (${_partners.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          ..._partners.take(5).map((p) => ListTile(
                dense: true,
                leading: const Icon(Icons.store, size: 18),
                title: Text(p['name'] as String? ?? '—'),
                subtitle: Text(
                    '${p['reason'] ?? '?'}${p['override_note'] != null ? ' · ${p['override_note']}' : ''}',
                    style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AdminPartnerDetailScreen(
                            restaurantId: p['restaurant_id'] as String,
                            initialName: p['name'] as String? ?? ''))),
              )),
          if (_partners.length > 5)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('+ ${_partners.length - 5} mais',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ),
        ],
      ),
    );
  }
}
