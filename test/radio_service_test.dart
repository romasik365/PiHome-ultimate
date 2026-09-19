import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/models/radio_station.dart';
import 'package:smart_display/services/app_storage.dart';
import 'package:smart_display/services/radio_service.dart';

/// Pruebas de la lógica de [RadioService]: rotación, favoritos, volumen y
/// temporizador de sueño. El plugin de audio se simula con un canal mock y el
/// archivo real de favoritos del usuario se preserva y restaura.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;
  File? favFile;

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

    // Aísla la configuración en una carpeta temporal propia: no toca los
    // favoritos reales del usuario ni colisiona con otras suites en paralelo.
    tempDir = Directory.systemTemp.createTempSync('sd_radio_test_');
    AppStorage.overrideDirectory = tempDir;
    favFile = AppStorage.configFile('favorites.json');
  });

  tearDownAll(() {
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    // Cada prueba empieza sin favoritos guardados + modo Linux forzado:
    // los tests corren en Windows, pero el código nativo (async) debe
    // ejercitarse como en la Pi (Platform.isLinux = true simulado).
    try {
      if (favFile != null && favFile!.existsSync()) favFile!.deleteSync();
    } catch (_) {}
    RadioService.debugTreatAsLinux = true;
  });

  tearDown(() {
    RadioService.debugTreatAsLinux = false;
  });

  group('rotación de emisoras', () {
    test('arranca con las emisoras de fábrica', () {
      final r = RadioService();
      expect(r.stations, hasLength(kDefaultStations.length));
      expect(r.currentStation.name, kDefaultStations.first.name);
      expect(r.currentStationIndex, 0);
      r.dispose();
    });

    test('changeStation avanza y retrocede con rotación circular', () {
      final r = RadioService();
      final n = r.stations.length;

      r.changeStation(1);
      expect(r.currentStationIndex, 1);

      r.changeStation(-1);
      expect(r.currentStationIndex, 0);

      // Desde la primera, retroceder va a la última.
      r.changeStation(-1);
      expect(r.currentStationIndex, n - 1);

      // Desde la última, avanzar vuelve a la primera.
      r.changeStation(1);
      expect(r.currentStationIndex, 0);
      r.dispose();
    });

    test('setStations reemplaza la lista y vacía restaura las de fábrica', () {
      final r = RadioService();
      const custom = Station(name: 'Custom', url: 'http://custom/stream');
      r.setStations([custom]);
      expect(r.stations, hasLength(1));
      expect(r.currentStation.name, 'Custom');

      r.setStations([]);
      expect(r.stations, hasLength(kDefaultStations.length));
      r.dispose();
    });

    test('setStations corrige un índice fuera de rango', () {
      final r = RadioService();
      r.currentStationIndex = 3;
      r.setStations([const Station(name: 'A', url: 'http://a')]);
      expect(r.currentStationIndex, 0);
      r.dispose();
    });
  });

  group('favoritos', () {
    const extra = Station(name: 'Extra', url: 'http://extra/stream');

    test('toggleFavorite añade y quita una emisora', () {
      final r = RadioService();
      expect(r.isFavorited(extra), isFalse);

      r.toggleFavorite(extra);
      expect(r.isFavorited(extra), isTrue);
      expect(r.stations.length, kDefaultStations.length + 1);

      r.toggleFavorite(extra);
      expect(r.isFavorited(extra), isFalse);
      expect(r.stations.length, kDefaultStations.length);
      r.dispose();
    });

    test('quitar la última favorita restaura las de fábrica', () {
      final r = RadioService();
      // Vacía la lista quitando una a una.
      for (final s in [...r.stations]) {
        r.toggleFavorite(s);
      }
      // Al quitar la última se restauran las de fábrica: nunca queda vacía.
      expect(r.stations, hasLength(kDefaultStations.length));
      expect(r.stations.first.name, kDefaultStations.first.name);
      r.dispose();
    });

    test('guarda y carga favoritos en disco', () async {
      final r1 = RadioService();
      r1.setStations([extra]);
      unawaited(r1.dispose());

      final r2 = RadioService();
      await r2.loadFavorites();
      expect(r2.stations, hasLength(1));
      expect(r2.stations.single.url, extra.url);
      r2.dispose();
    });

    test(
      'loadFavorites con archivo corrupto mantiene las de fábrica',
      () async {
        favFile!.writeAsStringSync('{no es json', flush: true);
        final r = RadioService();
        await r.loadFavorites();
        expect(r.stations, hasLength(kDefaultStations.length));
        r.dispose();
      },
    );
  });

  group('volumen y subtítulo', () {
    test('setVolume limita el valor entre 0.0 y 1.0', () async {
      final r = RadioService();
      await r.setVolume(2.0);
      expect(r.volume, 1.0);
      await r.setVolume(-1.0);
      expect(r.volume, 0.0);
      await r.setVolume(0.35);
      expect(r.volume, 0.35);
      r.dispose();
    });

    test('stationSubtitle omite el bitrate desconocido', () {
      final r = RadioService();
      // Kiss FM tiene géneros pero bitrate 0: no debe salir "• 0 kbps".
      expect(r.stationSubtitle, 'pop,top 40');
      r.setStations([
        const Station(
          name: 'HiFi',
          url: 'http://hifi',
          tags: 'jazz',
          bitrate: 320,
        ),
      ]);
      expect(r.stationSubtitle, 'jazz • 320 kbps');
      r.setStations([const Station(name: 'Muda', url: 'http://muda')]);
      expect(r.stationSubtitle, '');
      r.dispose();
    });
  });

  group('temporizador de sueño', () {
    testWidgets('cuenta atrás, mantiene el ajuste y se apaga solo', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final r = RadioService();
      var ticks = 0;
      var expired = false;

      r.setSleepTimer(2, onTick: () => ticks++, onExpire: () => expired = true);
      expect(r.sleepMinutesLeft, 2);
      expect(r.sleepTimerSetting, 2);

      await tester.pump(const Duration(minutes: 1));
      expect(r.sleepMinutesLeft, 1);
      expect(ticks, 1);
      // El ajuste configurado NO decrece (la UI lo usa para la selección).
      expect(r.sleepTimerSetting, 2);
      expect(expired, isFalse);

      await tester.pump(const Duration(minutes: 1));
      expect(expired, isTrue);
      expect(r.sleepMinutesLeft, 0);
      expect(r.sleepTimerSetting, 0);

      // No se espera al dispose: el plugin nativo mockeado no completa
      // dispose() dentro de la zona fake de los tests de widgets.
      unawaited(r.dispose());
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('poner 0 cancela el temporizador', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final r = RadioService();
      r.setSleepTimer(15);
      expect(r.sleepTimerSetting, 15);
      r.setSleepTimer(0);
      expect(r.sleepMinutesLeft, 0);
      expect(r.sleepTimerSetting, 0);

      // Avanza el tiempo: no debe dispararse nada.
      await tester.pump(const Duration(minutes: 20));
      expect(r.sleepMinutesLeft, 0);

      unawaited(r.dispose());
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('reproducción (sin esperar al plugin nativo)', () {
    // NOTA: el plugin mockeado no completa play()/dispose() (espera eventos
    // nativos que nunca llegan). Como RadioService actualiza sus indicadores
    // de forma síncrona, las pruebas verifican el estado sin await al plugin.
    test('play marca cargando y stop lo limpia de forma síncrona', () {
      final r = RadioService();
      unawaited(r.play());
      expect(r.isLoading, isTrue);
      expect(r.lastError, isNull);

      unawaited(r.stop());
      expect(r.isPlaying, isFalse);
      expect(r.isLoading, isFalse);
      unawaited(r.dispose());
    });

    test('toggle intenta reproducir cuando está parado', () {
      final r = RadioService();
      unawaited(r.toggle());
      expect(r.isLoading, isTrue);
      expect(r.isPlaying, isFalse);
      unawaited(r.stop());
      unawaited(r.dispose());
    });

    test('playStation salta a la emisora pedida', () {
      final r = RadioService();
      const target = Station(name: 'Objetivo', url: 'http://obj/stream');
      r.toggleFavorite(target);
      unawaited(r.playStation(target));
      expect(r.currentStation.url, target.url);
      expect(r.isLoading, isTrue);
      unawaited(r.dispose());
    });

    test('tras dispose, las acciones son no-op seguras', () async {
      final r = RadioService();
      unawaited(r.dispose());
      await r.play();
      await r.stop();
      await r.toggle();
      await r.setVolume(0.5);
      r.changeStation(1);
      r.setSleepTimer(10);
      expect(r.currentStationIndex, 0);
      expect(r.sleepTimerSetting, 0);
      expect(r.volume, 0.8); // no cambió: el servicio está inerte
    });
  });

  group('cambio de emisora en reproducción', () {
    // REGRESIÓN: antes las flechas ‹ › sólo cambiaban el nombre en pantalla y
    // seguía sonando el stream anterior; había que pulsar Detener y
    // Reproducir. Ahora la nueva emisora se conecta al instante.
    test('con la radio sonando, la flecha pide la nueva emisora al plugin', () {
      final r = RadioService();
      // Simula un stream ya conectado (en la app lo marca el propio plugin).
      r.isPlaying = true;
      r.changeStation(1);

      expect(r.currentStation.name, kDefaultStations[1].name);
      // play() marca "cargando" de forma SÍNCRONA: es la señal de que se ha
      // pedido conectar la nueva URL. Antes no se pedía nada y seguía sonando
      // la emisora vieja hasta pulsar Detener + Reproducir.
      expect(r.isLoading, isTrue);
      unawaited(r.dispose());
    });

    test('con la radio parada, cambiar de emisora no arranca el stream', () {
      final r = RadioService();
      r.changeStation(1);
      expect(r.currentStationIndex, 1);
      // play() marcaría "cargando" de forma síncrona; aquí no debe hacerlo.
      expect(r.isLoading, isFalse);
      r.dispose();
    });

    test('detener cancela la petición de reproducción', () {
      final r = RadioService();
      unawaited(r.play());
      expect(r.isLoading, isTrue);
      unawaited(r.stop());
      r.changeStation(1);
      expect(r.isLoading, isFalse, reason: 'ya no se reproduce sola');
      unawaited(r.dispose());
    });
  });
}
