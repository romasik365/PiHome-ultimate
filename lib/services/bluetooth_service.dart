import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'process_runner.dart';

/// Dispositivo Bluetooth descubierto o emparejado.
class BluetoothDevice {
  final String mac;
  final String name;
  final bool paired;
  final bool connected;

  const BluetoothDevice({
    required this.mac,
    required this.name,
    this.paired = false,
    this.connected = false,
  });
}

/// Servicio Bluetooth que usa `bluetoothctl` (BlueZ) en Linux.
///
/// Correcciones aplicadas tras depurarlo en la Pi 3B real:
///
/// * **`power on` se enviaba como UN solo argumento** ("power on"), que
///   `bluetoothctl` rechaza con "Invalid command in menu main: power on". El
///   interruptor de Ajustes nunca hacia nada. Ahora son dos argumentos.
/// * El adaptador puede estar **bloqueado por rfkill** (`hci0 Soft blocked:
///   yes`, estado tipico de una instalacion nueva): `power on` falla con
///   `org.bluez.Error.Failed` y `scan on` con `org.bluez.Error.NotReady`.
///   [ensureReady] desbloquea con `rfkill` y enciende el adaptador.
/// * Ante cualquier fallo se devolvian **dispositivos inventados** de prueba
///   ("Altavoz BT", "Auriculares Sony"...). Ahora los fallos se propagan o se
///   devuelven vacios con [lastError] explicado.
/// * Todos los comandos tienen **timeout** ([runSystemProcess]) para que un
///   `bluetoothctl` colgado no congele el sondeo de conectividad.
class BluetoothService {
  /// SOLO PARA PRUEBAS: fuerza el comportamiento de Linux sin importar la
  /// plataforma real, porque la batería de tests corre en Windows y los
  /// servicios sólo actúan en Linux. El runner es inyectable, así que los
  /// tests nunca tocan nmcli ni bluetoothctl de verdad.
  @visibleForTesting
  static bool debugTreatAsLinux = false;

  bool get _isLinux => Platform.isLinux || debugTreatAsLinux;

  BluetoothService({ProcessRunner? runner, this._allowSudo = true})
    : _run = runner ?? runSystemProcess;

  final ProcessRunner _run;
  final bool _allowSudo;

  static const _exe = 'bluetoothctl';

  /// `rfkill` vive en /usr/sbin, que NO esta en el PATH de un usuario normal
  /// (por eso `rfkill: command not found` en la Pi aunque este instalado).
  static const _rfkill = '/usr/sbin/rfkill';

  /// Motivo del ultimo fallo (o null si todo fue bien).
  String? lastError;

  Future<ProcessResult> _bt(
    List<String> args, {
    Duration timeout = const Duration(seconds: 12),
  }) => _run(_exe, args, timeout: timeout);

  /// ¿Esta el adaptador encendido? `bluetoothctl show` responde "Powered: yes".
  /// Devuelve null si no se puede saber (herramienta ausente o error).
  Future<bool?> isPowered() async {
    if (!_isLinux) return null;
    try {
      final result = await _bt(['show']);
      if (result.exitCode != 0) return null;
      final match = RegExp(
        r'^\s*Powered:\s*(\S+)',
        multiLine: true,
      ).firstMatch(result.stdout as String);
      if (match == null) return null;
      return match.group(1) == 'yes';
    } catch (_) {
      return null;
    }
  }

  /// ¿Hay bloqueo por software (rfkill) sobre el adaptador Bluetooth?
  Future<bool> isSoftBlocked() async {
    if (!_isLinux) return false;
    try {
      final result = await _run(_rfkill, [
        'list',
        'bluetooth',
      ], timeout: const Duration(seconds: 8));
      if (result.exitCode != 0) return false;
      return RegExp(
        r'Soft blocked:\s*yes',
        caseSensitive: false,
      ).hasMatch(result.stdout as String);
    } catch (_) {
      return false;
    }
  }

