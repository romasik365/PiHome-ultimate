import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:convert';

import 'package:smart_display/main.dart';
import 'package:smart_display/models/app_settings.dart';
import 'package:smart_display/services/bluetooth_service.dart';
import 'package:smart_display/services/connectivity_service.dart';
import 'package:smart_display/services/wifi_service.dart';
import 'package:smart_display/services/weather_service.dart';
import 'package:smart_display/services/app_storage.dart';

import 'dart:io';

class _FakeWifi extends WifiService {
  String? ssid;
  int? signal;
  _FakeWifi(this.ssid, {this.signal});
  @override
  Future<String?> currentSsid() async => ssid;
  @override
  Future<int?> signalOf(String s) async => signal;
}

class _FakeBt extends BluetoothService {
  List<BluetoothDevice> devices;
  _FakeBt(this.devices);
  @override
  Future<List<BluetoothDevice>> connectedDevices() async => devices;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  final weatherJson = jsonEncode({
    'current': {
      'temperature_2m': 21.4,
      'relative_humidity_2m': 55,
      'weather_code': 2,
      'wind_speed_10m': 12.3,
    },
    'daily': {
      'weather_code': [2, 61, 0],
      'temperature_2m_max': [25.2, 20.6, 23.0],
      'temperature_2m_min': [12.4, 10.6, 11.0],
    },
  });

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall call) async => 1,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall call) async => 1,
    );
    WeatherService.debugClient = MockClient(
      (_) async => http.Response(weatherJson, 200),
    );
    // Aísla la configuración en una carpeta temporal propia: no toca los
    // ficheros reales del usuario ni colisiona con otras suites en paralelo.
    tempDir = Directory.systemTemp.createTempSync('sd_conn_test_');
    AppStorage.overrideDirectory = tempDir;
  });

  tearDownAll(() {
    WeatherService.debugClient = null;
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpWith(
    WidgetTester tester, {
    AppSettings? settings,
    ConnectivityService? connectivity,
  }) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final base = (settings ?? AppSettings.defaults()).copyWith(
      alarmEnabled: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: SmartDisplayScreen(
          settings: base,
          onSettingsChanged: (_) {},
          connectivityService: connectivity,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  ConnectivityService svc(_FakeWifi wifi, _FakeBt bt) {
    final s = ConnectivityService(wifi: wifi, bluetooth: bt);
    addTearDown(() {
      s.pause();
      s.dispose();
    });
    return s;
  }

  testWidgets('sin conexion muestra wifi_off y bluetooth_disabled atenuados', (
    tester,
  ) async {
    await pumpWith(tester, connectivity: svc(_FakeWifi(''), _FakeBt(const [])));
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_disabled), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsNothing);
    expect(find.byIcon(Icons.bluetooth_connected), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('wifiEnabled=false apaga el wifi aunque haya SSID guardado', (
    tester,
  ) async {
    final s = AppSettings.defaults().copyWith(
      wifiSsid: 'MiCasa',
      wifiEnabled: false,
    );
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(_FakeWifi(''), _FakeBt(const [])),
    );
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('con ssid en vivo + wifiEnabled muestra wifi activo', (
    tester,
  ) async {
    final s = AppSettings.defaults().copyWith(wifiEnabled: true);
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(_FakeWifi('MiCasa'), _FakeBt(const [])),
    );
    expect(find.byIcon(Icons.wifi), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('ssid desconocido usa el guardado en ajustes como respaldo', (
    tester,
  ) async {
    // Fuera de Linux (o sin nmcli) el chequeo en vivo devuelve null: la UI
    // debe caer al SSID guardado y encender el icono.
    final s = AppSettings.defaults().copyWith(
      wifiEnabled: true,
      wifiSsid: 'MiCasa',
    );
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(_FakeWifi(null), _FakeBt(const [])),
    );
    expect(find.byIcon(Icons.wifi), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('ssid desconocido y sin respaldo muestra wifi_off', (
    tester,
  ) async {
    final s = AppSettings.defaults().copyWith(wifiEnabled: true);
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(_FakeWifi(null), _FakeBt(const [])),
    );
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('bluetooth conectado en vivo enciende bluetooth_connected', (
    tester,
  ) async {
    final s = AppSettings.defaults().copyWith(bluetoothEnabled: true);
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(
        _FakeWifi(''),
        _FakeBt(const [
          BluetoothDevice(
            mac: 'AA:BB:CC:DD:EE:09',
            name: 'Altavoz',
            paired: true,
            connected: true,
          ),
        ]),
      ),
    );
    expect(find.byIcon(Icons.bluetooth_connected), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('emparejado sin conectar muestra bluetooth a medio tono', (
    tester,
  ) async {
    final s = AppSettings.defaults().copyWith(
      bluetoothEnabled: true,
      pairedBluetoothIds: ['AA:BB:CC:DD:EE:01'],
    );
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(_FakeWifi(''), _FakeBt(const [])),
    );
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_connected), findsNothing);
    expect(find.byIcon(Icons.bluetooth_disabled), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('intensidad wifi baja usa wifi_1_bar', (tester) async {
    final s = AppSettings.defaults().copyWith(wifiEnabled: true);
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(_FakeWifi('MiCasa', signal: 20), _FakeBt(const [])),
    );
    expect(find.byIcon(Icons.wifi_1_bar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('showConnectivityIcons=false oculta ambos iconos', (
    tester,
  ) async {
    final s = AppSettings.defaults().copyWith(showConnectivityIcons: false);
    await pumpWith(
      tester,
      settings: s,
      connectivity: svc(_FakeWifi('MiCasa'), _FakeBt(const [])),
    );
    expect(find.byIcon(Icons.wifi), findsNothing);
    expect(find.byIcon(Icons.wifi_off), findsNothing);
    expect(find.byIcon(Icons.bluetooth_connected), findsNothing);
    expect(find.byIcon(Icons.bluetooth_disabled), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
