// Chat da limpeza (07/10/2026): o `dispose` lia o CleaningChatStore pelo
// `context` — quando o ecrã sai da árvore JUNTO com o Provider (fecho da
// app, troca de papel), `context.read` rebenta com "Looking up a deactivated
// widget's ancestor is unsafe" e o `unlisten` nunca corre. É o mesmo defeito
// corrigido no botão a 03/10. Agora o store fica guardado no initState.
//
// A prova: monta o chat dentro do Provider, troca a árvore inteira por um
// SizedBox (Provider e ecrã saem juntos) e exige (1) zero excepções e
// (2) o `unlisten` do mesmo bookingId chamado uma vez.
import 'package:bora_app/screens/shared/cleaning_chat_screen.dart';
import 'package:bora_app/stores/cleaning_chat_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StoreFalso extends ChangeNotifier implements CleaningChatStore {
  final List<String> ouvidos = [];
  final List<String> largados = [];

  @override
  void listen(String bookingId) => ouvidos.add(bookingId);

  @override
  void unlisten(String bookingId) => largados.add(bookingId);

  @override
  List<CleaningMessage> messagesForBooking(String bookingId) => const [];

  @override
  int unreadFor(String bookingId, String myRole) => 0;

  @override
  CleaningMessage? lastFor(String bookingId) => null;

  @override
  Future<void> markRead(String bookingId, String myRole) async {}

  @override
  Future<void> sendMessage({
    required String bookingId,
    required String senderRole,
    required String content,
  }) async {}
}

void main() {
  testWidgets('sair da árvore junto com o Provider não rebenta e larga o chat',
      (tester) async {
    final store = _StoreFalso();

    await tester.pumpWidget(
      ChangeNotifierProvider<CleaningChatStore>.value(
        value: store,
        child: const MaterialApp(
          home: CleaningChatScreen(
            bookingId: 'limpeza-123',
            myRole: 'client',
            title: 'Maria',
          ),
        ),
      ),
    );
    expect(store.ouvidos, ['limpeza-123']);

    // Provider e ecrã saem ao mesmo tempo — o cenário que partia o dispose.
    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull,
        reason: 'o dispose não pode ler o Provider pelo context');
    expect(store.largados, ['limpeza-123'],
        reason: 'o unlisten tem de correr com o store guardado no initState');
  });
}
