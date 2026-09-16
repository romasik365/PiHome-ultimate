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

/// Integración de la animación de arranque con la app completa.
///
/// Comprueba que [SmartDisplayApp] superpone el [BootScreen] cuando
/// `bootAnimation` está activo y lo retira al terminar, y que no aparece si el
/// usuario lo desactiva. Se mockean audio y clima y se respalda settings.json.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Directory? tempDir;

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

    // Aísla la configuración en una carpeta temporal propia: SmartDisplayApp
    // guarda ajustes al desmontarse y no debe tocar los del usuario.
    tempDir = Directory.systemTemp.createTempSync('sd_boot_test_');
    AppStorage.overrideDirectory = tempDir;
  });

  tearDownAll(() {
    WeatherService.debugClient = null;
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpApp(WidgetTester tester, AppSettings settings) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SmartDisplayApp(initialSettings: settings));
    await tester.pump();
  }

  testWidgets('con bootAnimation activo muestra el boot y luego lo retira', (
    tester,
  ) async {
    final settings = AppSettings.defaults().copyWith(
      alarmEnabled: false,
      bootAnimation: true,
      bootMinDurationMs: 100,
    );
    await pumpApp(tester, settings);

    expect(find.text('PiHome Ultimate'), findsOneWidget);

    // Duración mínima (100 ms) + fade-out (450 ms) y desaparece.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('PiHome Ultimate'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('con bootAnimation desactivado no aparece el boot', (
    tester,
  ) async {
    final settings = AppSettings.defaults().copyWith(
      alarmEnabled: false,
      bootAnimation: false,
    );
    await pumpApp(tester, settings);

    expect(find.text('PiHome Ultimate'), findsNothing);
    expect(find.text('Iniciando sistema…'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
