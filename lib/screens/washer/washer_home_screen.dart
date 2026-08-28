import '../../services/push_token_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/carwash_models.dart';
import '../../services/carwash_upload_service.dart';
import '../../stores/washer_store.dart';
import '../../utils/safe_image_picker.dart';
import '../shared/carwash_chat_screen.dart';
import 'washer_pickup_photos_screen.dart';

/// LAVAGEM AUTO — ecrã do lavador.
/// Ofertas rotativas com prazo + trabalho em curso com os botões de estado.
class WasherHomeScreen extends StatefulWidget {
  const WasherHomeScreen({super.key});

  @override
  State<WasherHomeScreen> createState() => _WasherHomeScreenState();
}

class _WasherHomeScreenState extends State<WasherHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Sem isto, quem for aprovado com a app JA ABERTA fica sem
    // aparelho registado ate reiniciar — e um pedido que chegue
    // nesse intervalo nao toca a ninguem. O portao de autenticacao
    // no main.dart apanha o arranque; isto apanha o meio da sessao.
    PushTokenService.registerForRole('washer').ignore();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<WasherStore>();
      await s.loadProfile();
      await s.refreshAll();
    });
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _erro(String? msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? 'Não foi possível concluir.')),
    );
  }

  Future<void> _avancar(CarwashBooking b) async {
    final store = context.read<WasherStore>();
    bool ok = false;

    switch (b.status) {
      case CarwashStatus.accepted:
        ok = await store.markOnTheWay(b.id);
      case CarwashStatus.onTheWay:
        // As 4 fotos vivem no ecrã próprio; ele é que chama markPickedUp.
        final feito = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => WasherPickupPhotosScreen(booking: b),
          ),
        );
        ok = feito == true;
      case CarwashStatus.pickedUp:
        ok = await store.markStarted(b.id);
      case CarwashStatus.inProgress:
        final fotos = await _pedirFotosDepois();
        ok = await store.markDelivering(b.id, photos: fotos);
      case CarwashStatus.delivering:
        ok = await store.markDelivered(b.id);
      default:
        return;
    }
    if (!ok) _erro(store.lastError);
  }

  /// Fotos do "depois" — OPCIONAIS. O ecrã convida, não obriga.
  Future<List<CarwashPhoto>> _pedirFotosDepois() async {
    // Lido ANTES do primeiro await: o context nao atravessa o gap assincrono.
    final b = context.read<WasherStore>().activeJob;
    if (b == null) return const [];

    final quer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mostre como ficou'),
        content: const Text(
          'Quer juntar fotos do carro lavado? O cliente gosta de ver — '
          'mas é à sua escolha.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Agora não')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tirar fotos')),
        ],
      ),
    );
    if (quer != true) return const [];

    final out = <CarwashPhoto>[];
    for (var i = 0; i < 3; i++) {
      final f = await SafeImagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (f == null) break;
      try {
        final path = await CarwashUploadService.upload(
          f,
          bookingId: b.id,
          kind: 'after',
          tag: 'depois$i',
        );
        out.add(CarwashPhoto(angle: '', url: path));
      } catch (_) {/* opcional — segue sem esta */}
      if (!mounted) break;
      final mais = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('Quer tirar mais uma?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Chega')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mais uma')),
          ],
        ),
      );
      if (mais != true) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WasherStore>();

    if (!store.isWasher) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Lavagem Auto'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(Spacing.xxl),
            child: Text(
              'A tua conta ainda não está registada como lavador.\n'
              'Fala com a equipa Bora.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    final ativos = store.jobs.where((j) => j.status.isActive).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lavagem Auto'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            if (!store.isApproved)
              Container(
                padding: const EdgeInsets.all(Spacing.lg),
                margin: const EdgeInsets.only(bottom: Spacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'A tua conta ainda está por aprovar. '
                  'Assim que for aprovada começas a receber pedidos.',
                ),
              ),

            if (store.offers.isNotEmpty) ...[
              const _Seccao('Pedidos para ti'),
              for (final o in store.offers)
                _OfertaCard(
                  booking: o,
                  onAccept: () async {
                    final ok = await store.accept(o.id);
                    if (!ok) _erro(store.lastError);
                  },
                  onReject: () async {
                    final ok = await store.reject(o.id);
                    if (!ok) _erro(store.lastError);
                  },
                ),
              const SizedBox(height: Spacing.lg),
            ],

            if (ativos.isNotEmpty) ...[
              const _Seccao('A decorrer'),
              for (final j in ativos)
                _TrabalhoCard(
                  booking: j,
                  onAvancar: () => _avancar(j),
                  onCall: () => _call(j.clientPhone),
                  onChat: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CarwashChatScreen(
                        bookingId: j.id,
                        myRole: 'washer',
                        title: 'Cliente',
                        otherPhone: j.clientPhone,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
            ],

            if (store.offers.isEmpty && ativos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.huge),
                child: Center(
                  child: Text('Sem pedidos de momento.',
                      style: TextStyle(color: AppColors.textSubtle)),
                ),
              ),

            if (store.jobs.any((j) => !j.status.isActive)) ...[
              const _Seccao('Feitos'),
              for (final j in store.jobs.where((j) => !j.status.isActive).take(10))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline,
                      color: AppColors.textSubtle),
                  title: Text('${j.plate} · ${j.serviceType.label}'),
                  subtitle: Text(j.status.clientLabel),
                  trailing: Text('${j.washerEarningsEur.toStringAsFixed(2)} €',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Seccao extends StatelessWidget {
  const _Seccao(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      );
}

class _OfertaCard extends StatelessWidget {
  const _OfertaCard({
    required this.booking,
    required this.onAccept,
    required this.onReject,
  });

  final CarwashBooking booking;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(b.serviceType.label,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Text('${b.washerEarningsEur.toStringAsFixed(2)} €',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 2),
          const Text('o que recebes',
              style: TextStyle(fontSize: 11, color: AppColors.textSubtle)),
          const SizedBox(height: Spacing.md),
          _linha(Icons.confirmation_number_outlined,
              '${b.plate}${b.carMakeModel.isEmpty ? '' : ' · ${b.carMakeModel}'}'
              '${b.carColor.isEmpty ? '' : ' · ${b.carColor}'}'),
          _linha(Icons.place_outlined, b.addressLine),
          if (b.pickupNotes.isNotEmpty)
            _linha(Icons.vpn_key_outlined, b.pickupNotes),
          _linha(Icons.phone_outlined, b.clientPhone),
          _linha(
            Icons.schedule,
            b.whenMode == 'now'
                ? 'Para agora'
                : 'Para ${b.scheduledAt.day}/${b.scheduledAt.month} às '
                    '${b.scheduledAt.hour.toString().padLeft(2, '0')}:'
                    '${b.scheduledAt.minute.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: onReject, child: const Text('Passar')),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: onAccept,
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Aceitar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linha(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(i, size: 16, color: AppColors.textSubtle),
            const SizedBox(width: Spacing.sm),
            Expanded(
                child: Text(t,
                    style: const TextStyle(color: AppColors.textSecondary))),
          ],
        ),
      );
}

class _TrabalhoCard extends StatelessWidget {
  const _TrabalhoCard({
    required this.booking,
    required this.onAvancar,
    required this.onCall,
    required this.onChat,
  });

  final CarwashBooking booking;
  final VoidCallback onAvancar;
  final VoidCallback onCall;
  final VoidCallback onChat;

  /// Texto do botão que faz avançar o pedido.
  String get _acao => switch (booking.status) {
        CarwashStatus.accepted => 'A caminho',
        CarwashStatus.onTheWay => 'Recolhi o carro',
        CarwashStatus.pickedUp => 'A lavar',
        CarwashStatus.inProgress => 'A entregar',
        CarwashStatus.delivering => 'Entregue',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${b.plate} · ${b.serviceType.label}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(b.status.clientLabel,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(b.addressLine,
              style: const TextStyle(color: AppColors.textSecondary)),
          if (b.pickupNotes.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(b.pickupNotes,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSubtle)),
          ],
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              IconButton.outlined(
                  onPressed: onCall, icon: const Icon(Icons.phone)),
              const SizedBox(width: Spacing.sm),
              IconButton.outlined(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline)),
              const SizedBox(width: Spacing.md),
              if (_acao.isNotEmpty)
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: onAvancar,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      child: Text(_acao,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
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
