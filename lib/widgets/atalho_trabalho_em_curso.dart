import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../screens/cleaner/cleaner_home_screen.dart';
import '../screens/washer/washer_home_screen.dart';
import '../services/notification_service.dart';
import '../services/trabalho_em_curso.dart';

/// O ATALHO — enquanto houver trabalho aceite, ele manda no ecrã.
///
/// Envolve a árvore inteira, por isso a barra aparece esteja a pessoa no ecrã
/// que estiver, e o regresso automático funciona venha ela de onde vier.
///
/// Faz três coisas, todas pedidas pelo Danilo a 2026-08-29 depois do teste no
/// telemóvel dele:
///  1. Ao abrir a app e ao voltar dela, se houver trabalho a meio, **entra
///     nele**. Antes caía no ecrã de motorista e ele julgou ter perdido a
///     lavagem.
///  2. Enquanto durar, uma barra sempre visível para voltar lá.
///  3. Quando acaba, a barra desaparece sozinha.
///
/// A verdade vem do servidor. Estado só no telemóvel morre quando o Android
/// mata a app — que é precisamente quando isto faz falta.
class AtalhoTrabalhoEmCurso extends StatefulWidget {
  const AtalhoTrabalhoEmCurso({super.key, required this.child});
  final Widget child;

  @override
  State<AtalhoTrabalhoEmCurso> createState() => _AtalhoTrabalhoEmCursoState();
}

class _AtalhoTrabalhoEmCursoState extends State<AtalhoTrabalhoEmCurso>
    with WidgetsBindingObserver {
  TrabalhoEmCurso? _trabalho;

  /// Já levámos a pessoa para dentro deste trabalho nesta sessão? Sem isto,
  /// cada volta ao foreground empurrava-a outra vez para lá mesmo que ela
  /// tivesse saído de propósito para ver outra coisa.
  String? _jaEntrouEm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificar(entrar: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verificar(entrar: true);
  }

  Future<void> _verificar({bool entrar = false}) async {
    final t = await lerTrabalhoEmCurso();
    if (!mounted) return;
    if (t != _trabalho) setState(() => _trabalho = t);
    if (t == null) {
      _jaEntrouEm = null;
      return;
    }
    if (entrar && _jaEntrouEm != t.bookingId) {
      _jaEntrouEm = t.bookingId;
      _abrir(t);
    }
  }

  void _abrir(TrabalhoEmCurso t) {
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => t.categoria == 'lavagem'
          ? const WasherHomeScreen()
          : const CleanerHomeScreen(),
    ))
        // Ao fechar o ecrã do trabalho, reconfirma com o servidor: se acabou,
        // a barra desaparece sem ninguém ter de a mandar embora.
        .then((_) => _verificar());
  }

  @override
  Widget build(BuildContext context) {
    final t = _trabalho;
    return Stack(
      children: [
        widget.child,
        if (t != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _abrir(t),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 10,
                            offset: Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.work_history_outlined,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.titulo,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                              Text(
                                t.morada.isEmpty
                                    ? t.passo
                                    : '${t.passo} · ${t.morada}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Voltar',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        const Icon(Icons.chevron_right, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
