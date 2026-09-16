import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/radio_station.dart';
import 'app_storage.dart';
import 'radio_directory_service.dart';

/// Emisoras de fábrica por defecto. Se usan como rotación inicial cuando el
/// usuario no ha seleccionado favoritas desde el directorio online.
const List<Station> kDefaultStations = [
  Station(
    name: 'Kiss FM 106.5',
    url: 'http://online.kissfm.ua/KissFM',
    countryCode: 'ES',
    tags: 'pop,top 40',
  ),
  Station(
    name: 'Hit FM (UKR)',
    url: 'http://195.95.206.17/HitFM',
    countryCode: 'UA',
    tags: 'pop',
  ),
  Station(
    name: 'RAC1 Notícies',
    url: 'https://playerservices.streamtheworld.com/api/livestream-redirect/RAC_1.mp3',
    countryCode: 'ES',
    tags: 'news,talk',
  ),
  // La URL original de zeno.fm devuelve 401; se sustituye por uno stream
  // ambiental verificado que entrega audio/mpeg.
  Station(
    name: 'SomaFM Drone Zone',
    url: 'https://ice1.somafm.com/dronezone-128-mp3',
    countryCode: 'US',
    tags: 'ambient,relax',
  ),
];

/// Reproductor de radio real basado en `audioplayers`.
///
/// Gestiona una **lista de emisoras activa** (favoritas del usuario o, si no
/// hay ninguna, las [kDefaultStations]) y un directorio online
/// ([RadioDirectoryService]) para buscar más.
class RadioService {
  final AudioPlayer _player = AudioPlayer();

  /// Emisoras de la rotación actual (favoritas o por defecto).
  List<Station> _stations = [...kDefaultStations];

  int currentStationIndex = 0;
  double volume = 0.8;
  int sleepMinutesLeft = 0;

  /// Minutos configurados en el último temporizador de sueño (0 = apagado).
  /// A diferencia de [sleepMinutesLeft], no decrece: sirve para que la
  /// interfaz mantenga seleccionado el botón elegido (15/30/45/60).
  int sleepTimerSetting = 0;
  String? lastError;
  bool isPlaying = false;
  bool isLoading = false;

  /// Directorio online (se crea bajo demanda).
  RadioDirectoryService? _directory;
  RadioDirectoryService get directory => _directory ??= RadioDirectoryService();

  // --- suscripciones ---
  Timer? _sleepTimer;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<AudioEvent>? _eventSub;
  Function()? _onStateChanged;
  bool _disposed = false;
  int _retriesLeft = 0;
  Future<void>? _configuring;

  /// True desde que el usuario pide reproducir hasta que detiene la radio
  /// (aunque el stream esté cargando o haya fallado).
  ///
  /// Lo usan las flechas  › de la tarjeta STREAMING para reproducir la nueva
  /// emisora al instante en lugar de dejar sonando la anterior.
  bool _playRequested = false;

  List<Station> get stations => List.unmodifiable(_stations);
  Station get currentStation {
    if (_stations.isEmpty) return kDefaultStations.first;
    final idx =
        ((currentStationIndex % _stations.length) + _stations.length) %
        _stations.length;
    return _stations[idx];
  }

  // ---- favoritos ----

  static const _favFile = 'favorites.json';

