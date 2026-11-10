import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/legal_identity.dart';

/// Como se abre uma ligação fora da app (os testes injetam um falso).
typedef AbrirLivroReclamacoes = Future<bool> Function(Uri uri);

/// Amarelo do Livro de Reclamações (o mesmo do selo em "Sobre / Informação
/// legal").
const Color kAmareloLivroReclamacoes = Color(0xFFFFD400);

/// Entrada "Livro de Reclamações" para a Ajuda e as Definições das apps
/// cliente, estafeta e parceiro (DL 156/2005, art. 5.º-B: quem vende online
/// tem o acesso ao Livro de Reclamações Eletrónico em destaque). Abre
/// https://www.livroreclamacoes.pt.
///
/// Missão fechar-tudo-2026-11-10, bloco E2b. O selo é desenhado com as cores
/// do Livro de Reclamações ([LivroReclamacoesSelo]); o ficheiro oficial do
/// ícone (manual da Direção-Geral do Consumidor) ainda não está em `assets/`
/// — quando estiver, troca-se só o [LivroReclamacoesSelo] por um
/// `Image.asset`. Texto legal: sem `.tr` de propósito, como o resto de
/// "Sobre / Informação legal".
class LivroReclamacoesEntrada extends StatelessWidget {
  const LivroReclamacoesEntrada({
    super.key,
    this.abrirLigacao,
    this.cartao = false,
  });

  final AbrirLivroReclamacoes? abrirLigacao;

  /// true = cartão com borda (folha de Ajuda); false = linha de lista
  /// (Definições).
  final bool cartao;

  static const String titulo = 'Livro de Reclamações';
  static const String subtitulo = 'Livro de Reclamações Eletrónico · '
      'livroreclamacoes.pt';

  static Uri get endereco => Uri.parse(LegalIdentity.livroReclamacoesUrl);

  static Future<bool> _lancarFora(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _abrir(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var ok = false;
    try {
      ok = await (abrirLigacao ?? _lancarFora)(endereco);
    } catch (e) {
      debugPrint('[LivroReclamacoesEntrada] não abriu: $e');
    }
    if (!ok) {
      messenger?.showSnackBar(SnackBar(
          content:
              Text('Não foi possível abrir ${LegalIdentity.livroReclamacoesUrl}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final linha = ListTile(
      key: const ValueKey('livro-reclamacoes-entrada'),
      leading: const LivroReclamacoesSelo(),
      title: const Text(titulo),
      subtitle: const Text(subtitulo),
      trailing: const Icon(Icons.open_in_new, size: 20),
      onTap: () => _abrir(context),
    );
    if (!cartao) return linha;
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: linha,
    );
  }
}

/// O selo amarelo e preto do Livro de Reclamações, em pequeno.
class LivroReclamacoesSelo extends StatelessWidget {
  const LivroReclamacoesSelo({super.key, this.tamanho = 40});

  final double tamanho;

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          color: kAmareloLivroReclamacoes,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Icon(Icons.menu_book, color: Colors.black, size: tamanho * 0.55),
      );
}
