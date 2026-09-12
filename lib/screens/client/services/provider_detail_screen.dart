import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../auth/auth_store.dart';
import '../../../services/destino_pendente.dart';
import '../../../models/provider_service_model.dart';
import '../../../models/service_provider_model.dart';
import '../../../models/staff_member_model.dart';
import '../../../stores/services_store.dart';
import '../../../widgets/bora/bora_accent_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import '../../../widgets/bora/coming_soon.dart';
import '../../../widgets/services/staff_avatar.dart';
import '../../register_client_screen.dart';
import 'booking_flow_screen.dart';
import 'gallery_viewer_screen.dart';

import '../../../l10n/tr.dart';

/// Vertical Serviços — detalhe de uma barbearia.
/// Hero, nome, rating, descrição, morada, lista de serviços (preço+duração),
/// CTA "Marcar" → fluxo de marcação.
class ProviderDetailScreen extends StatefulWidget {
  const ProviderDetailScreen({super.key, required this.provider});

  final ServiceProviderModel provider;

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  late Future<List<ProviderServiceModel>> _servicesFuture;
  late Future<List<StaffMemberModel>> _staffFuture;

  @override
  void initState() {
    super.initState();
    final store = context.read<ServicesStore>();
    _servicesFuture = store.fetchServices(widget.provider.id);
    _staffFuture = store.fetchStaff(widget.provider.id);
  }

