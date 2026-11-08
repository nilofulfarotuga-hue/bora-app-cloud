import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../screens/cleaner/cleaner_home_screen.dart';
import '../screens/handyman/handyman_home_screen.dart';
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
/// Missão m2 (08/11/2026), depois da faixa "Limpeza a decorrer — aceite — a
/// caminho" ficar presa no telemóvel do Danilo e tapar o interruptor Online:
///  4. Trabalho aceite para outro dia (mais de 3 h até à hora marcada) não é
///     "a decorrer": não há faixa nem entrada automática.
///  5. Volta a perguntar ao servidor a cada 60 s e quando a marcação muda
///     (tempo real), não só ao abrir a app.
///  6. Tem "×": esconde até o estado mudar.
///  7. Diz a altura que ocupa ([alturaOcupada]); os ecrãs com o interruptor
///     Online sobem-no por cima dela.
///
/// A verdade vem do servidor. Estado só no telemóvel morre quando o Android
/// mata a app — que é precisamente quando isto faz falta.
class AtalhoTrabalhoEmCurso extends StatefulWidget {
  const AtalhoTrabalhoEmCurso({super.key, required this.child});
  final Widget child;

  /// Quanto a faixa ocupa no fundo do ecrã (0 = não está à vista). O mapa do
  /// estafeta e o do motorista somam isto ao fundo do cartão do Online.
  static final ValueNotifier<double> alturaOcupada = ValueNotifier<double>(0);

  /// Altura da faixa (margem de baixo + conteúdo de duas linhas).
  static const double alturaFaixa = 76;

  /// De quanto em quanto tempo se volta a perguntar ao servidor.
  static const Duration intervalo = Duration(seconds: 60);

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

  /// "×": o trabalho (id + estado) que a pessoa mandou esconder.
  TrabalhoEmCurso? _escondido;

  Timer? _relogio;
  RealtimeChannel? _canal;
  String? _canalDe;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificar(entrar: true));
    _relogio = Timer.periodic(AtalhoTrabalhoEmCurso.intervalo, (_) {
      if (mounted) _verificar();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _relogio?.cancel();
    _fecharCanal();
    AtalhoTrabalhoEmCurso.alturaOcupada.value = 0;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verificar(entrar: true);
  }

  /// Só conta como "a decorrer" o que não é para mais tarde.
  TrabalhoEmCurso? _aDecorrer(TrabalhoEmCurso? t) =>
      (t == null || t.eParaMaisTarde(DateTime.now())) ? null : t;

  Future<void> _verificar({bool entrar = false}) async {
    final t = _aDecorrer(await lerTrabalhoEmCurso());
    if (!mounted) return;
    if (t != _trabalho) setState(() => _trabalho = t);
    _ouvir(t);
    _publicarAltura();
    if (t == null) {
      _jaEntrouEm = null;
      return;
    }
    if (entrar && _jaEntrouEm != t.bookingId) {
      _jaEntrouEm = t.bookingId;
      _abrir(t);
    }
  }

  /// Tempo real: qualquer mudança nesta marcação faz voltar a perguntar.
  void _ouvir(TrabalhoEmCurso? t) {
    final tabela = t?.tabela;
    final chave = t == null || tabela == null ? null : '$tabela:${t.bookingId}';
    if (chave == _canalDe) return;
    _fecharCanal();
    if (t == null || tabela == null) return;
    try {
      final sb = Supabase.instance.client;
      _canal = sb.channel('atalho-trabalho-${t.bookingId}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: tabela,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: t.bookingId,
          ),
          callback: (_) {
            if (mounted) _verificar();
          },
        ).subscribe();
      _canalDe = chave;
    } catch (e) {
      debugPrint('[AtalhoTrabalhoEmCurso] tempo real: $e');
    }
  }

  void _fecharCanal() {
    final c = _canal;
    _canal = null;
    _canalDe = null;
    if (c != null) {
      try {
        Supabase.instance.client.removeChannel(c);
      } catch (_) {}
    }
  }

  bool get _visivel {
    final t = _trabalho;
    return t != null && t != _escondido;
  }

  /// Fora do build: mexer no ValueNotifier durante o build reconstruía os
  /// ecrãs que o ouvem a meio de outro build.
  void _publicarAltura() {
    final altura = _visivel ? AtalhoTrabalhoEmCurso.alturaFaixa : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AtalhoTrabalhoEmCurso.alturaOcupada.value = altura;
    });
  }

  void _esconder() {
    setState(() => _escondido = _trabalho);
    _publicarAltura();
  }

  void _abrir(TrabalhoEmCurso t) {
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      // Regra 1.18: um caso por categoria, sem "o resto é limpeza".
      builder: (_) => switch (t.categoria) {
        'lavagem' => const WasherHomeScreen(),
        'casa' => const HandymanHomeScreen(),
        _ => const CleanerHomeScreen(),
      },
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
        if (t != null && _visivel)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('atalho_trabalho_em_curso'),
                  onTap: () => _abrir(t),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
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
                        IconButton(
                          key: const Key('atalho_trabalho_fechar'),
                          tooltip: 'Esconder',
                          visualDensity: VisualDensity.compact,
                          onPressed: _esconder,
                          icon: const Icon(Icons.close,
                              color: Colors.white70, size: 18),
                        ),
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
