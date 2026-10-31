import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/casa_models.dart';
import '../../stores/handyman_store.dart';
import '../../widgets/bora/bora.dart';
import 'casa_camara.dart';

/// CASA — documentos e validades do profissional. O que falta, o que foi
/// recusado e o que está a caducar, com um botão por item para enviar aqui
/// mesmo (sem refazer a candidatura). `casa_registar_documento` serve também
/// para reenviar.
class HandymanDocumentosScreen extends StatelessWidget {
  const HandymanDocumentosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HandymanStore>();
    final perfil = store.perfil;
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Documentos e validades'.tr),
      body: perfil == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: store.loadProfile,
              child: ListView(
                padding: const EdgeInsets.all(Spacing.lg),
                children: [CasaDocumentosPainel(perfil: perfil)],
              ),
            ),
    );
  }
}

/// Estado de um documento em PT-PT.
String casaEstadoDocumentoTexto(String estado) => switch (estado) {
      'approved' => 'Aprovado'.tr,
      'rejected' => 'Recusado'.tr,
      'expired' => 'Caducado'.tr,
      _ => 'Em análise'.tr,
    };

/// Aviso de caducidade (null = nada a dizer).
String? casaAvisoCaducidade(DateTime? validade, {DateTime? agora}) {
  final dias = casaDiasParaCaducar(validade, agora: agora);
  if (dias == null) return null;
  if (dias < 0) return 'Caducou. Envia o documento novo.'.tr;
  if (dias == 0) return 'Caduca hoje.'.tr;
  if (dias <= kCasaAvisoCaducidadeDias) {
    return 'Caduca daqui a {0} dias.'.trArgs([dias]);
  }
  return null;
}

/// Lista do que falta + documentos enviados. Usada no ecrã "Em análise" e no
/// ecrã dos documentos.
class CasaDocumentosPainel extends StatelessWidget {
  const CasaDocumentosPainel({super.key, required this.perfil, this.agora});

  final CasaPerfil perfil;
  final DateTime? agora;

  String? _nomeOficio(String? codigo) {
    if (codigo == null || codigo.isEmpty) return null;
    for (final o in perfil.oficios) {
      if (o.codigo == codigo) return o.nome;
    }
    return codigo;
  }

  @override
  Widget build(BuildContext context) {
    final faltas = casaDocumentosEmFalta(perfil, agora: agora);
    final atuais = casaDocumentosAtuais(perfil.documentos);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (faltas.isNotEmpty) ...[
          Text('O que falta'.tr,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          for (final f in faltas)
            _Linha(
              key: ValueKey('casa_falta_${f.tipo}_${f.oficio ?? ''}'),
              icone: Icons.error_outline,
              corIcone: AppColors.warning,
              titulo: f.titulo,
              subtitulo: f.explicacao,
              botao: 'Enviar'.tr,
              onTap: () =>
                  enviarDocumentoCasa(context, tipo: f.tipo, oficio: f.oficio),
            ),
          const SizedBox(height: Spacing.lg),
        ],
        Text('Documentos enviados'.tr,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary)),
        const SizedBox(height: Spacing.sm),
        if (atuais.isEmpty)
          Text('Ainda não enviaste nenhum documento.'.tr,
              style: const TextStyle(color: AppColors.textSecondary))
        else
          for (final d in atuais)
            Builder(builder: (context) {
              final aviso = casaAvisoCaducidade(d.validade, agora: agora);
              final oficio = _nomeOficio(d.oficio);
              final linhas = <String>[
                casaEstadoDocumentoTexto(d.estado),
                if (d.validade != null)
                  'Válido até {0}'.trArgs([
                    '${casaDiaMes(d.validade!)}/${d.validade!.year}',
                  ]),
                if (d.estado == 'rejected' &&
                    (d.motivo ?? '').trim().isNotEmpty)
                  'Motivo: {0}'.trArgs([d.motivo!.trim()]),
                if (aviso != null) aviso,
              ];
              final atencao = aviso != null || d.estado == 'rejected';
              return _Linha(
                icone: d.estado == 'approved' && aviso == null
                    ? Icons.check_circle
                    : (atencao ? Icons.warning_amber_rounded : Icons.hourglass_top),
                corIcone: d.estado == 'approved' && aviso == null
                    ? AppColors.primary
                    : (atencao ? AppColors.warning : AppColors.textSecondary),
                titulo: oficio == null
                    ? casaNomeDocumento(d.tipo)
                    : '${casaNomeDocumento(d.tipo)} · $oficio',
                subtitulo: linhas.join(' · '),
                botao: atencao ? 'Enviar de novo'.tr : null,
                onTap: () =>
                    enviarDocumentoCasa(context, tipo: d.tipo, oficio: d.oficio),
              );
            }),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    super.key,
    required this.icone,
    required this.corIcone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.botao,
  });

  final IconData icone;
  final Color corIcone;
  final String titulo;
  final String subtitulo;
  final String? botao;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icone, color: corIcone),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitulo,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          if (botao != null)
            TextButton(onPressed: onTap, child: Text(botao!))
          else
            IconButton(
              tooltip: 'Enviar de novo'.tr,
              onPressed: onTap,
              icon: const Icon(Icons.upload_file, color: AppColors.textSubtle),
            ),
        ],
      ),
    );
  }
}

