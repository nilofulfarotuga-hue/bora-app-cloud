import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/cleaning_models.dart';
import '../../../stores/cleaning_store.dart';
import '../../../utils/hora_lisboa.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/cleaning_chat_button.dart';
import '../../../widgets/selo_serie_limpeza.dart';
import '../../../widgets/ver_nas_minhas_reservas.dart';
import 'cleaning_payment_flow.dart';

import '../../../l10n/tr.dart';

/// LIMPEZA — acompanhamento da reserva (realtime via CleaningStore.trackBooking).
/// Timeline de estados + detalhes + ações do cliente (cancelar / confirmar /
/// avaliar). As transições são todas RPCs; aqui só se reage.
class CleaningTrackingScreen extends StatefulWidget {
  const CleaningTrackingScreen({
    super.key,
    required this.booking,
    this.acabadaDeMarcar = false,
  });

  final CleaningBooking booking;

  /// Aberto logo a seguir a marcar: mostra a faixa "Limpeza marcada" com o
  /// botão para o separador Reservas (10/10/2026).
  final bool acabadaDeMarcar;

  @override
  State<CleaningTrackingScreen> createState() => _CleaningTrackingScreenState();
}

class _CleaningTrackingScreenState extends State<CleaningTrackingScreen> {
  Map<String, dynamic>? _cleanerProfile;

  /// Equipa (19/11/2026): nome da profissional de cada vaga (id da reserva →
  /// nome), lido pela RPC pública da profissional.
  final Map<String, String> _nomesEquipa = {};

  /// Relê as vagas da equipa e os nomes de quem já aceitou.
  Future<void> _carregarEquipa() async {
    final b = _booking;
    final g = b.teamGroupId;
    if (!b.isTeam || g == null) return;
    final store = context.read<CleaningStore>();
    final team = await store.loadTeam(g);
    for (final t in team) {
      if (t.cleanerId == null || _nomesEquipa.containsKey(t.id)) continue;
      final nome = await store.cleanerNameOf(t.id);
      if (!mounted) return;
      if (nome != null && nome.isNotEmpty) {
        setState(() => _nomesEquipa[t.id] = nome);
      }
    }
  }
  // Regra de cancelamento de 24/11/2026: lidos das definições do servidor
  // (os mesmos valores por omissão que o `cancel_cleaning_booking` usa).
  int _cancelDeslocacaoMinCents = 500;
  int _cancelAtrasoMinutos = 15;
  bool _rated = false;

  /// Trava de re-entrada LOCAL deste ecrã (PADRAO_BORA 3.13).
  ///
  /// Os botões daqui estavam presos ao `busy` global do `CleaningStore` — um
  /// flag único que CINCO operações mexem (`createBooking`, `confirmCompleted`,
  /// `cancelBooking`, `cancelSeries`, `rateCleaner`). Bastava uma delas para
  /// o botão de outra nascer desligado: a mesma cicatriz da corrida real de
  /// 05/09/2026, agora num ecrã de dinheiro.
  ///
  /// Pior: o `busy` global **nunca** era ligado pelo pagamento
  /// (`createCardPayment` / `createMbwayPayment` / `markPaymentHeld` não
  /// chamam `_setBusy`), por isso o botão "Pagar agora" corria sem trava
  /// nenhuma. Esta trava fecha ANTES do primeiro `await` e só abre no
  /// `finally`, logo um segundo toque nunca chega ao servidor.
  ///
  /// É UMA trava para as quatro ações porque todas mexem na MESMA reserva —
  /// pagar enquanto se cancela era um cruzamento possível. O que se perdeu foi
  /// só a contaminação de operações de fora deste ecrã.
  bool _acaoEmCurso = false;

  /// Mesmo desenho do `UnifiedCheckoutButton` (`_loading` + saída à entrada):
  /// tranca, corre, e destranca sempre — inclusive quando a ação desiste a
  /// meio (diálogo fechado) ou rebenta.
  Future<void> _comTrava(Future<void> Function() acao) async {
    if (_acaoEmCurso) return;
    setState(() => _acaoEmCurso = true);
    try {
      await acao();
    } finally {
      if (mounted) setState(() => _acaoEmCurso = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final store = context.read<CleaningStore>();
      store.trackBooking(widget.booking);
      _carregarSerie();
      await _lerRegraCancelamento();
      if (!mounted) return;
      _loadCleanerProfile();
      _carregarEquipa();
    });
  }

