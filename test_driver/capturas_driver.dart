// Driver para `flutter drive` gravar as capturas de ecrã da App Store em
// disco — missão `ios-lancamento` (2026-09-07).
//
// O alvo mudou a 2026-09-08: era `capturas_loja_test.dart` (ecrãs
// desenhados com dados inventados, apagado) e passou a ser
// `demo_real_test.dart`, que percorre a app real ligada ao servidor.
//
// Irmão de `test_driver/integration_test.dart` (que grava em
// `.claude/testes-e2e/web-logs/shots/` para os testes E2E web); este grava em
// `artefactos/capturas/` para o passo "Publicar artefactos" do
// `build_ios.yml` apanhar junto com o vídeo/log do simulador.
//
// Uso (no CI, simulador iOS já arrancado):
//   flutter drive --driver=test_driver/capturas_driver.dart \
//     --target=integration_test/demo_real_test.dart \
//     -d "$UDID" --dart-define-from-file=.dart_defines
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final Directory pasta = Directory('artefactos/capturas');
  if (!pasta.existsSync()) {
    pasta.createSync(recursive: true);
  }
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final File ficheiro = File('${pasta.path}/$name.png');
      ficheiro.writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('CAPTURA_GRAVADA ${ficheiro.path} (${bytes.length} bytes)');
      return true;
    },
  );
  // ignore: avoid_print
  stdout.writeln('CAPTURAS_DRIVER_DONE ${base64Encode(utf8.encode('ok'))}');
}
