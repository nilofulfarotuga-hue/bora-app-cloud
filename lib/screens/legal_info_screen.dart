import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/legal_identity.dart';
import '../services/app_update_service.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// "Sobre / Informação legal" — quem opera a Bora, contactos, resolução
/// alternativa de litígios, Livro de Reclamações e ligações aos termos e à
/// privacidade. É o mesmo ecrã nos três papéis (cliente, estafeta, parceiro).
///
/// Os dados vêm todos de [LegalIdentity] (fonte única). Os textos ficam em
/// PT-PT sem `.tr` de propósito: são informação legal do operador, não
/// interface a traduzir.
///
/// Missão ronda-fecho-2026-09-22, bloco D1.
class LegalInfoScreen extends StatelessWidget {
  const LegalInfoScreen({super.key, this.abrirLigacao});

  /// Como se abre uma ligação fora da app. Por omissão é o `url_launcher`
  /// ([_lancarFora]); os testes injetam um falso para provar o toque sem
  /// plugin nativo.
  final AbrirLigacao? abrirLigacao;

  /// Amarelo do Livro de Reclamações (o logótipo oficial não é asset da app;
  /// desenha-se a caixa com as cores dele).
  static const Color _amareloLivro = Color(0xFFFFD400);

  /// Abre [uri] fora da app; se não der, mostra o endereço para copiar.
  Future<void> _abrir(BuildContext context, Uri uri) async {
    var ok = false;
    try {
      ok = await (abrirLigacao ?? _lancarFora)(uri);
    } catch (e) {
      debugPrint('[legal_info_screen] não abriu $uri: $e');
    }
    if (ok || !context.mounted) return;
    final alvo = (uri.scheme == 'mailto' || uri.scheme == 'tel')
        ? uri.path
        : uri.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Não foi possível abrir $alvo')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const build = AppUpdateService.installedVersionCode;
    const versao = build > 0
        ? 'Versão instalada: build $build'
        : 'Versão de desenvolvimento';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Sobre / Informação legal'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── (a) Nome da app + versão ─────────────────────────────────
            const _Cartao(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline, color: AppColors.primary),
                  title: Text(
                    LegalIdentity.appName,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(versao),
                ),
              ],
            ),

            // ── (b) Quem opera a Bora ────────────────────────────────────
            const _Cartao(
              titulo: 'Quem opera a Bora',
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${LegalIdentity.nome}, ${LegalIdentity.qualidade}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: Spacing.xs),
                      Text(
                        'NIF ${LegalIdentity.nif}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                      Text(
                        LegalIdentity.morada,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── (c) Contactos ────────────────────────────────────────────
            _Cartao(
              titulo: 'Contactos',
              children: [
                _LinhaLigacao(
                  icone: Icons.email_outlined,
                  titulo: 'Email',
                  subtitulo: LegalIdentity.email,
                  onTap: () => _abrir(context,
                      Uri(scheme: 'mailto', path: LegalIdentity.email)),
                ),
                _LinhaLigacao(
                  icone: Icons.phone_outlined,
                  titulo: 'Telefone',
                  subtitulo: LegalIdentity.telefone,
                  onTap: () => _abrir(context,
                      Uri(scheme: 'tel', path: LegalIdentity.telefoneE164)),
                ),
              ],
            ),

            // ── (d) Resolução alternativa de litígios ────────────────────
            _Cartao(
              titulo: 'Resolução alternativa de litígios',
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
                  child: Text(
                    LegalIdentity.ralAviso,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                ),
                _LinhaLigacao(
                  icone: Icons.gavel,
                  titulo:
                      '${LegalIdentity.cniaccSigla} — ${LegalIdentity.cniaccNome}',
                  subtitulo: _semEsquema(LegalIdentity.cniaccUrl),
                  onTap: () =>
                      _abrir(context, Uri.parse(LegalIdentity.cniaccUrl)),
                ),
                _LinhaLigacao(
                  icone: Icons.gavel,
                  titulo:
                      '${LegalIdentity.caccdcSigla} — ${LegalIdentity.caccdcNome}',
                  subtitulo: '${LegalIdentity.caccdcNota} · '
                      '${_semEsquema(LegalIdentity.caccdcUrl)}',
                  onTap: () =>
                      _abrir(context, Uri.parse(LegalIdentity.caccdcUrl)),
                ),
                _LinhaLigacao(
                  icone: Icons.public,
                  titulo: LegalIdentity.odrNome,
                  subtitulo: '${LegalIdentity.odrNota} · '
                      '${_semEsquema(LegalIdentity.odrUrl)}',
                  onTap: () => _abrir(context, Uri.parse(LegalIdentity.odrUrl)),
                ),
              ],
            ),

            // ── (e) Livro de Reclamações ─────────────────────────────────
            _Cartao(
              titulo: 'Livro de Reclamações',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
                  child: Material(
                    color: _amareloLivro,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.md),
                      onTap: () => _abrir(context,
                          Uri.parse(LegalIdentity.livroReclamacoesUrl)),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.lg, vertical: Spacing.md),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'LIVRO DE RECLAMAÇÕES',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: Spacing.xxs),
                            Text(
                              'Eletrónico',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.xs, Spacing.lg, Spacing.lg),
                  child: Text(
                    'Também podes apresentar reclamação no Livro de '
                    'Reclamações Eletrónico.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),

            // ── (f) Termos e privacidade ─────────────────────────────────
            _Cartao(
              titulo: 'Documentos',
              children: [
                _LinhaLigacao(
                  icone: Icons.description_outlined,
                  titulo: 'Termos e condições',
                  subtitulo: _semEsquema(LegalIdentity.termosUrl),
                  onTap: () =>
                      _abrir(context, Uri.parse(LegalIdentity.termosUrl)),
                ),
                _LinhaLigacao(
                  icone: Icons.privacy_tip_outlined,
                  titulo: 'Política de privacidade',
                  subtitulo: _semEsquema(LegalIdentity.privacidadeUrl),
                  onTap: () =>
                      _abrir(context, Uri.parse(LegalIdentity.privacidadeUrl)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `https://www.exemplo.pt/x` → `www.exemplo.pt/x` (para mostrar no ecrã).
String _semEsquema(String url) =>
    url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');

/// Como se abre uma ligação fora da app. Devolve `true` se abriu.
typedef AbrirLigacao = Future<bool> Function(Uri uri);

/// Por omissão: `url_launcher` em aplicação externa.
///
/// Não passa por `canLaunchUrl`: no Android 11+ ela dá falso negativo para
/// `https:`/`mailto:` sem `<queries>` no manifesto, e a pessoa ficava sem
/// nada. O erro de um launch impossível é apanhado em [LegalInfoScreen._abrir].
Future<bool> _lancarFora(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

// ─── Cartão de secção (mesmo desenho do _SectionCard do perfil) ──────────────

class _Cartao extends StatelessWidget {
  const _Cartao({required this.children, this.titulo});

  final List<Widget> children;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titulo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.lg,
                    Spacing.lg - Spacing.xxs, Spacing.lg, Spacing.xs),
                child: Text(
                  titulo!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ─── Linha que abre uma ligação ──────────────────────────────────────────────

class _LinhaLigacao extends StatelessWidget {
  const _LinhaLigacao({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icone, color: AppColors.primary),
      title: Text(
        titulo,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitulo,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing:
          const Icon(Icons.open_in_new, size: 18, color: AppColors.textSubtle),
      onTap: onTap,
    );
  }
}