  /// Quita el bloqueo por software del adaptador Bluetooth.
  ///
  /// En la Pi, `rfkill` esta en /usr/sbin (fuera del PATH), asi que se prueba
  /// esa ruta y despues el nombre corto; ambos con reintento `sudo -n`.
  Future<bool> unblock() async {
    if (!_isLinux) return false;
    lastError = null;
    for (final exe in [_rfkill, 'rfkill']) {
      final result = await runWithSudoFallback(
        _run,
        exe,
        ['unblock', 'bluetooth'],
        timeout: const Duration(seconds: 8),
        allowSudo: _allowSudo,
      );
      if (result.exitCode == 0) return true;
      lastError = processErrorMessage(result, 'rfkill no pudo desbloquear');
    }
    return false;
  }

  /// Deja el adaptador listo para usarse: desbloquea rfkill y lo enciende.
  ///
  /// Se llama al arrancar el kiosco (si el usuario tiene Bluetooth activado) y
  /// antes de escanear: sin esto, en una Pi recien instalada el adaptador esta
  /// bloqueado y la lista sale vacia sin ninguna explicacion.
  Future<bool> ensureReady() async {
    if (!_isLinux) return true;
    if (await isPowered() == true) return true;
    if (await isSoftBlocked()) await unblock();
    final result = await _bt([
      'power',
      'on',
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'No se pudo encender Bluetooth');
      return false;
    }
    return true;
  }

  /// Escanea dispositivos cercanos y devuelve los conocidos, marcando su estado.
  ///
  /// Primero prepara el adaptador ([ensureReady]): sin eso, en una Pi recien
  /// instalada `scan on` fallaba con `org.bluez.Error.NotReady` y la lista
  /// salia vacia sin explicacion. Despues consulta `devices` (todos los
  /// conocidos, incluidos los recien descubiertos) y cruza el resultado con
  /// `devices Paired` y `devices Connected` para rellenar `paired`/`connected`
  /// con el estado REAL de BlueZ y no con los ajustes guardados.
  ///
  /// En Windows devuelve dispositivos de demostracion para desarrollar.
  Future<List<BluetoothDevice>> scan({int seconds = 8}) async {
    if (!_isLinux) return _demoDevices();
    lastError = null;
    await ensureReady();

    final discovery = await _bt([
      '--timeout',
      '$seconds',
      'scan',
      'on',
    ], timeout: Duration(seconds: seconds + 8));
    if (discovery.exitCode != 0) {
      // Sin dongle/discovery falla, pero los dispositivos ya emparejados
      // siguen siendo validos: se anota el motivo y se sigue.
      lastError = processErrorMessage(discovery, 'No se pudo escanear');
    }

    final all = await _bt(['devices']);
    if (all.exitCode != 0) {
      lastError ??= processErrorMessage(all, 'No se pudo listar dispositivos');
      throw BluetoothUnavailable(lastError ?? 'No se pudo listar dispositivos');
    }
    final paired = await _macsOf(['devices', 'Paired']);
    final connected = await _macsOf(['devices', 'Connected']);
    return _parseDevices(
      all.stdout as String,
      paired: paired,
      connected: connected,
    );
  }

  /// Devuelve la lista de dispositivos emparejados.
  Future<List<BluetoothDevice>> pairedDevices() async {
    if (!_isLinux) return _demoDevices();
    final result = await _bt(['devices', 'Paired']);
    if (result.exitCode != 0) {
      lastError = processErrorMessage(
        result,
        'No se pudieron leer los emparejados',
      );
      return const [];
    }
    return _parseDevices(
      result.stdout as String,
      paired: {for (final d in _parseDevices(result.stdout as String)) d.mac},
    );
  }

