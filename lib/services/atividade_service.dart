/// COMPROVATIVO DE ATIVIDADE NAS FINANÇAS (Bloco C · 20/10/2026).
///
/// Uma verdade por pessoa, no servidor: `provider_atividade` (uma linha por
/// `user_id`, todos os papéis juntos — PADRAO_BORA §1.25). A app nunca escreve
/// nessa tabela: lê pelo RPC `provider_atividade_get` e envia pelo RPC
/// `provider_atividade_enviar`, depois de subir o ficheiro para o bucket
/// privado `provider-atividade`, na pasta `<user_id>/`.
///
/// Quem já trabalhava antes da data de corte NÃO fica bloqueado: só vê o aviso.
/// Para as candidaturas novas o servidor só deixa aprovar o papel depois de o
/// admin aprovar o comprovativo (gatilho `trg_atividade_antes_de_ativar`).
///
/// Falha aberta: sem rede ou com erro, o aviso não aparece e nada bloqueia.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/legal_fields_section.dart' show LegalFieldsValidators;
import 'robo_documentos.dart' show mensagemDaPrevia;
import 'robo_documentos_service.dart' show RoboDocumentosApp;

/// Os quatro estados, tal como vivem na coluna `atividade_status`.
enum AtividadeStatus { porEnviar, emAnalise, aprovada, recusada }

AtividadeStatus atividadeStatusDe(String? v) => switch (v) {
      'em_analise' => AtividadeStatus.emAnalise,
      'aprovada' => AtividadeStatus.aprovada,
      'recusada' => AtividadeStatus.recusada,
      _ => AtividadeStatus.porEnviar,
    };

/// NIF português válido para o comprovativo — as MESMAS regras do servidor
/// (`public._nif_valido`): 9 dígitos, dígito de controlo mod 11, sem os
/// números de enfeite (111111111, 123456789…) e a começar por 1, 2, 3, 5, 6,
/// 8 ou 9. Se uma mudar, mudam as duas (teste de paridade em
/// `test/atividade_service_test.dart`).
bool nifAtividadeValido(String raw) {
  final nif = LegalFieldsValidators.normalizeNif(raw);
  if (!LegalFieldsValidators.isValidNif(nif)) return false;
  return const {'1', '2', '3', '5', '6', '8', '9'}.contains(nif[0]);
}

/// Mensagem do campo do NIF (null = está bom).
String? validarNifAtividade(String? v) {
  final nif = LegalFieldsValidators.normalizeNif(v ?? '');
  if (nif.isEmpty) return 'Indica o teu NIF.';
  if (nif.length != 9) return 'O NIF tem 9 algarismos.';
  if (!nifAtividadeValido(nif)) {
    return 'Este NIF não é válido. Confirma os algarismos.';
  }
  return null;
}

/// Tipo do ficheiro pelos primeiros bytes (não pelo nome — o iPhone chama
/// `.jpg` a coisas que são HEIC). `heic` volta como tal para a mensagem certa;
/// o bucket só aceita jpg, png e pdf.
enum TipoComprovativo { pdf, jpg, png, heic, desconhecido }

TipoComprovativo tipoDoComprovativo(Uint8List b) {
  if (b.length >= 5 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46 &&
      b[4] == 0x2D) {
    return TipoComprovativo.pdf; // %PDF-
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return TipoComprovativo.jpg;
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return TipoComprovativo.png;
  }
  if (b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    final marca = String.fromCharCodes(b.sublist(8, 12));
    if (const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'heim', 'heis'}
        .contains(marca)) {
      return TipoComprovativo.heic;
    }
  }
  return TipoComprovativo.desconhecido;
}

/// Tamanho máximo (igual ao `file_size_limit` do bucket).
const int kComprovativoMaxBytes = 10 * 1024 * 1024;

/// Porque é que este ficheiro não pode ir (null = pode). PT-PT.
String? problemaDoComprovativo(Uint8List bytes) {
  if (bytes.isEmpty) return 'O ficheiro está vazio. Escolhe outro.';
  if (bytes.length > kComprovativoMaxBytes) {
    return 'O ficheiro tem mais de 10 MB. Tira uma foto ou escolhe um PDF mais pequeno.';
  }
  return switch (tipoDoComprovativo(bytes)) {
    TipoComprovativo.heic =>
      'Esta foto está em HEIC. Usa «Tirar foto» ou «Escolher da galeria» (a app converte para JPG) ou envia em PDF.',
    TipoComprovativo.desconhecido =>
      'Só dá para enviar uma foto (JPG ou PNG) ou um PDF.',
    _ => null,
  };
}

/// O estado do comprovativo da pessoa, tal como o servidor o devolve.
class AtividadeEstado {
  const AtividadeEstado({
    required this.ePrestador,
    this.papeis = const [],
    this.status = AtividadeStatus.porEnviar,
    this.temDocumento = false,
    this.documentoTipo,
    this.nif,
    this.nifSugerido,
    this.enviadoEm,
    this.decididoEm,
    this.motivo,
    this.obrigatoria = false,
    this.interruptor = false,
  });

