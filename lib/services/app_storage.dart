import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Acceso a la carpeta de configuración de la app.
///
/// Se usa sólo `dart:io` (sin dependencias nuevas) y funciona igual en Windows
/// y en la Raspberry Pi:
///   * Windows -> %APPDATA%\pi_home_ultimate
///   * Linux   -> $XDG_CONFIG_HOME/pi_home_ultimate (~/.config/...)
///
/// En plataformas sin sistema de archivos (web) devuelve `null` y quien lo use
/// debe seguir funcionando sin persistencia.
class AppStorage {
  static const String folderName = 'pi_home_ultimate';

  /// Carpeta de configuración alternativa, sólo para pruebas.
  ///
  /// Permite a cada suite aislar su configuración en una carpeta temporal para
  /// no leer ni escribir los ficheros reales del usuario (`settings.json` /
  /// `favorites.json`) y evitar carreras cuando varias suites corren en
  /// paralelo. Debe ser `null` en producción.
  @visibleForTesting
  static Directory? overrideDirectory;

  /// Carpeta de configuración, creándola si hace falta.
  static Directory? configDirectory() {
    final override = overrideDirectory;
    if (override != null) {
      try {
        if (!override.existsSync()) override.createSync(recursive: true);
        return override;
      } catch (_) {
        return override;
      }
    }
    try {
      final env = Platform.environment;
      String? base;
      if (Platform.isWindows) {
        base = env['APPDATA'];
      } else {
        base = env['XDG_CONFIG_HOME'];
        final home = env['HOME'];
        if (base == null && home != null) base = '$home/.config';
      }
      base ??= Directory.systemTemp.path;

      final dir = Directory('$base${Platform.pathSeparator}$folderName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Archivo dentro de la carpeta de configuración (o `null` si no hay disco).
  static File? configFile(String name) {
    final dir = configDirectory();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// Ruta legible de la carpeta de configuración (para mostrar en la interfaz).
  static String configPathLabel() =>
      configDirectory()?.path ?? '(sin persistencia)';
}
