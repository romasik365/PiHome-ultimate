import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_display/services/bluetooth_service.dart';
import 'package:smart_display/services/process_runner.dart';
import 'package:smart_display/services/wifi_service.dart';

/// Runner falso: responde según el comando y **graba cada llamada** con sus
/// argumentos, para poder verificar las regresiones reales encontradas en la
/// Raspberry Pi (por ejemplo, `power on` partido en dos argumentos).
class FakeRunner {
  FakeRunner(this.responses);

  /// Clave: "ejecutable arg1 arg2..." (con espacio simple).
  final Map<String, ProcessResult> responses;

  /// Cada llamada como lista de tokens (ejecutable + argumentos).
  final List<List<String>> calls = [];

  ProcessRunner get runner =>
      (
        String exe,
        List<String> args, {
        Duration timeout = const Duration(seconds: 8),
      }) async {
        calls.add([exe, ...args]);
        final key = '$exe ${args.join(' ')}';
        return responses[key] ?? ProcessResult(0, 1, '', 'no simulado: $key');
      };
}

ProcessResult _ok(String out) => ProcessResult(0, 0, out, '');

void main() {
  setUpAll(() {
    // Los servicios sólo actúan en Linux y la batería corre en Windows.
    WifiService.debugTreatAsLinux = true;
    BluetoothService.debugTreatAsLinux = true;
  });

  tearDownAll(() {
    WifiService.debugTreatAsLinux = false;
    BluetoothService.debugTreatAsLinux = false;
  });

  group('WifiService (nmcli simulado)', () {
    test('scan agrupa por SSID, desescapa ":" y ordena por señal', () async {
      final fake = FakeRunner({
        'nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list --rescan yes': _ok(
          'Casa\\:Planta2:70:WPA2\n'
          'btelecom_6A82A3:66:WPA2\n'
          'btelecom_6A82A3:80:WPA2\n'
          ':12:WPA2\n'
          'CafeLibre:45:\n',
        ),
      });

      final nets = await WifiService(runner: fake.runner).scan();

      // Ordenadas por señal; las dos celdas de la misma red se agrupan.
      expect(nets.map((n) => n.ssid).toList(), [
        'btelecom_6A82A3',
        'Casa:Planta2',
        'CafeLibre',
      ]);
      expect(nets.first.signalStrength, 80);
      expect(nets[1].secured, isTrue);
      expect(nets.last.secured, isFalse);
    });

    test(
      'scan lanza WifiUnavailable cuando polkit deniega el escaneo',
      () async {
        // Caso real en la Pi: la app lanzada por SSH no puede forzar un rescan.
        final fake = FakeRunner({
          'nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list --rescan yes':
              ProcessResult(0, 1, '', 'Error: ... not authorized.'),
        });
        final service = WifiService(runner: fake.runner, allowSudo: false);

        await expectLater(service.scan(), throwsA(isA<WifiUnavailable>()));
        expect(service.lastError, contains('not authorized'));
      },
    );

    test('currentSsid acepta "yes:" y "*:" y "" cuando no hay red', () async {
      final fake = FakeRunner({
        'nmcli -t -f ACTIVE,SSID dev wifi list': _ok('*:MiCasa\n'),
      });
      expect(await WifiService(runner: fake.runner).currentSsid(), 'MiCasa');
    });

    test('connect reintenta con sudo -n si falla sin privilegios', () async {
      final fake = FakeRunner({
        'nmcli dev wifi connect MiRed password abc': ProcessResult(
          0,
          1,
          '',
          'Error: not authorized',
        ),
        'sudo -n nmcli dev wifi connect MiRed password abc': _ok('Conectado'),
      });

      final ok = await WifiService(runner: fake.runner)
          .connect('MiRed', password: 'abc');

      expect(ok, isTrue);
      expect(fake.calls.length, 2);
      expect(fake.calls[1], [
        'sudo',
        '-n',
        'nmcli',
        'dev',
        'wifi',
        'connect',
        'MiRed',
        'password',
        'abc',
      ]);
    });
  });

  group('ProcessRunner real', () {
    test('mata el proceso si supera el timeout', () async {
      final exe = Platform.isWindows ? 'powershell' : 'sleep';
      final args = Platform.isWindows
          ? ['-NoProfile', '-Command', 'Start-Sleep -Seconds 5']
          : ['5'];

      final watch = Stopwatch()..start();
      final result = await runSystemProcess(
        exe,
        args,
        timeout: const Duration(milliseconds: 400),
      );
      watch.stop();

      expect(result.exitCode, isNot(0));
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('BluetoothService (bluetoothctl simulado)', () {
    test('REGRESIÓN Pi: toggle envía "power on" como DOS argumentos', () async {
      // Antes se llamaba a bluetoothctl con el argumento único "power on", que
      // BlueZ 5.82 rechaza con "Invalid command in menu main: power on", así
      // que el interruptor de Ajustes no hacía nada.
      final fake = FakeRunner({});

      await BluetoothService(
        runner: fake.runner,
        allowSudo: false,
      ).toggle(true);

      expect(
        fake.calls,
        containsAllInOrder([
          const ['bluetoothctl', 'power', 'on'],
        ]),
      );
    });

    test('ensureReady desbloquea rfkill y enciende el adaptador', () async {
      final fake = FakeRunner({
        'bluetoothctl show': _ok('Powered: no\nPowerState: off-blocked'),
        '/usr/sbin/rfkill list bluetooth': _ok(
          '0: hci0: Bluetooth\n\tSoft blocked: yes\n\tHard blocked: no\n',
        ),
        '/usr/sbin/rfkill unblock bluetooth': _ok(''),
        'bluetoothctl power on': _ok('Changing power on succeeded'),
      });

      final ok = await BluetoothService(runner: fake.runner).ensureReady();

      expect(ok, isTrue);
      expect(
        fake.calls.any((c) => listEquals(c, ['bluetoothctl', 'power', 'on'])),
        isTrue,
      );
    });

    test(
      'ensureReady no toca nada si el adaptador ya está encendido',
      () async {
        final fake = FakeRunner({'bluetoothctl show': _ok('Powered: yes\n')});

        final ok = await BluetoothService(runner: fake.runner).ensureReady();

        expect(ok, isTrue);
        expect(fake.calls.map((c) => c.join(' ')), ['bluetoothctl show']);
      },
    );

    test('scan marca emparejados y conectados según BlueZ', () async {
      final fake = FakeRunner({
        'bluetoothctl show': _ok('Powered: yes\n'),
        'bluetoothctl --timeout 8 scan on': _ok('Discovery started\n'),
        'bluetoothctl devices': _ok(
          'Device AA:01 Altavoz\nDevice AA:02 Auriculares\n',
        ),
        'bluetoothctl devices Paired': _ok('Device AA:01 Altavoz\n'),
        'bluetoothctl devices Connected': _ok('Device AA:02 Auriculares\n'),
      });

      final devs = await BluetoothService(runner: fake.runner).scan(seconds: 8);

      expect(devs, hasLength(2));
      expect(devs.firstWhere((d) => d.mac == 'AA:01').paired, isTrue);
      expect(devs.firstWhere((d) => d.mac == 'AA:01').connected, isFalse);
      expect(devs.firstWhere((d) => d.mac == 'AA:02').connected, isTrue);
    });

    test(
      'connectedDevices nunca lanza aunque bluetoothctl se cuelgue',
      () async {
        Future<ProcessResult> hung(
          String exe,
          List<String> args, {
          Duration timeout = const Duration(seconds: 8),
        }) {
          throw TimeoutException('proceso colgado');
        }

        expect(
          await BluetoothService(runner: hung).connectedDevices(),
          isEmpty,
        );
      },
    );
  });
}
