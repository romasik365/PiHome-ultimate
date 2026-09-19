import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'app_storage.dart';

/// Sonido de alarma local (pitido) usando reproductor nativo en Linux.
///
/// Sintetiza un WAV PCM de 16 bits y lo reproduce con aplay en Linux.
/// En Windows no se reproduce (la alarma visual sigue funcionando).
class BeepService {
  Process? _process;
  bool _playing = false;

  static const _fileName = 'alarm_beep.wav';

  Future<String?> _ensureFile() async {
    final file = AppStorage.configFile(_fileName);
    if (file == null) return null;
    if (!file.existsSync()) {
      await file.writeAsBytes(_buildBeepWav(), flush: true);
    }
    return file.path;
  }

  Future<void> start() async {
    if (_playing) return;
    final path = await _ensureFile();
    if (path == null) {
      _playing = false;
      return;
    }

    if (Platform.isLinux) {
      _playing = true;
      try {
        _process = await Process.start('aplay', ['-q', '-f', 'S16_LE', path]);
        _process!.exitCode.then((_) {
          _playing = false;
          _process = null;
        });
      } catch (_) {
        _playing = false;
      }
    } else {
      // En Windows no hay reproductor nativo, la alarma solo visual
      _playing = false;
    }
  }

  Future<void> stop() async {
    _playing = false;
    if (Platform.isLinux) {
      try {
        _process?.kill();
      } catch (_) {}
      _process = null;
    }
  }

  Future<void> dispose() async {
    _playing = false;
    if (Platform.isLinux) {
      try {
        _process?.kill();
      } catch (_) {}
      _process = null;
    }
  }

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

    bytes.add('RIFF'.codeUnits);
    w32(36 + dataSize);
    bytes.add('WAVE'.codeUnits);
    bytes.add('fmt '.codeUnits);
    w32(16);
    w16(1);
    w16(1);
    w32(sampleRate);
    w32(sampleRate * 2);
    w16(2);
    w16(16);
    bytes.add('data'.codeUnits);
    w32(dataSize);

    for (var i = 0; i < sampleCount; i++) {
      final ms = i * 1000 ~/ sampleRate;
      final posInCycle = ms % (beepMs + gapMs);
      var sample = 0;
      if (posInCycle < beepMs) {
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
