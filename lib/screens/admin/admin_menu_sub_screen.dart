import 'package:flutter/material.dart';

import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_menu_registry.dart';

/// Sub-ecrã "Mais ..." de uma secção do menu do painel (ronda 04/10): as
/// entradas que não cabem nas 5 da secção abrem-se daqui, uma por linha.
class AdminMenuSubScreen extends StatelessWidget {
  const AdminMenuSubScreen({
    super.key,
    required this.titulo,
    required this.itens,
  });

  final String titulo;
  final List<AdminMenuItem> itens;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: titulo),
      body: ListView.separated(
        itemCount: itens.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final it = itens[i];
          return ListTile(
            leading: Icon(it.icon, color: it.color),
            title: Text(it.title),
            subtitle: Text(it.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => it.builder())),
          );
        },
      ),
    );
  }
}
