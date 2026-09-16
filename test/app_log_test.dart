import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/services/app_log.dart';
import 'package:smart_display/services/app_storage.dart';

/// Pruebas de [AppLog]: escritura en disco, niveles, rotación, lectura y
/// enganche de los manejadores globales de error. La carpeta de configuración
/// se aísla en un directorio temporal propio.
void main() {
  Directory? tempDir;
  File? logFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('sd_applog_test_');
    AppStorage.overrideDirectory = tempDir;
    logFile = AppStorage.configFile('app.log');
  });

  tearDownAll(() {
    AppStorage.overrideDirectory = null;
    try {
      tempDir?.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    AppLog.resetForTest();
    AppLog.clear();
  });

  test('logFilePath apunta a la carpeta de configuración', () {
    expect(AppLog.logFilePath(), logFile!.path);
  });

  test('info escribe una línea con fecha y nivel', () {
    AppLog.info('hola mundo');

    final content = logFile!.readAsStringSync();
    expect(content, contains('[INFO] hola mundo'));
    expect(
      RegExp(r'^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')
          .hasMatch(content.split('\n').first),
      isTrue,
      reason: 'la primera línea debe empezar por fecha ISO',
    );
  });

  test('warn y error usan su propio nivel', () {
    AppLog.warn('cuidado');
    AppLog.error('fallo', Exception('boom'), StackTrace.current);

    final content = logFile!.readAsStringSync();
    expect(content, contains('[WARN] cuidado'));
    expect(content, contains('[ERROR] fallo :: Exception: boom'));
    expect(content, contains('app_log_test.dart'));
  });

  test('readTail devuelve sólo las últimas líneas', () {
    for (var i = 0; i < 50; i++) {
      AppLog.info('linea $i');
    }

    final tail = AppLog.readTail(maxLines: 10);
    expect(tail, hasLength(10));
    expect(tail.last, contains('linea 49'));
  });

  test('readTail sin fichero devuelve una lista vacía', () {
    expect(AppLog.readTail(), isEmpty);
  });

  test('rota el fichero al superar el tamaño máximo', () {
    logFile!.writeAsStringSync('x' * (AppLog.maxBytes + 1));

    AppLog.info('tras rotar');

    final rotated = File('${logFile!.path}.1');
    expect(rotated.existsSync(), isTrue, reason: 'debe existir app.log.1');
    expect(logFile!.lengthSync(), lessThan(AppLog.maxBytes));
    expect(logFile!.readAsStringSync(), contains('tras rotar'));
  });

  test('clear borra el log y sus rotaciones', () {
    logFile!.writeAsStringSync('x' * (AppLog.maxBytes + 1));
    AppLog.info('provoca rotacion');

    AppLog.clear();

    expect(logFile!.existsSync(), isFalse);
    expect(File('${logFile!.path}.1').existsSync(), isFalse);
    expect(File('${logFile!.path}.2').existsSync(), isFalse);
  });

  test('con enabled=false no escribe nada', () {
    AppLog.enabled = false;
    AppLog.info('no deberia aparecer');
    expect(logFile!.existsSync(), isFalse);
  });

  test('install engancha FlutterError.onError y registra el fallo', () {
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    });

    // Se anula el manejador previo para no ensuciar la salida del test.
    FlutterError.onError = null;
    AppLog.install();

    expect(FlutterError.onError, isNotNull);
    expect(PlatformDispatcher.instance.onError, isNotNull);

    FlutterError.onError!(FlutterErrorDetails(exception: Exception('caida')));

    final content = logFile!.readAsStringSync();
    expect(content, contains('FlutterError'));
    expect(content, contains('caida'));
  });

  test('install es idempotente', () {
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    });

    FlutterError.onError = null;
    AppLog.install();
    final first = FlutterError.onError;
    AppLog.install();
    expect(identical(FlutterError.onError, first), isTrue);
  });
}
