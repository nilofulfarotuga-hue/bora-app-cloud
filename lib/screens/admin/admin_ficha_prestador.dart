/// FICHA COMPLETA DO PRESTADOR (limpeza e lavagem) no painel — missão
/// documentos-todos-papeis-22-10. Mostra tudo o que o cadastro pede, pela
/// mesma ordem: foto de perfil, dados pessoais, documento de identificação,
/// carta de condução (lavagem), NIF, comprovativo de atividade, IBAN,
/// materiais, zona de trabalho e a declaração DSA. Cada foto abre em ecrã
/// inteiro com zoom; o que falta aparece a vermelho com o botão
/// "Pedir documentos em falta". Painel em PT-BR.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/driver_documentos.dart'
    show DocEmFalta, idadeEmAnos;
import '../../services/prestador_documentos.dart';
import '../../widgets/admin_documentos.dart';
import '../../widgets/private_bucket_image.dart';

/// 'cleaner' (limpeza) ou 'washer' (lavagem).
typedef PapelPrestador = String;

String _baldeDe(PapelPrestador p) =>
    p == 'washer' ? 'washer-documents' : 'cleaner-documents';

String _quemDe(PapelPrestador p) =>
    p == 'washer' ? 'lavador' : 'profissional de limpeza';

/// O que falta (mesma regra da app do prestador), com o comprovativo.
List<DocEmFalta> faltaDoPrestador(PapelPrestador papel, Map<String, dynamic> l) =>
    papel == 'washer'
        ? documentosEmFaltaLavagem(l, atividadeEmFalta: atividadeEmFaltaDe(l))
        : documentosEmFaltaLimpeza(l, atividadeEmFalta: atividadeEmFaltaDe(l));

/// Abre a ficha. [linha] é a linha de `cleaners`/`washers` (to_jsonb).
Future<void> abrirFichaPrestador(
  BuildContext context, {
  required PapelPrestador papel,
  required Map<String, dynamic> linha,
  VoidCallback? aoMudar,
}) async {
  final l = Map<String, dynamic>.from(linha);
  await juntarAtividadeAdmin(Supabase.instance.client, [l]);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (sheetCtx, sc) => _FichaPrestador(
        papel: papel,
        l: l,
        scrollController: sc,
        aoMudar: aoMudar,
      ),
    ),
  );
}

class _FichaPrestador extends StatelessWidget {
  const _FichaPrestador({
    required this.papel,
    required this.l,
    required this.scrollController,
    this.aoMudar,
  });
  final PapelPrestador papel;
  final Map<String, dynamic> l;
  final ScrollController scrollController;
  final VoidCallback? aoMudar;

