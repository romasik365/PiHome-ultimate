import 'dart:async';
import 'dart:io';

import 'bluetooth_service.dart';
import 'wifi_service.dart';

/// Estado unificado de conectividad para la barra superior.
///
/// Ciclo de vida:
///   * `unknown=true` = aún sin chequear o herramienta ausente (nmcli /
///     bluetoothctl no existen, sin permisos...). La UI muestra icono
///     atenuado con tooltip "desconocido".
///   * WiFi: `ssid==null` = sin red. `signal` 0-100 si se conoce.
///   * BT: lista de dispositivos realmente conectados + nº emparejados
///     conocidos por ajustes (respaldo cuando no hay chequeo en vivo).
class ConnectivityStatus {
  final bool wifiUnknown;
  final String? wifiSsid;
  final int? wifiSignal;
  final bool btUnknown;
  final List<BluetoothDevice> btConnected;
  final int btPairedKnown;

  const ConnectivityStatus({
    this.wifiUnknown = true,
    this.wifiSsid,
    this.wifiSignal,
    this.btUnknown = true,
    this.btConnected = const [],
    this.btPairedKnown = 0,
  });

  /// Hay red Wi-Fi activa (se conoce el SSID).
  bool get hasWifi => wifiSsid != null;

  /// Hay audio/dispositivo BT realmente conectado.
  bool get hasBtConnected => btConnected.isNotEmpty;

  /// Hay dispositivos emparejados conocidos pero ninguno conectado ahora.
  bool get hasBtPairedOnly => btConnected.isEmpty && btPairedKnown > 0;
}

/// Servicio que unifica WiFi + Bluetooth en un único Stream.
///
/// La pantalla principal escucha [stream] y repinta una sola vez por ciclo,
/// en vez de un setState por cada Future suelto. Hace el chequeo en vivo
/// (nmcli / bluetoothctl en Linux) y expone si las herramientas faltan
/// ([ConnectivityStatus.wifiUnknown] / `btUnknown`) para que la UI no mienta.
class ConnectivityService {
  final WifiService wifi;
  final BluetoothService bluetooth;
  final Duration interval;

  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();
  Timer? _timer;
  bool _disposed = false;
  bool _started = false;
  bool _paused = false;

  /// Último estado emitido (útil para tests y primer frame).
  ConnectivityStatus current = const ConnectivityStatus();

  ConnectivityService({
    WifiService? wifi,
    BluetoothService? bluetooth,
    this.interval = const Duration(seconds: 30),
  }) : wifi = wifi ?? WifiService(),
       bluetooth = bluetooth ?? BluetoothService();

  Stream<ConnectivityStatus> get stream => _controller.stream;

  /// Arranca el chequeo inmediato + periódico.
  void start() {
    if (_disposed || _started) return;
    _started = true;
    _paused = false;
    refresh();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  /// Pausa el chequeo periódico sin cerrar el stream (se reanuda con
  /// [resume]). Útil en tests de widgets para no dejar Timers pendientes.
  void pause() {
    if (!_started) return;
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Reanuda el chequeo periódico tras [pause].
  void resume() {
    if (_disposed || !_started || !_paused) return;
    _paused = false;
    refresh();
    _timer ??= Timer.periodic(interval, (_) => refresh());
  }

  /// Un ciclo de chequeo. Nunca lanza: a falta de herramientas marca
  /// `unknown` y conserva el último dato bueno conocido.
  Future<void> refresh() async {
    if (_disposed || _paused) return;
    String? ssid;
    bool wifiUnknown = false;
    int? signal;
    try {
      ssid = await wifi.currentSsid();
      if (ssid == null) {
        // Desconocido: conserva el último SSID bueno si lo había.
        wifiUnknown = current.wifiSsid == null;
        ssid = current.wifiSsid;
      } else if (ssid.isEmpty) {
        ssid = null;
      } else {
        signal = await wifi.signalOf(ssid);
      }
    } catch (_) {
      wifiUnknown = true;
      ssid = current.wifiSsid;
      signal = current.wifiSignal;
    }

    List<BluetoothDevice> connected = current.btConnected;
    bool btUnknown = false;
    try {
      connected = await bluetooth.connectedDevices();
      // Fuera de Linux connectedDevices() devuelve [] siempre: no podemos
      // distinguir "nada conectado" de "sin herramienta". Se marca unknown
      // salvo que sepamos que hay emparejados (entonces no es desconocido,
      // es "emparejado sin conectar").
      if (!Platform.isLinux && connected.isEmpty) {
        btUnknown = current.btPairedKnown == 0;
      }
    } catch (_) {
      btUnknown = true;
    }

    current = ConnectivityStatus(
      wifiUnknown: wifiUnknown,
      wifiSsid: ssid,
      wifiSignal: signal ?? current.wifiSignal,
      btUnknown: btUnknown,
      btConnected: connected,
      btPairedKnown: current.btPairedKnown,
    );
    if (!_disposed && !_controller.isClosed) _controller.add(current);
  }

  /// Actualiza el nº de emparejados conocidos desde los ajustes guardados.
  /// Es el respaldo cuando el chequeo en vivo no aporta nada.
  void setPairedKnown(int count) {
    if (_disposed || count == current.btPairedKnown) return;
    current = ConnectivityStatus(
      wifiUnknown: current.wifiUnknown,
      wifiSsid: current.wifiSsid,
      wifiSignal: current.wifiSignal,
      btUnknown: current.btUnknown,
      btConnected: current.btConnected,
      btPairedKnown: count,
    );
    if (!_controller.isClosed) _controller.add(current);
  }

  void dispose() {
    _disposed = true;
    _started = false;
    _paused = false;
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }
}
