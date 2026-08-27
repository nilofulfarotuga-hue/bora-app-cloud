import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/carwash_models.dart';
import '../../../services/carwash_upload_service.dart';
import '../../../stores/carwash_store.dart';
import '../../shared/carwash_chat_screen.dart';
import 'carwash_payment_flow.dart';

/// LAVAGEM AUTO — acompanhamento do cliente.
/// Barra de estados igual à da entrega + ETA + fotos antes/depois + chat.
class CarwashTrackingScreen extends StatefulWidget {
  const CarwashTrackingScreen({super.key});

  @override
  State<CarwashTrackingScreen> createState() => _CarwashTrackingScreenState();
}

class _CarwashTrackingScreenState extends State<CarwashTrackingScreen>
    with WidgetsBindingObserver {
  String _washerName = '';
  String _washerPhone = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWasher());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Espelho do servidor ao voltar ao foreground: o realtime pode ter
    // perdido eventos com a app em background.
    if (state == AppLifecycleState.resumed) {
      context.read<CarwashStore>().refreshTracked().then((_) => _loadWasher());
    }
  }

  Future<void> _loadWasher() async {
    final b = context.read<CarwashStore>().tracked;
    if (b?.washerId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('washers')
          .select('name, phone')
          .eq('id', b!.washerId!)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _washerName = (row['name'] ?? '').toString();
          _washerPhone = (row['phone'] ?? '').toString();
        });
      }
    } catch (_) {/* nome do lavador é conforto, não bloqueia */}
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _cancelar(CarwashBooking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar a lavagem?'),
        content: Text(
          b.status == CarwashStatus.scheduled
              ? 'Ainda ninguém aceitou, por isso não há qualquer custo.'
              : 'Já há um lavador a caminho. Pode haver uma taxa de cancelamento.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancelar lavagem')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final store = context.read<CarwashStore>();
    final done = await store.cancelBooking(b.id);
    // Se já tinha sido pago, devolve o que exceder a taxa de cancelamento.
    if (done && b.paymentMethod != 'cash' && b.paymentStatus != 'unpaid') {
      await store.reversePayment(b.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done ? 'Lavagem cancelada.' : 'Não foi possível cancelar.'),
    ));
  }

  Future<void> _confirmar(CarwashBooking b) async {
    int estrelas = 5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Correu tudo bem?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Confirme para fechar o pedido.'),
              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setLocal(() => estrelas = i),
                      icon: Icon(
                        i <= estrelas ? Icons.star : Icons.star_border,
                        color: AppColors.warning,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Agora não')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await context
        .read<CarwashStore>()
        .confirmCompletion(b.id, rating: estrelas);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.watch<CarwashStore>().tracked;
    if (b == null) {
      return const Scaffold(
        body: Center(child: Text('Sem pedido para acompanhar.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('A sua lavagem'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (b.washerId != null && b.status.isActive)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CarwashChatScreen(
                    bookingId: b.id,
                    myRole: 'client',
                    title: _washerName.isEmpty ? 'Lavador' : _washerName,
                    otherPhone: _washerPhone,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<CarwashStore>().refreshTracked(),
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            _EstadoCabecalho(booking: b, washerName: _washerName),
            const SizedBox(height: Spacing.lg),
            _BarraEstados(status: b.status),
            const SizedBox(height: Spacing.xl),

            if (b.washerId != null && b.status.isActive) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _call(_washerPhone),
                      icon: const Icon(Icons.phone),
                      label: const Text('Ligar'),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CarwashChatScreen(
                            bookingId: b.id,
                            myRole: 'client',
                            title: _washerName.isEmpty ? 'Lavador' : _washerName,
                            otherPhone: _washerPhone,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Mensagem'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
            ],

            // Por pagar (cartão/MB WAY): dá uma segunda oportunidade sem
            // obrigar a refazer o pedido.
            if (b.paymentMethod != 'cash' &&
                b.paymentStatus == 'unpaid' &&
                b.status.isActive) ...[
              Container(
                padding: const EdgeInsets.all(Spacing.lg),
                margin: const EdgeInsets.only(bottom: Spacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Falta o pagamento',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Este pedido ainda não foi pago por '
                      '${b.paymentMethod == 'card' ? 'cartão' : 'MB WAY'}.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: Spacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final store = context.read<CarwashStore>();
                          await CarwashPaymentFlow.pay(context, store, b);
                        },
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        child: Text(
                            'Pagar ${b.totalEur.toStringAsFixed(2)} €'),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            _CartaoDados(booking: b),

            if (b.photosBefore.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              _Fotos(
                titulo: 'Como o carro estava na recolha',
                fotos: b.photosBefore,
              ),
            ],
            if (b.photosAfter.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              _Fotos(titulo: 'Como ficou', fotos: b.photosAfter),
            ],

            const SizedBox(height: Spacing.xl),

            if (b.status == CarwashStatus.delivered)
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () => _confirmar(b),
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Está tudo certo — fechar pedido'),
                ),
              ),

            if (b.status == CarwashStatus.scheduled ||
                b.status == CarwashStatus.accepted ||
                b.status == CarwashStatus.onTheWay) ...[
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: () => _cancelar(b),
                child: const Text('Cancelar lavagem',
                    style: TextStyle(color: AppColors.error)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EstadoCabecalho extends StatelessWidget {
  const _EstadoCabecalho({required this.booking, required this.washerName});
  final CarwashBooking booking;
  final String washerName;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    String subtitulo;
    if (b.status == CarwashStatus.scheduled) {
      subtitulo = 'Estamos a procurar um lavador perto de si.';
    } else if (b.showsEta && b.etaAt != null) {
      final h = b.etaAt!;
      subtitulo = 'Chega daqui a ~${b.etaMinutes} min '
          '(por volta das ${h.hour.toString().padLeft(2, '0')}:'
          '${h.minute.toString().padLeft(2, '0')}).';
    } else {
      subtitulo = switch (b.status) {
        CarwashStatus.pickedUp => 'O carro já está com o lavador.',
        CarwashStatus.inProgress => 'A lavagem está a decorrer.',
        CarwashStatus.delivering => 'O carro está lavado e a caminho de volta.',
        CarwashStatus.delivered => 'O carro foi entregue. Confirme para fechar.',
        CarwashStatus.completed => 'Pedido fechado. Obrigado!',
        CarwashStatus.cancelled => 'Este pedido foi cancelado.',
        _ => '',
      };
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            b.status.clientLabel,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (washerName.isNotEmpty && b.status.isActive) ...[
            const SizedBox(height: 2),
            Text('com $washerName',
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: Spacing.xs),
          Text(subtitulo,
              style: const TextStyle(
                  color: AppColors.textSecondary, height: 1.35)),
        ],
      ),
    );
  }
}

class _BarraEstados extends StatelessWidget {
  const _BarraEstados({required this.status});
  final CarwashStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == CarwashStatus.cancelled) return const SizedBox.shrink();
    final atual = status.step;

    return Column(
      children: [
        for (var i = 0; i < kCarwashSteps.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= atual ? AppColors.primary : AppColors.divider,
                    ),
                    child: i < atual
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  if (i < kCarwashSteps.length - 1)
                    Container(
                      width: 2,
                      height: 26,
                      color: i < atual ? AppColors.primary : AppColors.divider,
                    ),
                ],
              ),
              const SizedBox(width: Spacing.md),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  kCarwashSteps[i],
                  style: TextStyle(
                    fontWeight: i == atual ? FontWeight.w800 : FontWeight.w400,
                    color: i <= atual
                        ? AppColors.textPrimary
                        : AppColors.textSubtle,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _CartaoDados extends StatelessWidget {
  const _CartaoDados({required this.booking});
  final CarwashBooking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _linha('Serviço', b.serviceType.label),
          _linha('Matrícula', b.plate),
          if (b.carMakeModel.isNotEmpty) _linha('Carro', b.carMakeModel),
          _linha('Onde', b.addressLine),
          _linha('Pagamento',
              switch (b.paymentMethod) {
                'card' => 'Cartão',
                'mbway' => 'MB WAY',
                _ => 'Dinheiro',
              }),
          const Divider(height: Spacing.xl),
          Row(
            children: [
              const Expanded(
                child: Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text('${b.totalEur.toStringAsFixed(2)} €',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linha(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(k,
                  style: const TextStyle(color: AppColors.textSubtle)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

/// Fotos do bucket PRIVADO — mostradas por signed URL.
class _Fotos extends StatelessWidget {
  const _Fotos({required this.titulo, required this.fotos});
  final String titulo;
  final List<CarwashPhoto> fotos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: fotos.length,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
            itemBuilder: (_, i) => _FotoTile(foto: fotos[i]),
          ),
        ),
      ],
    );
  }
}

class _FotoTile extends StatelessWidget {
  const _FotoTile({required this.foto});
  final CarwashPhoto foto;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: CarwashUploadService.signedUrl(foto.url),
      builder: (_, snap) {
        final aCarregar = snap.connectionState == ConnectionState.waiting;
        final url = snap.data;
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: url == null
                  // Sem URL: distinguir "ainda a carregar" de "não deu".
                  // Antes ficava em roda-viva para sempre quando a foto
                  // não existia no bucket.
                  ? Container(
                      width: 140,
                      height: 88,
                      color: AppColors.surface2,
                      child: Center(
                        child: aCarregar
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.image_not_supported_outlined,
                                color: AppColors.textSubtle),
                      ),
                    )
                  : Image.network(url,
                      width: 140,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            width: 140,
                            height: 88,
                            color: AppColors.surface2,
                            child: const Icon(Icons.broken_image,
                                color: AppColors.textSubtle),
                          )),
            ),
            if (foto.angle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(foto.angle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSubtle)),
              ),
          ],
        );
      },
    );
  }
}
