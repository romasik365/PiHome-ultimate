import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/services/app_log.dart';
import 'package:smart_display/services/app_storage.dart';
import 'package:smart_display/widgets/app_bootstrap.dart';
import 'package:smart_display/widgets/error_screen.dart';

/// Pruebas de [AppBootstrap]: la app real se muestra mientras no hay errores,
/// y ante un fallo fatal se sustituye por [ErrorScreen] con botón de reinicio
/// que vuelve a montar la aplicación desde cero.
void main() {
  Directory? tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('sd_bootstrap_test_');
    AppStorage.overrideDirectory = tempDir;
  });

  tearDownAll(() {
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    AppLog.resetForTest();
    AppLog.onFatal = null;
  });

  tearDown(() {
    AppLog.onFatal = null;
    AppLog.resetForTest();
  });

  testWidgets('sin errores muestra la aplicación real', (tester) async {
    await tester.pumpWidget(
      AppBootstrap(
        appBuilder: (key) => MaterialApp(
          key: key,
          home: const Scaffold(body: Text('APP REAL')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('APP REAL'), findsOneWidget);
    expect(find.byType(ErrorScreen), findsNothing);
  });

  testWidgets('un error fatal sustituye la interfaz por ErrorScreen', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppBootstrap(
        appBuilder: (key) => MaterialApp(
          key: key,
          home: const Scaffold(body: Text('APP REAL')),
        ),
      ),
    );
    await tester.pump();

    // El árbol ya montado registró su callback: se dispara como haría
    // FlutterError.onError ante un fallo irrecuperable.
    AppLog.onFatal?.call(Exception('boom irrecuperable'), StackTrace.current);
    await tester.pump();

    expect(find.byType(ErrorScreen), findsOneWidget);
    expect(find.text('Algo ha ido mal'), findsOneWidget);
    expect(find.textContaining('boom irrecuperable'), findsWidgets);
    expect(find.text('APP REAL'), findsNothing);
  });

  testWidgets('Reiniciar oculta el error y remonta la app con otra key', (
    tester,
  ) async {
    final keys = <Key?>[];
    await tester.pumpWidget(
      AppBootstrap(
        appBuilder: (key) {
          keys.add(key);
          return MaterialApp(
            key: key,
            home: const Scaffold(body: Text('APP REAL')),
          );
        },
      ),
    );
    await tester.pump();

    AppLog.onFatal?.call(Exception('caida'), StackTrace.current);
    await tester.pump();
    expect(find.byType(ErrorScreen), findsOneWidget);

    await tester.tap(find.text('Reiniciar'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorScreen), findsNothing);
    expect(find.text('APP REAL'), findsOneWidget);
    // La app se reconstruyó con una key nueva (initState limpio).
    expect(keys.length, greaterThan(1));
    expect(keys.first, isNot(equals(keys.last)));
  });

  testWidgets('ErrorScreen sin onRestart no ofrece el botón Reiniciar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ErrorScreen(error: Exception('solo lectura'))),
      ),
    );
    await tester.pump();

    expect(find.text('Algo ha ido mal'), findsOneWidget);
    expect(find.text('Reiniciar'), findsNothing);
    expect(find.text('Copiar detalles'), findsOneWidget);
    // Muestra dónde está el log para poder diagnosticar.
    expect(find.textContaining('app.log'), findsOneWidget);
  });
}