  factory AtividadeEstado.fromJson(Map<String, dynamic> j) {
    DateTime? data(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    String? texto(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return AtividadeEstado(
      ePrestador: j['e_prestador'] == true,
      papeis: (j['papeis'] is List)
          ? (j['papeis'] as List).map((e) => e.toString()).toList()
          : const [],
      status: atividadeStatusDe(j['atividade_status']?.toString()),
      temDocumento: j['tem_documento'] == true,
      documentoTipo: texto(j['documento_tipo']),
      nif: texto(j['nif']),
      nifSugerido: texto(j['nif_sugerido']),
      enviadoEm: data(j['enviado_em']),
      decididoEm: data(j['decidido_em']),
      motivo: texto(j['motivo']),
      obrigatoria: j['obrigatoria'] == true,
      interruptor: j['interruptor'] == true,
    );
  }

  final bool ePrestador;
  final List<String> papeis;
  final AtividadeStatus status;
  final bool temDocumento;
  final String? documentoTipo;
  final String? nif;
  final String? nifSugerido;
  final DateTime? enviadoEm;
  final DateTime? decididoEm;
  final String? motivo;

  /// O passo conta para a aprovação desta pessoa (candidatura nova com o
  /// interruptor ligado). Para quem já trabalhava é sempre false.
  final bool obrigatoria;
  final bool interruptor;

  /// Ainda tem de enviar alguma coisa. "Em análise" sem documento é o caso de
  /// quem disse que já tem atividade aberta mas ainda não mandou o papel.
  bool get precisaDeEnviar =>
      status == AtividadeStatus.porEnviar ||
      status == AtividadeStatus.recusada ||
      (status == AtividadeStatus.emAnalise && !temDocumento);

  /// Mostra-se o aviso no ecrã principal do prestador. Nunca bloqueia nada.
  bool get mostrarAviso => ePrestador && precisaDeEnviar;

  /// Pode enviar pelo ecrã — só quando o comprovativo falta (por enviar,
  /// recusado, ou em análise sem documento). Depois de enviado fica à espera
  /// da decisão; para trocar, o admin usa "Pedir de novo". O bucket e a RPC
  /// dizem o mesmo (ronda 1 da revisão, 20/10/2026).
  bool get podeEnviar => ePrestador && precisaDeEnviar;

  String get rotulo => switch (status) {
        AtividadeStatus.porEnviar => 'Por enviar',
        AtividadeStatus.emAnalise =>
          temDocumento ? 'Em análise' : 'Falta o comprovativo',
        AtividadeStatus.aprovada => 'Aprovada',
        AtividadeStatus.recusada => 'Recusada',
      };

  /// O que o ecrã diz, em PT-PT simples.
  String get explicacao => switch (status) {
        AtividadeStatus.porEnviar =>
          'Para trabalhares no Bora por conta própria precisas de atividade aberta nas '
              'Finanças. Envia o teu NIF e uma foto ou PDF do comprovativo.',
        AtividadeStatus.emAnalise => temDocumento
            ? 'Recebemos o teu comprovativo. Vamos ver e avisamos-te. Se enviaste o '
                'ficheiro errado, fala connosco no Suporte.'
            : 'Disseste-nos que já tens atividade aberta nas Finanças. Falta enviares o '
                'comprovativo (foto ou PDF).',
        AtividadeStatus.aprovada =>
          'O teu comprovativo de atividade está aprovado. Obrigado!',
        AtividadeStatus.recusada =>
          'O comprovativo foi recusado${motivo == null ? '' : ': $motivo'}. Envia outro, por favor.',
      };
}

/// Resultado de um envio.
class EnvioAtividade {
  const EnvioAtividade.ok(this.estado)
      : erro = null,
        avisoRobo = null,
        caminho = null;
  const EnvioAtividade.falhou(this.erro)
      : estado = null,
        avisoRobo = null,
        caminho = null;

  /// O robô de documentos diz, com confiança, que o ficheiro parece não ser o
  /// comprovativo. Nada foi enviado ainda: a app mostra [avisoRobo] e deixa a
  /// pessoa escolher outro ficheiro ou enviar mesmo assim (o ficheiro já está
  /// no balde, em [caminho]).
  const EnvioAtividade.avisoDoRobo({required this.avisoRobo, required this.caminho})
      : estado = null,
        erro = null;

  final AtividadeEstado? estado;
  final String? erro;
  final String? avisoRobo;
  final String? caminho;
  bool get ok => estado != null;
  bool get eAvisoDoRobo => avisoRobo != null;
}

/// Traduz o erro do servidor para PT-PT (função pura, testada).
String mensagemDoErroAtividade(Object e) {
  final s = e.toString();
  if (s.contains('nif_invalido')) {
    return 'Este NIF não é válido. Confirma os algarismos.';
  }
  if (s.contains('ja_aprovada')) return 'O teu comprovativo já está aprovado.';
  if (s.contains('ja_enviado') || s.contains('row-level security')) {
    return 'O teu comprovativo já foi enviado e está em análise. Se precisas de o '
        'trocar, fala connosco no Suporte.';
  }
  if (s.contains('nao_e_prestador')) {
    return 'Esta conta ainda não tem nenhum trabalho no Bora. Faz primeiro a candidatura.';
  }
  if (s.contains('documento_nao_encontrado') ||
      s.contains('documento_invalido')) {
    return 'O ficheiro não chegou ao servidor. Tenta outra vez.';
  }
  if (s.contains('tipo_invalido') || s.contains('mime') || s.contains('415')) {
    return 'Só dá para enviar uma foto (JPG ou PNG) ou um PDF.';
  }
  if (s.contains('Payload too large') ||
      s.contains('413') ||
      s.contains('exceeded')) {
    return 'O ficheiro tem mais de 10 MB. Tira uma foto ou escolhe um PDF mais pequeno.';
  }
  if (s.contains('sem_sessao') || s.contains('JWT')) {
    return 'A tua sessão terminou. Entra outra vez na app e tenta de novo.';
  }
  if (e is TimeoutException) {
    return 'A ligação está lenta. Tenta outra vez daqui a pouco.';
  }
  return 'Não foi possível enviar. Verifica a ligação e tenta outra vez.';
}

class AtividadeService {
  AtividadeService._();

  static const String bucket = 'provider-atividade';
  static const Duration _tecto = Duration(seconds: 8);

  static SupabaseClient get _sb => Supabase.instance.client;

  /// O estado da pessoa com sessão; null sem sessão, sem rede ou com erro.
  static Future<AtividadeEstado?> carregar() async {
    try {
      if (_sb.auth.currentUser == null) return null;
      final r = await _sb.rpc('provider_atividade_get').timeout(_tecto);
      if (r is Map) {
        return AtividadeEstado.fromJson(Map<String, dynamic>.from(r));
      }
    } catch (_) {
      // falha aberta: sem aviso, sem bloqueio
    }
    return null;
  }

  /// Sobe o ficheiro para `<user_id>/comprovativo_<hora>.<ext>` e regista o
  /// envio com o NIF. Nunca põe "aprovada": o servidor deixa "em análise".
  static Future<EnvioAtividade> enviar({
    required String nif,
    required Uint8List bytes,
    bool ignorarRobo = false,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      return const EnvioAtividade.falhou(
          'A tua sessão terminou. Entra outra vez na app e tenta de novo.');
    }
    final nifLimpo = LegalFieldsValidators.normalizeNif(nif);
    final erroNif = validarNifAtividade(nifLimpo);
    if (erroNif != null) return EnvioAtividade.falhou(erroNif);
    final problema = problemaDoComprovativo(bytes);
    if (problema != null) return EnvioAtividade.falhou(problema);

    final tipo = tipoDoComprovativo(bytes);
    final (ext, mime) = switch (tipo) {
      TipoComprovativo.pdf => ('pdf', 'application/pdf'),
      TipoComprovativo.png => ('png', 'image/png'),
      _ => ('jpg', 'image/jpeg'),
    };
    final path =
        '$uid/comprovativo_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _sb.storage
          .from(bucket)
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: mime))
          .timeout(const Duration(seconds: 60));
      // Verificação na hora (adendo 3): o robô olha para o ficheiro ANTES de ele
      // ser enviado. Só avisa quando está a agir e tem a certeza de que está
      // errado; sem rede ou com qualquer problema, segue como dantes.
      if (!ignorarRobo) {
        final p = await RoboDocumentosApp.previa(
            campo: 'provider_atividade.documento_path', path: path, nif: nifLimpo);
        if (p != null && p.avisar) {
          return EnvioAtividade.avisoDoRobo(
            avisoRobo: mensagemDaPrevia(
                campo: 'provider_atividade.documento_path',
                tipoDetetado: p.tipoDetetado),
            caminho: path,
          );
        }
      }
      return _registar(nifLimpo, path);
    } catch (e) {
      return EnvioAtividade.falhou(mensagemDoErroAtividade(e));
    }
  }

  /// "Enviar mesmo assim": o ficheiro já está no balde; só falta registar o envio.
  static Future<EnvioAtividade> enviarCaminho({
    required String nif,
    required String caminho,
  }) async {
    final nifLimpo = LegalFieldsValidators.normalizeNif(nif);
    final erroNif = validarNifAtividade(nifLimpo);
    if (erroNif != null) return EnvioAtividade.falhou(erroNif);
    try {
      return await _registar(nifLimpo, caminho);
    } catch (e) {
      return EnvioAtividade.falhou(mensagemDoErroAtividade(e));
    }
  }

  static Future<EnvioAtividade> _registar(String nifLimpo, String path) async {
    final r = await _sb.rpc('provider_atividade_enviar', params: {
      'p_nif': nifLimpo,
      'p_documento_path': path,
    }).timeout(_tecto);
    if (r is Map) {
      return EnvioAtividade.ok(
          AtividadeEstado.fromJson(Map<String, dynamic>.from(r)));
    }
    return const EnvioAtividade.falhou(
        'Não foi possível enviar. Verifica a ligação e tenta outra vez.');
  }
}
