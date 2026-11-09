import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../l10n/tr.dart';
import '../services/entrada_social_cliente.dart';

/// Botões "Continuar com Google" (e, no iPhone, "Continuar com a Apple") dos
/// ecrãs de entrada e de registo do CLIENTE. Estafeta e parceiro não os têm.
///
/// Abre a página do Google/Apple ([EntradaSocialCliente.iniciar]); quando a
/// conta de cliente fica aberta (o AuthStore conclui a entrada), chama
/// [aoEntrar] uma vez — o ecrã que o usa decide se fecha, volta ao carrinho ou
/// deixa o `_RootNavigator` trocar de ecrã.
///
/// Os interruptores vêm do painel (`login_google_ativo`, `login_apple_ativo`).
class EntradaSocialBotoes extends StatefulWidget {
  const EntradaSocialBotoes({
    super.key,
    required this.aoEntrar,
    this.separador,
    this.separadorEmCima = false,
    this.desligado = false,
  });

  final VoidCallback aoEntrar;

  /// Texto do divisor ("ou", "ou regista-te por email"); `null` = sem divisor.
  final String? separador;

  /// `true` põe o divisor antes dos botões (entrada, depois do "Entrar");
  /// `false` põe-no depois (registo, antes do formulário).
  final bool separadorEmCima;

  /// Outro trabalho em curso no ecrã (ex.: a criar conta por email).
  final bool desligado;

  @override
  State<EntradaSocialBotoes> createState() => _EntradaSocialBotoesState();
}

class _EntradaSocialBotoesState extends State<EntradaSocialBotoes> {
  ({bool google, bool apple}) _ligados =
      EntradaSocialCliente.ultimosInterruptores;
  bool _aAbrir = false;
  bool _aEsperar = false;
  late final AuthStore _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthStore>();
    _auth.addListener(_aoMudarConta);
    EntradaSocialCliente.lerInterruptores().then((v) {
      if (mounted) setState(() => _ligados = v);
    });
  }

  @override
  void didUpdateWidget(EntradaSocialBotoes antigo) {
    super.didUpdateWidget(antigo);
    // A pessoa desistiu do Google e entrou/criou conta por email: a conta que
    // vai abrir é desse caminho, que trata da navegação sozinho.
    if (widget.desligado && !antigo.desligado) _aEsperar = false;
  }

  @override
  void dispose() {
    _auth.removeListener(_aoMudarConta);
    super.dispose();
  }

  void _aoMudarConta() {
    if (!_aEsperar || !mounted || _auth.currentClient == null) return;
    _aEsperar = false;
    widget.aoEntrar();
  }

  Future<void> _entrar(OAuthProvider fornecedor) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _aAbrir = true);
    _aEsperar = true;
    var abriu = false;
    try {
      abriu = await EntradaSocialCliente.iniciar(fornecedor);
    } catch (e) {
      debugPrint('EntradaSocialBotoes: ${fornecedor.name} => $e');
    }
    if (!abriu) {
      _aEsperar = false;
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Não foi possível abrir a página para entrar. Tenta outra vez.'.tr),
      ));
    }
    if (mounted) setState(() => _aAbrir = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = botoesDeEntradaVisiveis(
      web: kIsWeb,
      plataforma: defaultTargetPlatform,
      googleLigado: _ligados.google,
      appleLigado: _ligados.apple,
    );
    if (!v.google && !v.apple) return const SizedBox.shrink();

    final ocupado = _aAbrir || widget.desligado;
    final texto = widget.separador;
    final divisor = texto == null ? null : _Divisor(texto: texto);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (divisor != null && widget.separadorEmCima) ...[
          divisor,
          const SizedBox(height: 16),
        ],
        // Apple primeiro: a Apple pede o botão dela pelo menos tão à vista
        // como os outros.
        if (v.apple)
          BotaoEntradaApple(
            onPressed: ocupado ? null : () => _entrar(OAuthProvider.apple),
          ),
        if (v.apple && v.google) const SizedBox(height: 12),
        if (v.google)
          BotaoEntradaGoogle(
            onPressed: ocupado ? null : () => _entrar(OAuthProvider.google),
          ),
        if (divisor != null && !widget.separadorEmCima) ...[
          const SizedBox(height: 20),
          divisor,
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _Divisor extends StatelessWidget {
  const _Divisor({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}

/// Botão do Google: fundo branco, contorno cinzento, o "G" do Google e texto
/// (regras de marca do Google para o botão de entrada).
class BotaoEntradaGoogle extends StatelessWidget {
  const BotaoEntradaGoogle({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'btn_google',
      child: SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          key: const Key('entrar_google'),
          icon: const SizedBox(
            width: 20,
            height: 20,
            child: CustomPaint(painter: _LogoGooglePainter()),
          ),
          label: Text(
            'Continuar com Google'.tr,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Botão da Apple: preto com a maçã e o texto a branco (estilo "black" das
/// regras da Apple para "Iniciar sessão com a Apple").
class BotaoEntradaApple extends StatelessWidget {
  const BotaoEntradaApple({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'btn_apple',
      child: SizedBox(
        height: 50,
        child: FilledButton.icon(
          key: const Key('entrar_apple'),
          icon: const Icon(Icons.apple, color: Colors.white, size: 22),
          label: Text(
            'Continuar com a Apple'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black,
            disabledBackgroundColor: Colors.black54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// O "G" do Google, desenhado (sem ficheiro de imagem), nas cores da marca.
class _LogoGooglePainter extends CustomPainter {
  const _LogoGooglePainter();

  static const _azul = Color(0xFF4285F4);
  static const _verde = Color(0xFF34A853);
  static const _amarelo = Color(0xFFFBBC05);
  static const _vermelho = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final traco = s * 0.2;
    final centro = Offset(size.width / 2, size.height / 2);
    final r = (s - traco) / 2;
    final caixa = Rect.fromCircle(center: centro, radius: r);
    Paint tinta(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = traco;
    double g(double graus) => graus * 3.141592653589793 / 180;

    // Ângulos no sentido dos ponteiros, 0° = direita.
    canvas.drawArc(caixa, g(0), g(45), false, tinta(_azul));
    canvas.drawArc(caixa, g(45), g(90), false, tinta(_verde));
    canvas.drawArc(caixa, g(135), g(85), false, tinta(_amarelo));
    canvas.drawArc(caixa, g(220), g(100), false, tinta(_vermelho));
    // A barra do G.
    canvas.drawRect(
      Rect.fromLTRB(centro.dx, centro.dy - traco / 2, centro.dx + r + traco / 2,
          centro.dy + traco / 2),
      Paint()..color = _azul,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
