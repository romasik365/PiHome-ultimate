import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_storage.dart';

/// Registro de eventos y errores en un fichero de texto con rotación.
///
/// Escribe en `app.log` dentro de la carpeta de configuración (ver
/// [AppStorage]). Cuando el fichero supera [maxBytes] se rota:
/// `app.log` -> `app.log.1` -> `app.log.2`, descartando el más antiguo. Así el
/// log de un equipo encendido semanas nunca crece sin control.
///
/// Nunca lanza excepciones: si el disco falla, la app sigue funcionando.
class AppLog {
  AppLog._();

  static const String _fileName = 'app.log';

  /// Tamaño máximo de cada fichero antes de rotar (1 MB).
  static const int maxBytes = 1024 * 1024;

  /// Número total de ficheros conservados (`app.log` + `.1` + `.2`).
  static const int maxFiles = 3;

  /// Permite silenciar el log (por ejemplo en pruebas puntuales).
  static bool enabled = true;

  /// Callback invocado ante un error fatal no capturado.
  ///
  /// Lo asigna [AppBootstrap] para poder sustituir la interfaz por una pantalla
  /// de error en lugar de dejar la pantalla en blanco. Es `null` mientras no
  /// haya interfaz montada (por ejemplo durante el arranque temprano).
  static void Function(Object error, StackTrace? stack)? onFatal;

  static bool _installed = false;
  static bool _writing = false;

  static File? _resolveFile() => AppStorage.configFile(_fileName);

  /// Ruta del fichero de log (para mostrarla en la interfaz).
  static String logFilePath() => _resolveFile()?.path ?? '(sin persistencia)';

  /// Registra un mensaje informativo.
  static void info(String message) => _write('INFO', message);

  /// Registra una advertencia.
  static void warn(String message) => _write('WARN', message);

  /// Registra un error, opcionalmente con su excepción y traza.
  static void error(String message, [Object? error, StackTrace? stack]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' :: $error');
    if (stack != null) buffer.write('\n$stack');
    _write('ERROR', buffer.toString());
  }

  /// Engancha los manejadores globales de errores para que todo fallo quede
  /// registrado en disco: errores de widgets/render y errores de plataforma.
  ///
  /// Es idempotente: llamarlo dos veces no duplica el registro. Aun así,
  /// [onFatal] se puede registrar en cualquier llamada posterior, porque
  /// `main()` engancha los manejadores antes de que exista interfaz y la raíz
  /// de la app completa el callback cuando ya puede mostrar la pantalla de
  /// error.
  static void install({
    void Function(Object error, StackTrace? stack)? onFatal,
  }) {
    if (onFatal != null) AppLog.onFatal = onFatal;
    if (_installed) return;
    _installed = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error(
        'FlutterError: ${details.exceptionAsString()}',
        details.exception,
        details.stack,
      );
      onFatal?.call(details.exception, details.stack);
      // Se conserva el comportamiento por defecto (imprimir en consola).
      previous?.call(details);
    };

    PlatformDispatcher.instance.onError = (err, stack) {
      error('Error de plataforma', err, stack);
      onFatal?.call(err, stack);
      return true;
    };
  }

  /// Devuelve las últimas [maxLines] líneas del log (para el visor de Ajustes).
  static List<String> readTail({int maxLines = 200}) {
    try {
      final file = _resolveFile();
      if (file == null || !file.existsSync()) return const [];
      final lines = file.readAsLinesSync();
      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } catch (_) {
      return const [];
    }
  }

  /// Borra todos los ficheros de log.
  static void clear() {
    try {
      final file = _resolveFile();
      if (file == null) return;
      for (var i = 0; i < maxFiles; i++) {
        final f = i == 0 ? file : File('${file.path}.$i');
        if (f.existsSync()) f.deleteSync();
      }
    } catch (_) {}
  }

  /// Restaura el estado interno (sólo para pruebas).
  @visibleForTesting
  static void resetForTest() {
    enabled = true;
    _installed = false;
    _writing = false;
  }

  static void _write(String level, String message) {
    final line = '[${DateTime.now().toIso8601String()}] [$level] $message\n';
    if (kDebugMode) debugPrint(line.trimRight());

    // `_writing` evita recursión si el propio log provocase otro error.
    if (!enabled || _writing) return;
    _writing = true;
    try {
      final file = _resolveFile();
      if (file == null) return;
      _rotateIfNeeded(file);
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Escribir el log nunca debe tumbar la app.
    } finally {
      _writing = false;
    }
  }

  /// Rota los ficheros si el actual supera [maxBytes].
  static void _rotateIfNeeded(File file) {
    if (!file.existsSync()) return;
    if (file.lengthSync() < maxBytes) return;

    // El fichero más antiguo se descarta.
    final oldest = File('${file.path}.${maxFiles - 1}');
    if (oldest.existsSync()) oldest.deleteSync();

    // Se desplazan los intermedios hacia arriba.
    for (var i = maxFiles - 2; i >= 1; i--) {
      final src = File('${file.path}.$i');
      if (src.existsSync()) src.renameSync('${file.path}.${i + 1}');
    }

    file.renameSync('${file.path}.1');
  }
}
