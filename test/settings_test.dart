import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/models/app_settings.dart';
import 'package:smart_display/screens/settings_screen.dart';
import 'package:smart_display/services/app_storage.dart';
import 'package:smart_display/services/radio_service.dart';
import 'package:smart_display/services/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() {
    // Evita el plugin nativo de audio durante los tests de widgets.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (MethodCall call) async => 1,
        );

    // Aísla la configuración en una carpeta temporal propia: no toca los
    // ajustes reales del usuario ni colisiona con otras suites en paralelo.
    tempDir = Directory.systemTemp.createTempSync('sd_settings_test_');
    AppStorage.overrideDirectory = tempDir;
  });

  tearDownAll(() {
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('AppSettings sobrevive a toMap/fromMap', () {
    final custom = AppSettings.defaults().copyWith(
      accentColor: const Color(0xFF10B981),
      fontFamily: 'Georgia',
      clockFontSize: 173,
      dateFontSize: 27,
      cardTextScale: 1.4,
      cardHeight: 132,
      clockWeight: 700,
      showSeconds: true,
      showDate: false,
      use24Hour: false,
      nightMode: true,
      locationLabel: "📍 Lleida",
      weatherLabel: 'Lleida',
      latitude: 41.6176,
      longitude: 0.62,
      weatherRefreshMinutes: 45,
      stationIndex: 2,
      volume: 0.35,
      alarmEnabled: false,
      alarmHour: 6,
      alarmMinute: 45,
      sunriseEnabled: false,
      sunriseMinutesBefore: 25,
      screensaverEnabled: true,
      screensaverMinutes: 7,
    );

    final restored = AppSettings.fromMap(custom.toMap());

    expect(restored.accentColor.toARGB32(), custom.accentColor.toARGB32());
    expect(restored.fontFamily, 'Georgia');
    expect(restored.clockFontSize, 173);
    expect(restored.dateFontSize, 27);
    expect(restored.cardTextScale, 1.4);
    expect(restored.cardHeight, 132);
    expect(restored.clockWeight, 700);
    expect(restored.showSeconds, isTrue);
    expect(restored.showDate, isFalse);
    expect(restored.use24Hour, isFalse);
    expect(restored.nightMode, isTrue);
    expect(restored.locationLabel, "📍 Lleida");
    expect(restored.weatherLabel, 'Lleida');
    expect(restored.latitude, 41.6176);
    expect(restored.longitude, 0.62);
    expect(restored.weatherRefreshMinutes, 45);
    expect(restored.stationIndex, 2);
    expect(restored.volume, 0.35);
    expect(restored.alarmEnabled, isFalse);
    expect(restored.alarmHour, 6);
    expect(restored.alarmMinute, 45);
    expect(restored.sunriseEnabled, isFalse);
    expect(restored.sunriseMinutesBefore, 25);
    expect(restored.screensaverEnabled, isTrue);
    expect(restored.screensaverMinutes, 7);
  });

  test('fromMap tolera claves ausentes o corruptas', () {
    final restored = AppSettings.fromMap(<String, dynamic>{
      'font': 42,
      'clockSize': 'grande',
      'night': 'sí',
      'lat': null,
      'vol': 0.5,
    });

    final defaults = AppSettings.defaults();
    expect(restored.fontFamily, defaults.fontFamily);
    expect(restored.clockFontSize, defaults.clockFontSize);
    expect(restored.nightMode, isFalse);
    expect(restored.latitude, defaults.latitude);
    expect(restored.volume, 0.5);
  });

  test('SettingsStore guarda y recupera en disco', () async {
    // La carpeta de configuración está aislada (tempDir), así que no se toca
    // el archivo real del usuario ni hace falta respaldarlo.
    final saved = AppSettings.defaults().copyWith(
      accentColor: const Color(0xFFEC4899),
      fontFamily: 'Verdana',
      clockFontSize: 150,
      showSeconds: true,
    );
    await SettingsStore.save(saved);

    final loaded = await SettingsStore.load();
    expect(loaded.accentColor.toARGB32(), saved.accentColor.toARGB32());
    expect(loaded.fontFamily, 'Verdana');
    expect(loaded.clockFontSize, 150);
    expect(loaded.showSeconds, isTrue);
    expect(loaded.weatherLabel, saved.weatherLabel);
    expect(loaded.alarmHour, saved.alarmHour);
  });

  testWidgets('La pantalla de ajustes (Android) navega y responde', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final radio = RadioService();
    var current = AppSettings.defaults();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: SettingsScreen(
          settings: current,
          radio: radio,
          onChanged: (s) => current = s,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Lista principal: 8 secciones (añadidas Wi-Fi y Bluetooth).
    expect(find.text('Pantalla'), findsOneWidget);
    expect(find.text('Tipografía'), findsOneWidget);
    expect(find.text('Reloj y fecha'), findsOneWidget);
    expect(find.text('Clima'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Red Wi-Fi'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Alarma y amanecer'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Alarma y amanecer'), findsOneWidget);

    Future<void> openSection(String section) async {
      final scrollable = find.byType(Scrollable).first;
      // La lista es lazy: tras bajar, los tiles de arriba se destruyen y
      // el finder queda vacio. Se sube a ciegas con drag antes de buscar.
      await tester.drag(scrollable, const Offset(0, 800));
      await tester.pumpAndSettle();
      final tile = find.text(section);
      await tester.scrollUntilVisible(tile, 200, scrollable: scrollable);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    // TIPOGRAFÍA: dos desplegables + dos sliders + vista previa.
    await openSection('Tipografía');
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.text('VISTA PREVIA'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // RELOJ: tres interruptores.
    await openSection('Reloj y fecha');
    expect(find.byType(Switch), findsNWidgets(3));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // ALARMA: el primer switch desactiva la alarma vía onChanged.
    await openSection('Alarma y amanecer');
    expect(current.alarmEnabled, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(current.alarmEnabled, isFalse);

    expect(tester.takeException(), isNull);
    radio.dispose();
  });

  testWidgets('Restablecer ajustes pide confirmación y aplica los defaults', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final radio = RadioService();
    AppSettings? captured;
    final modified = AppSettings.defaults().copyWith(
      accentColor: const Color(0xFF10B981),
      nightMode: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: SettingsScreen(
          settings: modified,
          radio: radio,
          onChanged: (s) => captured = s,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.text('Restablecer todos los ajustes');
    await tester.scrollUntilVisible(button, 100);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    // Diálogo de confirmación visible; cancelar no cambia nada.
    expect(find.text('Restablecer ajustes'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(captured, isNull);

    // Confirmar aplica los valores por defecto.
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restablecer'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(
      captured!.accentColor.toARGB32(),
      AppSettings.defaults().accentColor.toARGB32(),
    );
    expect(captured!.nightMode, isFalse);
    expect(tester.takeException(), isNull);
    radio.dispose();
  });
}
