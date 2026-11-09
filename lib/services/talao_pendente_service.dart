// M1 adendo 1 (08/11/2026) — Danilo: "toda foto de talão que o estafeta tira
// tem de ficar guardada num sítio certo, para sempre, e nunca se pode perder."
//
// Fila durável das fotos de talão do estafeta (mercado/restaurante
// não-parceiro e Favores):
//
//  1. `guardar` copia a foto para a pasta de documentos da app
//     (taloes_pendentes/<pedido>_<fotoId>.jpg) e regista-a nas
//     SharedPreferences ANTES de qualquer envio. App fechada = foto guardada.
//  2. `enviar` sobe-a pelo ReceiptUploadService com o MESMO fotoId em todas
//     as tentativas: o servidor (upload-receipt) grava
//     AAAA/MM/<pedido>/<fotoId>.jpg sem substituir e uma repetição devolve o
//     mesmo caminho (nunca duplica). Falhou → a cópia local fica.
//  3. `iniciarReenvioAutomatico` tenta as pendentes já e de 60 em 60 s.
//  4. Limpeza: só se apagam cópias locais de fotos JÁ confirmadas no servidor
//     há mais de 7 dias. Uma pendente nunca se apaga.
//
// Web: não há disco por caminho. A fila fica só em memória e o envio é
// directo, como antes.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/io_compat.dart';
import 'receipt_upload_service.dart';

/// Assinatura do envio ao servidor (a de [ReceiptUploadService.uploadReceipt]).
/// Trocável nos testes para não precisar do Supabase.
typedef EnviarTalaoFn = Future<String> Function({
  required String orderId,
  required File photoFile,
  required int totalCents,
  String? fotoId,
  DateTime? tiradaEm,
});

/// Uma foto de talão na fila do telemóvel.
@immutable
class TalaoPendente {
  const TalaoPendente({
    required this.orderId,
    required this.fotoId,
    required this.localPath,
    required this.totalCents,
    required this.tiradaEm,
    this.estado = estadoPendente,
    this.path,
    this.tentativas = 0,
    this.ultimoErro,
    this.ultimaTentativa,
    this.enviadoEm,
  });

  static const String estadoPendente = 'pendente';
  static const String estadoEnviado = 'enviado';

  /// A cópia local desapareceu antes de subir (raro: só se alguém limpar os
  /// dados da app). Deixa de se tentar; o ecrã pede outra foto.
  static const String estadoSemFicheiro = 'sem_ficheiro';

  final String orderId;
  final String fotoId;
  final String localPath;
  final int totalCents;
  final DateTime tiradaEm;
  final String estado;

  /// Caminho no bucket `receipts`, só depois de o servidor confirmar.
  final String? path;
  final int tentativas;

  /// Último erro, com prefixo `rede:`, `servidor:` ou `ficheiro:`.
  final String? ultimoErro;
  final DateTime? ultimaTentativa;
  final DateTime? enviadoEm;

  bool get pendente => estado == estadoPendente;
  bool get enviado => estado == estadoEnviado && path != null;
  bool get falhouPorRede => ultimoErro?.startsWith('rede:') ?? false;

  TalaoPendente _comoEnviado(String caminho, DateTime quando) => TalaoPendente(
        orderId: orderId,
        fotoId: fotoId,
        localPath: localPath,
        totalCents: totalCents,
        tiradaEm: tiradaEm,
        estado: estadoEnviado,
        path: caminho,
        tentativas: tentativas + 1,
        ultimaTentativa: quando,
        enviadoEm: quando,
      );

  TalaoPendente _comFalha(String erro, DateTime quando, {String? novoEstado}) =>
      TalaoPendente(
        orderId: orderId,
        fotoId: fotoId,
        localPath: localPath,
        totalCents: totalCents,
        tiradaEm: tiradaEm,
        estado: novoEstado ?? estado,
        path: path,
        tentativas: tentativas + 1,
        ultimoErro: erro,
        ultimaTentativa: quando,
        enviadoEm: enviadoEm,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'orderId': orderId,
        'fotoId': fotoId,
        'localPath': localPath,
        'totalCents': totalCents,
        'tiradaEm': tiradaEm.toIso8601String(),
        'estado': estado,
        'path': path,
        'tentativas': tentativas,
        'ultimoErro': ultimoErro,
        'ultimaTentativa': ultimaTentativa?.toIso8601String(),
        'enviadoEm': enviadoEm?.toIso8601String(),
      };

