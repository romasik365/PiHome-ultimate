import 'dart:io';

/// Red Wi-Fi detectada durante el escaneo.
class WifiNetwork {
  final String ssid;
  final int signalStrength; // 0–100
  final bool secured;

  const WifiNetwork({
    required this.ssid,
    required this.signalStrength,
    required this.secured,
  });
}

/// Servicio Wi-Fi que usa `nmcli` en Linux.
/// En otros sistemas operativos devuelve datos de prueba sin llamadas reales.
class WifiService {
  /// Escanea redes Wi-Fi disponibles.
  Future<List<WifiNetwork>> scan() async {
    if (!Platform.isLinux) return _mockNetworks();
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'SSID,SIGNAL,SECURITY',
        'dev',
        'wifi',
      ]);
      if (result.exitCode != 0) return _mockNetworks();
      return (result.stdout as String)
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            final parts = l.split(':');
            // BUG REAL (TEST 2): nmcli separa con ':' y el SSID puede
            // contener ':' (p. ej. "Casa:Planta2"); el parseo antiguo
            // partia en 3 y descartaba la red (parts.length<3 nunca
            // cuadraba). Ahora se separan por la derecha: los dos
            // ultimos campos son SIGNAL y SECURITY.
            if (parts.length < 3) return null;
            final security = parts.removeLast().trim();
            final signalRaw = parts.removeLast().trim();
            final ssid = parts.join(':').trim();
            if (ssid.isEmpty) return null;
            return WifiNetwork(
              ssid: ssid,
              signalStrength: int.tryParse(signalRaw) ?? 0,
              secured: security.isNotEmpty && security != '--',
            );
          })
          .whereType<WifiNetwork>()
          .toList();
    } catch (_) {
      return _mockNetworks();
    }
  }

  /// Conecta a una red Wi-Fi.
  /// Devuelve true si la conexión fue exitosa.
  Future<bool> connect(String ssid, {String password = ''}) async {
    if (!Platform.isLinux) return true;
    try {
      final args = password.isNotEmpty
          ? ['dev', 'wifi', 'connect', ssid, 'password', password]
          : ['dev', 'wifi', 'connect', ssid];
      final result = await Process.run('nmcli', args);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Activa o desactiva el adaptador Wi-Fi.
  Future<void> toggle(bool on) async {
    if (!Platform.isLinux) return;
    try {
      await Process.run('nmcli', ['radio', 'wifi', on ? 'on' : 'off']);
    } catch (_) {}
  }

  /// Devuelve el SSID al que está conectado actualmente, o null.
  ///
  /// Convención híbrida usada por la pantalla principal:
  ///   * `null` = desconocido (sin `nmcli`, fuera de Linux o error) ->
  ///     la interfaz usa el SSID guardado en ajustes como respaldo.
  ///   * `''` (vacía) = se sabe que NO hay red activa -> el icono se apaga
  ///     aunque haya un SSID guardado.
  ///   * otro texto = SSID activo (manda sobre el ajuste).
  Future<String?> currentSsid() async {
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'ACTIVE,SSID',
        'dev',
        'wifi',
      ]);
      if (result.exitCode != 0) return null;
      final line = (result.stdout as String)
          .split('\n')
          .firstWhere((l) => l.startsWith('yes:'), orElse: () => '');
      if (line.isEmpty) return '';
      final ssid = line.substring(4).trim();
      return ssid.isEmpty ? '' : ssid;
    } catch (_) {
      return null;
    }
  }

  /// Intensidad 0-100 de la red [ssid], o null si se desconoce.
  ///
  /// En Linux usa `nmcli -t -f IN-USE,SSID,SIGNAL dev wifi`. Fuera de Linux
  /// devuelve null (la UI usa el icono genérico).
  Future<int?> signalOf(String ssid) async {
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'IN-USE,SSID,SIGNAL',
        'dev',
        'wifi',
      ]);
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
        final name = rest.substring(0, lastColon);
        final sig = int.tryParse(rest.substring(lastColon + 1).trim());
        if (inUse == '*' && name == ssid) return sig;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<WifiNetwork> _mockNetworks() => const [
    WifiNetwork(ssid: 'Red-Hogar', signalStrength: 90, secured: true),
    WifiNetwork(ssid: 'Vecino_5G', signalStrength: 60, secured: true),
    WifiNetwork(ssid: 'CafeLibre', signalStrength: 45, secured: false),
  ];
}
