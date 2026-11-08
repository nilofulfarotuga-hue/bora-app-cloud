// M1 08/11/2026 — Favor: até quanto o estafeta pode comprar e a aprovação do
// cliente quando o preço na loja é maior (padrão dos grandes, conselho 08/11).
//
// Vive FORA de errand_execution_sheet.dart (ficheiro inteiro em zona vermelha
// da tranca por causa do _finalizePurchase): a folha do Favor só o mostra na
// fase de compra e lê o [FavorTetoController] para ligar/desligar o
// "Confirmar compra". O fecho da compra (finalize_errand_purchase) não muda.
//
// Contratos do servidor (fonte da verdade):
//   docs/propostas/m1-dinheiro-favores-2026-11-08/02_favor_aprovacao_com_tecto.sql
//   errand_teto_compra · estafeta_favor_pedir_aprovacao · estafeta_favor_sem_resposta
// Sem as funções novas no servidor (PGRST202), o tecto volta a ser a
// estimativa × 1,2 e o pedido segue pelo caminho antigo
// (errand_request_budget_increase), para nada partir antes da migração.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../services/order_photo_upload_service.dart';
import '../utils/euros.dart';
import '../utils/io_compat.dart' show File, boraLocalImage;
import '../utils/safe_image_picker.dart';
import '../utils/valor_em_centimos.dart';

/// O que a folha do Favor precisa de saber para o botão "Confirmar compra".
/// Só o [FavorTetoCompraCard] escreve aqui; a folha só lê.
class FavorTetoController extends ChangeNotifier {
  int? _tetoCents;
  bool _cancelado = false;
  bool _esperaMbway = false;

  /// Tecto atual em cêntimos (null = ainda não lido).
  int? get tetoCents => _tetoCents;

  /// O Favor vai ser cancelado (cliente ou estafeta sem resposta).
  bool get cancelado => _cancelado;

  /// Aprovado, mas o MB Way da diferença ainda não está pago.
  bool get esperaMbway => _esperaMbway;

  void _atualizar({
    required int? tetoCents,
    required bool cancelado,
    required bool esperaMbway,
  }) {
    if (tetoCents == _tetoCents &&
        cancelado == _cancelado &&
        esperaMbway == _esperaMbway) {
      return;
    }
    _tetoCents = tetoCents;
    _cancelado = cancelado;
    _esperaMbway = esperaMbway;
    notifyListeners();
  }

  /// false = não deixar fechar a compra com este total do talão.
  bool podeConfirmar(int talaoCents) => motivoBloqueio(talaoCents) == null;

  /// Porque é que o "Confirmar compra" está desligado (null = está ligado).
  String? motivoBloqueio(int talaoCents) {
    if (_cancelado) return 'O Favor vai ser cancelado. Não compres nada.';
    if (_esperaMbway) {
      final teto = _tetoCents ?? 0;
      if (talaoCents <= 0 || talaoCents > teto) {
        return 'Enquanto o MB Way da diferença não aparecer pago, só podes '
            'confirmar uma compra até ${eurCents(teto)}.';
      }
    }
    return null;
  }
}

class FavorTetoCompraCard extends StatefulWidget {
  const FavorTetoCompraCard({super.key, required this.order, this.controller});

  final OrderModel order;
  final FavorTetoController? controller;

  @override
  State<FavorTetoCompraCard> createState() => _FavorTetoCompraCardState();
}