  /// Tolerante: uma linha estragada devolve null em vez de rebentar a fila.
  static TalaoPendente? fromJson(Object? j) {
    if (j is! Map) return null;
    final orderId = j['orderId'];
    final fotoId = j['fotoId'];
    final localPath = j['localPath'];
    final tirada = DateTime.tryParse('${j['tiradaEm']}');
    if (orderId is! String || fotoId is! String || localPath is! String) {
      return null;
    }
    if (tirada == null) return null;
    DateTime? data(Object? v) => v is String ? DateTime.tryParse(v) : null;
    int inteiro(Object? v) => v is num ? v.toInt() : 0;
    String? texto(Object? v) => v is String ? v : null;
    final estado = j['estado'];
    return TalaoPendente(
      orderId: orderId,
      fotoId: fotoId,
      localPath: localPath,
      totalCents: inteiro(j['totalCents']),
      tiradaEm: tirada,
      estado: estado is String ? estado : estadoPendente,
      path: texto(j['path']),
      tentativas: inteiro(j['tentativas']),
      ultimoErro: texto(j['ultimoErro']),
      ultimaTentativa: data(j['ultimaTentativa']),
      enviadoEm: data(j['enviadoEm']),
    );
  }
}

class TalaoPendenteService {
  TalaoPendenteService._();

  static const String chavePrefs = 'taloes_pendentes_v1';
  static const String pasta = 'taloes_pendentes';
  static const Duration intervaloReenvio = Duration(seconds: 60);
  static const Duration limiteEnvioPadrao = Duration(seconds: 60);
  static const Duration guardarCopiaEnviada = Duration(days: 7);

  /// Envio ao servidor. Trocável nos testes.
  static EnviarTalaoFn enviarParaServidor = ReceiptUploadService.uploadReceipt;

  /// Pasta base da cópia local. Trocável nos testes.
  static Future<String> Function() pastaBase = _pastaDocumentos;

  /// Relógio. Trocável nos testes.
  static DateTime Function() agora = DateTime.now;

  static final List<TalaoPendente> _lista = <TalaoPendente>[];
  static bool _carregadoOk = false;
  static Future<void>? _carregamento;
  static final Map<String, Future<String?>> _emCurso =
      <String, Future<String?>>{};
  static Future<void>? _reenvio;
  static Timer? _relogio;
  static final math.Random _sorte = math.Random();

  static Future<String> _pastaDocumentos() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// Lê a fila gravada no telemóvel (uma vez). Os métodos síncronos
  /// ([ultimoDo], [pendentesDo], [porFotoId]) só veem o disco depois disto.
  static Future<void> carregar() {
    if (kIsWeb || _carregadoOk) return Future<void>.value();
    return _carregamento ??=
        _carregarDoDisco().whenComplete(() => _carregamento = null);
  }