/// Número (apólice/certificado) e validade de um documento.
Future<({String numero, DateTime? validade})?> pedirNumeroEValidade(
  BuildContext context, {
  required String tipo,
}) async {
  final ctrl = TextEditingController();
  try {
    return await _dialogoNumeroEValidade(context, tipo: tipo, ctrl: ctrl);
  } finally {
    // Depois da animação de saída do diálogo (o campo ainda o usa).
    Future<void>.delayed(const Duration(milliseconds: 600), ctrl.dispose);
  }
}

Future<({String numero, DateTime? validade})?> _dialogoNumeroEValidade(
  BuildContext context, {
  required String tipo,
  required TextEditingController ctrl,
}) {
  final obrigatorio = casaDocumentoPedeNumero(tipo);
  DateTime? validade;
  final rotulo = switch (tipo) {
    'seguro_acidentes' || 'seguro_rc' => 'Número da apólice'.tr,
    'cartao_cidadao' => 'Número do documento (opcional)'.tr,
    _ => 'Número do certificado'.tr,
  };
  return showDialog<({String numero, DateTime? validade})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(casaNomeDocumento(tipo)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctrl,
              decoration: InputDecoration(labelText: rotulo),
            ),
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(validade == null
                  ? (obrigatorio
                      ? 'Escolher a validade *'.tr
                      : 'Escolher a validade'.tr)
                  : 'Válido até {0}'.trArgs([
                      '${casaDiaMes(validade!)}/${validade!.year}',
                    ])),
              onPressed: () async {
                final hoje = DateTime.now();
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime(hoje.year + 1, hoje.month, hoje.day),
                  firstDate: hoje,
                  lastDate: DateTime(hoje.year + 15),
                  helpText: 'Válido até'.tr,
                );
                if (d != null) setLocal(() => validade = d);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar'.tr),
          ),
          FilledButton(
            onPressed: () {
              if (obrigatorio && (ctrl.text.trim().isEmpty || validade == null)) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text('Indica o número e a validade do documento.'.tr)));
                return;
              }
              Navigator.pop(ctx, (numero: ctrl.text.trim(), validade: validade));
            },
            child: Text('Continuar'.tr),
          ),
        ],
      ),
    ),
  );
}

/// Escolhe a imagem do documento (câmara ou galeria), pede número e validade
/// quando o tipo leva, e regista. Devolve se ficou enviado.
Future<bool> enviarDocumentoCasa(
  BuildContext context, {
  required String tipo,
  String? oficio,
}) async {
  final store = context.read<HandymanStore>();
  final messenger = ScaffoldMessenger.of(context);
  final fonte = await casaEscolherFonte(context);
  if (fonte == null || !context.mounted) return false;
  final f = await casaTirarFoto(context, fonte: fonte, imageQuality: 85);
  if (f == null || !context.mounted) return false;
  String? numero;
  DateTime? validade;
  if (casaDocumentoPedeNumero(tipo) || tipo == 'cartao_cidadao') {
    final r = await pedirNumeroEValidade(context, tipo: tipo);
    if (r == null) return false;
    numero = r.numero;
    validade = r.validade;
  }
  try {
    await store.registarDocumento(
      ficheiro: f,
      tipo: tipo,
      oficio: oficio,
      numero: numero,
      validade: validade,
    );
    messenger.showSnackBar(
        SnackBar(content: Text('Documento enviado. Vamos rever em breve.'.tr)));
    return true;
  } catch (e) {
    debugPrint('[CASA] documento $tipo falhou: $e');
    messenger.showSnackBar(SnackBar(content: Text(casaErroTexto(e))));
    return false;
  }
}
