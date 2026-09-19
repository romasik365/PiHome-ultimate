import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Ejecuta un proceso del sistema y devuelve su resultado.
///
/// Es **inyectable** para poder probar los servicios de Wi-Fi y Bluetooth sin
/// `nmcli` ni `bluetoothctl` reales (ver `test/wifi_service_test.dart`).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Duration timeout,
});

/// Runner real: lanza el proceso, espera como máximo [timeout] y lo **mata** si
/// se pasa del tiempo.
///
/// `Process.run` no admite timeout. En una Raspberry Pi 3B, con el D-Bus
/// cargado, un `bluetoothctl` que se queda colgado bloqueaba el sondeo de
/// conectividad para siempre (el stream dejaba de emitir y la barra superior se
/// quedaba congelada). Aquí, al agotarse el tiempo se mata el proceso y se
/// devuelve un resultado con código -1, que los servicios tratan como fallo.
Future<ProcessResult> runSystemProcess(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final process = await Process.start(executable, arguments);
  final stdoutFuture = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final stderrFuture = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final killer = Timer(timeout, () async {
    await _killProcessTree(process);
  });
  try {
    final code = await process.exitCode;
    return ProcessResult(
      process.pid,
      code,
      await stdoutFuture,
      await stderrFuture,
    );
  } finally {
    killer.cancel();
  }
}

/// Mata el proceso y, en Windows, todo su árbol.
///
/// Matando sólo al padre, un `cmd /c ...` (o cualquier intérprete) deja vivos a
/// sus hijos y el `exitCode` no se resuelve hasta que éstos terminan.
Future<void> _killProcessTree(Process process) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    } else {
      process.kill(ProcessSignal.sigkill);
    }
  } catch (_) {
    try {
      process.kill();
    } catch (_) {
      // Ya había terminado.
    }
  }
}

/// Ejecuta [executable] y, si falla, reintenta con `sudo -n` (sin contraseña).
///
/// En la Pi el kiosco necesita `nmcli dev wifi rescan` o `rfkill unblock`, y
/// NetworkManager/bluez piden autorización polkit cuando la sesión no es local
/// (por ejemplo si la app se lanzó por SSH). Con `sudo -n` el usuario del
/// kiosco (con NOPASSWD en `/etc/sudoers.d/`) lo consigue igualmente; si no hay
/// sudo configurado, `sudo -n` falla al instante y se devuelve el primer error.
Future<ProcessResult> runWithSudoFallback(
  ProcessRunner runner,
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 8),
  bool allowSudo = true,
}) async {
  final result = await runner(executable, arguments, timeout: timeout);
  if (result.exitCode == 0 || !allowSudo) return result;
  try {
    final sudo = await runner('sudo', [
      '-n',
      executable,
      ...arguments,
    ], timeout: timeout);
    return sudo.exitCode == 0 ? sudo : result;
  } catch (_) {
    return result;
  }
}

/// Primer mensaje de error legible de un resultado de proceso.
///
/// `nmcli`/`bluetoothctl` escriben el motivo real en stderr ("not authorized",
/// "org.bluez.Error.NotReady"...). Se usa para que la pantalla de Ajustes pueda
/// explicar qué ha pasado en lugar de mostrar un "Error" genérico.
String processErrorMessage(ProcessResult result, [String fallback = '']) {
  final err = (result.stderr as String?)?.trim() ?? '';
  if (err.isNotEmpty) {
    return err.split('\n').first.trim();
  }
  final out = (result.stdout as String?)?.trim() ?? '';
  if (out.isNotEmpty) return out.split('\n').first.trim();
  if (result.exitCode == -1) return 'El comando tardó demasiado';
  return fallback.isEmpty
      ? 'El comando falló (código ${result.exitCode})'
      : fallback;
}