  static Future<void> _carregarDoDisco() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // Sem acesso ao disco: tenta-se outra vez na próxima chamada e, até lá,
      // nada se escreve por cima do que lá está.
      debugPrint('[talao_pendente] ler fila: $e');
      return;
    }
    try {
      final bruto = prefs.getString(chavePrefs);
      final lido = (bruto == null || bruto.isEmpty) ? null : jsonDecode(bruto);
      if (lido is List) {
        final vistos = _lista.map((t) => t.fotoId).toSet();
        for (final j in lido) {
          final t = TalaoPendente.fromJson(j);
          if (t != null && vistos.add(t.fotoId)) _lista.add(t);
        }
      }
    } catch (e) {
      debugPrint('[talao_pendente] fila ilegível: $e');
    }
    _carregadoOk = true;
  }

  static Future<void> _gravar() async {
    if (kIsWeb || !_carregadoOk) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        chavePrefs,
        jsonEncode(_lista.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[talao_pendente] gravar fila: $e');
    }
  }

  static void _substituir(TalaoPendente t) {
    final i = _lista.indexWhere((x) => x.fotoId == t.fotoId);
    if (i >= 0) {
      _lista[i] = t;
    } else {
      _lista.add(t);
    }
  }

  static String _novoFotoId(DateTime quando) {
    final hex = _sorte.nextInt(0x1000000).toRadixString(16).padLeft(6, '0');
    return '${quando.millisecondsSinceEpoch}-$hex';
  }

  static String _nomeSeguro(String orderId) {
    final s = orderId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  /// Guarda a foto no telemóvel ANTES de a enviar e devolve a entrada da
  /// fila. Não lança: se a cópia falhar (disco cheio), fica o caminho
  /// original da câmara.
  static Future<TalaoPendente> guardar({
    required String orderId,
    required File foto,
    required int totalCents,
  }) async {
    final quando = agora();
    final fotoId = _novoFotoId(quando);
    var localPath = foto.path;
    if (!kIsWeb) {
      await carregar();
      try {
        final base = await pastaBase();
        final dir = Directory('$base/$pasta');
        await dir.create(recursive: true);
        final destino = File('${dir.path}/${_nomeSeguro(orderId)}_$fotoId.jpg');
        await destino.writeAsBytes(await foto.readAsBytes(), flush: true);
        localPath = destino.path;
      } catch (e) {
        debugPrint('[talao_pendente] cópia local falhou, fica o original: $e');
      }
    }
    final t = TalaoPendente(
      orderId: orderId,
      fotoId: fotoId,
      localPath: localPath,
      totalCents: totalCents,
      tiradaEm: quando,
    );
    _lista.add(t);
    await _gravar();
    return t;
  }

  /// Envia a foto e devolve o caminho confirmado pelo servidor, ou null se
  /// falhou (a entrada fica 'pendente' com o erro; a cópia local nunca se
  /// apaga). Se a mesma foto já está a subir, devolve esse mesmo envio.
  static Future<String?> enviar(
    TalaoPendente t, {
    Duration limite = limiteEnvioPadrao,
  }) {
    final jaEmCurso = _emCurso[t.fotoId];
    if (jaEmCurso != null) return jaEmCurso;
    final envio = _enviarUmaVez(t, limite);
    _emCurso[t.fotoId] = envio;
    // _enviarUmaVez nunca lança, por isso este whenComplete também não.
    unawaited(envio.whenComplete(() {
      _emCurso.remove(t.fotoId);
    }));
    return envio;
  }

  static Future<String?> _enviarUmaVez(
      TalaoPendente pedido, Duration limite) async {
    try {
      await carregar();
      final t = porFotoId(pedido.fotoId) ?? pedido;
      if (t.enviado) return t.path;
      final foto = File(t.localPath);
      if (!kIsWeb && !await foto.exists()) {
        _substituir(t._comFalha(
          'ficheiro: a foto já não está no telemóvel',
          agora(),
          novoEstado: TalaoPendente.estadoSemFicheiro,
        ));
        await _gravar();
        return null;
      }
      try {
        final caminho = await enviarParaServidor(
          orderId: t.orderId,
          photoFile: foto,
          totalCents: t.totalCents,
          fotoId: t.fotoId,
          tiradaEm: t.tiradaEm,
        ).timeout(limite);
        _substituir(t._comoEnviado(caminho, agora()));
        await _gravar();
        return caminho;
      } catch (e) {
        debugPrint('[talao_pendente] envio ${t.fotoId} falhou: $e');
        _substituir(t._comFalha(_descreverErro(e), agora()));
        await _gravar();
        return null;
      }
    } catch (e) {
      debugPrint('[talao_pendente] envio: $e');
      return null;
    }
  }

  static String _descreverErro(Object e) {
    final txt = e.toString();
    final curto = txt.length > 300 ? txt.substring(0, 300) : txt;
    final rede = e is TimeoutException ||
        e is SocketException ||
        RegExp(
          r'SocketException|ClientException|Failed host lookup|'
          r'Connection (closed|refused|reset|failed|timed out)|'
          r'Network is unreachable',
          caseSensitive: false,
        ).hasMatch(txt);
    return '${rede ? 'rede' : 'servidor'}: $curto';
  }

  /// Tenta enviar todas as pendentes, uma de cada vez. Se já está a correr,
  /// devolve a volta em curso (nunca duas ao mesmo tempo).
  ///
  /// Para não gastar os dados do estafeta com uma foto que o servidor recusa
  /// sempre, depois de 3 falhas a espera cresce (2, 4, 8… até 15 min). O
  /// "Confirmar compra" do ecrã chama [enviar] directo e não espera.
  static Future<void> reenviarPendentes() {
    return _reenvio ??=
        _reenviarTodas().whenComplete(() => _reenvio = null);
  }

  static Future<void> _reenviarTodas() async {
    try {
      await carregar();
      await _limpar();
      final quando = agora();
      final fila = _lista.where((t) => t.pendente).toList();
      for (final t in fila) {
        if (!_podeTentar(t, quando)) continue;
        await enviar(t);
      }
    } catch (e) {
      debugPrint('[talao_pendente] reenvio: $e');
    }
  }

  static bool _podeTentar(TalaoPendente t, DateTime quando) {
    final ultima = t.ultimaTentativa;
    if (ultima == null || t.tentativas <= 3) return true;
    final minutos = math.min(15, 1 << math.min(t.tentativas - 3, 4));
    return quando.difference(ultima) >= Duration(minutes: minutos);
  }

  /// Apaga só cópias locais de fotos confirmadas no servidor há mais de
  /// 7 dias (e tira-as da fila). Pendentes nunca.
  static Future<void> _limpar() async {
    if (kIsWeb) return;
    final limite = agora().subtract(guardarCopiaEnviada);
    final velhas = _lista
        .where((t) =>
            t.enviado && t.enviadoEm != null && t.enviadoEm!.isBefore(limite))
        .toList();
    if (velhas.isEmpty) return;
    for (final t in velhas) {
      // Só o que está na NOSSA pasta (nunca a foto original da câmara).
      if (t.localPath.contains(pasta)) {
        try {
          final f = File(t.localPath);
          if (await f.exists()) await f.delete();
        } catch (e) {
          debugPrint('[talao_pendente] limpar ${t.fotoId}: $e');
        }
      }
      _lista.removeWhere((x) => x.fotoId == t.fotoId);
    }
    await _gravar();
  }

  /// Tenta já e depois de 60 em 60 s. Chamar à vontade: só arranca uma vez.
  static void iniciarReenvioAutomatico() {
    if (kIsWeb || _relogio != null) return;
    _relogio = Timer.periodic(intervaloReenvio, (_) {
      if (_carregadoOk && !_lista.any((t) => t.pendente)) return;
      unawaited(reenviarPendentes());
    });
    unawaited(reenviarPendentes());
  }

  /// Fotos deste pedido que ainda não subiram.
  static List<TalaoPendente> pendentesDo(String orderId) =>
      _lista.where((t) => t.orderId == orderId && t.pendente).toList();

  /// A foto mais recente deste pedido que ainda serve (pendente ou já no
  /// servidor). Null se não há nenhuma.
  static TalaoPendente? ultimoDo(String orderId) {
    TalaoPendente? r;
    for (final t in _lista) {
      if (t.orderId != orderId) continue;
      if (t.estado == TalaoPendente.estadoSemFicheiro) continue;
      if (r == null || !t.tiradaEm.isBefore(r.tiradaEm)) r = t;
    }
    return r;
  }

  /// A versão mais recente de uma entrada (estado, caminho, erro).
  static TalaoPendente? porFotoId(String fotoId) {
    for (final t in _lista) {
      if (t.fotoId == fotoId) return t;
    }
    return null;
  }

  /// Texto PT-PT para o estafeta quando [enviar] devolve null.
  static String avisoNaoEnviado(TalaoPendente t) {
    if (t.estado == TalaoPendente.estadoSemFicheiro) {
      return 'A foto do talão já não está no telemóvel. '
          'Toca em "Confirmar compra" e tira outra foto do talão.';
    }
    final erro = t.ultimoErro;
    if (erro == null || t.falhouPorRede) {
      return 'Sem rede: o talão ficou guardado no telemóvel e vai subir '
          'sozinho. O pedido fecha quando ele chegar ao servidor. '
          'Toca em "Confirmar compra" para tentar de novo.';
    }
    final motivo = erro
        .replaceFirst(RegExp(r'^servidor:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '');
    return 'O talão ficou guardado no telemóvel, mas o servidor ainda não o '
        'aceitou ($motivo). Vai tentar de novo sozinho; toca em '
        '"Confirmar compra" para tentar já.';
  }

  /// Esquece o que está em memória (como se a app reiniciasse). Não mexe no
  /// disco nem no [enviarParaServidor]/[pastaBase]/[agora] injectados.
  @visibleForTesting
  static void reiniciarMemoriaParaTeste() {
    _relogio?.cancel();
    _relogio = null;
    _lista.clear();
    _carregadoOk = false;
    _carregamento = null;
    _emCurso.clear();
    _reenvio = null;
  }
}
