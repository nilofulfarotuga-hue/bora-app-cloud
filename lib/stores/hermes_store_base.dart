// Missão hermes-diretor-2026-11-20 (B10) — base comum dos stores dos ecrãs do Hermes no painel.
// Um ecrã pode fechar a meio de uma leitura: depois disso ninguém é avisado (evita "used after dispose").

import 'package:flutter/foundation.dart';

abstract class HermesStoreBase extends ChangeNotifier {
  bool _fechado = false;

  /// `true` enquanto uma leitura está a decorrer (o ecrã mostra o círculo).
  bool carregando = false;

  /// Último erro de leitura (o ecrã traduz para PT-BR). Nulo = sem erro.
  Object? erro;

  /// `true` quando a tabela ou a função ainda não existe no servidor
  /// (o ecrã mostra uma faixa calma, nunca um erro vermelho).
  bool naoLigado = false;

  @override
  void dispose() {
    _fechado = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_fechado) super.notifyListeners();
  }
}