  @override
  void dispose() {
    // Não usar context aqui — o store sobrevive ao ecrã; limpar só o canal
    // é seguro via clearTracked chamado pelo próximo trackBooking.
    super.dispose();
  }

  // read (não watch): este getter é usado em callbacks; o build observa o
  // store diretamente e rebuilda quando o realtime substitui a reserva.
  CleaningBooking get _booking =>
      context.read<CleaningStore>().tracked ?? widget.booking;

  /// S1 (01/11/2026): estado da série (parada? próxima data?). Só nas
  /// marcações recorrentes; o resultado fica no store e o build observa-o.
  Future<void> _carregarSerie() async {
    final gid = _booking.recurrenceGroupId;
    if (!_booking.isRecurring || gid == null) return;
    final store = context.read<CleaningStore>();
    // A "próxima" prefere a irmã já marcada: sem a lista (ecrã aberto de
    // fora), carrega-a antes.
    if (store.bookings.isEmpty) await store.loadMyBookings();
    await store.estadoDaSerie(gid);
  }

  /// Perfil público da profissional atribuída (RPC própria — RLS não expõe
  /// a tabela cleaners a clientes).
  Future<void> _loadCleanerProfile() async {
    final b = context.read<CleaningStore>().tracked ?? widget.booking;
    if (b.cleanerId == null) return;
    try {
      final res = await Supabase.instance.client.rpc(
        'cleaning_booking_cleaner_public',
        params: {'p_booking_id': b.id},
      );
      if (!mounted || res == null) return;
      setState(() => _cleanerProfile = Map<String, dynamic>.from(res as Map));
    } catch (e) {
      debugPrint('cleaning_booking_cleaner_public error => $e');
    }
  }

  // ── ações ────────────────────────────────────────────────────────────────

  /// Lê do servidor os números da regra de cancelamento (24/11/2026).
  Future<void> _lerRegraCancelamento() async {
    final store = context.read<CleaningStore>();
    final minimo = await store.getSettingInt(
        'cleaning_cancel_travel_comp_cents', _cancelDeslocacaoMinCents);
    final atraso = await store.getSettingInt(
        'cleaning_pro_late_no_fee_minutes', _cancelAtrasoMinutos);
    if (!mounted) return;
    setState(() {
      _cancelDeslocacaoMinCents = minimo;
      _cancelAtrasoMinutos = atraso;
    });
  }

  /// O que o cliente paga se cancelar agora (regra de 24/11/2026). Só para
  /// mostrar: o valor final é SEMPRE decidido no servidor.
  CancelamentoLimpeza _previsaoCancelamento(CleaningBooking b) {
    final equipa = context.read<CleaningStore>().teamOf(b);
    // O servidor cancela a equipa toda pela vaga 1: a conta parte sempre dela.
    final principal = b.isTeamSister
        ? equipa.firstWhere((v) => v.teamSlot == 1, orElse: () => b)
        : b;
    return CancelamentoLimpeza.calcular(
      principal: principal,
      equipa: equipa,
      agora: DateTime.now(),
      minimoCents: _cancelDeslocacaoMinCents,
      atrasoMinutos: _cancelAtrasoMinutos,
    );
  }

  /// Texto do aviso antes de confirmar o cancelamento.
  String _cancelFeePreview(CleaningBooking b) {
    final p = _previsaoCancelamento(b);
    if (p.profissionalAtrasada) {
      return 'Cancelamento grátis: a profissional ainda não começou {0} minutos depois da hora marcada.'
          .trArgs([_cancelAtrasoMinutos]);
    }
    if (p.gratis) {
      return 'Cancelamento grátis: a profissional ainda não está a caminho.'.tr;
    }
    final taxa = CleaningLabels.euro(p.taxaClienteCents);
    final quem = p.profissionaisACaminho > 1
        ? '{0} profissionais já estão a caminho.'
            .trArgs([p.profissionaisACaminho])
        : 'A profissional já está a caminho.'.tr;
    var texto = '$quem ${'Se cancelares agora, pagas só a deslocação: {0}.'.trArgs([taxa])}';
    final pagoPorApp = b.paymentStatus == 'held' &&
        (b.paymentMethod == 'card' || b.paymentMethod == 'mbway');
    if (pagoPorApp) {
      final volta = CancelamentoLimpeza.devolvidoCents(
          b.totalCents, p.taxaClienteCents);
      if (volta > 0) {
        texto +=
            '\n${'O resto ({0}) volta para o teu cartão ou MB WAY.'.trArgs([CleaningLabels.euro(volta)])}';
      }
    }
    return texto;
  }

