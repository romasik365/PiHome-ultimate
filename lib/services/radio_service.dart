import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/radio_station.dart';
import 'app_storage.dart';
import 'radio_directory_service.dart';

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
    name: 'RAC1 Not\\u00edcies',
    url: 'https://playerservices.streamtheworld.com/api/livestream-redirect/RAC_1.mp3',
    countryCode: 'ES',
    tags: 'news,talk',
  ),
  Station(
    name: 'SomaFM Drone Zone',
    url: 'https://ice1.somafm.com/dronezone-128-mp3',
    countryCode: 'US',
    tags: 'ambient,relax',
  ),
];

class _LinuxAudioPlayer {
  Process? _process;
  bool _isPlaying = false;
  Function()? _onPlaybackChanged;
  String? _playerCommand;
  bool _playerCommandChecked = false;

  Future<String?> _findPlayer() async {
    for (final cmd in ['mpg123', 'omxplayer', 'cvlc', 'vlc']) {
      try {
        final r = await Process.run('which', [cmd]);
        if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty)
          return cmd;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _resolvePlayer() async {
    if (_playerCommandChecked) return _playerCommand;
    _playerCommandChecked = true;
    if (Platform.isLinux) {
      _playerCommand = await _findPlayer();
    }
    return _playerCommand;
  }

  Future<bool> play(String url, {double volume = 0.8}) async {
    final cmd = await _resolvePlayer();
    if (cmd == null) return false;
    stop();
    _isPlaying = true;
    _onPlaybackChanged?.call();
    try {
      final args = _buildArgs(url, volume);
      _process = await Process.start(cmd, args);
      _process!.exitCode.then((_) {
        _isPlaying = false;
        _onPlaybackChanged?.call();
        _process = null;
      });
      return true;
    } catch (e) {
      _isPlaying = false;
      _onPlaybackChanged?.call();
      return false;
    }
  }

  List<String> _buildArgs(String url, double volume) {
    if (_playerCommand == 'mpg123')
      return [
        '--gapless',
        '-r',
        '44100',
        '-f',
        (volume * 100).round().toString(),
        url,
      ];
    if (_playerCommand == 'omxplayer')
      return ['-o', 'both', '--vol', (volume * 100).round().toString(), url];
    if (_playerCommand == 'cvlc' || _playerCommand == 'vlc')
      return ['--play', '--quiet', '--no-video', url];
    return [url];
  }

  void stop() {
    _process?.kill();
    _process = null;
    _isPlaying = false;
    _onPlaybackChanged?.call();
  }

  bool get isPlaying => _isPlaying;
  void setOnPlaybackChanged(Function()? cb) {
    _onPlaybackChanged = cb;
  }
}

class RadioService {
  /// SOLO PARA PRUEBAS: fuerza el comportamiento de Linux sin importar la
  /// plataforma real, igual que [WifiService.debugTreatAsLinux]. Los tests
  /// corren en Windows pero necesitan ejercitar el código nativo (async,
  /// `isLoading` síncrono...).
  @visibleForTesting
  static bool debugTreatAsLinux = false;

  bool get _isLinux => Platform.isLinux || debugTreatAsLinux;

  final _LinuxAudioPlayer _linux = _LinuxAudioPlayer();
  List<Station> _stations = [...kDefaultStations];
  int currentStationIndex = 0;
  double volume = 0.8;
  int sleepMinutesLeft = 0;
  int sleepTimerSetting = 0;
  String? lastError;
  bool isPlaying = false;
  bool isLoading = false;
  RadioDirectoryService? _dir;
  RadioDirectoryService get directory => _dir ??= RadioDirectoryService();
  Timer? _sleepTimer;
  Function()? _onStateChanged;
  bool _disposed = false;

  List<Station> get stations => List.unmodifiable(_stations);
  Station get currentStation {
    if (_stations.isEmpty) return kDefaultStations.first;
    final idx =
        ((currentStationIndex % _stations.length) + _stations.length) %
        _stations.length;
    return _stations[idx];
  }

  /// Subtítulo corto de la emisora actual para la interfaz.
  ///
  /// Muestra los géneros y, si el bitrate es conocido (>0), el bitrate en kbps.
  /// Omite el bitrate cuando es 0 (emisoras de fábrica sin ese dato) para no
  /// mostrar "• 0 kbps" enganoso.
  String get stationSubtitle {
    final s = currentStation;
    final tags = s.tags.trim();
    final hasBitrate = s.bitrate > 0;
    if (tags.isEmpty && !hasBitrate) return '';
    if (tags.isEmpty) return '${s.bitrate} kbps';
    if (hasBitrate) return '$tags • ${s.bitrate} kbps';
    return tags;
  }

  static const _favFile = 'favorites.json';

  Future<void> init({Function()? onStateChanged}) async {
    _onStateChanged = onStateChanged;
    await loadFavorites();
    if (_isLinux) _linux.setOnPlaybackChanged(onStateChanged);
  }

  Future<void> loadFavorites() async {
    try {
      final f = AppStorage.configFile(_favFile);
      if (f == null || !await f.exists()) return;
      final raw = await f.readAsString();
      final data = jsonDecode(raw);
      if (data is List && data.isNotEmpty) {
        final favs = data
            .map((e) => Station.fromMap(e as Map<String, dynamic>))
            .where((s) => s.url.isNotEmpty)
            .toList();
        if (favs.isNotEmpty) {
          _stations = favs;
          currentStationIndex %= _stations.length;
        }
      }
    } catch (e) {
      debugPrint('RadioService: error loading favorites: ');
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    isLoading = true;
    lastError = null;
    if (_isLinux) {
      final ok = await _linux.play(currentStation.url, volume: volume);
      if (ok) {
        isPlaying = true;
        isLoading = false;
        _onStateChanged?.call();
      } else {
        isLoading = false;
        lastError = 'No hay reproductor de audio (mpg123/omxplayer)';
      }
    } else {
      isLoading = false;
      lastError = 'Radio no disponible en esta plataforma';
    }
  }

  Future<void> playStation(Station s) async {
    if (_disposed) return;
    final idx = _stations.indexWhere((st) => st.url == s.url);
    if (idx >= 0) currentStationIndex = idx;
    await play();
  }

  void changeStation(int delta, {bool announce = true, bool autoplay = true}) {
    if (_disposed) return;
    if (_stations.length > 1) {
      final old = currentStationIndex;
      currentStationIndex =
          ((currentStationIndex + delta) % _stations.length +
              _stations.length) %
          _stations.length;
      if (announce && old != currentStationIndex) _notify();
    }
    if (autoplay && (isPlaying || isLoading)) unawaited(play());
  }

  Future<void> toggle() async {
    if (_disposed) return;
    if (isPlaying || isLoading)
      await stop();
    else
      await play();
  }

  Future<void> stop() async {
    if (_disposed) return;
    isPlaying = false;
    isLoading = false;
    _linux.stop();
    _notify();
  }

  Future<void> setVolume(double v) async {
    if (_disposed) return;
    volume = v.clamp(0.0, 1.0);
    _notify();
  }

  void setSleepTimer(
    int mins, {
    void Function()? onTick,
    void Function()? onExpire,
  }) {
    if (_disposed) return;
    _sleepTimer?.cancel();
    sleepMinutesLeft = mins;
    sleepTimerSetting = mins;
    if (mins > 0) {
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

  Future<void> dispose() async {
    _disposed = true;
    _onStateChanged = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _linux.stop();
  }

  void resetToDefaults() {
    setStations([...kDefaultStations]);
  }

  void setStations(List<Station> list) {
    if (isPlaying) {
      stop();
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

  bool isFavorited(Station s) => _stations.any((st) => st.url == s.url);
  void toggleFavorite(Station s) {
    final idx = _stations.indexWhere((st) => st.url == s.url);
    if (idx >= 0) {
      if (_stations.length == 1)
        _stations
          ..clear()
          ..addAll(kDefaultStations);
      else
        _stations.removeAt(idx);
    } else {
      _stations.add(s);
    }
    if (currentStationIndex >= _stations.length) currentStationIndex = 0;
    saveFavorites();
    _notify();
  }

  Future<void> saveFavorites() async {
    try {
      final f = AppStorage.configFile(_favFile);
      if (f == null) return;
      await f.writeAsString(
        jsonEncode(_stations.map((s) => s.toMap()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('RadioService: error saving: ');
    }
  }
}
