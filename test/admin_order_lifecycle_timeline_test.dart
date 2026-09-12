import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/screens/admin/admin_order_detail_screen.dart')
        .readAsStringSync();
  });

  test('timeline administrativa inclui todas as mudanças de estado', () {
    expect(source, contains(".from('order_status_events')"));
    expect(source, contains("'from_status'"));
    expect(source, contains("'to_status'"));
    expect(source, contains("'actor_uid'"));
  });

  test('timeline administrativa expõe falhas persistidas do lifecycle', () {
    expect(source, contains(".from('order_lifecycle_errors')"));
    expect(source, contains("'error_message'"));
    expect(source, contains("'Falha de lifecycle'"));
  });
}
