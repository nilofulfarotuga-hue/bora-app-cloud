import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/session_store.dart';
import 'client_main_screen.dart';
import 'festas_screen.dart';

/// Entrada do build de preview: mostra o início do cliente e abre por cima a
/// categoria Festas. O voltar deixa a pessoa no início normal da app.
///
/// Só é usada quando `kFestasPreview` está ligado — ver
/// `lib/config/festas_preview.dart`.
class FestasPreviewEntrada extends StatefulWidget {
  const FestasPreviewEntrada({super.key});

  @override
  State<FestasPreviewEntrada> createState() => _FestasPreviewEntradaState();
}

class _FestasPreviewEntradaState extends State<FestasPreviewEntrada> {
  bool _abriu = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // O papel de cliente é o que faz as lojas carregarem. Sem conta: nesta
      // preview ninguém cria pedido — o pagamento trava antes disso.
      final session = context.read<SessionStore>();
      if (session.role != UserRole.client) {
        await session.setRole(UserRole.client);
      }
      if (!mounted || _abriu) return;
      _abriu = true;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FestasScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const ClientMainScreen();
}