  Future<void> _cancel() => _comTrava(_cancelarReserva);

  Future<void> _cancelarReserva() async {
    final store = context.read<CleaningStore>();
    // A taxa depende de a profissional já estar a caminho: relê o estado (e o
    // da equipa) antes de mostrar o valor, para não avisar com dados velhos.
    await store.refreshTracked();
    final g = _booking.teamGroupId;
    if (_booking.isTeam && g != null) await store.loadTeam(g);
    if (!mounted) return;
    final b = _booking;
    // S2 (01/11/2026): numa série, cancelar é SÓ esta limpeza — a série
    // continua (o servidor já não a mata). Para acabar com ela, o segundo
    // botão leva ao "Parar a série toda".
    final emSerie = b.isRecurring &&
        b.recurrenceGroupId != null &&
        store.serieEmCache(b.recurrenceGroupId!)?.parada != true;
    final escolha = await showDialog<_EscolhaCancelar>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar limpeza?'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (emSerie) ...[
              Text(
                'Cancelas só esta limpeza. A série continua na próxima data.'
                    .tr,
                key: const Key('limpeza_cancelar_so_esta'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Spacing.sm),
            ],
            Text(_cancelFeePreview(b)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _EscolhaCancelar.manter),
            child: Text('Manter'.tr),
          ),
          if (emSerie)
            TextButton(
              key: const Key('limpeza_cancelar_parar_serie'),
              onPressed: () => Navigator.pop(ctx, _EscolhaCancelar.serie),
              child: Text('Parar a série toda'.tr,
                  style: const TextStyle(color: AppColors.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _EscolhaCancelar.esta),
            child: Text('Cancelar limpeza'.tr,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (escolha == _EscolhaCancelar.serie) {
      // Já dentro da trava do _cancel: chama o fluxo direto (o _cancelSeries
      // voltaria para trás por a trava estar fechada).
      await _pararSerie();
      return;
    }
    if (escolha != _EscolhaCancelar.esta) return;
    try {
      final cancelada = await store.cancelBooking(b.id);
      // Liberta a retenção do cartão / estorna MB Way (no-op sem PI): o
      // servidor devolve o total menos a taxa de deslocação, se houver.
      // Prémio do check-in: não houve pagamento; o vale volta sozinho.
      if (b.paymentMethod != 'cash' && b.paymentMethod != 'premio') {
        store.reversePayment(cancelada?.id ?? b.id);
      }
      if (!mounted) return;
      // O valor que conta é o do servidor (a profissional pode ter saído
      // entre o aviso e a confirmação).
      final taxa = cancelada?.cancelFeeCents ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(taxa > 0
                ? 'Limpeza cancelada. Taxa de deslocação: {0}.'
                    .trArgs([CleaningLabels.euro(taxa)])
                : 'Limpeza cancelada, sem custos.'.tr)),
      );
      // A série continua: volta a ler a próxima data.
      _carregarSerie();
    } catch (_) {
      if (!mounted) return;
      // Nunca deixar o botão "mudo" (2026-08-16): ressincroniza com o
      // servidor — se a reserva já estava cancelada (outro device / backend),
      // isso é sucesso do ponto de vista do cliente.
      await store.refreshTracked();
      if (!mounted) return;
      final agora = store.tracked;
      if (agora != null && agora.id == b.id && agora.status.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A limpeza já estava cancelada.'.tr)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível cancelar.'.tr)),
      );
    }
  }

  /// Liga à profissional (tel:) — número vem do perfil público pós-aceitação.
  Future<void> _callCleaner() async {
    final phone = _cleanerProfile?['phone'] as String?;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Retoma o pagamento pendente (cartão/MB Way) a partir do tracking.
  Future<void> _payNow() => _comTrava(_pagarAgora);

  Future<void> _pagarAgora() async {
    final store = context.read<CleaningStore>();
    final ok = await CleaningPaymentFlow.pay(context, store, _booking);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pagamento confirmado. 💚'.tr)),
      );
      store.loadMyBookings();
    }
  }

  Future<void> _cancelSeries() => _comTrava(_pararSerie);

  Future<void> _pararSerie() async {
    final b = _booking;
    final groupId = b.recurrenceGroupId;
    if (groupId == null) return;
    final store = context.read<CleaningStore>();
    // 02/11/2026 (zerar B2): o servidor diz o que vai cancelar e quanto volta.
    // 09/11/2026 (M10 b2): o que volta vai para a Carteira Bora (servidor).
    final previsao = await store.previsaoSerie(groupId);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Parar a recorrência?'.tr),
        // Texto igual ao que o cancel_cleaning_series faz (01/11/2026): o
        // anterior dizia "a limpeza atual mantém-se", mas a atual também é
        // cancelada quando faltam mais de 24 h.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Não se marcam mais limpezas desta série. As já marcadas para daqui a mais de 24 h são canceladas; as das próximas 24 h mantêm-se.'
                    .tr),
            if (previsao.devolveCents > 0) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Devolvemos {0} à tua Carteira Bora, podes usar já.'
                    .trArgs([CleaningLabels.euro(previsao.devolveCents)]),
                key: const Key('limpeza_parar_serie_devolve'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Manter'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Parar série'.tr,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await store.cancelSeries(groupId);
      // Esta limpeza pode ter sido cancelada pelo servidor (mais de 24 h).
      await store.refreshTracked();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(previsao.devolveCents > 0
                ? 'Recorrência cancelada. Devolvemos {0} à tua Carteira Bora, podes usar já.'
                    .trArgs([CleaningLabels.euro(previsao.devolveCents)])
                : 'Recorrência cancelada.'.tr)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível parar a série.'.tr)),
      );
    }
  }

  Future<void> _confirmDone() => _comTrava(_confirmarConclusao);

  /// Nota: `_askRating` fica DE FORA da trava de propósito — é chamado daqui
  /// dentro, e travá-lo também faria a avaliação sair sem abrir.
  Future<void> _confirmarConclusao() async {
    final store = context.read<CleaningStore>();
    final b = _booking;
    try {
      // Cartão/MB Way já foram cobrados na reserva (2026-07-05) — confirmar
      // só liberta os ganhos à profissional; não há captura Stripe.
      await store.confirmCompleted(b.id);
      if (!mounted) return;
      await _askRating();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível confirmar.'.tr)),
      );
    }
  }

  Future<void> _askRating() async {
    if (_rated) return;
    final store = context.read<CleaningStore>();
    var stars = 5;
    final commentCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Como correu a limpeza?'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setDialogState(() => stars = i),
                      icon: Icon(
                        i <= stars ? Icons.star : Icons.star_border,
                        color: AppColors.warning,
                        size: 30,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                    hintText: 'Comentário (opcional)'.tr),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Agora não'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Enviar'.tr),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;
    try {
      await store.rateCleaner(_booking.id, stars,
          comment: commentCtrl.text.trim());
      if (!mounted) return;
      setState(() => _rated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Obrigado pela avaliação! 💚'.tr)),
      );
    } catch (e) {
      if (!mounted) return;
      final already = e.toString().contains('already_rated');
      if (already) setState(() => _rated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(already
                ? 'Já avaliaste esta limpeza.'.tr
                : 'Não foi possível enviar a avaliação.')),
      );
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleaningStore>();
    final b = store.tracked ?? widget.booking;
    final emSerie = b.isRecurring && b.recurrenceGroupId != null;
    final serie = emSerie
        ? (store.serieEmCache(b.recurrenceGroupId!) ?? SerieEstado.desconhecido)
        : SerieEstado.desconhecido;
    // Recarrega o perfil quando a profissional é atribuída via realtime.
    if (b.cleanerId != null && _cleanerProfile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCleanerProfile();
      });
    }

    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Limpeza · {0}'.trArgs([b.status.labelPt]),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
            BoraBottomActionBar.folgaInferior(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.acabadaDeMarcar && !b.status.isCancelled) ...[
              ReservaMarcadaFaixa(titulo: 'Limpeza marcada!'.tr),
              const SizedBox(height: Spacing.lg),
            ],
            if (b.status.isCancelled)
              _CancelledBanner(booking: b)
            else
              _StatusTimeline(status: b.status),
            const SizedBox(height: Spacing.lg),
            if (!b.status.isCancelled &&
                b.paymentMethod != 'cash' &&
                b.paymentStatus == 'unpaid') ...[
              _PaymentPendingBanner(
                  busy: _acaoEmCurso,
                  mbway: b.paymentMethod == 'mbway',
                  onPay: _payNow),
              const SizedBox(height: Spacing.lg),
            ],
            if (b.isTeam) ...[
              _TeamCard(
                team: store.teamOf(b),
                nomes: _nomesEquipa,
                booking: b,
                onRefresh: _carregarEquipa,
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (b.cleanerId != null) ...[
              _CleanerCard(profile: _cleanerProfile, onCall: _callCleaner),
              // Chat disponível de "confirmada" até o cliente confirmar
              // (mesma janela da RLS de cleaning_messages).
              if (const [
                CleaningStatus.accepted,
                CleaningStatus.onTheWay,
                CleaningStatus.inProgress,
                CleaningStatus.done,
              ].contains(b.status)) ...[
                const SizedBox(height: Spacing.sm),
                CleaningChatButton(
                  bookingId: b.id,
                  myRole: 'client',
                  title: (_cleanerProfile?['name'] as String?)?.isNotEmpty ==
                          true
                      ? _cleanerProfile!['name'] as String
                      : 'A tua profissional'.tr,
                  otherPhone: _cleanerProfile?['phone'] as String?,
                  showPreview: true,
                ),
              ],
              const SizedBox(height: Spacing.lg),
            ],
            _DetailsCard(booking: b),
            const SizedBox(height: Spacing.lg),
            // S1 (01/11/2026): "Semanal · próxima: 08/11 10:00" ou "Série
            // parada" (cleaning_recurrence_stops / cleaning_series_next_at).
            if (emSerie) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: SeloLimpeza(
                  serie.parada
                      ? 'Série parada'.tr
                      : linhaSerieLimpeza(
                          b,
                          b.proximaDaSerie(store.bookings, serie.proxima,
                              agora: DateTime.now())),
                  key: const Key('limpeza_serie_linha'),
                  icone: serie.parada ? Icons.event_busy : Icons.repeat,
                  apagado: serie.parada,
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (b.status == CleaningStatus.done) ...[
              BoraPrimaryButton(
                label: 'Confirmar limpeza concluída'.tr,
                icon: Icons.check_circle,
                loading: _acaoEmCurso,
                onPressed: _confirmDone,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Confirma para libertar o pagamento à profissional. Sem confirmação, é confirmada automaticamente em 24 h.'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
              ),
            ],
            if (b.status == CleaningStatus.completed && !_rated)
              BoraPrimaryButton(
                label: 'Avaliar a profissional'.tr,
                icon: Icons.star,
                onPressed: _askRating,
              ),
            if (const [
              CleaningStatus.scheduled,
              CleaningStatus.accepted,
              CleaningStatus.onTheWay,
            ].contains(b.status)) ...[
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: _acaoEmCurso ? null : _cancel,
                child: Text('Cancelar limpeza'.tr,
                    style: const TextStyle(color: AppColors.error)),
              ),
            ],
            // S1: a série continua mesmo com esta limpeza cancelada ou feita —
            // o botão fica enquanto a série não estiver parada.
            if (emSerie && !serie.parada)
              TextButton(
                key: const Key('limpeza_parar_serie'),
                onPressed: _acaoEmCurso ? null : _cancelSeries,
                child: Text('Parar a série toda'.tr,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── widgets internos ────────────────────────────────────────────────────────

/// Resposta do diálogo "Cancelar limpeza?" (S2): manter, cancelar só esta,
/// ou parar a série toda.
enum _EscolhaCancelar { manter, esta, serie }

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});
  final CleaningStatus status;

  static const _steps = [
    (CleaningStatus.scheduled, 'Agendada', Icons.event_available),
    (CleaningStatus.accepted, 'Confirmada', Icons.how_to_reg),
    (CleaningStatus.onTheWay, 'A caminho', Icons.directions_walk),
    (CleaningStatus.inProgress, 'Em curso', Icons.cleaning_services),
    (CleaningStatus.completed, 'Concluída', Icons.check_circle),
  ];

  int get _currentIndex {
    switch (status) {
      case CleaningStatus.scheduled:
        return 0;
      case CleaningStatus.accepted:
        return 1;
      case CleaningStatus.onTheWay:
        return 2;
      case CleaningStatus.inProgress:
        return 3;
      case CleaningStatus.done:
      case CleaningStatus.completed:
        return 4;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      _steps[i].$3,
                      size: 22,
                      color: i <= current
                          ? AppColors.primary
                          : AppColors.textSubtle,
                    ),
                    if (i < _steps.length - 1)
                      Container(
                        width: 2,
                        height: 22,
                        color: i < current
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                  ],
                ),
                const SizedBox(width: Spacing.md),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _steps[i].$2,
                    style: TextStyle(
                      color: i <= current
                          ? AppColors.textPrimary
                          : AppColors.textSubtle,
                      fontWeight:
                          i == current ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PaymentPendingBanner extends StatelessWidget {
  const _PaymentPendingBanner(
      {required this.busy, required this.mbway, required this.onPay});
  final bool busy;

  /// 19/10/2026: com MB Way o botão diz o que faz (pedido MB Way no telemóvel).
  final bool mbway;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: AppColors.warning),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Pagamento pendente — conclui para garantires a tua limpeza.'.tr,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onPay,
            child: Text(mbway ? 'Pagar com MB Way'.tr : 'Pagar agora'.tr,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner({required this.booking});
  final CleaningBooking booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cancel, color: AppColors.error, size: 30),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.status.labelPt,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                if (booking.cancelFeeCents > 0)
                  Text(
                    booking.cancelledBy == 'client'
                        ? 'Taxa de deslocação (a profissional já estava a caminho): {0}'
                            .trArgs([CleaningLabels.euro(booking.cancelFeeCents)])
                        : 'Taxa de cancelamento: {0}'.trArgs([CleaningLabels.euro(booking.cancelFeeCents)]),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CleanerCard extends StatelessWidget {
  const _CleanerCard({required this.profile, required this.onCall});
  final Map<String, dynamic>? profile;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p?['name'] as String? ?? 'A tua profissional';
    final photo = p?['photo_url'] as String? ?? '';
    final rating = (p?['rating_avg'] as num?)?.toDouble() ?? 0;
    final count = (p?['ratings_count'] as num?)?.toInt() ?? 0;
    final done = (p?['cleanings_done'] as num?)?.toInt() ?? 0;
    final hasPhone = (p?['phone'] as String?)?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryWash,
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty
                ? const Icon(Icons.person, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text(
                  count > 0
                      ? '★ {0} ({1}) · {2} limpezas'.trArgs([rating.toStringAsFixed(1), count, done])
                      : done > 0
                          ? '{0} limpezas'.trArgs([done])
                          : 'Nova na plataforma',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (hasPhone)
            IconButton(
              onPressed: onCall,
              tooltip: 'Ligar'.tr,
              icon: const Icon(Icons.call, color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}

/// Equipa (19/11/2026): cada vaga com a sua profissional ("Maria ✓",
/// "Vaga 2 — à espera"), o chat com cada uma e, em dinheiro, quanto se
/// entrega a cada uma.
class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.nomes,
    required this.booking,
    required this.onRefresh,
  });
  final List<CleaningBooking> team;
  final Map<String, String> nomes;
  final CleaningBooking booking;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final vagas = team.isEmpty ? [booking] : team;
    final confirmadas = vagas.where((t) => t.cleanerId != null).length;
    final shares = {for (final t in vagas) t.myShareCents};
    return Container(
      key: const Key('limpeza_equipa_cartao'),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_outlined, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'A tua equipa · {0} de {1} confirmadas'
                      .trArgs([confirmadas, booking.teamSize]),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar'.tr,
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: onRefresh,
              ),
            ],
          ),
          for (final t in vagas)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        t.status.isCancelled
                            ? Icons.cancel_outlined
                            : t.cleanerId != null
                                ? Icons.check_circle
                                : Icons.hourglass_top,
                        size: 18,
                        color: t.cleanerId != null && !t.status.isCancelled
                            ? AppColors.primary
                            : AppColors.textSubtle,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          t.status.isCancelled
                              ? 'Vaga {0} — {1}'
                                  .trArgs([t.teamSlot, t.status.labelPt])
                              : t.cleanerId != null
                                  ? '{0} ✓ · {1}'.trArgs([
                                      nomes[t.id] ?? 'Vaga {0}'.trArgs([t.teamSlot]),
                                      t.status.labelPt,
                                    ])
                                  : 'Vaga {0} — à espera de profissional'
                                      .trArgs([t.teamSlot]),
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  // Cada profissional tem o seu chat (vaga 1 usa o de cima).
                  if (t.teamSlot > 1 &&
                      t.cleanerId != null &&
                      const [
                        CleaningStatus.accepted,
                        CleaningStatus.onTheWay,
                        CleaningStatus.inProgress,
                        CleaningStatus.done,
                      ].contains(t.status))
                    CleaningChatButton(
                      bookingId: t.id,
                      myRole: 'client',
                      title: nomes[t.id] ?? 'Vaga {0}'.trArgs([t.teamSlot]),
                    ),
                ],
              ),
            ),
          if (booking.paymentMethod == 'cash') ...[
            const SizedBox(height: Spacing.sm),
            Text(
              shares.length == 1
                  ? 'Em dinheiro: entregas {0} a cada profissional.'
                      .trArgs([CleaningLabels.euro(shares.first)])
                  : 'Em dinheiro: {0}.'.trArgs([
                      vagas
                          .map((t) => 'vaga ${t.teamSlot} ${CleaningLabels.euro(t.myShareCents)}')
                          .join(' · ')
                    ]),
              key: const Key('limpeza_equipa_dinheiro'),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.booking});
  final CleaningBooking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Serviço'.tr, '${b.typeLabel} · ${b.sizeLabel}'),
          _row('Quando'.tr, _fmtDateTime(b.scheduledAt)),
          _row('Onde'.tr,
              '${b.addressStreet}, ${b.addressCity} ${b.addressPostal}'),
          _row('Produtos'.tr,
              b.productsBy == 'cleaner' ? 'A profissional traz' : 'Do cliente'),
          if (b.isRecurring) _row('Recorrência'.tr, b.recurrenceLabel),
          _row(
              'Pagamento'.tr,
              switch (b.paymentMethod) {
                'card' => 'Cartão',
                'mbway' => 'MB Way',
                'premio' => 'Prémio do check-in (pago pela Bora)'.tr,
                _ => 'Dinheiro'.tr,
              }),
          if (b.notes.isNotEmpty) _row('Notas'.tr, b.notes),
          const Divider(height: Spacing.lg),
          if (b.isTeam) ...[
            // Equipa: o preço de uma profissional × N; produtos uma vez só;
            // cada profissional conduz e recebe a sua deslocação.
            _row('Equipa'.tr,
                '{0} profissionais × {1} h'.trArgs([b.teamSize, b.hours ?? 0])),
            _row('Trabalho'.tr,
                '{0} × {1}'.trArgs([b.teamSize, CleaningLabels.euro(b.perProWorkCents)])),
            if (b.teamProductsCents > 0)
              _row('Produtos'.tr, '+ ${CleaningLabels.euro(b.teamProductsCents)}'),
            if (b.travelFeeCents > 0)
              _row(CleaningLabels.travelFeeLabel(b.travelDistanceKm),
                  '+ {0} × {1}'.trArgs([b.teamSize, CleaningLabels.euro(b.travelFeeCents)])),
            _row('Total'.tr, CleaningLabels.euro(b.clientTotalCents), bold: true),
          ] else ...[
          _row('Base'.tr, CleaningLabels.euro(b.baseCents)),
          if (b.typeSurchargeCents > 0)
            _row('Suplemento'.tr, '+ ${CleaningLabels.euro(b.typeSurchargeCents)}'),
          if (b.recurringDiscountCents > 0)
            _row('Desconto'.tr,
                '- ${CleaningLabels.euro(b.recurringDiscountCents)}'),
          if (b.productsFeeCents > 0)
            _row('Produtos'.tr, '+ ${CleaningLabels.euro(b.productsFeeCents)}'),
          // Taxa de deslocação (19/11/2026): já dentro do total; km de estrada
          // gravados pelo servidor na reserva.
          if (b.travelFeeCents > 0)
            _row(CleaningLabels.travelFeeLabel(b.travelDistanceKm),
                '+ ${CleaningLabels.euro(b.travelFeeCents)}'),
          _row('Total'.tr, CleaningLabels.euro(b.totalCents), bold: true),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child:
                Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dia e hora em Lisboa de um instante (nunca a hora do telemóvel): o
  /// servidor e o painel mostram a mesma hora da limpeza.
  static String _fmtDateTime(DateTime instante) {
    final d = paredeLisboa(instante);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} às '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
