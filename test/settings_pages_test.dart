import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/models/app_settings.dart';
import 'package:smart_display/screens/settings_screen.dart';
import 'package:smart_display/services/radio_service.dart';

/// Abre las 6 sub-paginas de ajustes a resolucion real (800x480): cualquier
/// excepcion de ejecucion o overflow de layout hace fallar el test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (MethodCall call) async => 1,
        );
  });

  testWidgets('Las 6 sub-paginas se construyen sin excepciones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final radio = RadioService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: SettingsScreen(
          settings: AppSettings.defaults(),
          radio: radio,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openAndCheck(
      String section, {
      bool networkPage = false,
    }) async {
      final tile = find.text(section);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile, warnIfMissed: false);
      if (networkPage) {
        // La pagina Radio muestra un spinner mientras consulta el directorio.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
      } else {
        await tester.pumpAndSettle();
      }
      final exception = tester.takeException();
      expect(
        exception,
        isNull,
        reason: 'Excepcion al abrir "$section": $exception',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      final backException = tester.takeException();
      expect(
        backException,
        isNull,
        reason: 'Excepcion al volver de "$section": $backException',
      );
    }

    await openAndCheck('Pantalla');
    await openAndCheck('Tipografía');
    await openAndCheck('Reloj y fecha');
    await openAndCheck('Clima');
    await openAndCheck('Radio', networkPage: true);
    await openAndCheck('Alarma y amanecer');

    radio.dispose();
  });
}
