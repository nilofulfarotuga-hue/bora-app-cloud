/// Secção TVDE da ficha do motorista no painel (missão
/// documentos-todos-papeis-22-10): tudo o que o motorista de passageiros tem
/// de ter, num sítio só — os impedimentos que o servidor calcula
/// (`admin_tvde_motoristas_conformidade`), o certificado TVDE, o contrato com
/// o operador, a carta, o seguro, o carro, o dístico e os documentos enviados
/// (`tvde_driver_documents`) com o estado de cada um. Cada ficheiro abre em
/// ecrã inteiro com zoom; o que falta aparece a vermelho.
///
/// Os ficheiros do TVDE ficam no balde `driver-documents` com caminho solto
/// (`<uid>/tvde/…`) — passa-se o [DocFoto.balde] para o painel os assinar.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import 'admin_documentos.dart';

/// Rótulos dos tipos de documento TVDE (como estão na base).
const Map<String, String> kRotulosDocTvde = {
  'certificado_tvde_imt': 'Certificado TVDE (IMT)',
  'contrato_operador': 'Contrato com o operador',
  'seguro': 'Seguro',
  'carta_conducao': 'Carta de condução',
  'dut': 'Documento único (DUA/livrete)',
  'inspecao': 'Inspeção',
  'registo_criminal': 'Registo criminal',
  'curso_atualizacao': 'Curso de atualização',
};

class _DadosTvde {
  _DadosTvde({
    this.motivos = const [],
    this.avisos = const [],
    this.ficha,
    this.veiculos = const [],
    this.docs = const [],
    this.erro,
  });
  final List<String> motivos;
  final List<String> avisos;
  final Map<String, dynamic>? ficha;
  final List<Map<String, dynamic>> veiculos;
  final List<Map<String, dynamic>> docs;
  final String? erro;
}

Future<_DadosTvde> _carregar(String userId, String? driverId) async {
  final sb = Supabase.instance.client;
  List<String> rotulos(Object? l) => (l is List ? l : const [])
      .whereType<Map>()
      .map((m) => m['rotulo']?.toString() ?? m['codigo']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
  try {
    final conf = await sb.rpc('admin_tvde_motoristas_conformidade');
    final eu = (conf is List ? conf : const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => m['user_id']?.toString() == userId)
        .toList();
    final ficha = await sb
        .from('motorista_ficha_legal')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    final dv = await sb
        .from('tvde_driver_vehicle')
        .select('vehicle_id, ativo')
        .eq('driver_user_id', userId);
    final ids = List<Map<String, dynamic>>.from(dv)
        .map((r) => r['vehicle_id']?.toString())
        .whereType<String>()
        .toList();
    final veiculos = ids.isEmpty
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await sb.from('tvde_vehicles').select().inFilter('id', ids));
    final docs = driverId == null
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await sb
            .from('tvde_driver_documents')
            .select()
            .eq('driver_id', driverId)
            .order('uploaded_at', ascending: false));
    return _DadosTvde(
      motivos: eu.isEmpty ? const [] : rotulos(eu.first['motivos']),
      avisos: eu.isEmpty ? const [] : rotulos(eu.first['avisos']),
      ficha: ficha == null ? null : Map<String, dynamic>.from(ficha),
      veiculos: veiculos,
      docs: docs,
    );
  } catch (e) {
    return _DadosTvde(erro: e.toString());
  }
}

String _validade(Object? v) {
  final d = DateTime.tryParse(v?.toString() ?? '');
  if (d == null) return '';
  final hoje = DateTime.now();
  final caducado = d.isBefore(DateTime(hoje.year, hoje.month, hoje.day));
  return ' · validade ${docData(v)}${caducado ? ' (CADUCADO)' : ''}';
}

/// O motorista é TVDE (passageiros) ou já tem dados TVDE.
bool eMotoristaTvde(Map<String, dynamic> d) {
  final vt = d['vehicle_type']?.toString();
  return vt == 'carro_passageiros' ||
      vt == 'carPassengers' ||
      docTexto(d['tvde_cert_foto_path']) != null ||
      docTexto(d['tvde_contrato_operador_path']) != null ||
      docTexto(d['carta_b_emitida_em']) != null ||
      docTexto(d['tvde_operator_id']) != null;
}

class FichaTvdeSecao extends StatefulWidget {
  const FichaTvdeSecao({super.key, required this.driver});

  /// Linha de `drivers` (com as colunas tvde_*).
  final Map<String, dynamic> driver;

  @override
  State<FichaTvdeSecao> createState() => _FichaTvdeSecaoState();
}

