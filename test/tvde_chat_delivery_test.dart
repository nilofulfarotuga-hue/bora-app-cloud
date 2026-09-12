import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final store = File('lib/stores/tvde_chat_store.dart').readAsStringSync();
  final screen =
      File('lib/screens/shared/tvde_chat_screen.dart').readAsStringSync();

  test(
      'a mensagem confirmada entra no estado local antes de depender do realtime',
      () {
    expect(store, contains(".from('tvde_messages')"));
    expect(store, contains('.insert({'));
    expect(store, contains('.select()'));
    expect(store, contains('.single()'));
    expect(store, contains('_upsert(rideId, TvdeMessage.fromMap'));
  });

  test('o chat tem histórico explícito e subscrição observável', () {
    expect(store, contains('Future<void> _loadHistory'));
    expect(store, contains('PostgresChangeEvent.insert'));
    expect(store, contains('PostgresChangeEvent.update'));
    expect(store, contains('RealtimeSubscribeStatus.subscribed'));
    expect(store, contains('syncErrorForRide'));
  });

  test('o texto só é apagado depois de sendMessage concluir', () {
    final send = screen.substring(
      screen.indexOf('Future<void> _send() async'),
      screen.indexOf('void _scrollToEnd()'),
    );
    expect(send.indexOf('await context.read<TvdeChatStore>().sendMessage'),
        lessThan(send.indexOf('_controller.clear()')));
    expect(screen, contains('final syncError = store.syncErrorForRide'));
  });
}
