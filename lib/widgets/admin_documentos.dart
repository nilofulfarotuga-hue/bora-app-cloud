/// DOCUMENTOS DOS PRESTADORES NO PAINEL — peças comuns a todos os papéis
/// (estafeta, motorista TVDE, limpeza, lavagem). Missão
/// documentos-todos-papeis-22-10: o Danilo tem de ver TODOS os documentos de
/// TODOS os papéis, com o que falta a vermelho e um botão para o pedir.
///
/// Painel em PT-BR; a frase que o prestador recebe é PT-PT (é a app dele).
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../screens/admin/_admin_rpc_errors.dart';
import '../services/driver_documentos.dart' show juntarComE;
import 'private_bucket_image.dart';

/// Texto limpo ou null (vazio / só espaços contam como em falta).
String? docTexto(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// dd/mm/aaaa (e hh:mm com [hora]); "—" sem data.
String docData(Object? v, {bool hora = false}) {
  final t = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  if (t == null) return '—';
  String dd(int n) => n.toString().padLeft(2, '0');
  final d = '${dd(t.day)}/${dd(t.month)}/${t.year}';
  return hora ? '$d ${dd(t.hour)}:${dd(t.minute)}' : d;
}

// ── Comprovativo de atividade (provider_atividade, um por pessoa) ───────────

/// Pendura em cada linha `_atividade` (provider_atividade) e `_fiscal`
/// (driver_fiscal_status, "tenho atividade aberta"). Falha aberta.
Future<void> juntarAtividadeAdmin(
  SupabaseClient sb,
  List<Map<String, dynamic>> linhas, {
  String chaveUser = 'user_id',
}) async {
  final ids = linhas
      .map((d) => d[chaveUser]?.toString())
      .whereType<String>()
      .toSet()
      .toList();
  if (ids.isEmpty) return;
  try {
    final at = await sb
        .from('provider_atividade')
        .select('user_id, nif, documento_path, documento_tipo, '
            'atividade_status, obrigatoria, enviado_em, decidido_em, motivo')
        .inFilter('user_id', ids);
    final porUser = {
      for (final r in List<Map<String, dynamic>>.from(at))
        r['user_id'].toString(): r
    };
    final fs = await sb
        .from('driver_fiscal_status')
        .select('user_id, atividade_aberta, confirmado_em')
        .inFilter('user_id', ids);
    final fiscal = {
      for (final r in List<Map<String, dynamic>>.from(fs))
        r['user_id'].toString(): r
    };
    for (final d in linhas) {
      final uid = d[chaveUser]?.toString();
      d['_atividade'] = porUser[uid];
      d['_fiscal'] = fiscal[uid];
    }
  } catch (e) {
    debugPrint('[admin_documentos] atividade: $e');
  }
}

/// O comprovativo conta para esta pessoa e ainda não chegou (ou foi
/// recusado). Para quem já trabalhava antes do corte nunca falta.
bool atividadeEmFaltaDe(Map<String, dynamic> d) {
  final a = d['_atividade'];
  if (a is! Map || a['obrigatoria'] != true) return false;
  return docTexto(a['documento_path']) == null ||
      a['atividade_status'] == 'recusada';
}

// ── Peças visuais ────────────────────────────────────────────────────────────

class DocSeccao extends StatelessWidget {
  const DocSeccao(this.titulo, {super.key});
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        titulo.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Uma linha "rótulo: valor". Vazio → "—"; vazio e obrigatório → "Falta" a
/// vermelho.
class DocCampo extends StatelessWidget {
  const DocCampo(this.label, this.value, {super.key, this.falta = false});
  final String label;
  final Object? value;
  final bool falta;

  @override
  Widget build(BuildContext context) {
    final v = docTexto(value);
    final vazio = v == null || v == '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              vazio ? (falta ? 'Falta' : '—') : v,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: vazio && falta ? AppColors.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _abrirExterno(BuildContext context, String urlOrPath) async {
  try {
    final url = await resolveSignedUrlIfPrivate(urlOrPath);
    if (url == null) throw Exception('sem_endereco');
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível abrir o documento neste aparelho.')));
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o documento: $e')));
  }
}

bool _ePdf(String urlOrPath) =>
    urlOrPath.toLowerCase().split('?').first.endsWith('.pdf');

/// Miniatura de um documento de bucket privado (toca para abrir em ecrã
/// inteiro com zoom; PDF abre por fora) ou, sem ficheiro, "Falta: …" a
/// vermelho (obrigatório) / "Não enviado (opcional)".
///
/// [urlOrPath] aceita URL assinado, `balde/caminho` ou caminho solto com
/// [balde] (o painel guarda as três formas, conforme o papel).
class DocFoto extends StatelessWidget {
  const DocFoto({
    super.key,
    required this.titulo,
    required this.urlOrPath,
    required this.obrigatoria,
    this.balde,
    this.detalhe,
  });
  final String titulo;
  final String? urlOrPath;
  final bool obrigatoria;
  final String? balde;

  /// Linha pequena por baixo do título (validade, estado…).
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    final bruto = docTexto(urlOrPath);
    final url = (bruto == null || balde == null)
        ? bruto
        : withPrivateBucketPrefix(balde!, bruto);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (detalhe != null) ...[
            const SizedBox(height: 2),
            Text(detalhe!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 6),
          if (url != null && _ePdf(url))
            OutlinedButton.icon(
              onPressed: () => _abrirExterno(context, url),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text('Abrir $titulo (PDF)'),
            )
          else if (url != null)
            PrivateBucketImage(
              urlOrPath: url,
              height: 170,
              width: double.infinity,
              borderRadius: BorderRadius.circular(10),
              tituloAmpliada: titulo,
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: obrigatoria ? Colors.red.shade50 : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: obrigatoria
                        ? Colors.red.shade300
                        : AppColors.divider),
              ),
              child: Text(
                obrigatoria
                    ? 'Falta: ${titulo.toLowerCase()}'
                    : 'Não enviado (opcional)',
                style: TextStyle(
                  color: obrigatoria ? AppColors.error : AppColors.textSecondary,
                  fontWeight: obrigatoria ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Comprovativo de atividade (bucket privado `provider-atividade`): estado,
/// miniatura (foto) ou botão do PDF, e "Aprovar comprovativo" em análise.
class DocComprovativoAtividade extends StatelessWidget {
  const DocComprovativoAtividade({
    super.key,
    required this.atividade,
    required this.falta,
    this.onAprovar,
  });
  final Map<String, dynamic>? atividade;
  final bool falta;
  final VoidCallback? onAprovar;

  @override
  Widget build(BuildContext context) {
    final a = atividade;
    final path = docTexto(a?['documento_path']);
    final status = a?['atividade_status']?.toString();
    final rotuloEstado = switch (status) {
      'aprovada' => 'Aprovado',
      'recusada' =>
        'Recusado${docTexto(a?['motivo']) == null ? '' : ': ${a!['motivo']}'}',
      'em_analise' => path == null ? 'Falta enviar' : 'Em análise',
      _ => a == null ? 'Sem registo' : 'Por enviar',
    };
    final pdf = (a?['documento_tipo']?.toString() ?? '') == 'pdf';
    final completo =
        path == null ? null : withPrivateBucketPrefix('provider-atividade', path);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Comprovativo de atividade',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Estado: $rotuloEstado'
            '${docTexto(a?['enviado_em']) == null ? '' : ' · enviado ${docData(a!['enviado_em'], hora: true)}'}',
            style: TextStyle(
              fontSize: 13,
              color: status == 'aprovada'
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          if (completo != null && !pdf)
            PrivateBucketImage(
              urlOrPath: completo,
              height: 170,
              width: double.infinity,
              borderRadius: BorderRadius.circular(10),
              tituloAmpliada: 'Comprovativo de atividade',
            )
          else if (completo != null && pdf)
            OutlinedButton.icon(
              onPressed: () => _abrirExterno(context, completo),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Abrir comprovativo (PDF)'),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: falta ? Colors.red.shade50 : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: falta ? Colors.red.shade300 : AppColors.divider),
              ),
              child: Text(
                falta
                    ? 'Falta: comprovativo de atividade'
                    : 'Não enviado (não obrigatório para esta conta)',
                style: TextStyle(
                  color: falta ? AppColors.error : AppColors.textSecondary,
                  fontWeight: falta ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          if (completo != null && status == 'em_analise' && onAprovar != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: onAprovar,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Aprovar comprovativo'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Caixa vermelha "Falta: …" com o botão "Pedir documentos em falta".
class DocFaltaCaixa extends StatelessWidget {
  const DocFaltaCaixa({super.key, required this.falta, required this.onPedir});
  final List<String> falta;
  final VoidCallback? onPedir;

  @override
  Widget build(BuildContext context) {
    if (falta.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in falta)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Falta: ${f.toLowerCase()}',
                style: const TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700),
              ),
            ),
          if (onPedir != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: onPedir,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Pedir documentos em falta'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Ações ────────────────────────────────────────────────────────────────────

/// Frase que o prestador recebe (PT-PT). [quem]: "estafeta", "motorista",
/// "profissional de limpeza", "lavador".
String textoPedidoDocumentos(String quem, List<String> itens,
        {String ecra = 'Falta enviar'}) =>
    'Na tua conta de $quem falta: '
    '${juntarComE(itens.map((i) => i.toLowerCase()).toList())}. '
    'Abre a app Bora e envia em "$ecra" — aparece logo à entrada.';

/// "Pedir documentos em falta": confirma com a frase exata, manda aviso na
/// app + notificação (RPC `admin_send_push_notification`, a porta única de
/// mensagens do painel, que já grava no log de ações do admin), deixa uma
/// linha no e2e_log e, sem notificações ligadas, oferece o SMS já escrito no
/// telemóvel do admin (não há SMS automático).
Future<void> pedirDocumentosEmFalta(
  BuildContext ctx, {
  required String userId,
  required String tipoDestino,
  required String quem,
  required List<String> itens,
  String? telefone,
  String? refId,
  String ecra = 'Falta enviar',
}) async {
  if (itens.isEmpty) return;
  final texto = textoPedidoDocumentos(quem, itens, ecra: ecra);
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dCtx) => AlertDialog(
      title: const Text('Pedir documentos em falta'),
      content: Text('Vai receber:\n\n$texto'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dCtx, true),
          child: const Text('Enviar'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final sb = Supabase.instance.client;
  bool temAparelho = false;
  try {
    final r = await sb.rpc('admin_send_push_notification', params: {
      'p_recipient_type': tipoDestino,
      'p_recipient_id': userId,
      'p_title': 'Faltam documentos na tua candidatura',
      'p_body': texto,
      'p_data': {'tipo': 'documentos_em_falta'},
    });
    temAparelho = r is Map && r['fcm_token_found'] == true;
  } catch (e) {
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(humanizeAdminRpcError(e)),
      backgroundColor: AppColors.error,
    ));
    return;
  }
  try {
    final id = refId ?? userId;
    await sb.from('e2e_log').insert({
      'fluxo': 'documentos-prestadores',
      'passo': 'pedir-documentos-$tipoDestino',
      'estado': 'ok',
      'detalhe': 'ref=${id.length > 8 ? id.substring(0, 8) : id} '
          'itens=${itens.join(', ')} aparelho=$temAparelho',
      'device': 'painel-admin',
    });
  } catch (e) {
    debugPrint('[admin_documentos] e2e_log: $e');
  }
  if (!ctx.mounted) return;
  final phone = telefone?.replaceAll(' ', '');
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    duration: const Duration(seconds: 8),
    content: Text(temAparelho
        ? 'Pedido enviado (aviso na app + notificação).'
        : 'Aviso gravado na app, mas esta pessoa não tem notificações '
            'ligadas. Manda também por SMS.'),
    action: (phone == null || phone.isEmpty)
        ? null
        : SnackBarAction(
            label: 'SMS',
            // `query` à mão: queryParameters troca os espaços por '+',
            // que a app de SMS mostra tal e qual.
            onPressed: () => launchUrl(Uri(
              scheme: 'sms',
              path: phone,
              query: 'body=${Uri.encodeComponent(texto)}',
            )),
          ),
  ));
}

/// Aprova o comprovativo de atividade ali mesmo. Devolve true se aprovou.
Future<bool> aprovarComprovativoAtividade(
  BuildContext ctx, {
  required String userId,
  required String nome,
  String? nif,
}) async {
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dCtx) => AlertDialog(
      title: const Text('Aprovar comprovativo?'),
      content: Text('Confirmas que viste o comprovativo de $nome e que a '
          'atividade está aberta com o NIF ${nif ?? '—'}?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dCtx, true),
          child: const Text('Aprovar'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await Supabase.instance.client
        .rpc('admin_provider_atividade_decidir', params: {
      'p_user_id': userId,
      'p_acao': 'aprovar',
      'p_motivo': null,
      'p_avisar': true,
    });
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Comprovativo aprovado (a pessoa foi avisada).'),
        backgroundColor: AppColors.success,
      ));
    }
    return true;
  } catch (e) {
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(e.toString().contains('sem_documento')
            ? 'Ainda não há comprovativo para aprovar.'
            : humanizeAdminRpcError(e)),
        backgroundColor: AppColors.error,
      ));
    }
    return false;
  }
}
