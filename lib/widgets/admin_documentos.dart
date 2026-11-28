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
import '../services/robo_documentos.dart';
import '../services/robo_documentos_service.dart';
import 'admin_robo_documentos.dart';
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
  // Robô fiscal de documentos (adendo 3): o veredito de cada documento, junto à linha (`_robo`).
  await juntarVereditosRobo(sb, linhas, chaveUser: chaveUser);
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

/// Abre o comprovativo de atividade (balde privado `provider-atividade`,
/// endereço assinado de curta duração) por fora: serve para foto e PDF.
Future<void> abrirComprovativoAtividade(BuildContext context, String path) =>
    _abrirExterno(context, withPrivateBucketPrefix('provider-atividade', path));

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
    this.veredito,
    this.onDesfazer,
  });
  final String titulo;
  final String? urlOrPath;
  final bool obrigatoria;
  final String? balde;

  /// Linha pequena por baixo do título (validade, estado…).
  final String? detalhe;

  /// O que o robô diz deste ficheiro (null = não viu, ou o ficheiro mudou).
  final VereditoRobo? veredito;
  final Future<void> Function(VereditoRobo)? onDesfazer;

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
          if (veredito != null && url != null)
            RoboVereditoChip(veredito: veredito!, onDesfazer: onDesfazer),
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
    this.veredito,
    this.onDesfazer,
  });
  final Map<String, dynamic>? atividade;
  final bool falta;
  final VoidCallback? onAprovar;

  /// O que o robô diz do comprovativo. Se disser "errado", o botão Aprovar
  /// fica a vermelho com o aviso (a decisão continua a ser só do Danilo).
  final VereditoRobo? veredito;
  final Future<void> Function(VereditoRobo)? onDesfazer;

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
          if (veredito != null && completo != null)
            RoboVereditoChip(veredito: veredito!, onDesfazer: onDesfazer),
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
            if (veredito != null && veredito!.errado && !veredito!.desfeito)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Atenção: o robô diz que este ficheiro NÃO é o comprovativo. '
                  'Confere antes de aprovar.',
                  key: Key('robo-aviso-botao-aprovar'),
                  style: TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            FilledButton.icon(
              key: const Key('aprovar-comprovativo'),
              style: FilledButton.styleFrom(
                backgroundColor: (veredito != null && veredito!.errado && !veredito!.desfeito)
                    ? AppColors.error
                    : AppColors.success,
              ),
              onPressed: onAprovar,
              icon: const Icon(Icons.verified_outlined),
              label: Text((veredito != null && veredito!.errado && !veredito!.desfeito)
                  ? 'Aprovar mesmo assim (o robô diz errado)'
                  : 'Aprovar comprovativo'),
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

/// [18/11/2026] Resultado de um botão do painel numa janela por cima de tudo.
/// O SnackBar ficava POR BAIXO da ficha (bottom sheet) e o Danilo achava que o
/// botão "não fazia nada" (Shelen, 18/11 20:27-20:37: três pedidos enviados,
/// nenhum visto). Uma janela abre sempre por cima da ficha.
Future<void> avisoResultadoAdmin(
  BuildContext ctx, {
  required String titulo,
  required String texto,
  bool ok = true,
  String? acaoExtra,
  VoidCallback? onAcaoExtra,
}) async {
  if (!ctx.mounted) return;
  await showDialog<void>(
    context: ctx,
    builder: (dCtx) => AlertDialog(
      key: Key(ok ? 'admin-resultado-ok' : 'admin-resultado-erro'),
      icon: Icon(ok ? Icons.check_circle : Icons.error_outline,
          color: ok ? AppColors.success : AppColors.error, size: 40),
      title: Text(titulo),
      content: Text(texto),
      actions: [
        if (acaoExtra != null && onAcaoExtra != null)
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx);
              onAcaoExtra();
            },
            child: Text(acaoExtra),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(dCtx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

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
  const titulo = 'Faltam documentos na tua candidatura';
  bool temAparelho = false;
  try {
    // [18/11/2026] Porta própria: o aviso abre o ecrã de pendências da pessoa
    // (kind `documentos_em_falta`). Sem a função no servidor (migração por
    // aplicar), usa a porta antiga, que já entrega o aviso e a notificação.
    dynamic r;
    try {
      r = await sb.rpc('admin_pedir_documentos_em_falta', params: {
        'p_user_id': userId,
        'p_papel': tipoDestino,
        'p_titulo': titulo,
        'p_texto': texto,
        'p_itens': itens,
      });
    } catch (e) {
      if (!funcaoAindaNaoInstalada(e)) rethrow;
      r = await sb.rpc('admin_send_push_notification', params: {
        'p_recipient_type': tipoDestino,
        'p_recipient_id': userId,
        'p_title': titulo,
        'p_body': texto,
        'p_data': {'tipo': 'documentos_em_falta'},
      });
    }
    temAparelho = r is Map && r['fcm_token_found'] == true;
  } catch (e) {
    if (!ctx.mounted) return;
    await avisoResultadoAdmin(ctx,
        ok: false,
        titulo: 'O pedido NÃO foi enviado',
        texto: humanizeAdminRpcError(e));
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
  await avisoResultadoAdmin(
    ctx,
    titulo: 'Pedido enviado',
    texto: temAparelho
        ? 'A pessoa recebeu o aviso na app e a notificação no telemóvel. '
            'Ao tocar, abre a lista do que falta, onde envia cada documento.'
        : 'O aviso ficou gravado na app (no sino), mas esta pessoa não tem '
            'notificações ligadas. Mande também por SMS.',
    acaoExtra: (phone == null || phone.isEmpty) ? null : 'Mandar por SMS',
    // `query` à mão: queryParameters troca os espaços por '+', que a app de
    // SMS mostra tal e qual.
    onAcaoExtra: (phone == null || phone.isEmpty)
        ? null
        : () => launchUrl(Uri(
              scheme: 'sms',
              path: phone,
              query: 'body=${Uri.encodeComponent(texto)}',
            )),
  );
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
      await avisoResultadoAdmin(ctx,
          titulo: 'Comprovativo aprovado',
          texto: 'O comprovativo de $nome está aprovado e a pessoa foi avisada. '
              'Já pode aprovar o cadastro.');
    }
    return true;
  } catch (e) {
    if (ctx.mounted) {
      await avisoResultadoAdmin(ctx,
          ok: false,
          titulo: 'O comprovativo NÃO foi aprovado',
          texto: e.toString().contains('sem_documento')
              ? 'Ainda não há comprovativo para aprovar.'
              : humanizeAdminRpcError(e));
    }
    return false;
  }
}

/// Motivo mínimo da exceção do admin (o servidor recusa abaixo disto).
const int kMinLetrasMotivoExcecao = 10;

/// [18/11/2026] "Aprovar mesmo assim (exceção do admin)": o Danilo já mandou
/// aprovar gente sem o comprovativo aprovado (Felipe 16/11, Shelen 18/11 — à
/// mão por SQL). Pede o motivo, aprova pela RPC
/// `admin_aprovar_prestador_excecao` (a trava continua ligada para os outros)
/// e grava quem e porquê. [papel]: driver, cleaner, washer, handyman ou
/// service_provider; [id] é o id da linha desse papel. Devolve true se aprovou.
Future<bool> aprovarPrestadorComExcecao(
  BuildContext ctx, {
  required String papel,
  required String id,
  required String nome,
}) async {
  final ctrl = TextEditingController();
  String? erro;
  final motivo = await showDialog<String>(
    context: ctx,
    builder: (dCtx) => StatefulBuilder(
      builder: (dCtx, setLocal) => AlertDialog(
        key: const Key('admin-excecao-dialogo'),
        title: const Text('Aprovar mesmo assim (exceção do admin)'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vai aprovar $nome sem o comprovativo de atividade aprovado. '
                  'Fica registrado quem aprovou e porquê. A regra continua '
                  'ligada para os outros cadastros.'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('admin-excecao-motivo'),
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo (obrigatório, mínimo 10 letras)',
                  hintText: 'Ex.: ordem do Danilo, comprovativo chega amanhã',
                  border: OutlineInputBorder(),
                ),
              ),
              if (erro != null) ...[
                const SizedBox(height: 8),
                Text(erro!,
                    style: const TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancelar'),
          ),
          // Sempre ativo: um botão cinzento "não faz nada" aos olhos do
          // Danilo. Sem motivo, diz o que falta em vez de ignorar o toque.
          FilledButton(
            key: const Key('admin-excecao-confirmar'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.length < kMinLetrasMotivoExcecao) {
                setLocal(() => erro =
                    'Escreva o motivo com pelo menos $kMinLetrasMotivoExcecao letras.');
                return;
              }
              Navigator.pop(dCtx, t);
            },
            child: const Text('Aprovar com exceção'),
          ),
        ],
      ),
    ),
  );
  if (motivo == null) return false;
  try {
    await Supabase.instance.client.rpc('admin_aprovar_prestador_excecao',
        params: {'p_papel': papel, 'p_id': id, 'p_motivo': motivo});
    if (ctx.mounted) {
      await avisoResultadoAdmin(ctx,
          titulo: 'Aprovado com exceção',
          texto: '$nome está aprovado(a). Ficou registrado: "$motivo".');
    }
    return true;
  } catch (e) {
    if (ctx.mounted) {
      await avisoResultadoAdmin(ctx,
          ok: false,
          titulo: 'NÃO foi aprovado',
          texto: humanizeAdminRpcError(e));
    }
    return false;
  }
}
