import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/services/radio_service.dart';

/// REGRESIÓN: `play()` y `changeStation()` rearmaban el contador de reintentos,
/// así que un stream que no conecta reintentaba en bucle infinito (saltando de
/// emisora sin parar). Esta prueba comprueba que sólo hay un reintento.
///
/// Vive en su propio archivo porque el canal simulado de audioplayers sólo
/// contesta en la primera prueba de cada archivo (los mensajes del canal de
/// eventos de cada reproductor quedan pendientes y bloquean al resto).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('un stream que no carga reintenta una vez y se detiene', (
    tester,
  ) async {
    // El plugin simulado nunca emite el evento "prepared", así que cada intento
    // acaba en timeout: es exactamente el camino de error que probamos.
    final previousTimeout = AudioPlayer.preparationTimeout;
    AudioPlayer.preparationTimeout = const Duration(milliseconds: 50);
    addTearDown(() => AudioPlayer.preparationTimeout = previousTimeout);

    final urls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall call) async {
        if (call.method == 'setSourceUrl') {
          final args = call.arguments;
          urls.add(args is Map ? '${args['url']}' : '$args');
        }
        return 1;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall call) async => 1,
    );

    await tester.pumpWidget(const SizedBox());
    final radio = RadioService();

    unawaited(radio.play());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(urls, [
      kDefaultStations.first.url,
      kDefaultStations[1].url,
    ], reason: 'un intento + un solo reintento');
    expect(radio.currentStationIndex, 1);
    expect(radio.isLoading, isFalse, reason: 'deja de intentarlo');
    expect(radio.lastError, isNotNull);

    unawaited(radio.dispose());
    await tester.pump();
  });
}
