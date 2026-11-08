// AMIGO BORA (08/11/2026, missão m4-amigo-bora-v1) — a entrada ÚNICA do
// assistente na home do cliente: um botão arredondado por baixo da pesquisa,
// "Ajuda-me a escolher", com o avatar (bolha verde com pontos laranja, sem
// rosto). Na primeira vez aparece um cartão de 2 linhas com "Agora não", que
// esconde o cartão para sempre (o botão fica). Nenhum pop-up, nenhuma
// obrigação. O botão flutuante antigo do assistente saiu (BoraClientFabs só
// tem o suporte).
//
// Com `assistant_enabled = false` nada disto se desenha. O cartão só aparece
// com `assistant_personality_enabled = true` (servidor pronto).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_colors.dart';
import '../../../l10n/tr.dart';
import '../../../services/assistant_service.dart';
import 'assistant_chat_screen.dart';

/// Chave de SharedPreferences: o cliente já fechou o cartão de boas-vindas.
const String kAmigoBoraCartaoFechadoKey = 'amigo_bora.cartao_fechado';

/// Texto do cartão quando o painel não tem outro.
const String kAmigoBoraBoasVindas =
    'Sou o Amigo Bora. Sei o que há na Guarda e o que costumas pedir. Pergunta-me o que quiseres.';

/// O avatar do Amigo (assets/branding/amigo_bora.png, 1x/2x/3x).
class AmigoBoraAvatar extends StatelessWidget {
  const AmigoBoraAvatar({super.key, this.tamanho = 28});

  final double tamanho;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/amigo_bora.png',
      width: tamanho,
      height: tamanho,
      semanticLabel: 'Amigo Bora',
      errorBuilder: (_, __, ___) => CircleAvatar(
        radius: tamanho / 2,
        backgroundColor: AppColors.primary,
        child: Icon(Icons.chat_bubble_outline,
            size: tamanho * 0.55, color: Colors.white),
      ),
    );
  }
}

/// Botão + cartão da primeira vez, para pôr por baixo da barra de pesquisa.
class AmigoBoraEntrada extends StatefulWidget {
  const AmigoBoraEntrada({super.key, this.abrir});

  /// Abre o Amigo (por defeito, o ecrã do assistente). Trocável nos testes.
  final VoidCallback? abrir;

  @override
  State<AmigoBoraEntrada> createState() => _AmigoBoraEntradaState();
}

class _AmigoBoraEntradaState extends State<AmigoBoraEntrada> {
  bool _cartaoFechado = true; // até ler as preferências, não pisca

  @override
  void initState() {
    super.initState();
    AssistantFlags.carregar();
    _lerPreferencia();
  }

  Future<void> _lerPreferencia() async {
    try {
      final p = await SharedPreferences.getInstance();
      final fechado = p.getBool(kAmigoBoraCartaoFechadoKey) ?? false;
      if (mounted) setState(() => _cartaoFechado = fechado);
    } catch (_) {/* sem preferências: fica escondido */}
  }

  Future<void> _fecharCartao() async {
    setState(() => _cartaoFechado = true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kAmigoBoraCartaoFechadoKey, true);
    } catch (_) {}
  }

  void _abrir() {
    final f = widget.abrir;
    if (f != null) {
      f();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AssistantChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AssistantFlags.enabled,
      builder: (context, ligado, _) {
        if (!ligado) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Botao(onTap: _abrir),
              ValueListenableBuilder<bool>(
                valueListenable: AssistantFlags.personalidade,
                builder: (context, amigo, _) {
                  if (!amigo || _cartaoFechado) return const SizedBox.shrink();
                  return ValueListenableBuilder<String>(
                    valueListenable: AssistantFlags.boasVindasAmigo,
                    builder: (context, texto, _) => _Cartao(
                      texto: texto.isEmpty ? kAmigoBoraBoasVindas.tr : texto,
                      onAbrir: _abrir,
                      onAgoraNao: _fecharCartao,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Botao extends StatelessWidget {
  const _Botao({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const StadiumBorder(
        side: BorderSide(color: AppColors.primaryLight),
      ),
      child: InkWell(
        key: const Key('amigo-bora-botao'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AmigoBoraAvatar(tamanho: 28),
              const SizedBox(width: 8),
              Text(
                'Ajuda-me a escolher'.tr,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.texto,
    required this.onAbrir,
    required this.onAgoraNao,
  });

  final String texto;
  final VoidCallback onAbrir;
  final VoidCallback onAgoraNao;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('amigo-bora-cartao'),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onAbrir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AmigoBoraAvatar(tamanho: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          texto,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('amigo-bora-agora-nao'),
                    onPressed: onAgoraNao,
                    child: Text('Agora não'.tr),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
