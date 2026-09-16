import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import 'app_storage.dart';

/// Persistencia de los ajustes en un archivo JSON.
///
/// La resolución de la carpeta vive en [AppStorage] (punto único):
///   * Windows -> %APPDATA%\pi_home_ultimate\settings.json
///   * Linux   -> $XDG_CONFIG_HOME/pi_home_ultimate/settings.json
///                (o ~/.config/pi_home_ultimate/settings.json)
class SettingsStore {
  static const String _fileName = 'settings.json';

  static File? _resolveFile() => AppStorage.configFile(_fileName);

  /// Ruta del archivo de ajustes. Útil para depurar y para las pruebas.
  static String? settingsFilePath() => _resolveFile()?.path;

  /// Devuelve los ajustes guardados o los valores por defecto.
  static Future<AppSettings> load() async {
    final file = _resolveFile();
    if (file == null || !file.existsSync()) return AppSettings.defaults();
    try {
      final raw = await file.readAsString();
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) return AppSettings.fromMap(map);
    } catch (_) {
      // Archivo corrupto o sin permisos: se usan los valores por defecto.
    }
    return AppSettings.defaults();
  }

  /// Guarda los ajustes. Nunca lanza excepciones: si falla, la app sigue
  /// funcionando con los ajustes en memoria.
  static Future<void> save(AppSettings settings) async {
    final file = _resolveFile();
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(settings.toMap()), flush: true);
    } catch (_) {}
  }

  /// Guarda los ajustes de forma síncrona al cerrar la app (en dispose).
  static void saveSync(AppSettings settings) {
    final file = _resolveFile();
    if (file == null) return;
    try {
      file.writeAsStringSync(jsonEncode(settings.toMap()), flush: true);
    } catch (_) {}
  }
}
