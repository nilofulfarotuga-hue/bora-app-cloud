import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/casa_models.dart';
import '../../../stores/casa_store.dart';
import '../../../utils/safe_image_picker.dart';
import '../../../widgets/bora_foto_ecra_inteiro.dart';
import 'casa_regras.dart';

/// CASA — peças pequenas partilhadas pelos ecrãs do cliente (31/10/2026).
/// Mesmo desenho dos ecrãs da Limpeza: cartões brancos com borda fina, verde
/// para o que está escolhido, laranja nunca (fica para o ladrilho da home).

/// Título de secção (igual ao `_sectionTitle` do assistente da limpeza).
class CasaTituloSecao extends StatelessWidget {
  const CasaTituloSecao(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        texto,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Cartão branco com borda fina.
class CasaCartao extends StatelessWidget {
  const CasaCartao({
    super.key,
    required this.child,
    this.destacado = false,
    this.onTap,
    this.padding = const EdgeInsets.all(Spacing.lg),
  });

  final Widget child;
  final bool destacado;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final caixa = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: destacado ? AppColors.primary : AppColors.divider,
          width: destacado ? 2 : 1,
        ),
      ),
      child: child,
    );
    if (onTap == null) return caixa;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: onTap,
      child: caixa,
    );
  }
}

/// Uma opção de pagamento (molde: `_PaymentOption` da limpeza).
class CasaOpcaoPagamento extends StatelessWidget {
  const CasaOpcaoPagamento({
    super.key,
    required this.metodo,
    required this.selecionado,
    required this.onTap,
  });

  final CasaMetodoPagamento metodo;
  final bool selecionado;
  final VoidCallback onTap;

  IconData get _icone => switch (metodo.codigo) {
        'card' => Icons.credit_card,
        'mbway' => Icons.phone_iphone,
        _ => Icons.euro,
      };

  @override
  Widget build(BuildContext context) {
    final ativo = metodo.disponivel;
    final marcado = selecionado && ativo;
    final cor = ativo
        ? (marcado ? AppColors.primary : AppColors.textSecondary)
        : AppColors.textSubtle;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: ativo ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: marcado ? AppColors.primary : AppColors.divider,
              width: marcado ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(_icone, color: cor),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  metodo.rotulo,
                  style: TextStyle(
                    color: ativo ? AppColors.textPrimary : AppColors.textSubtle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (marcado)
                const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista das três opções de pagamento + a explicação do limite do dinheiro.
class CasaEscolhaPagamento extends StatelessWidget {
  const CasaEscolhaPagamento({
    super.key,
    required this.totalCents,
    required this.config,
    required this.metodo,
    required this.onEscolher,
  });

  final int totalCents;
  final CasaConfig config;
  final String? metodo;
  final ValueChanged<String> onEscolher;

  @override
  Widget build(BuildContext context) {
    final metodos = casaMetodosPagamento(totalCents: totalCents, config: config);
    final dinheiro = casaDinheiroPermitido(totalCents, config.maxCashCents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in metodos)
          CasaOpcaoPagamento(
            metodo: m,
            selecionado: metodo == m.codigo,
            onTap: () => onEscolher(m.codigo),
          ),
        if (!dinheiro)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              casaExplicacaoDinheiro(config),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

/// Foto de um balde privado (`casa-fotos`): pede um URL assinado ao store e
/// abre em ecrã inteiro ao tocar. Sem URL (rede, permissões) mostra um
/// quadrado com ícone — nunca um erro.
class CasaFotoPrivada extends StatefulWidget {
  const CasaFotoPrivada({
    super.key,
    required this.storagePath,
    this.tamanho = 88,
    this.titulo,
  });

  final String storagePath;
  final double tamanho;
  final String? titulo;

  @override
  State<CasaFotoPrivada> createState() => _CasaFotoPrivadaState();
}

class _CasaFotoPrivadaState extends State<CasaFotoPrivada> {
  String? _url;
  bool _tentou = false;

  @override
  void initState() {
    super.initState();
    _resolver();
  }

  @override
  void didUpdateWidget(covariant CasaFotoPrivada oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _url = null;
      _tentou = false;
      _resolver();
    }
  }

  Future<void> _resolver() async {
    final url = await context.read<CasaStore>().urlFoto(widget.storagePath);
    if (!mounted) return;
    setState(() {
      _url = url;
      _tentou = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tamanho;
    final url = _url;
    Widget conteudo;
    if (url == null) {
      conteudo = Center(
        child: _tentou
            ? const Icon(Icons.image_outlined, color: AppColors.textSubtle)
            : const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      );
    } else {
      conteudo = Image.network(
        url,
        width: t,
        height: t,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.textSubtle),
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: url == null
          ? null
          : () => BoraFotoEcraInteiro.abrir(context,
              urlOrPath: url, titulo: widget.titulo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          width: t,
          height: t,
          color: AppColors.surface2,
          child: conteudo,
        ),
      ),
    );
  }
}

/// Fila de fotos privadas com título ("Antes", "Depois", …).
class CasaFilaDeFotos extends StatelessWidget {
  const CasaFilaDeFotos({
    super.key,
    required this.titulo,
    required this.fotos,
  });

  final String titulo;
  final List<CasaFoto> fotos;

  @override
  Widget build(BuildContext context) {
    if (fotos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final f in fotos)
                CasaFotoPrivada(storagePath: f.storagePath, titulo: titulo),
            ],
          ),
        ],
      ),
    );
  }
}

