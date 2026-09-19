import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smart_display/main.dart';
import 'package:smart_display/models/app_settings.dart';
import 'package:smart_display/services/app_storage.dart';
import 'package:smart_display/services/weather_service.dart';

import 'helpers/fake_connectivity_services.dart';

/// Pruebas de widgets de la pantalla principal a resolución real (800x480).
///
/// * El plugin de audio se simula con canales mock.
/// * El clima se sirve desde un [MockClient] (sin red real).
/// * La conectividad se simula sin ejecutar procesos nativos.
/// * Los ajustes y favoritos usan una carpeta temporal aislada.
/// * NUNCA se usa pumpAndSettle: el reloj tiene un Timer.periodic de 1 s.
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

    // Aísla la configuración en una carpeta temporal propia (sin favoritos):
    // la radio arranca con las emisoras de fábrica y no se toca el usuario.
    tempDir = Directory.systemTemp.createTempSync('sd_main_test_');
    AppStorage.overrideDirectory = tempDir;
  });

  tearDownAll(() {
    WeatherService.debugClient = null;
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Ajustes deterministas para las pruebas de interfaz.
  ///
  /// La alarma viene activada por defecto (07:00 de lunes a viernes): si la
  /// prueba se ejecuta después de esa hora, el overlay "¡BUENOS DÍAS!" tapa
  /// toda la pantalla y ningún toque llega a las tarjetas.
  AppSettings testSettings({AppSettings? base}) =>
      (base ?? AppSettings.defaults()).copyWith(alarmEnabled: false);

  /// Monta la pantalla principal y devuelve la lista de cambios de ajustes
  /// notificados. Recuerda: sólo pump(), nunca pumpAndSettle() (el reloj tiene
  /// un Timer.periodic de 1 s).
  Future<List<AppSettings>> pumpMain(
    WidgetTester tester, {
    AppSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final changes = <AppSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: SmartDisplayScreen(
          settings: settings ?? testSettings(),
          onSettingsChanged: changes.add,
          wifiService: FakeWifiService(),
          bluetoothService: FakeBluetoothService(),
        ),
      ),
    );
    // Un frame más para que arranquen los timers de initState.
    await tester.pump(const Duration(milliseconds: 100));
    return changes;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('se construye con tarjetas, badges y clima mockeado', (
    tester,
  ) async {
    await pumpMain(tester);

    expect(find.text('CLIMA'), findsOneWidget);
    expect(find.text('STREAMING'), findsOneWidget);
    expect(find.text('ALARMA'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Noche'), findsOneWidget);
    expect(find.text('Reposo'), findsOneWidget);
    expect(find.text('Guissona, Lleida'), findsOneWidget);

    // El clima mockeado llega a la tarjeta.
    expect(find.textContaining('21°C'), findsOneWidget);
    expect(find.text('Parcialmente nublado'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('el badge de noche notifica el cambio de modo', (tester) async {
    final changes = await pumpMain(tester);

    await tester.tap(find.text('Noche'), warnIfMissed: false);
    await tester.pump();

    expect(changes, isNotEmpty);
    expect(changes.last.nightMode, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('el reposo manual se activa y se despierta con un toque', (
    tester,
  ) async {
    await pumpMain(tester);

    await tester.tap(find.text('Reposo'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Toca para despertar'), findsOneWidget);

    await tester.tap(find.text('Toca para despertar'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Toca para despertar'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('la tarjeta de clima abre el pronóstico con datos mockeados', (
    tester,
  ) async {
    await pumpMain(tester);

    await tester.tap(find.text('CLIMA'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Pronóstico · '), findsOneWidget);
    expect(find.text('Humedad: 55% · Viento: 12 km/h'), findsOneWidget);
    expect(find.text('Mañana'), findsOneWidget);

    // Cierra el diálogo con el botón de cerrar.
    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Pronóstico · '), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('la tarjeta de alarma abre su modal', (tester) async {
    await pumpMain(tester);

    await tester.tap(find.text('ALARMA'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alarma y Despertador'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('las flechas cambian de emisora y persisten el índice', (
    tester,
  ) async {
    final changes = await pumpMain(tester);

    expect(find.text('Kiss FM 106.5'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_right), warnIfMissed: false);
    await tester.pump();

    expect(find.text('Hit FM (UKR)'), findsOneWidget);
    expect(changes.last.stationIndex, 1);

    await tester.tap(find.byIcon(Icons.arrow_left), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Kiss FM 106.5'), findsOneWidget);
    expect(changes.last.stationIndex, 0);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('el modal de volumen configura el temporizador de sueño', (
    tester,
  ) async {
    await pumpMain(tester);

    await tester.tap(find.byIcon(Icons.volume_up), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Volumen y Apagado'), findsOneWidget);

    await tester.tap(find.text('30 m'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Se apaga en: 30 min'), findsOneWidget);

    await tester.tap(find.text('Off'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Se apaga en: 30 min'), findsNothing);

    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('el botón de reproducción entra en estado de carga', (
    tester,
  ) async {
    await pumpMain(tester);

    await tester.tap(find.text('Reproducir'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('Ajustes navega a la pantalla de ajustes y vuelve', (
    tester,
  ) async {
    await pumpMain(tester);

    await tester.tap(find.text('Ajustes'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tipografía'), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('CLIMA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('con la radio parada las flechas sólo cambian el nombre', (
    tester,
  ) async {
    final changes = await pumpMain(tester);

    expect(find.textContaining('Reproducir'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_right), warnIfMissed: false);
    await tester.pump();

    expect(find.text('Hit FM (UKR)'), findsOneWidget);
    expect(changes.last.stationIndex, 1);
    // Sin reproducción en marcha no debe arrancar sola.
    expect(find.textContaining('Reproducir'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('el temporizador de sueño sigue vivo tras cerrar el modal', (
    tester,
  ) async {
    await pumpMain(tester);

    await tester.tap(find.byIcon(Icons.volume_up), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('15 m'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Se apaga en: 15 min'), findsOneWidget);

    // Al cerrar el modal el temporizador sigue corriendo: su tick no puede
    // repintar un diálogo que ya no existe (antes lanzaba
    // "setState() called after dispose()").
    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });
}