  Future<void> _startBooking({ProviderServiceModel? preselected}) async {
    // "Em breve": a ficha e os serviços continuam visíveis, mas não se marca.
    // O servidor rejeita na mesma (STORE_COMING_SOON) — isto é só a UI.
    if (widget.provider.comingSoon) {
      showComingSoonBlockedSnackBar(context);
      return;
    }
    // Quem chegou de fora (site, QR, link) pode não ter sessão: a ficha é de
    // leitura pública, mas marcar exige conta. Guarda-se o destino para o
    // ClientMainScreen trazer a pessoa de volta A ESTA ficha depois do
    // registo — e não à home genérica.
    if (context.read<AuthStore>().currentClient == null) {
      await DestinoPendente.guardar('servico', widget.provider.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const RegisterClientScreen()),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(
          provider: widget.provider,
          preselectedService: preselected,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: p.name),
      body: SafeArea(
        child: Column(
          children: [
            if (p.comingSoon) ComingSoonBanner(text: p.comingSoonLabel),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Spacing.xxxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero(p),
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (p.ratingsCount > 0) ...[
                            const SizedBox(height: Spacing.sm),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 18, color: AppColors.warning),
                                const SizedBox(width: Spacing.xxs),
                                Text(
                                  '{0} · {1} avaliações'.trArgs([p.avgRating.toStringAsFixed(1), p.ratingsCount]),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (p.address != null && p.address!.isNotEmpty) ...[
                            const SizedBox(height: Spacing.sm),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 16, color: AppColors.textSubtle),
                                const SizedBox(width: Spacing.xs),
                                Expanded(
                                  child: Text(
                                    p.address!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (p.description != null &&
                              p.description!.isNotEmpty) ...[
                            const SizedBox(height: Spacing.lg),
                            Text(
                              p.description!,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          _socialRow(p),
                          _aboutSection(p),
                          _teamSection(),
                          _gallerySection(p),
                          const SizedBox(height: Spacing.xl),
                          Text(
                            'Serviços'.tr,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          _servicesList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // CTA laranja único do ecrã (regra 1 laranja/ecrã).
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
              // "Em breve": botão cinzento (não invisível) que explica porquê.
              child: p.comingSoon
                  ? Tooltip(
                      message: kComingSoonBlockedMessage,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showComingSoonBlockedSnackBar(context),
                        child: AbsorbPointer(
                          child: BoraAccentButton(
                            label: 'Marcar'.tr,
                            icon: Icons.event_available,
                            onPressed: null,
                          ),
                        ),
                      ),
                    )
                  : BoraAccentButton(
                      label: 'Marcar'.tr,
                      icon: Icons.event_available,
                      onPressed: () => _startBooking(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(ServiceProviderModel p) {
    final url = (p.heroImageUrl != null && p.heroImageUrl!.isNotEmpty)
        ? p.heroImageUrl!
        : (p.photoUrl ?? '');
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _heroFallback(),
              loadingBuilder: (_, child, prog) =>
                  prog == null ? child : _heroFallback(),
            )
          : _heroFallback(),
    );
  }

  Widget _heroFallback() => Container(
        decoration: const BoxDecoration(gradient: AppColors.tileReserveTable),
        alignment: Alignment.center,
        child: const Icon(Icons.content_cut, color: Colors.white, size: 48),
      );

  /// Secção "A nossa equipa" — cartões horizontais com foto (ou avatar de
  /// iniciais), nome, função e chips de especialidades. Só aparece se houver
  /// equipa activa; enquanto carrega ou se vazia, não ocupa espaço.
  Widget _teamSection() {
    return FutureBuilder<List<StaffMemberModel>>(
      future: _staffFuture,
      builder: (context, snap) {
        final staff = snap.data ?? const <StaffMemberModel>[];
        if (snap.connectionState != ConnectionState.done || staff.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.xl),
            Text(
              'A nossa equipa'.tr,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: staff.length,
                separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
                itemBuilder: (_, i) => _StaffCard(staff: staff[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Ícones discretos de Instagram/Facebook — só aparecem se o prestador tiver
  /// preenchido o respetivo link no admin. Aceita handle (@nome) ou URL completo.
  Widget _socialRow(ServiceProviderModel p) {
    final ig = p.socialInstagram?.trim() ?? '';
    final fb = p.socialFacebook?.trim() ?? '';
    if (ig.isEmpty && fb.isEmpty) return const SizedBox.shrink();

    Uri? toUri(String value, String base) {
      if (value.isEmpty) return null;
      final normalized = value.startsWith('http')
          ? value
          : '$base${value.startsWith('@') ? value.substring(1) : value}';
      return Uri.tryParse(normalized);
    }

    Future<void> open(Uri? uri) async {
      if (uri == null) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Row(
        children: [
          if (ig.isNotEmpty)
            IconButton(
              onPressed: () => open(toUri(ig, 'https://instagram.com/')),
              icon: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.textSecondary, size: 22),
              tooltip: 'Instagram'.tr,
              visualDensity: VisualDensity.compact,
            ),
          if (fb.isNotEmpty)
            IconButton(
              onPressed: () => open(toUri(fb, 'https://facebook.com/')),
              icon: const Icon(Icons.facebook,
                  color: AppColors.textSecondary, size: 22),
              tooltip: 'Facebook'.tr,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  /// Secção "Sobre" — história do prestador (`about_text`). Fallback
  /// silencioso: sem texto, sem secção.
  Widget _aboutSection(ServiceProviderModel p) {
    final about = p.aboutText?.trim() ?? '';
    if (about.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.xl),
        Text(
          'Sobre'.tr,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          about,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Secção "Galeria" — fotos do prestador (`gallery_urls`). Fallback
  /// silencioso: sem fotos, sem secção. Tap abre visualizador em ecrã cheio.
  Widget _gallerySection(ServiceProviderModel p) {
    final photos = p.galleryUrls;
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.xl),
        Text(
          'Galeria'.tr,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
            itemBuilder: (_, i) => InkWell(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GalleryViewerScreen(
                    imageUrls: photos,
                    initialIndex: i,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: CachedNetworkImage(
                  imageUrl: photos[i],
                  width: 110,
                  height: 110,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.surface),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surface,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image,
                        color: AppColors.textSubtle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _servicesList() {
    return FutureBuilder<List<ProviderServiceModel>>(
      future: _servicesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text(
            snap.error.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: AppColors.error),
          );
        }
        final services = snap.data ?? const [];
        if (services.isEmpty) {
          return Text(
            'Este prestador ainda não tem serviços.'.tr,
            style: const TextStyle(color: AppColors.textSecondary),
          );
        }
        return Column(
          children: [
            for (final s in services) ...[
              _ServiceTile(service: s, onTap: () => _startBooking(preselected: s)),
              if (s != services.last) const SizedBox(height: Spacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap});

  final ProviderServiceModel service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (service.description != null &&
                      service.description!.isNotEmpty) ...[
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      service.description!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: Spacing.xs),
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          size: 14, color: AppColors.textSubtle),
                      const SizedBox(width: Spacing.xxs),
                      Text(
                        service.durationLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSubtle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            Text(
              service.priceLabel,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão compacto de um profissional na secção "A nossa equipa".
class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff});

  final StaffMemberModel staff;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        children: [
          StaffAvatar(staff: staff, radius: 44),
          const SizedBox(height: Spacing.sm),
          Text(
            staff.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if ((staff.bio ?? '').isNotEmpty) ...[
            const SizedBox(height: Spacing.xxs),
            Text(
              staff.bio!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (staff.specialties.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final s in staff.specialties.take(2)) _chip(s),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
