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
//
// O ROSTO (09/11/2026, missão m11-amigo-rosto — "Não é o chat não. Ele vai
// ser um rosto"): com `amigo_rosto_ativo` (por defeito ligado) o botão sem
// rosto sai e no lugar fica o rostinho vivo (pestaneja, olha à volta, sorri)
// com "Sou o Amigo. Fala comigo", que abre o ecrã do rosto (AmigoScreen).
// Há também o mosaico "Amigo" no início da grelha de categorias
// (`amigo_mosaico_categorias`). Desligado, volta tudo ao de 08/11.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../services/assistant_service.dart';
import '../../../services/amigo_voz.dart';
import '../../../widgets/amigo/amigo_rosto.dart';
import 'amigo_screen.dart';
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
    // m11 adendo 4: na web, o toque que abre o Amigo já desbloqueia a voz.
    amigoDesbloquearVozNoPrimeiroToque();
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
    abrirAmigo(context);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AssistantFlags.enabled,
      builder: (context, ligado, _) {
        if (!ligado) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: AssistantFlags.rostoAtivo,
          builder: (context, rosto, _) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rosto ? _BotaoRosto(onTap: _abrir) : _Botao(onTap: _abrir),
                ValueListenableBuilder<bool>(
                  valueListenable: AssistantFlags.personalidade,
                  builder: (context, amigo, _) {
                    if (!amigo || _cartaoFechado) return const SizedBox.shrink();
                    return ValueListenableBuilder<String>(
                      valueListenable: AssistantFlags.boasVindasAmigo,
                      builder: (context, texto, _) => _Cartao(
                        texto: texto.isEmpty ? kAmigoBoraBoasVindas.tr : texto,
                        rosto: rosto,
                        onAbrir: _abrir,
                        onAgoraNao: _fecharCartao,
                      ),
                    );
                  },
                ),
              ],
            ),
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
    this.rosto = false,
  });

  final String texto;
  final bool rosto;
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
                    rosto
                        ? const AmigoRosto(tamanho: 40, emocao: AmigoEmocao.alegre)
                        : const AmigoBoraAvatar(tamanho: 36),
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

/// Abre o Amigo: o ecrã do rosto (ou, com o rosto desligado no painel, a
/// conversa escrita de 08/11). Com [mensagem], o Amigo recebe-a logo depois
/// de cumprimentar (ex.: "Pede ao Amigo" numa pesquisa sem resultado).
void abrirAmigo(BuildContext context, {String? mensagem}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AssistantFlags.rostoAtivo.value
          ? AmigoScreen(mensagemInicial: mensagem)
          : AssistantChatScreen(mensagemInicial: mensagem),
    ),
  );
}

/// O rostinho vivo por baixo da pesquisa: "Sou o Amigo. Fala comigo".
class _BotaoRosto extends StatelessWidget {
  const _BotaoRosto({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sou o Amigo. Fala comigo'.tr,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const Key('amigo-rosto-entrada'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.primaryLight),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(
              children: [
                const AmigoRosto(tamanho: 46, emocao: AmigoEmocao.neutro),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sou o Amigo. Fala comigo'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Conversa, comida, mercado, Favores… o que quiseres.'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.mic_rounded, color: AppColors.primary, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Deve aparecer o mosaico "Amigo" na grelha de categorias? (puro, testado)
bool amigoMosaicoVisivel() =>
    AssistantFlags.enabled.value &&
    AssistantFlags.rostoAtivo.value &&
    AssistantFlags.mosaico.value;

/// O mosaico "Amigo" no início da grelha de categorias: o mesmo desenho dos
/// outros ladrilhos (cantos, sombra, rótulo branco em baixo), com o rostinho
/// animado no lugar da imagem.
class AmigoMosaico extends StatelessWidget {
  const AmigoMosaico({super.key, this.onTap});

  final VoidCallback? onTap;

  static const double _rotulo = 12 * 1.12 * 2;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Amigo'.tr,
      identifier: 'tile_amigo',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('amigo-mosaico'),
        onTap: onTap ?? () => abrirAmigo(context),
        borderRadius: BorderRadius.circular(Radii.xl),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDCFCE7), Color(0xFF86EFAC)],
            ),
            borderRadius: BorderRadius.circular(Radii.xl),
            boxShadow: AppColors.shadowCard,
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(builder: (context, c) {
            final livre = (c.maxHeight - _rotulo - 10).clamp(16.0, 400.0);
            final porAltura = livre / AmigoRosto.alturaPara(1, AmigoVariante.rosto);
            final larga = c.maxWidth * 0.8;
            final rosto = (larga < porAltura ? larga : porAltura) < 16
                ? 16.0
                : (larga < porAltura ? larga : porAltura);
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AmigoRosto(tamanho: rosto, emocao: AmigoEmocao.alegre),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x55000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 7,
                  right: 7,
                  bottom: 7,
                  child: SizedBox(
                    height: _rotulo,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Amigo'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
