/// Implementação web do `io_compat`.
///
/// Não é um stub morto: no browser o `image_picker` devolve `XFile` cujo
/// `path` é uma `blob:` URL, e `XFile(blobUrl).readAsBytes()` lê mesmo os
/// bytes. Por isso o upload de fotos (favores, talões, avatares, KYC) funciona
/// a sério na web com o mesmo código do mobile.
///
/// O que **não** existe no browser é escrita em disco por caminho
/// (`writeAsString`/`writeAsBytes`). Esses call-sites já estão atrás de
/// `kIsWeb` (`admin_export_service`), por isso o lançamento aqui é a rede de
/// segurança honesta, não um caminho quente.
library;

import 'dart:typed_data';

// XFile vem reexportado pelo image_picker (que já é dependência directa), por
// isso não é preciso declarar o cross_file no pubspec.
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Substituto de `dart:io`'s `File` para a web.
///
/// Suporta o único padrão que `lib/` usa: construir a partir do `path` de um
/// `XFile` do `image_picker` e ler os bytes para upload.
class File {
  File(this.path);

  final String path;

  Future<Uint8List> readAsBytes() => XFile(path).readAsBytes();

  Future<String> readAsString() => XFile(path).readAsString();

  Future<int> length() async => (await readAsBytes()).length;

  Future<bool> exists() async => path.isNotEmpty;

  bool existsSync() => path.isNotEmpty;

  Never _noDisk(String op) => throw UnsupportedError(
        'File.$op não existe no browser (não há sistema de ficheiros por '
        'caminho). Este caminho devia estar atrás de um guard kIsWeb.',
      );

  Future<File> writeAsString(String contents) => _noDisk('writeAsString');

  Future<File> writeAsBytes(List<int> bytes) => _noDisk('writeAsBytes');

  Future<void> delete() => _noDisk('delete');

  int lengthSync() => _noDisk('lengthSync');
}

/// Substituto de `Directory` — só existe para o código compilar; qualquer uso
/// real está atrás de `kIsWeb`.
class Directory {
  Directory(this.path);

  final String path;

  bool existsSync() => false;
}

/// Substituto de `Platform`. No browser não somos Android nem iOS — as
/// verificações `Platform.isAndroid` do código (bolha flutuante, token push)
/// devem dar `false`, que é exatamente o comportamento correto na web.
abstract final class Platform {
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isFuchsia = false;

  static const String operatingSystem = 'web';
  static const String operatingSystemVersion = 'browser';
  static const String localeName = 'pt_PT';
}

/// `SocketException` é apanhada pelo logger de crash do `main.dart`.
class SocketException implements Exception {
  const SocketException(this.message);

  final String message;

  @override
  String toString() => 'SocketException: $message';
}

class FileSystemException implements Exception {
  const FileSystemException([this.message = '']);

  final String message;

  @override
  String toString() => 'FileSystemException: $message';
}

/// Preview de uma foto acabada de escolher.
///
/// Na web o `path` é uma `blob:` URL, que o `NetworkImage` renderiza
/// diretamente — não há download nem pedido de rede real.
ImageProvider boraLocalImage(String path) => NetworkImage(path);
