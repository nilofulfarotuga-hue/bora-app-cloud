// Botões flutuantes dos ecrãs principais do cliente.
//
// BORA ASSISTENTE (07/10/2026) — eram dois: assistente (verde, em cima) e
// suporte (laranja, em baixo). AMIGO BORA (08/11/2026, missão m4): o
// assistente passou a ter UMA entrada só, o botão "Ajuda-me a escolher" junto
// à pesquisa da home (`AmigoBoraEntrada`); aqui fica só o suporte de sempre
// (`BoraSupportFab`, intocado). O nome da classe mantém-se para não mexer nos
// cinco ecrãs que a usam.

import 'package:flutter/material.dart';

import 'bora_support_fab.dart';

class BoraClientFabs extends StatelessWidget {
  const BoraClientFabs({super.key, this.orderId});

  final String? orderId;

  @override
  Widget build(BuildContext context) => BoraSupportFab(orderId: orderId);
}
