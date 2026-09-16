import 'dart:io';

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

/// Servicio Bluetooth que usa `bluetoothctl` en Linux.
/// En otros sistemas operativos devuelve datos de prueba sin llamadas reales.
class BluetoothService {
  /// Escanea dispositivos Bluetooth cercanos (~5 s).
  Future<List<BluetoothDevice>> scan() async {
    if (!Platform.isLinux) return _mockDevices();
    try {
      await Process.run('bluetoothctl', ['--timeout', '5', 'scan', 'on']);
      final list = await Process.run('bluetoothctl', ['devices']);
      return _parseDevices(list.stdout as String, paired: false);
    } catch (_) {
      return _mockDevices();
    }
  }

  /// Devuelve la lista de dispositivos emparejados.
  Future<List<BluetoothDevice>> pairedDevices() async {
    if (!Platform.isLinux) return _mockDevices();
    try {
      final result = await Process.run('bluetoothctl', ['devices', 'Paired']);
      return _parseDevices(result.stdout as String, paired: true);
    } catch (_) {
      return _mockDevices();
    }
  }

  /// Empareja con un dispositivo por su dirección MAC.
  Future<bool> pair(String mac) async {
    if (!Platform.isLinux) return true;
    try {
      final r = await Process.run('bluetoothctl', ['pair', mac]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Conecta a un dispositivo emparejado.
  Future<bool> connect(String mac) async {
    if (!Platform.isLinux) return true;
    try {
      final r = await Process.run('bluetoothctl', ['connect', mac]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Desconecta un dispositivo.
  Future<bool> disconnect(String mac) async {
    if (!Platform.isLinux) return true;
    try {
      final r = await Process.run('bluetoothctl', ['disconnect', mac]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Activa o desactiva el adaptador Bluetooth.
  Future<void> toggle(bool on) async {
    if (!Platform.isLinux) return;
    try {
      await Process.run('bluetoothctl', [on ? 'power on' : 'power off']);
    } catch (_) {}
  }

  /// Devuelve los dispositivos Bluetooth actualmente conectados.
  ///
  /// En Linux usa `bluetoothctl devices Connected`. En otras plataformas
  /// devuelve lista vacía (la pantalla principal usa los ajustes guardados
  /// como respaldo, ver modo híbrido).
  Future<List<BluetoothDevice>> connectedDevices() async {
    if (!Platform.isLinux) return [];
    try {
      final result = await Process.run('bluetoothctl', [
        'devices',
        'Connected',
      ]);
      if (result.exitCode != 0) return [];
      return _parseDevices(
        result.stdout as String,
        paired: true,
        connected: true,
      );
    } catch (_) {
      return [];
    }
  }

  List<BluetoothDevice> _parseDevices(
    String output, {
    required bool paired,
    bool connected = false,
  }) {
    return output
        .split('\n')
        .where((l) => l.startsWith('Device '))
        .map((l) {
          final rest = l.substring(7).trim();
          final spaceIdx = rest.indexOf(' ');
          if (spaceIdx < 0) return null;
          final mac = rest.substring(0, spaceIdx);
          final name = rest.substring(spaceIdx + 1).trim();
          return BluetoothDevice(
            mac: mac,
            name: name.isEmpty ? mac : name,
            paired: paired,
            connected: connected,
          );
        })
        .whereType<BluetoothDevice>()
        .toList();
  }

  List<BluetoothDevice> _mockDevices() => const [
    BluetoothDevice(mac: 'AA:BB:CC:DD:EE:01', name: 'Altavoz BT', paired: true),
    BluetoothDevice(mac: 'AA:BB:CC:DD:EE:02', name: 'Auriculares Sony'),
    BluetoothDevice(mac: 'AA:BB:CC:DD:EE:03', name: 'Teclado BT'),
  ];
}
