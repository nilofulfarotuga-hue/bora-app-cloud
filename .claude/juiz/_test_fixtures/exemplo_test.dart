import 'package:flutter_test/flutter_test.dart';
void main() {
  test('soma simples', () {
    expect(2 + 2, equals(4));
    expect(2 + 3, equals(5));
  });
  test('subtracao', () {
    expect(5 - 3, equals(2));
  });
}
