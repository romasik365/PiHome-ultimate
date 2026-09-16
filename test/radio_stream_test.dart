import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/services/radio_service.dart';

/// REGRESIÓN: al pulsar la flecha ‹ › con la radio sonando no se pedía nada al
/// plugin de audio y seguía sonando la emisora anterior; había que pulsar
/// Detener + Reproducir. Esta prueba comprueba la URL real que se pide.
///
/// Vive en su propio archivo porque el canal simulado de audioplayers sólo
/// contesta en la primera prueba de cada archivo (los mensajes del canal de
/// eventos de cada reproductor quedan pendientes y bloquean al resto).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('las flechas conectan con la nueva emisora mientras suena', (
    tester,
  ) async {
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
    expect(urls, [kDefaultStations.first.url], reason: 'arranca la primera');

    radio.changeStation(1);
    await tester.pump();

    expect(radio.currentStation.name, kDefaultStations[1].name);
    expect(urls, [
      kDefaultStations.first.url,
      kDefaultStations[1].url,
    ], reason: 'el plugin debe recibir la nueva URL, no la anterior');

    unawaited(radio.dispose());
    await tester.pump();
  });
}