/// Avatar + nome + estrelas + trabalhos feitos + selos do profissional.
class CasaResumoProfissional extends StatelessWidget {
  const CasaResumoProfissional({super.key, required this.pessoa});

  final CasaPessoaResumo pessoa;

  @override
  Widget build(BuildContext context) {
    final p = pessoa;
    final linha = p.ratingsCount > 0
        ? '★ {0} ({1}) · {2} trabalhos'.trArgs([
            p.ratingAvg.toStringAsFixed(1).replaceAll('.', ','),
            p.ratingsCount,
            p.jobsDone,
          ])
        : p.jobsDone > 0
            ? '{0} trabalhos feitos'.trArgs([p.jobsDone])
            : 'Novo no Bora'.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryWash,
              backgroundImage:
                  p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
              child: p.photoUrl.isEmpty
                  ? const Icon(Icons.person, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nome.isEmpty ? 'Profissional'.tr : p.nome,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    linha,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (p.selos.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final s in p.selos)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryWash,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        casaSeloTr(s),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Linha "rótulo ........ valor" dos resumos.
class CasaLinhaResumo extends StatelessWidget {
  const CasaLinhaResumo(this.rotulo, this.valor,
      {super.key, this.forte = false});

  final String rotulo;
  final String valor;
  final bool forte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(rotulo,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            flex: 3,
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: forte ? FontWeight.w800 : FontWeight.w600,
                fontSize: forte ? 16 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ícone de cada ofício (o nome vem do servidor).
IconData casaIconeOficio(String codigo) => switch (codigo) {
      'montagem' => Icons.chair_alt_outlined,
      'fixacao' => Icons.hardware_outlined,
      'reparacoes' => Icons.handyman_outlined,
      'canalizacao' => Icons.plumbing_outlined,
      'jardinagem' => Icons.grass_outlined,
      'mudancas' => Icons.local_shipping_outlined,
      'eletricidade' => Icons.electrical_services_outlined,
      'gas' => Icons.local_fire_department_outlined,
      'pladur' => Icons.foundation_outlined,
      'pintura' => Icons.format_paint_outlined,
      _ => Icons.home_repair_service_outlined,
    };

// ── escolher uma foto (câmara ou galeria) ───────────────────────────────────

/// Foto lida para memória, pronta a subir.
class CasaFotoLida {
  const CasaFotoLida(this.bytes, this.extensao);
  final Uint8List bytes;
  final String extensao;
}

/// Pergunta câmara ou galeria, abre o seletor e devolve os bytes. null quando
/// o cliente desiste ou falha — e nesse caso JÁ disse porquê numa barra.
///
/// Regra 1.26: nenhum ecrã fica preso à espera de permissão. O seletor tem
/// tecto de tempo; a permissão recusada dá frase clara com o que fazer.
Future<CasaFotoLida?> casaEscolherFoto(BuildContext context) async {
  void avisa(String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  ImageSource? fonte;
  if (kIsWeb) {
    fonte = ImageSource.gallery;
  } else {
    fonte = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Tirar foto agora'.tr),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Escolher da galeria'.tr),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
  if (fonte == null || !context.mounted) return null;
  try {
    var expirou = false;
    final x = await SafeImagePicker.pickImage(
      source: fonte,
      maxWidth: 1600,
      imageQuality: 80,
    ).timeout(const Duration(minutes: 2), onTimeout: () {
      expirou = true;
      return null;
    });
    if (expirou) {
      avisa('A câmara não respondeu. Tenta outra vez ou escolhe da galeria.'.tr);
      return null;
    }
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    if (bytes.isEmpty) {
      avisa('Não consegui ler a foto.'.tr);
      return null;
    }
    final nome = x.name.toLowerCase();
    final ext = nome.contains('.') ? nome.split('.').last : 'jpg';
    return CasaFotoLida(bytes, ext);
  } on PlatformException catch (e) {
    final negado = e.code.contains('denied') || e.code.contains('access');
    if (!negado) {
      avisa('Não consegui abrir as fotos. Tenta outra vez.'.tr);
    } else if (fonte == ImageSource.camera) {
      avisa(
          'Sem acesso à câmara. Autoriza nas definições do telemóvel, ou escolhe da galeria.'.tr);
    } else {
      avisa('Sem acesso às fotos. Autoriza nas definições do telemóvel.'.tr);
    }
    return null;
  } catch (_) {
    avisa('Não consegui abrir as fotos. Tenta outra vez.'.tr);
    return null;
  }
}
