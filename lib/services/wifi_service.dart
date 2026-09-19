import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'process_runner.dart';

/// Red Wi-Fi detectada durante el escaneo.
class WifiNetwork {
  final String ssid;
  final int signalStrength; // 0-100
  final bool secured;

  const WifiNetwork({
    required this.ssid,
    required this.signalStrength,
    required this.secured,
  });
}

/// No se ha podido consultar el estado del Wi-Fi.
///
/// Antes de esta correccion, ante cualquier fallo de `nmcli` (sin permisos de
/// polkit, herramienta ausente, D-Bus saturado) el servicio devolvia **redes
/// inventadas de prueba**: en la Pi el usuario veia "Red-Hogar" o "Vecino_5G"
/// que no existian y al pulsarlas no pasaba nada. Ahora el fallo se propaga
/// con el mensaje real y la pantalla de Ajustes lo explica.
class WifiUnavailable implements Exception {
  final String message;
  const WifiUnavailable(this.message);

  @override
  String toString() => message;
}

/// Servicio Wi-Fi que usa `nmcli` (NetworkManager) en Linux.
///
/// * En Windows devuelve datos de demostracion para desarrollar la interfaz.
/// * Todos los comandos tienen **timeout** ([runSystemProcess]): en la Pi 3B un
///   `nmcli` colgado bloqueaba el sondeo de conectividad indefinidamente.
/// * Los comandos con privilegios se reintentan con `sudo -n`
///   ([runWithSudoFallback]): NetworkManager pide autorizacion polkit cuando la
///   sesion no es local (p. ej. app lanzada por SSH).
/// * [lastError] guarda el motivo del ultimo fallo para mostrarlo en Ajustes.
class WifiService {
  /// SOLO PARA PRUEBAS: fuerza el comportamiento de Linux sin importar la
  /// plataforma real, porque la batería de tests corre en Windows y los
  /// servicios sólo actúan en Linux. El runner es inyectable, así que los
  /// tests nunca tocan nmcli ni bluetoothctl de verdad.
  @visibleForTesting
  static bool debugTreatAsLinux = false;

  bool get _isLinux => Platform.isLinux || debugTreatAsLinux;

  WifiService({ProcessRunner? runner, this._allowSudo = true})
    : _run = runner ?? runSystemProcess;

  final ProcessRunner _run;
  final bool _allowSudo;

  static const _exe = 'nmcli';

  /// Motivo del ultimo fallo (o null si todo fue bien).
  String? lastError;

  Future<ProcessResult> _nmcli(
    List<String> args, {
    Duration timeout = const Duration(seconds: 10),
  }) => runWithSudoFallback(
    _run,
    _exe,
    args,
    timeout: timeout,
    allowSudo: _allowSudo,
  );

  /// Escanea las redes visibles y las devuelve ordenadas por senal.
  ///
  /// Usa `--rescan yes` para forzar una busqueda nueva: sin esto, `nmcli`
  /// devuelve la lista **cacheada** de NetworkManager, que en la Pi suele
  /// limitarse a la red conectada y el usuario no ve las demas redes.
  ///
  /// Lanza [WifiUnavailable] si el escaneo falla.
  Future<List<WifiNetwork>> scan() async {
    if (!_isLinux) return _demoNetworks();
    lastError = null;

    final result = await _nmcli([
      '-t',
      '-f',
      'SSID,SIGNAL,SECURITY',
      'dev',
      'wifi',
      'list',
      '--rescan',
      'yes',
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'nmcli no pudo escanear');
      throw WifiUnavailable(lastError!);
    }

    // Se agrupa por SSID conservando la mejor senal: nmcli puede listar varias
    // celdas (BSSID) de la misma red.
    final best = <String, WifiNetwork>{};
    for (final line in (result.stdout as String).split('\n')) {
      final net = _parseNetwork(line);
      if (net == null) continue;
      final existing = best[net.ssid];
      if (existing == null || net.signalStrength > existing.signalStrength) {
        best[net.ssid] = net;
      }
    }
    final networks = best.values.toList()
      ..sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
    return networks;
  }