class _FavorTetoCompraCardState extends State<FavorTetoCompraCard> {
  Map<String, dynamic>? _teto; // última resposta boa do servidor
  bool _tetoCarregado = false; // já houve uma tentativa (boa ou má)
  bool _tetoAntigo = false; // funções novas ainda não estão no servidor
  Future<void>? _tetoEmCurso;
  Timer? _poll; // 4 s enquanto o cliente não responde / MB Way por pagar
  Timer? _contagem; // 1 s, contagem decrescente do prazo do cliente
  DateTime? _expiraLocal; // fim do prazo no relógio do telemóvel
  bool _cancelamentoPedido = false; // o estafeta pediu para cancelar
  bool _busy = false;
  String? _info; // avisos dentro do cartão (o SnackBar fica por trás da folha)
  String? _erro;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshTeto());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _contagem?.cancel();
    super.dispose();
  }

  // ── Leitura do estado ────────────────────────────────────────────────

  /// O limite antigo (o que o cartão/MB Way já reservou): estimativa × 1,2.
  int get _tetoEstimativaCents =>
      (widget.order.errandEstimatedPurchaseCents * 1.2).round();

  int get _tetoCents {
    final v = _teto?['teto_cents'];
    return v is num ? v.toInt() : _tetoEstimativaCents;
  }

  Map<String, dynamic>? get _aprovacao {
    final a = _teto?['aprovacao'];
    return a is Map ? Map<String, dynamic>.from(a) : null;
  }

  String? get _estadoAprovacao => _aprovacao?['estado'] as String?;
  String? get _budgetStatus => _teto?['budget_status'] as String?;

  /// À espera do cliente: pedido novo com prazo, ou pedido antigo sem prazo.
  bool get _pendente =>
      _estadoAprovacao == 'pendente' ||
      (_aprovacao == null && _budgetStatus == 'pending');

  bool get _esperaMbway => _teto?['espera_pagamento_mbway'] == true;

  bool get _cancelado =>
      _cancelamentoPedido || _estadoAprovacao == 'cancelar';

  int get _segundosRestantes {
    final fim = _expiraLocal;
    if (fim == null) return 0;
    final ms = fim.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  Future<void> _refreshTeto({bool forcar = false}) async {
    final emCurso = _tetoEmCurso;
    if (emCurso != null) {
      // O poll salta; um pedido explícito espera e volta a ler (senão uma
      // leitura velha em curso podia ficar por cima da resposta nova).
      if (!forcar) return;
      await emCurso;
      if (!mounted) return;
    }
    final f = _lerTeto();
    _tetoEmCurso = f;
    try {
      await f;
    } finally {
      if (identical(_tetoEmCurso, f)) _tetoEmCurso = null;
    }
  }

  Future<void> _lerTeto() async {
    final id = widget.order.id;
    Map<String, dynamic>? novo;
    try {
      if (!_tetoAntigo) {
        try {
          final res = await Supabase.instance.client.rpc(
            'errand_teto_compra',
            params: {'p_order_id': id},
          );
          if (res is Map && res['ok'] == true) {
            novo = Map<String, dynamic>.from(res);
          } else {
            debugPrint('[favor] tecto: $res');
          }
        } on PostgrestException catch (e) {
          debugPrint('[favor] tecto: ${e.code} ${e.message}');
          // Função ainda não está no servidor → caminho antigo.
          if (_funcaoEmFalta(e)) _tetoAntigo = true;
        }
      }
      if (novo == null && _tetoAntigo) {
        final row = await Supabase.instance.client
            .from('orders')
            .select('errand_budget_status, errand_budget_requested_cents')
            .eq('id', id)
            .maybeSingle();
        final s = row?['errand_budget_status'] as String?;
        final pedido =
            (row?['errand_budget_requested_cents'] as num?)?.toInt();
        final base = _tetoEstimativaCents;
        novo = {
          'budget_status': s,
          'pedido_cents': pedido,
          'teto_cents': (s == 'approved' && pedido != null && pedido > base)
              ? pedido
              : base,
        };
      }
    } catch (e) {
      debugPrint('[favor] tecto: $e');
    }
    if (!mounted) return;
    final lido = novo;
    setState(() {
      _tetoCarregado = true;
      if (lido != null) {
        _teto = lido;
        _acertarRelogio();
      }
    });
    _acertarTimers();
    _publicar();
  }

  /// Fim do prazo do cliente no relógio do telemóvel, a partir dos segundos
  /// que o servidor diz que faltam (não depende do relógio do telemóvel
  /// bater certo com o do servidor). Só acerta se fugiu mais de 2 s.
  void _acertarRelogio() {
    final a = _aprovacao;
    if (a == null || a['estado'] != 'pendente') {
      _expiraLocal = null;
      return;
    }
    DateTime? fim;
    final seg = a['segundos_restantes'];
    if (seg is num) {
      fim = DateTime.now().add(Duration(seconds: seg.toInt()));
    } else if (a['expira_em'] is String) {
      fim = DateTime.tryParse(a['expira_em'] as String)?.toLocal();
    }
    if (fim == null) return;
    final atual = _expiraLocal;
    if (atual == null || atual.difference(fim).inSeconds.abs() > 2) {
      _expiraLocal = fim;
    }
  }

  void _acertarTimers() {
    if (!mounted) return;
    if (_pendente || _esperaMbway) {
      _poll ??= Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) unawaited(_refreshTeto());
      });
    } else {
      _poll?.cancel();
      _poll = null;
    }
    if (_estadoAprovacao == 'pendente' && _segundosRestantes > 0) {
      _contagem ??= Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {});
        if (_segundosRestantes <= 0) {
          t.cancel();
          _contagem = null;
        }
      });
    } else {
      _contagem?.cancel();
      _contagem = null;
    }
  }

  void _publicar() {
    widget.controller?._atualizar(
      tetoCents: _tetoCarregado ? _tetoCents : null,
      cancelado: _cancelado,
      esperaMbway: _esperaMbway,
    );
  }

  // ── "O preço é maior" ────────────────────────────────────────────────

  Future<void> _precoMaior() async {
    final r = await showDialog<_PrecoMaior>(
      context: context,
      builder: (_) => _PrecoMaiorDialog(tetoCents: _tetoCents),
    );
    if (r == null || !mounted) return;
    setState(() {
      _busy = true;
      _erro = null;
      _info = null;
    });
    try {
      if (_tetoAntigo) {
        await _pedirAntigo(r.cents);
      } else {
        await _pedirNovo(r.cents, r.foto);
      }
      await _refreshTeto(forcar: true);
    } on PostgrestException catch (e) {
      debugPrint('[favor] pedir aprovação: ${e.code} ${e.message}');
      if (_funcaoEmFalta(e) && !_tetoAntigo) {
        // Função nova ainda não está no servidor → caminho antigo.
        _tetoAntigo = true;
        try {
          await _pedirAntigo(r.cents);
          await _refreshTeto(forcar: true);
        } catch (e2) {
          debugPrint('[favor] pedir aumento (antigo): $e2');
          if (mounted) setState(() => _erro = _textoErro(null));
        }
      } else if (mounted) {
        setState(() => _erro = _textoErro(null));
      }
    } catch (e) {
      debugPrint('[favor] pedir aprovação: $e');
      if (mounted) setState(() => _erro = _textoErro(null));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pedirNovo(int cents, File? foto) async {
    String? fotoUrl;
    var fotoFalhou = false;
    if (foto != null) {
      try {
        // Mesmo caminho da foto de entrega do estafeta (upload-order-photo).
        fotoUrl = await OrderPhotoUploadService.uploadOrderPhoto(
          photoFile: foto,
          pathPrefix: 'favor_preco_${widget.order.id}',
        );
      } catch (e) {
        // Segue sem a foto: o cliente está à espera e o valor é o que conta.
        debugPrint('[favor] foto da etiqueta: $e');
        fotoFalhou = true;
      }
    }
    final res = await Supabase.instance.client.rpc(
      'estafeta_favor_pedir_aprovacao',
      params: {
        'p_order_id': widget.order.id,
        'p_novo_total_cents': cents,
        'p_foto_url': fotoUrl,
      },
    );
    if (!mounted) return;
    final m = res is Map ? res : const <String, dynamic>{};
    if (m['ok'] == true && m['dentro_do_teto'] == true) {
      const txt = 'Está dentro do limite: podes comprar.';
      setState(() => _info = txt);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(txt)));
    } else if (m['ok'] == true) {
      if (fotoFalhou) {
        setState(() => _info =
            'Pedido enviado sem a foto da etiqueta (o envio da foto falhou).');
      }
    } else if (m['error'] == 'pedido_em_curso') {
      setState(() => _info = 'Já há um pedido à espera do cliente.');
    } else {
      setState(() => _erro = _textoErro(m['error'] as String?));
    }
  }

  /// Caminho de antes da M1 (sem prazo nem foto), só enquanto as funções
  /// novas não estiverem no servidor.
  Future<void> _pedirAntigo(int cents) async {
    await Supabase.instance.client.rpc(
      'errand_request_budget_increase',
      params: {'p_order_id': widget.order.id, 'p_new_total_cents': cents},
    );
    if (!mounted) return;
    setState(() => _info =
        'Pedido enviado ao cliente. Aguarda a autorização antes de comprar.');
  }

  /// A função ainda não existe no servidor (migração por aplicar).
  static bool _funcaoEmFalta(PostgrestException e) =>
      e.code == 'PGRST202' ||
      e.message.contains('Could not find the function');

  static String _textoErro(String? codigo) => switch (codigo) {
        'valor_invalido' => 'Escreve um valor válido, por exemplo 15,40.',
        'pedido_fechado' => 'Este pedido já está fechado.',
        'favor_sem_compra' => 'Este Favor não tem compra.',
        'compra_ja_fechada' => 'A compra deste Favor já foi confirmada.',
        'nao_e_o_teu_pedido' => 'Este pedido não está atribuído a ti.',
        'auth_required' => 'A sessão expirou. Entra de novo na app.',
        _ => 'Não foi possível pedir a aprovação. Verifica a ligação e '
            'tenta de novo.',
      };

  // ── O cliente não respondeu a tempo ──────────────────────────────────

  Future<void> _semResposta(String escolha) async {
    if (escolha == 'cancelar') {
      final taxa =
          (_teto?['taxa_cancelar_sem_resposta_cents'] as num?)?.toInt();
      final taxaTxt = taxa != null
          ? 'a taxa de deslocação de ${eurCents(taxa)}'
          : 'a taxa de deslocação';
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar o Favor?'),
          content: Text(
            'O cliente não respondeu. Vamos pedir o cancelamento do Favor e '
            '$taxaTxt é cobrada ao cliente.\n\nNão compres nada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cancelar Favor'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _erro = null;
      _info = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'estafeta_favor_sem_resposta',
        params: {'p_order_id': widget.order.id, 'p_escolha': escolha},
      );
      if (!mounted) return;
      final m = res is Map ? res : const <String, dynamic>{};
      if (m['ok'] == true) {
        if (escolha == 'cancelar') {
          setState(() => _cancelamentoPedido = true);
          _publicar();
        }
      } else if (m['error'] == 'ainda_a_espera') {
        setState(() => _info = 'O cliente ainda tem tempo para responder.');
      } else if (m['error'] == 'sem_pedido_pendente') {
        setState(() => _info = 'O cliente acabou de responder.');
      } else {
        setState(() =>
            _erro = 'Não foi possível guardar a escolha. Tenta de novo.');
      }
      await _refreshTeto(forcar: true);
    } catch (e) {
      debugPrint('[favor] sem resposta ($escolha): $e');
      if (mounted) {
        setState(() => _erro =
            'Não foi possível guardar a escolha. Verifica a ligação e tenta '
            'de novo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Desenho ──────────────────────────────────────────────────────────

  static String _mmss(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Widget _aviso(String texto, Color cor) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cor),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );

  List<Widget> _linhasTeto() {
    if (!_tetoCarregado) {
      return const [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'A ver até quanto podes comprar…',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ];
    }
    final teto = _tetoCents;
    if (teto <= 0) {
      return const [
        Text(
          'Limite da compra por definir. Se o total passar a estimativa, '
          'carrega em «O preço é maior» antes de pagar.',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ];
    }
    return [
      Text(
        'Podes comprar até ${eurCents(teto)}',
        key: const Key('favor_teto_valor'),
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Nunca pagues do teu bolso acima deste valor.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    ];
  }

  List<Widget> _linhasAprovacao() {
    if (!_tetoCarregado) return const [];
    final estado = _estadoAprovacao;

    if (_cancelado) {
      final peloEstafeta = _cancelamentoPedido ||
          _aprovacao?['respondido_por'] == 'estafeta_sem_resposta';
      return [
        _aviso(
          peloEstafeta
              ? 'Pedido de cancelamento enviado. Não compres nada.'
              : 'O Favor vai ser cancelado. Não compres nada.',
          AppColors.error,
        ),
      ];
    }

    if (_pendente) {
      final pedido = (_aprovacao?['pedido_cents'] as num?)?.toInt() ??
          (_teto?['pedido_cents'] as num?)?.toInt();
      final linhas = <Widget>[const SizedBox(height: 12)];
      if (pedido != null) {
        linhas.add(Text(
          'Pediste aprovação para ${eurCents(pedido)}.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ));
      }
      final comPrazo = estado == 'pendente' && _expiraLocal != null;
      final s = _segundosRestantes;
      if (comPrazo && s > 0) {
        linhas.addAll([
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  color: AppColors.warning, size: 28),
              const SizedBox(width: 8),
              Text(
                _mmss(s),
                key: const Key('favor_aprovacao_contagem'),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'O cliente foi avisado, aguarda a resposta aqui',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ]);
      } else if (comPrazo) {
        linhas.addAll([
          const SizedBox(height: 6),
          const Text(
            'O cliente não respondeu a tempo. Escolhe:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('favor_sem_resposta_so_ate_teto'),
            onPressed: _busy ? null : () => _semResposta('so_ate_teto'),
            child: Text('Comprar só até ${eurCents(_tetoCents)}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('favor_sem_resposta_cancelar'),
            onPressed: _busy ? null : () => _semResposta('cancelar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
            child: const Text('Cancelar Favor'),
          ),
        ]);
      } else {
        linhas.addAll(const [
          SizedBox(height: 6),
          Text(
            'À espera da autorização do cliente…',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ]);
      }
      return linhas;
    }

    final linhas = <Widget>[];
    if (_esperaMbway) {
      linhas.add(_aviso(
        'Aprovado — espera que o cliente pague a diferença por MB Way. '
        'Compra só depois de aparecer pago.',
        AppColors.warning,
      ));
    } else if (estado == 'aprovado' ||
        (estado == null && _budgetStatus == 'approved')) {
      linhas.add(_aviso(
        'Aprovado: podes comprar até ${eurCents(_tetoCents)}',
        AppColors.success,
      ));
    } else if (estado == 'so_ate_teto') {
      linhas.add(_aviso(
        'Compra só até ${eurCents(_tetoCents)}',
        AppColors.warning,
      ));
    } else if (estado == null && _budgetStatus == 'rejected') {
      // Caminho antigo (sem aprovacao): o cliente recusou.
      linhas.add(_aviso(
        'Recusado — não compres; cancela o favor.',
        AppColors.error,
      ));
    }
    if (!_esperaMbway) {
      linhas.addAll([
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('favor_preco_maior'),
          onPressed: _busy ? null : _precoMaior,
          icon: const Icon(Icons.trending_up),
          label: Text(_busy ? 'A enviar…' : 'O preço é maior'),
        ),
        const SizedBox(height: 4),
        const Text(
          'Só se o total vai passar o limite. Pede ANTES de pagar.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ]);
    }
    return linhas;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('favor_teto_compra_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._linhasTeto(),
          ..._linhasAprovacao(),
          if (_info != null) ...[
            const SizedBox(height: 8),
            Text(
              _info!,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary),
            ),
          ],
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(_erro!,
                style: const TextStyle(fontSize: 13, color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}

// ── Diálogo "O preço é maior": novo total + foto da etiqueta (opcional) ──

typedef _PrecoMaior = ({int cents, File? foto});

class _PrecoMaiorDialog extends StatefulWidget {
  const _PrecoMaiorDialog({required this.tetoCents});

  final int tetoCents;

  @override
  State<_PrecoMaiorDialog> createState() => _PrecoMaiorDialogState();
}

class _PrecoMaiorDialogState extends State<_PrecoMaiorDialog> {
  final _ctrl = TextEditingController();
  File? _foto;
  String? _erro;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Mesma câmara protegida da foto do talão (SafeImagePicker ignora o
  /// segundo toque em vez de rebentar com `already_active`).
  Future<void> _tirarFoto() async {
    try {
      final x = await SafeImagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (x == null || !mounted) return;
      final path = x.path;
      setState(() {
        _foto = File(path);
        _erro = null;
      });
    } catch (e) {
      debugPrint('[favor] câmara (etiqueta): $e');
      if (mounted) {
        setState(() =>
            _erro = 'Não foi possível abrir a câmara. Tenta de novo.');
      }
    }
  }

  void _enviar() {
    final cents = valorEmCentimos(_ctrl.text);
    if (cents == null) {
      setState(() => _erro = 'Escreve o novo total, por exemplo 15,40.');
      return;
    }
    Navigator.pop<_PrecoMaior>(context, (cents: cents, foto: _foto));
  }

  @override
  Widget build(BuildContext context) {
    final foto = _foto;
    return AlertDialog(
      title: const Text('O preço é maior'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tetoCents > 0
                  ? 'Podias comprar até ${eurCents(widget.tetoCents)}. '
                      'Escreve o novo total e, se puderes, tira foto da '
                      'etiqueta do preço. O cliente é avisado na hora.'
                  : 'Escreve o novo total e, se puderes, tira foto da '
                      'etiqueta do preço. O cliente é avisado na hora.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('favor_preco_maior_valor'),
              controller: _ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [ValorEmEurosInputFormatter()],
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Novo total',
                suffixText: '€',
                errorText: _erro,
              ),
            ),
            const SizedBox(height: 10),
            if (foto == null)
              OutlinedButton.icon(
                onPressed: _tirarFoto,
                icon: const Icon(Icons.photo_camera),
                label: const Text('Foto da etiqueta (opcional)'),
              )
            else
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image(
                      image: boraLocalImage(foto.path),
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton(
                    onPressed: _tirarFoto,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'Tirar nova foto',
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _enviar,
          child: const Text('Pedir aprovação'),
        ),
      ],
    );
  }
}
