// Leitor de áudio partilhado na web (07/10/2026): a porta do desbloqueio
// dispara o toque silencioso UMA vez, no primeiro pointer-down, e ignora
// movimentos, subidas e toques seguintes. É isto que faz o leitor partilhado
// (um só para todos os SoundService na web) ficar desbloqueado no Safari
// antes de o painel do parceiro ou a oferta TVDE precisarem de tocar.
import 'package:bora_app/services/sound_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesbloqueioAudioWeb', () {
    test('só o primeiro pointer-down desbloqueia; o resto é ignorado', () async {
      var toquesSilenciosos = 0;
      final porta = DesbloqueioAudioWeb(() async => toquesSilenciosos++);

      expect(porta.feito, isFalse);
      expect(porta.tratar(const PointerMoveEvent()), isFalse,
          reason: 'mover o dedo não é um gesto que o Safari aceite');
      expect(porta.tratar(const PointerUpEvent()), isFalse);
      expect(toquesSilenciosos, 0);

      expect(porta.tratar(const PointerDownEvent()), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(porta.feito, isTrue);
      expect(toquesSilenciosos, 1);

      expect(porta.tratar(const PointerDownEvent()), isFalse,
          reason: 'o segundo toque não volta a tocar o silêncio');
      expect(porta.tratar(const PointerDownEvent()), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(toquesSilenciosos, 1);
    });

    test('um erro no toque silencioso não impede a porta de ficar fechada',
        () async {
      final porta = DesbloqueioAudioWeb(() async => throw StateError('x'));
      expect(porta.tratar(const PointerDownEvent()), isTrue);
      expect(porta.feito, isTrue);
      // O erro fica no Future (unawaited) — a porta já está marcada.
      await Future<void>.delayed(Duration.zero).catchError((_) {});
    });
  });

  test('fora da web o desbloqueio global não se instala (idempotente)', () {
    // Em testes (VM) `kIsWeb` é falso: não há rota global nem leitor criado.
    SoundService.instalarDesbloqueioWeb();
    SoundService.instalarDesbloqueioWeb();
    expect(SoundService.audioWebDesbloqueado, isFalse);
  });
}
