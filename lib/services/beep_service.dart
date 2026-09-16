import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'app_storage.dart';

/// Sonido de alarma local ("pitido") sin assets ni red.
///
/// Sintetiza en caliente un WAV PCM de 16 bits (3 pitidos de 880 Hz con
/// envolvente para evitar clics), lo guarda en la carpeta de configuración y
/// lo reproduce en bucle con un [AudioPlayer] independiente del de la radio,
/// de modo que detener la alarma no interfiere con la emisora.
class BeepService {
  AudioPlayer? _player;
  bool _playing = false;

  static const _fileName = 'alarm_beep.wav';

  /// Crea el archivo WAV la primera vez que hace falta.
  Future<String?> _ensureFile() async {
    final file = AppStorage.configFile(_fileName);
    if (file == null) return null;
    if (!file.existsSync()) {
      await file.writeAsBytes(_buildBeepWav(), flush: true);
    }
    return file.path;
  }

  /// Empieza a sonar el pitido en bucle. No hace nada si ya está sonando.
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      final path = await _ensureFile();
      if (!_playing) {
        // Se llamó a stop() mientras se creaba/verificaba el archivo.
        return;
      }
      if (path == null) {
        _playing = false;
        return;
      }
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(1.0);
      if (!_playing) return;
      await player.play(DeviceFileSource(path));
    } catch (_) {
      _playing = false;
      // Sin audio disponible: la alarma visual sigue apareciendo.
    }
  }

  /// Detiene el pitido.
  Future<void> stop() async {
    _playing = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Libera el reproductor.
  Future<void> dispose() async {
    _playing = false;
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }

  /// WAV mono 16-bit 44,1 kHz: 3 pitidos de 250 ms separados por 150 ms.
  static Uint8List _buildBeepWav() {
    const sampleRate = 44100;
    const frequency = 880.0;
    const beepMs = 250;
    const gapMs = 150;
    const beeps = 3;
    const totalMs = (beepMs + gapMs) * beeps;
    const sampleCount = sampleRate * totalMs ~/ 1000;
    const dataSize = sampleCount * 2;

    final bytes = BytesBuilder();
    void w32(int v) => bytes.add([
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ]);
    void w16(int v) => bytes.add([v & 0xFF, (v >> 8) & 0xFF]);

    // Cabecera RIFF/WAVE (PCM, mono, 16 bits).
    bytes.add('RIFF'.codeUnits);
    w32(36 + dataSize);
    bytes.add('WAVE'.codeUnits);
    bytes.add('fmt '.codeUnits);
    w32(16); // tamaño del bloque fmt
    w16(1); // PCM
    w16(1); // mono
    w32(sampleRate);
    w32(sampleRate * 2); // bytes por segundo
    w16(2); // bytes por muestra (bloque)
    w16(16); // bits por muestra
    bytes.add('data'.codeUnits);
    w32(dataSize);

    for (var i = 0; i < sampleCount; i++) {
      final ms = i * 1000 ~/ sampleRate;
      final posInCycle = ms % (beepMs + gapMs);
      var sample = 0;
      if (posInCycle < beepMs) {
        // Envolvente del 10% a cada lado para evitar clics.
        final pos = posInCycle / beepMs;
        final envelope = pos < 0.1
            ? pos / 0.1
            : (pos > 0.9 ? (1 - pos) / 0.1 : 1.0);
        final t = i / sampleRate;
        sample =
            (math.sin(2 * math.pi * frequency * t) * 0.6 * envelope * 32767)
                .round();
      }
      w16(sample & 0xFFFF);
    }
    return bytes.toBytes();
  }
}
