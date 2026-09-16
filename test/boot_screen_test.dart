import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/models/app_settings.dart';
import 'package:smart_display/widgets/boot_screen.dart';

void main() {
  Future<void> pumpBoot(
    WidgetTester tester, {
    required Future<void> onReady,
    Duration minDuration = const Duration(milliseconds: 10),
    Duration fadeOut = const Duration(milliseconds: 10),
    VoidCallback? onFinished,
  }) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: BootScreen(
          accent: const Color(0xFF6366F1),
          onReady: onReady,
          minDuration: minDuration,
          fadeOut: fadeOut,
          onFinished: onFinished,
        ),
      ),
    );
  }

  testWidgets('muestra el titulo y el subtitulo de arranque', (tester) async {
    await pumpBoot(tester, onReady: Future<void>.value());
    expect(find.text('PiHome Ultimate'), findsOneWidget);
    expect(find.text('Iniciando sistema…'), findsOneWidget);

    // Deja que el boot termine y se desmonte (evita timers pendientes).
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('el logotipo late (la escala cambia con el tiempo)', (
    tester,
  ) async {
    // Un Completer controla cuándo termina la "carga" para poder observarla.
    final ready = Completer<void>();
    await pumpBoot(tester, onReady: ready.future);

    double scaleNow() => tester
        .widget<ScaleTransition>(find.byType(ScaleTransition))
        .scale
        .value;

    final first = scaleNow();
    await tester.pump(const Duration(milliseconds: 350));
    final second = scaleNow();

    expect(second, isNot(closeTo(first, 0.001)));

    // Completa la carga y deja al widget salir limpiamente.
    ready.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('onFinished se llama solo tras cumplir la duracion minima', (
    tester,
  ) async {
    var finished = false;
    await pumpBoot(
      tester,
      onReady: Future<void>.value(),
      minDuration: const Duration(milliseconds: 300),
      fadeOut: const Duration(milliseconds: 50),
      onFinished: () => finished = true,
    );

    await tester.pump(const Duration(milliseconds: 150));
    expect(finished, isFalse);

    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, isTrue);
  });

  testWidgets('respeta la duracion minima aunque la carga sea instantanea', (
    tester,
  ) async {
    var finished = false;
    await pumpBoot(
      tester,
      onReady: Future<void>.value(),
      minDuration: const Duration(milliseconds: 500),
      fadeOut: const Duration(milliseconds: 10),
      onFinished: () => finished = true,
    );

    await tester.pump(const Duration(milliseconds: 250));
    expect(finished, isFalse);

    await tester.pump(const Duration(milliseconds: 400));
    expect(finished, isTrue);
  });

  group('AppSettings: animacion de arranque', () {
    test('valores por defecto activan la animacion con 1200 ms', () {
      final d = AppSettings.defaults();
      expect(d.bootAnimation, isTrue);
      expect(d.bootMinDurationMs, 1200);
    });

    test('copyWith cambia la animacion de arranque', () {
      final s = AppSettings.defaults().copyWith(
        bootAnimation: false,
        bootMinDurationMs: 2000,
      );
      expect(s.bootAnimation, isFalse);
      expect(s.bootMinDurationMs, 2000);
    });

    test('sobrevive a toMap/fromMap', () {
      final custom = AppSettings.defaults().copyWith(
        bootAnimation: false,
        bootMinDurationMs: 2400,
      );
      final restored = AppSettings.fromMap(custom.toMap());
      expect(restored.bootAnimation, isFalse);
      expect(restored.bootMinDurationMs, 2400);
    });

    test('fromMap tolera claves ausentes (usa los valores por defecto)', () {
      final restored = AppSettings.fromMap(<String, dynamic>{});
      expect(restored.bootAnimation, AppSettings.defaults().bootAnimation);
      expect(
        restored.bootMinDurationMs,
        AppSettings.defaults().bootMinDurationMs,
      );
    });
  });
}
