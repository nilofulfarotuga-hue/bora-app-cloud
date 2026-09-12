// Driver para `flutter drive` correr os testes de integration_test no browser
// (Chrome headless via chromedriver). Grava os screenshots pedidos por
// `binding.takeScreenshot(name)` como ficheiros PNG em
// `.claude/testes-e2e/web-logs/shots/<name>.png`.
//
// Uso:
//   chromedriver --port=4444 &
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/<ficheiro>.dart -d web-server \
//     --browser-name=chrome --web-run-headless
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final Directory shots =
      Directory('.claude/testes-e2e/web-logs/shots');
  if (!shots.existsSync()) {
    shots.createSync(recursive: true);
  }
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final File file = File('${shots.path}/$name.png');
      file.writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('SHOT_SAVED ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
  // Marcador de fim para logs.
  stdout.writeln('DRIVER_DONE ${base64Encode(utf8.encode('ok'))}');
}
