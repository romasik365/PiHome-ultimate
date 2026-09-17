import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

import 'package:smart_display/main.dart';
import 'package:smart_display/models/app_settings.dart';
import 'package:smart_display/services/app_storage.dart';
import 'package:smart_display/services/settings_store.dart';
import 'package:smart_display/services/weather_service.dart';

/// Pruebas de integración de extremo a extremo: montan la **aplicación real**
/// (`SmartDisplayApp`) y recorren los flujos críticos del kiosco encadenando
/// varias pantallas, en lugar de comprobar widgets aislados.
///
/// Se ejecutan en un dispositivo/escritorio:
///   flutter test integration_test -d windows
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/app_test.dart -d linux
///
/// Notas de estabilidad:
///  * El reloj usa un `Timer.periodic` de 1 s, por lo que **nunca** se usa
///    `pumpAndSettle` (no hay reposo): se avanza con `pump` acotados.
///  * El clima se sirve desde un `MockClient`; el audio se mockea por canal.
///  * La configuración se aísla en una carpeta temporal (`overrideDirectory`),
///    de modo que no se tocan los ficheros reales del usuario.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
    WeatherService.debugClient = MockClient(
      (_) async => http.Response(weatherJson, 200),
    );

    tempDir = Directory.systemTemp.createTempSync('sd_e2e_');
    AppStorage.overrideDirectory = tempDir;
  });

  tearDownAll(() {
    WeatherService.debugClient = null;
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Ajustes deterministas: sin animación de arranque (arranque directo) y sin
  /// alarma (el overlay "¡BUENOS DÍAS!" taparía la interfaz según la hora).
  AppSettings e2eSettings() => AppSettings.defaults().copyWith(
    bootAnimation: false,
    alarmEnabled: false,
  );

  /// Monta la aplicación completa a resolución real de kiosco.
  Future<void> pumpApp(WidgetTester tester, {AppSettings? settings}) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      SmartDisplayApp(initialSettings: settings ?? e2eSettings()),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Desmonta la app (dispara `dispose`, que guarda los ajustes en disco).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// Avanza varios frames sin `pumpAndSettle` (el reloj nunca se detiene).
  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('arranque completo muestra la pantalla principal', (
    tester,
  ) async {
    await pumpApp(tester);
    await settle(tester);

    expect(find.text('CLIMA'), findsOneWidget);
    expect(find.text('STREAMING'), findsOneWidget);
    expect(find.text('ALARMA'), findsOneWidget);
    expect(find.text('⚙️ Ajustes'), findsOneWidget);
    // El clima servido por el MockClient llega a la tarjeta.
    expect(find.textContaining('21°C'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('la pantalla principal abre y cierra Ajustes', (tester) async {
    await pumpApp(tester);
    await settle(tester);

    await tester.tap(find.text('⚙️ Ajustes'), warnIfMissed: false);
    await settle(tester, frames: 8);
    expect(find.text('Pantalla'), findsOneWidget);
    expect(find.text('Red Wi-Fi'), findsOneWidget);

    await tester.pageBack();
    await settle(tester, frames: 8);
    expect(find.text('Pantalla'), findsNothing);
    expect(find.text('CLIMA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('el icono de Wi-Fi abre la página de red', (tester) async {
    await pumpApp(
      tester,
      settings: e2eSettings().copyWith(wifiEnabled: true, wifiSsid: 'MiCasa'),
    );
    await settle(tester);

    await tester.tap(find.byIcon(Icons.wifi), warnIfMissed: false);
    await settle(tester, frames: 8);

    // La ruta nombrada monta el cuerpo de ajustes de Wi-Fi con su AppBar.
    expect(find.text('Red Wi-Fi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('cambiar a modo noche se persiste en disco', (tester) async {
    await pumpApp(tester);
    await settle(tester);

    await tester.tap(find.text('🌙 Noche'), warnIfMissed: false);
    await settle(tester);

    // SmartDisplayApp guarda con un retardo de 500 ms tras el cambio.
    await tester.pump(const Duration(milliseconds: 700));

    final stored = await SettingsStore.load();
    expect(stored.nightMode, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('el reposo se activa y se despierta con un toque', (
    tester,
  ) async {
    await pumpApp(tester);
    await settle(tester);

    await tester.tap(find.text('💤 Reposo'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('Toca para despertar'), findsOneWidget);

    await tester.tap(find.text('Toca para despertar'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('Toca para despertar'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