  /// Empareja con un dispositivo por su direccion MAC.
  ///
  /// Tras emparejar se marca como `trusted`: sin eso, BlueZ no se reconecta
  /// solo cuando el dispositivo vuelve a estar al alcance.
  Future<bool> pair(String mac) async {
    if (!_isLinux) return true;
    lastError = null;
    final result = await _bt([
      '--timeout',
      '25',
      'pair',
      mac,
    ], timeout: const Duration(seconds: 40));
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'No se pudo emparejar');
      return false;
    }
    await trust(mac);
    return true;
  }

  /// Marca el dispositivo como confiable (reconexion automatica).
  Future<bool> trust(String mac) async {
    if (!_isLinux) return false;
    final result = await _bt(['trust', mac]);
    return result.exitCode == 0;
  }

  /// Conecta a un dispositivo emparejado.
  Future<bool> connect(String mac) async {
    if (!_isLinux) return true;
    lastError = null;
    final result = await _bt([
      '--timeout',
      '20',
      'connect',
      mac,
    ], timeout: const Duration(seconds: 35));
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'No se pudo conectar');
      return false;
    }
    return true;
  }

  /// Desconecta un dispositivo.
  Future<bool> disconnect(String mac) async {
    if (!_isLinux) return true;
    final result = await _bt(['disconnect', mac]);
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'No se pudo desconectar');
    }
    return result.exitCode == 0;
  }

  /// Olvida un dispositivo (desempareja y borra su ficha).
  Future<bool> forget(String mac) async {
    if (!_isLinux) return false;
    final result = await _bt(['remove', mac]);
    if (result.exitCode != 0) {
      lastError = processErrorMessage(result, 'No se pudo olvidar');
    }
    return result.exitCode == 0;
  }

  /// Activa o desactiva el adaptador Bluetooth.
  ///
  /// CORREGIDO: antes se llamaba con el argumento unico "power on", que
  /// bluetoothctl rechaza ("Invalid command in menu main: power on"), de modo
  /// que el interruptor de Ajustes no hacia absolutamente nada.
  Future<void> toggle(bool on) async {
    if (!_isLinux) return;
    lastError = null;
    if (on) await unblock();
    final result = await _bt([
      'power',
      on ? 'on' : 'off',
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) {
      lastError = processErrorMessage(
        result,
        on ? 'No se pudo encender Bluetooth' : 'No se pudo apagar Bluetooth',
      );
    }
  }

  /// Devuelve los dispositivos Bluetooth actualmente conectados.
  ///
  /// Es el metodo que llama el sondeo periodico de conectividad: por eso es el
  /// mas ligero posible (una sola llamada, sin escaneo) y nunca lanza.
  Future<List<BluetoothDevice>> connectedDevices() async {
    if (!_isLinux) return const [];
    try {
      final result = await _bt(['devices', 'Connected']);
      if (result.exitCode != 0) return const [];
      return _parseDevices(
        result.stdout as String,
        connected: {
          for (final d in _parseDevices(result.stdout as String)) d.mac,
        },
      );
    } catch (_) {
      return const [];
    }
  }

  /// MACs listadas por `bluetoothctl devices <filtro>` (una por linea).
  Future<Set<String>> _macsOf(List<String> args) async {
    final result = await _bt(args);
    if (result.exitCode != 0) return const {};
    final macs = <String>{};
    final re = RegExp(r'^Device\s+(\S+)', multiLine: true);
    for (final match in re.allMatches(result.stdout as String)) {
      macs.add(match.group(1)!);
    }
    return macs;
  }

  /// Parsea la salida de `bluetoothctl devices`: "Device MAC Nombre ...".
  List<BluetoothDevice> _parseDevices(
    String output, {
    Set<String> paired = const {},
    Set<String> connected = const {},
  }) {
    final devices = <BluetoothDevice>[];
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('Device ')) continue;
      final rest = trimmed.substring(7).trim();
      final spaceIdx = rest.indexOf(' ');
      if (spaceIdx < 0) continue;
      final mac = rest.substring(0, spaceIdx);
      final name = rest.substring(spaceIdx + 1).trim();
      devices.add(
        BluetoothDevice(
          mac: mac,
          name: name.isEmpty ? mac : name,
          paired: paired.contains(mac),
          connected: connected.contains(mac),
        ),
      );
    }
    return devices;
  }

  /// Dispositivos de demostracion para desarrollar en Windows.
  List<BluetoothDevice> _demoDevices() => const [
    BluetoothDevice(mac: 'AA:BB:CC:DD:EE:01', name: 'Altavoz BT', paired: true),
    BluetoothDevice(mac: 'AA:BB:CC:DD:EE:02', name: 'Auriculares Sony'),
    BluetoothDevice(mac: 'AA:BB:CC:DD:EE:03', name: 'Teclado BT'),
  ];
}

/// No se ha podido consultar el estado de Bluetooth.
class BluetoothUnavailable implements Exception {
  final String message;
  const BluetoothUnavailable(this.message);

  @override
  String toString() => message;
}
