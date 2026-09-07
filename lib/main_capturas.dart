// Entrypoint ALTERNATIVO só para gerar capturas de ecrã da App Store —
// missão `ios-lancamento` (2026-09-07). NÃO É o entrypoint de produção
// (esse continua a ser `lib/main.dart`, intocado por este ficheiro).
//
// Propositalmente NÃO chama Supabase.initialize / Firebase.initializeApp /
// Stripe nem cria nenhum Timer.periodic — os 7 ecrãs-alvo em
// `screens/capturas/captura_screens.dart` são 100% estáticos (dados falsos
// hardcoded), para o `pumpAndSettle` do integration_test assentar sempre.
//
// Uso manual (fora do CI, só para pré-visualizar no Windows/Chrome):
//   flutter run -t lib/main_capturas.dart -d chrome
import 'package:flutter/material.dart';

import 'config/app_theme.dart';
import 'screens/capturas/captura_screens.dart';

void main() {
  runApp(const CapturasApp());
}

/// App mínima — um menu com os 7 ecrãs-alvo, cada um navegável por índice.
/// O `integration_test/capturas_loja_test.dart` NÃO precisa de passar por
/// este menu: pumpa os widgets de `captura_screens.dart` diretamente dentro
/// do seu próprio `MaterialApp` de teste. Este ficheiro serve para uso manual
/// e para deixar as 7 rotas nomeadas disponíveis (`/01-mercado`, etc.).
class CapturasApp extends StatelessWidget {
  const CapturasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bora — Capturas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (_) => const _CapturasMenuScreen(),
        for (final CapturaScreenSpec spec in capturaScreens)
          '/${spec.fileName}': spec.builder,
      },
    );
  }
}

class _CapturasMenuScreen extends StatelessWidget {
  const _CapturasMenuScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capturas — App Store')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: capturaScreens.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final spec = capturaScreens[index];
          return ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(spec.titulo),
            subtitle: Text(spec.fileName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/${spec.fileName}'),
          );
        },
      ),
    );
  }
}