  /// Conecta a una red. Devuelve true si la conexion fue exitosa.
  ///
  /// `nmcli` termina con codigo != 0 si falla la autenticacion o el DHCP; el
  /// timeout es largo (45 s) porque la asociacion puede tardar en la Pi.
  Future<bool> connect(String ssid, {String password = ''}) async {
    if (!_isLinux) return true;
    lastError = null;
    final args = password.isNotEmpty
        ? ['dev', 'wifi', 'connect', ssid, 'password', password]
        : ['dev', 'wifi', 'connect', ssid];
    final result = await _nmcli(args, timeout: const Duration(seconds: 45));
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'No se pudo conectar');
      return false;
    }
    return true;
  }

  /// Activa o desactiva la radio Wi-Fi del adaptador.
  Future<void> toggle(bool on) async {
    if (!_isLinux) return;
    lastError = null;
    final result = await _nmcli(['radio', 'wifi', on ? 'on' : 'off']);
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'No se pudo cambiar la radio');
    }
  }

  /// ¿Esta la radio Wi-Fi encendida? `null` = desconocido.
  Future<bool?> radioEnabled() async {
    if (!_isLinux) return null;
    try {
      final result = await _nmcli([
        '-t',
        '-f',
        'WIFI',
        'radio',
      ], timeout: const Duration(seconds: 8));
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim() == 'enabled';
    } catch (_) {
      return null;
    }
  }

  /// Enciende la radio si estaba apagada. Se usa al arrancar el kiosco.
  Future<bool> ensureEnabled() async {
    if (!_isLinux) return true;
    final enabled = await radioEnabled();
    if (enabled == null || enabled) return true;
    await toggle(true);
    return true;
  }

  /// Devuelve el SSID al que esta conectado actualmente, o null.
  ///
  /// Convencion hibrida usada por la pantalla principal:
  ///   * `null` = desconocido (sin `nmcli`, fuera de Linux o error) ->
  ///     la interfaz usa el SSID guardado en ajustes como respaldo.
  ///   * `''` (vacia) = se sabe que NO hay red activa -> el icono se apaga
  ///     aunque haya un SSID guardado.
  ///   * otro texto = SSID activo (manda sobre el ajuste).
  Future<String?> currentSsid() async {
    if (!_isLinux) return null;
    try {
      final result = await _nmcli([
        '-t',
        '-f',
        'ACTIVE,SSID',
        'dev',
        'wifi',
        'list',
      ], timeout: const Duration(seconds: 8));
      if (result.exitCode != 0) return null;
      for (final line in (result.stdout as String).split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // Formato terse "yes:MiRed"; versiones antiguas usan "*:MiRed".
        final sep = trimmed.indexOf(':');
        if (sep <= 0) continue;
        final active = trimmed.substring(0, sep);
        if (active != 'yes' && active != '*') continue;
        final ssid = _unescape(trimmed.substring(sep + 1).trim());
        return ssid.isEmpty ? '' : ssid;
      }
      return '';
    } catch (_) {
      return null;
    }
  }

  /// Intensidad 0-100 de la red [ssid], o null si se desconoce.
  Future<int?> signalOf(String ssid) async {
    if (!_isLinux) return null;
    try {
      final result = await _nmcli([
        '-t',
        '-f',
        'IN-USE,SSID,SIGNAL',
        'dev',
        'wifi',
        'list',
      ], timeout: const Duration(seconds: 8));
      if (result.exitCode != 0) return null;
      for (final line in (result.stdout as String).split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // Formato IN-USE:SSID:SIGNAL; el SSID puede contener ':'.
        String inUse;
        String rest;
        if (trimmed.startsWith('*')) {
          inUse = '*';
          rest = trimmed.substring(1);
          if (rest.startsWith(':')) rest = rest.substring(1);
        } else if (trimmed.startsWith(':')) {
          inUse = '';
          rest = trimmed.substring(1);
        } else {
          continue;
        }
        final lastColon = rest.lastIndexOf(':');
        if (lastColon < 0) continue;
        final name = _unescape(rest.substring(0, lastColon));
        final sig = int.tryParse(rest.substring(lastColon + 1).trim());
        if (inUse == '*' && name == ssid) return sig;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parsea una linea terse "SSID:SIGNAL:SECURITY" de `nmcli`.
  ///
  /// En modo terse `nmcli` **escapa** el ':' dentro de los valores con '\', por
  /// lo que el SSID se separa por la derecha y se desescapa despues.
  WifiNetwork? _parseNetwork(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final securitySep = trimmed.lastIndexOf(':');
    if (securitySep < 0) return null;
    final security = trimmed.substring(securitySep + 1).trim();
    final rest = trimmed.substring(0, securitySep);
    final signalSep = rest.lastIndexOf(':');
    if (signalSep < 0) return null;
    final signal = int.tryParse(rest.substring(signalSep + 1).trim());
    final ssid = _unescape(rest.substring(0, signalSep)).trim();
    if (ssid.isEmpty) return null; // redes ocultas o celdas sin SSID
    return WifiNetwork(
      ssid: ssid,
      signalStrength: signal ?? 0,
      secured: security.isNotEmpty && security != '--',
    );
  }

  /// Deshace el escapado de `nmcli`: '\' escapa el caracter siguiente.
  static String _unescape(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (value[i] == r'\' && i + 1 < value.length) {
        i++;
        out.write(value[i]);
      } else {
        out.write(value[i]);
      }
    }
    return out.toString();
  }

  /// Redes de demostracion para desarrollar en Windows (no se usan en la Pi).
  List<WifiNetwork> _demoNetworks() => const [
    WifiNetwork(ssid: 'Red-Hogar', signalStrength: 90, secured: true),
    WifiNetwork(ssid: 'Vecino_5G', signalStrength: 60, secured: true),
    WifiNetwork(ssid: 'CafeLibre', signalStrength: 45, secured: false),
  ];
}
