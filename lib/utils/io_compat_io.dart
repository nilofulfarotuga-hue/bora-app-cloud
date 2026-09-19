/// Implementação mobile/desktop do `io_compat`: reexporta o `dart:io` real.
///
/// Nada aqui muda o comportamento do Android — é literalmente o `dart:io` que
/// os ficheiros já usavam antes.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

export 'dart:io'
    show
        Directory,
        File,
        FileSystemException,
        Platform,
        SocketException;

/// Preview de uma foto acabada de escolher no aparelho.
///
/// No mobile é o `FileImage` de sempre. Na web passa a `NetworkImage` sobre a
/// `blob:` URL do `image_picker` (ver `io_compat_web.dart`).
ImageProvider boraLocalImage(String path) => FileImage(File(path));