class _FichaTvdeSecaoState extends State<FichaTvdeSecao> {
  late final Future<_DadosTvde> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _carregar(widget.driver['user_id']?.toString() ?? '',
        widget.driver['id']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    return FutureBuilder<_DadosTvde>(
      future: _futuro,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final t = snap.data!;
        final f = t.ficha ?? const <String, dynamic>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DocSeccao('Motorista TVDE (passageiros)'),
            if (t.erro != null)
              Text('Não foi possível ler os dados TVDE: ${t.erro}',
                  style: const TextStyle(color: AppColors.error)),
            if (t.motivos.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Impede de trabalhar:',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final m in t.motivos)
                      Text('Falta: $m',
                          style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            for (final a in t.avisos)
              Text('Aviso: $a',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.warning)),
            DocCampo('Certificado TVDE n.º', f['tvde_cert_numero'], falta: true),
            DocCampo('Certificado: validade', docTexto(f['tvde_cert_validade']) == null ? null : docData(f['tvde_cert_validade']), falta: true),
            DocFoto(
              titulo: 'Certificado TVDE (foto)',
              urlOrPath: docTexto(d['tvde_cert_foto_path']),
              obrigatoria: true,
              balde: 'driver-documents',
            ),
            DocCampo('Carta n.º', f['carta_numero'], falta: true),
            DocCampo('Carta: validade', docTexto(f['carta_validade']) == null ? null : docData(f['carta_validade']), falta: true),
            DocCampo('Carta B emitida em', docTexto(d['carta_b_emitida_em']) == null ? null : docData(d['carta_b_emitida_em']), falta: true),
            DocCampo('Fala português', d['fala_portugues'] == null ? null : (d['fala_portugues'] == true ? 'Sim' : 'Não')),
            DocCampo('Curso de atualização', docTexto(d['tvde_curso_atualizacao_em']) == null ? null : docData(d['tvde_curso_atualizacao_em'])),
            DocCampo('Operador', f['operador_nome'] ?? (docTexto(d['tvde_operator_id']) == null ? null : 'associado'), falta: true),
            DocCampo('Operador: NIF / licença', [docTexto(f['operador_nif']), docTexto(f['operador_licenca'])].whereType<String>().join(' · ')),
            DocFoto(
              titulo: 'Contrato com o operador',
              urlOrPath: docTexto(d['tvde_contrato_operador_path']),
              obrigatoria: true,
              balde: 'driver-documents',
            ),
            DocCampo('Dístico n.º', [docTexto(f['distico_numero']), _validade(f['distico_validade']).replaceFirst(' · ', '')].where((s) => s != null && s.isNotEmpty).join(' · ')),
            DocCampo('Inspeção', docTexto(f['inspecao_validade']) == null ? null : 'válida até ${docData(f['inspecao_validade'])}'),
            DocCampo('Seguro', [docTexto(f['seguro_seguradora']), docTexto(f['seguro_apolice'])].whereType<String>().join(' · ') + _validade(f['seguro_validade'])),
            DocCampo('Seguro cobre passageiros', f['seguro_cobre_passageiros'] == null ? null : (f['seguro_cobre_passageiros'] == true ? 'Sim' : 'Não')),
            const DocSeccao('Carro TVDE'),
            if (t.veiculos.isEmpty)
              const DocFoto(
                  titulo: 'Carro TVDE associado', urlOrPath: null, obrigatoria: true),
            for (final v in t.veiculos) ...[
              DocCampo('Carro', '${docTexto(v['marca']) ?? ''} ${docTexto(v['modelo']) ?? ''} · ${docTexto(v['matricula']) ?? '—'}'.trim()),
              DocCampo('Estado', switch (v['estado']) {
                'aprovado' => 'Aprovado',
                'pendente' || 'submetido' => 'À espera de aprovação',
                'recusado' => 'Recusado${docTexto(v['estado_motivo']) == null ? '' : ': ${v['estado_motivo']}'}',
                final e => docTexto(e),
              }),
              DocCampo('Registo IMT', '${docTexto(v['registo_imt_numero']) ?? '—'}${_validade(v['registo_imt_validade'])}'),
              DocCampo('Inspeção (próxima)', docTexto(v['inspecao_proxima']) == null ? null : docData(v['inspecao_proxima']), falta: true),
              DocCampo('Seguro do carro', '${docTexto(v['seguro_seguradora']) ?? '—'}${_validade(v['seguro_validade'])}', falta: true),
              DocFoto(
                titulo: 'Foto do carro',
                urlOrPath: docTexto(v['foto_path']),
                obrigatoria: true,
                balde: 'driver-documents',
              ),
              DocFoto(
                titulo: 'Seguro (foto)',
                urlOrPath: docTexto(v['seguro_path']),
                obrigatoria: true,
                balde: 'driver-documents',
              ),
            ],
            const DocSeccao('Documentos TVDE enviados'),
            if (t.docs.isEmpty)
              const Text('Nenhum documento TVDE enviado.',
                  style: TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w600)),
            for (final doc in t.docs)
              DocFoto(
                titulo: kRotulosDocTvde[doc['doc_type']] ??
                    doc['doc_type']?.toString() ??
                    'Documento',
                detalhe: 'Estado: ${switch (doc['status']) {
                  'approved' || 'aprovado' => 'Aprovado',
                  'rejected' || 'recusado' => 'Recusado',
                  _ => 'À espera de revisão',
                }}${_validade(doc['validade'])} · enviado ${docData(doc['uploaded_at'], hora: true)}',
                urlOrPath: docTexto(doc['file_path']),
                obrigatoria: false,
                balde: 'driver-documents',
              ),
          ],
        );
      },
    );
  }
}