  @override
  Widget build(BuildContext context) {
    final falta = faltaDoPrestador(papel, l);
    final chaves = falta.map((f) => f.chave).toSet();
    bool faltaItem(String c) => chaves.contains(c);
    final foto = docTexto(l['photo_url']);
    final nascimento = DateTime.tryParse(l['birth_date']?.toString() ?? '');
    final idade = idadeEmAnos(nascimento, DateTime.now());
    final docs = docsDe(l);
    final materiais = (docs['materials_list'] is List)
        ? (docs['materials_list'] as List).map((e) => e.toString()).toList()
        : (l['equipment'] is List)
            ? (l['equipment'] as List).map((e) => e.toString()).toList()
            : const <String>[];
    final fiscal = l['_fiscal'];
    final atividadeAberta =
        fiscal is Map ? fiscal['atividade_aberta'] as bool? : null;
    final balde = _baldeDe(papel);
    final userId = l['user_id']?.toString();
    final nome = docTexto(l['name']) ?? '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: ListView(
        controller: scrollController,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Center(
            child: foto != null
                ? SizedBox(
                    width: 110,
                    height: 110,
                    child: PrivateBucketImage(
                      urlOrPath: foto,
                      width: 110,
                      height: 110,
                      borderRadius: BorderRadius.circular(55),
                      tituloAmpliada: 'Foto de perfil',
                    ),
                  )
                : Container(
                    width: 110,
                    height: 110,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: const Text('Falta:\nfoto',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700)),
                  ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(nome,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          Center(
            child: Text(
              '${papel == 'washer' ? 'Lavagem' : 'Limpeza'} · ${switch (l['approval_status']) {
                'approved' => 'aprovado',
                'pending' => 'pendente',
                'rejected' => 'recusado',
                'suspended' => 'suspenso',
                final s => s?.toString() ?? '—',
              }}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          if (falta.isNotEmpty) ...[
            const SizedBox(height: 14),
            DocFaltaCaixa(
              falta: falta.map((f) => f.rotulo).toList(),
              onPedir: userId == null
                  ? null
                  : () => pedirDocumentosEmFalta(context,
                      userId: userId,
                      tipoDestino: papel,
                      quem: _quemDe(papel),
                      itens: falta.map((f) => f.rotulo).toList(),
                      telefone: l['phone'] as String?,
                      refId: l['id']?.toString()),
            ),
          ],
          if (docTexto(l['rejection_reason']) != null) ...[
            const SizedBox(height: 12),
            Text('Motivo de recusa: ${l['rejection_reason']}',
                style: const TextStyle(color: AppColors.error)),
          ],

          const DocSeccao('Dados pessoais'),
          DocCampo('Nome que aparece', l['name']),
          DocCampo('Nome legal', l['legal_name'], falta: faltaItem('legal_name')),
          DocCampo('Telefone', l['phone']),
          DocCampo('E-mail', l['email']),
          DocCampo(
            'Data de nascimento',
            nascimento == null
                ? null
                : '${docData(l['birth_date'])}${idade == null ? '' : ' ($idade anos)'}',
            falta: faltaItem('birth_date'),
          ),
          DocCampo('Morada', l['address'], falta: faltaItem('address')),

          const DocSeccao('Documentos'),
          DocFoto(
            titulo: 'Documento de identificação',
            urlOrPath: docCaminho(l, 'id_doc'),
            obrigatoria: true,
            balde: balde,
          ),
          if (papel == 'washer')
            DocFoto(
              titulo: 'Carta de condução',
              urlOrPath: docCaminho(l, 'driving_license'),
              obrigatoria: true,
              balde: balde,
            ),
          if (docCaminho(l, 'address_proof') != null)
            DocFoto(
              titulo: 'Comprovativo de morada',
              urlOrPath: docCaminho(l, 'address_proof'),
              obrigatoria: false,
              balde: balde,
            ),

          const DocSeccao('Fiscal'),
          DocCampo('NIF', l['nif'], falta: faltaItem('nif')),
          DocCampo('Atividade aberta',
              atividadeAberta == null ? null : (atividadeAberta ? 'Sim' : 'Não')),
          DocComprovativoAtividade(
            atividade: l['_atividade'] is Map
                ? Map<String, dynamic>.from(l['_atividade'] as Map)
                : null,
            falta: faltaItem('atividade'),
            onAprovar: userId == null
                ? null
                : () async {
                    final ok = await aprovarComprovativoAtividade(context,
                        userId: userId,
                        nome: nome,
                        nif: (l['_atividade'] as Map?)?['nif']?.toString() ??
                            l['nif']?.toString());
                    if (ok && context.mounted) {
                      Navigator.of(context).maybePop();
                      aoMudar?.call();
                    }
                  },
          ),

          const DocSeccao('Pagamento'),
          DocCampo('IBAN', l['iban'], falta: faltaItem('iban')),
          DocCampo('MB Way', l['mbway_phone']),

          const DocSeccao('Trabalho'),
          DocCampo(
            'Materiais',
            docs['materials_ok'] == true
                ? (materiais.isEmpty ? 'Confirmados' : materiais.join(', '))
                : null,
            falta: faltaItem('materials'),
          ),
          DocCampo('Zona base', l['base_address']),
          DocCampo('Raio', l['service_radius_km'] == null
              ? null
              : '${(l['service_radius_km'] as num).round()} km'),
          DocCampo('Sobre', l['bio']),

          const DocSeccao('Termos'),
          DocCampo(
            'Autocertificação DSA',
            docTexto(l['dsa_self_certified_at']) == null
                ? null
                : '${docData(l['dsa_self_certified_at'], hora: true)}'
                    '${docTexto(l['dsa_self_cert_version']) == null ? '' : ' · v${l['dsa_self_cert_version']}'}',
            falta: faltaItem('dsa'),
          ),
          DocCampo('Candidatura', docData(l['created_at'], hora: true)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Linha vermelha "Falta: …" para os cartões das listas.
class LinhaFaltaPrestador extends StatelessWidget {
  const LinhaFaltaPrestador({super.key, required this.falta});
  final List<DocEmFalta> falta;

  @override
  Widget build(BuildContext context) {
    if (falta.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'Falta: ${falta.map((f) => f.rotulo.toLowerCase()).join(', ')}',
        style: const TextStyle(
            fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600),
      ),
    );
  }
}
