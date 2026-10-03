import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

/// Termos e Condições com versão (missão fecho-mensal-2026-09, B6A).
///
/// Embrulha o ecrã principal do cliente e do estafeta. No arranque pergunta ao
/// servidor (`legal_terms_pending`) se há uma versão em vigor que este
/// utilizador ainda não aceitou; se houver, põe por cima um ecrã com o texto e
/// um único botão "Aceito" (`legal_terms_accept`). Sem aceitar não se passa.
///
/// Falha aberta: sem sessão Supabase ou sem rede, a app segue normalmente e a
/// pergunta repete-se no próximo arranque — um erro de rede nunca tranca ninguém.
class TermsGate extends StatefulWidget {
  const TermsGate({super.key, required this.audience, required this.child});

  /// 'cliente' ou 'estafeta' (igual a `legal_terms_versions.audience`).
  final String audience;
  final Widget child;

  @override
  State<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<TermsGate> {
  Map<String, dynamic>? _pendente;
  bool _aGravar = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return;
    try {
      final r = await sb.rpc('legal_terms_pending',
          params: {'p_audience': widget.audience});
      if (!mounted) return;
      if (r is Map) setState(() => _pendente = Map<String, dynamic>.from(r));
    } catch (e) {
      debugPrint('[TermsGate] legal_terms_pending: $e');
    }
  }

  Future<void> _aceitar() async {
    final v = _pendente;
    if (v == null) return;
    setState(() {
      _aGravar = true;
      _erro = null;
    });
    try {
      await Supabase.instance.client.rpc('legal_terms_accept', params: {
        'p_audience': widget.audience,
        'p_version': v['version'],
        'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });
      if (mounted) setState(() => _pendente = null);
    } catch (e) {
      if (mounted) {
        setState(() => _erro =
            'Não foi possível gravar a aceitação. Verifique a ligação e tente outra vez.');
      }
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _pendente;
    if (v == null) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: Colors.white,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.description_outlined,
                        size: 40, color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text(
                      (v['title'] ?? 'Termos e Condições').toString(),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          (v['body'] ?? '').toString(),
                          style: const TextStyle(fontSize: 15, height: 1.45),
                        ),
                      ),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 8),
                      Text(_erro!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _aGravar ? null : _aceitar,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        child: _aGravar
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Aceito',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