  /// Carga las emisoras favoritas desde disco. Si no hay ninguna, mantiene
  /// las de fábrica.
  Future<void> loadFavorites() async {
    try {
      final file = AppStorage.configFile(_favFile);
      if (file == null || !await file.exists()) return;
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is List && data.isNotEmpty) {
        final favs = data
            .map((e) => Station.fromMap(e as Map<String, dynamic>))
            .where((s) => s.url.isNotEmpty)
            .toList();
        if (favs.isNotEmpty) {
          _stations = favs;
          currentStationIndex = currentStationIndex % _stations.length;
        }
      }
    } catch (error) {
      debugPrint('RadioService: no se pudieron cargar favoritos ($error)');
    }
  }

  /// Persiste las emisoras favoritas en disco.
  Future<void> saveFavorites() async {
    try {
      final file = AppStorage.configFile(_favFile);
      if (file == null) return;
      await file.writeAsString(
        jsonEncode(_stations.map((s) => s.toMap()).toList()),
        flush: true,
      );
    } catch (error) {
      debugPrint('RadioService: no se pudieron guardar favoritos ($error)');
    }
  }

  /// Reemplaza la rotación actual por [list].
  /// Si [list] está vacía, restaura las emisoras de fábrica.
  void setStations(List<Station> list) {
    final stop = isPlaying; // NUEVO 1: detener antes de reemplazar la rotacion.
    if (stop) {
      unawaited(_player.stop());
      isPlaying = false;
      isLoading = false;
    }
    _stations
      ..clear()
      ..addAll(list.isEmpty ? kDefaultStations : list);
    if (currentStationIndex >= _stations.length) currentStationIndex = 0;
    saveFavorites();
    _notify();
  }

  /// Restaura las emisoras de fábrica (borra los favoritos guardados).
  void resetToDefaults() => setStations([...kDefaultStations]);

  /// Añade o quita [station] de las favoritas (también actualiza la rotación).
  /// Nunca deja la lista vacía: quitar la última restaura las de fábrica.
  void toggleFavorite(Station station) {
    final idx = _stations.indexWhere((s) => s.url == station.url);
    if (idx >= 0) {
      if (_stations.length == 1) {
        _stations
          ..clear()
          ..addAll(kDefaultStations);
      } else {
        _stations.removeAt(idx);
      }
    } else {
      _stations.add(station);
    }
    if (currentStationIndex >= _stations.length) currentStationIndex = 0;
    saveFavorites();
    _notify();
  }

  /// Devuelve true si [station] está en la rotación actual.
  bool isFavorited(Station station) =>
      _stations.any((s) => s.url == station.url);

  /// Subtítulo de la emisora actual: géneros y bitrate, omitiendo lo que se
  /// desconozca (antes mostraba un espurio "• 0 kbps").
  String get stationSubtitle => [
    if (currentStation.tags.isNotEmpty) currentStation.tags,
    if (currentStation.bitrate > 0) '${currentStation.bitrate} kbps',
  ].join(' • ');

  /// Inicializa el servicio: suscripciones + carga de favoritas.
  Future<void> init({required void Function()? onStateChanged}) async {
    _onStateChanged = onStateChanged;

    _stateSub = _player.onPlayerStateChanged.listen(
      (state) {
        if (state == PlayerState.playing) {
          isPlaying = true;
          isLoading = false;
        } else if (state == PlayerState.paused) {
          isPlaying = false;
          isLoading = false;
        }
        if (state == PlayerState.completed) {
          stop();
          isPlaying = false;
        }
        _notify();
      },
      onError: (e) {
        lastError = 'Stream error: $e';
        isPlaying = false;
        isLoading = false;
        _notify();
      },
    );

    _eventSub = _player.eventStream.listen(
      (_) {},
      onError: (e) {
        lastError = 'Event error: $e';
        _notify();
      },
    );

    await setVolume(volume);
    await loadFavorites();
  }

  /// Configura volumen + release mode. Se guarda en [_configuring] para no
  /// superponer llamadas.
  Future<void> _configure() {
    _configuring ??= _doConfigure();
    return _configuring!;
  }

  Future<void> _doConfigure() async {
    try {
      await _player.setVolume(volume);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (e) {
      lastError = 'configure: $e';
    } finally {
      _configuring = null;
    }
  }

  /// Reproduce la emisora activa.
  ///
  /// El estado de "cargando" se activa de forma SÍNCRONA, antes de esperar al
  /// plugin nativo: la interfaz responde al instante (spinner) aunque el
  /// stream tarde en conectar, y las pruebas no dependen del plugin.
  Future<void> play() async {
    if (_disposed) return;
    _playRequested = true;
    // Intento nuevo del usuario: se rearma el reintento automático.
    _retriesLeft = 1;
    await _startStream();
  }

  /// Conecta con la emisora activa (con reintento automático si falla).
  ///
  /// Está separada de [play] para que los reintentos NO reinicien el contador:
  /// antes [play] y [changeStation] lo ponían a 1 en cada intento, de modo que
  /// un stream caído se quedaba reintentando en bucle infinito.
  Future<void> _startStream() async {
    if (_disposed) return;
    isLoading = true;
    _notify();
    try {
      await _configure();
      await _player.play(UrlSource(currentStation.url));
    } catch (e) {
      lastError = 'play error: $e';
      if (!await _retryNext()) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Reproduce [station] y salta a ella en la rotación.
  Future<void> playStation(Station station) async {
    if (_disposed) return;
    final idx = _stations.indexWhere((s) => s.url == station.url);
    if (idx >= 0) currentStationIndex = idx;
    await play();
  }

  /// Reintenta con la emisora siguiente si la actual falla (máx. 2 intentos).
  Future<bool> _retryNext() async {
    if (_disposed || _retriesLeft <= 0) return false;
    _retriesLeft--;
    // Sin autoplay: este método lanza el stream de la nueva emisora justo
    // después, así que no debe dispararlo dos veces.
    changeStation(1, announce: false, autoplay: false);
    await _startStream();
    return true;
  }

  /// Cambia de emisora. Si [announce] es true, avisa para repintar la interfaz.
  ///
  /// Si la radio está sonando (o intentando sonar) la nueva emisora se
  /// reproduce al instante: antes las flechas ‹ › sólo cambiaban el nombre en
  /// pantalla y seguía sonando el stream anterior hasta pulsar
  /// Detener + Reproducir.
  void changeStation(int delta, {bool announce = true, bool autoplay = true}) {
    if (_disposed) return;
    if (_stations.length > 1) {
      final old = currentStationIndex;
      currentStationIndex = ((currentStationIndex + delta) % _stations.length);
      if (currentStationIndex < 0) {
        currentStationIndex += _stations.length;
      }
      if (announce && old != currentStationIndex) {
        _notify();
      }
    }
    if (autoplay && (isPlaying || isLoading || _playRequested)) {
      unawaited(play());
    }
  }

  /// Alterna play / stop.
  Future<void> toggle() async {
    if (!_disposed) {
      if (isPlaying || isLoading) {
        await stop();
      } else {
        await play();
      }
    }
  }

  /// Detiene la reproducción.
  ///
  /// Los indicadores se limpian de forma SÍNCRONA antes de avisar al plugin:
  /// la interfaz deja de mostrar "cargando" al instante aunque el plugin
  /// nativo tarde (o no responda, como en las pruebas).
  Future<void> stop() async {
    if (_disposed) return;
    _playRequested = false;
    isPlaying = false;
    isLoading = false;
    _retriesLeft = 0;
    try {
      await _player.stop();
    } catch (_) {}
    _notify();
  }

  /// Ajusta el volumen (0.0–1.0) al reproductor y a la variable local.
  Future<void> setVolume(double value) async {
    if (_disposed) return;
    volume = value.clamp(0.0, 1.0);
    _notify();
    try {
      await _player.setVolume(volume);
    } catch (e) {
      lastError = 'volume: $e';
    }
  }

  /// Temporizador de apagado: detiene la radio tras [minutes] (0 = cancela).
  void setSleepTimer(
    int minutes, {
    void Function()? onTick,
    void Function()? onExpire,
  }) {
    if (_disposed) return;
    _sleepTimer?.cancel();
    sleepMinutesLeft = minutes;
    sleepTimerSetting = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer.periodic(const Duration(minutes: 1), (t) {
        sleepMinutesLeft--;
        onTick?.call();
        if (sleepMinutesLeft <= 0) {
          unawaited(stop());
          onExpire?.call();
          t.cancel();
          sleepMinutesLeft = 0;
          sleepTimerSetting = 0;
          _notify();
        }
      });
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) _onStateChanged?.call();
  }

  /// Libera los recursos del reproductor.
  Future<void> dispose() async {
    _disposed = true;
    _onStateChanged = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    unawaited(_stateSub?.cancel());
    unawaited(_eventSub?.cancel());
    _stateSub = null;
    _eventSub = null;
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
