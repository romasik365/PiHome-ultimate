import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/models/radio_station.dart';
import 'package:smart_display/services/geocoding_service.dart';
import 'package:smart_display/services/radio_directory_service.dart';

void main() {
  group('Station', () {
    final json = <String, dynamic>{
      'name': '  RAC1 Notícies ',
      'url': 'https://example.com/stream.mp3',
      'countrycode': 'es',
      'tags': 'news,talk',
      'lastcheckok': 1,
      'codec': 'MP3',
      'bitrate': 128,
    };

    test('fromJson recorta, normaliza el país y parsea metadatos', () {
      final s = Station.fromJson(json);
      expect(s.name, 'RAC1 Notícies'); // recortado
      expect(s.url, 'https://example.com/stream.mp3');
      expect(s.countryCode, 'ES'); // mayúsculas
      expect(s.tags, 'news,talk');
      expect(s.lastCheckOk, isTrue);
      expect(s.codec, 'MP3');
      expect(s.bitrate, 128);
    });

    test('fromJson tolera campos ausentes', () {
      final s = Station.fromJson(const {});
      expect(s.name, '');
      expect(s.url, '');
      expect(s.countryCode, '');
      expect(s.lastCheckOk, isFalse);
      expect(s.bitrate, 0);
    });

    test('lastcheckok distinto de 1 se considera caída', () {
      final s = Station.fromJson(const {'lastcheckok': 0});
      expect(s.lastCheckOk, isFalse);
    });

    test('displayName añade el país sólo si se conoce', () {
      expect(Station.fromJson(json).displayName, 'RAC1 Notícies · ES');
      expect(const Station(name: 'Sola', url: 'u').displayName, 'Sola');
    });

    test('toMap/fromMap hacen un viaje de ida y vuelta', () {
      final original = Station.fromJson(json);
      final restored = Station.fromMap(original.toMap());
      expect(restored.name, original.name);
      expect(restored.url, original.url);
      expect(restored.countryCode, original.countryCode);
      expect(restored.tags, original.tags);
      expect(restored.lastCheckOk, original.lastCheckOk);
      expect(restored.codec, original.codec);
      expect(restored.bitrate, original.bitrate);
    });

    test('fromMap tolera tipos corruptos', () {
      final s = Station.fromMap(const {
        'n': 42,
        'u': null,
        'c': 7,
        't': true,
        'ok': 'sí',
        'cd': 3.5,
        'br': 'alto',
      });
      expect(s.name, '');
      expect(s.url, '');
      expect(s.countryCode, '');
      expect(s.lastCheckOk, isFalse);
      expect(s.codec, '');
      expect(s.bitrate, 0);
    });
  });

  group('RadioCountry', () {
    test('fromJson normaliza y ordena campos', () {
      final c = RadioCountry.fromJson(const {
        'name': 'Spain',
        'countrycode': 'es',
        'stationcount': 1234,
      });
      expect(c.name, 'Spain');
      expect(c.countryCode, 'ES');
      expect(c.stationCount, 1234);
    });

    test('nombre vacío se sustituye por Desconocido', () {
      final c = RadioCountry.fromJson(const {'name': '   '});
      expect(c.name, 'Desconocido');
      expect(c.stationCount, 0);
    });

    test('toMap conserva los datos', () {
      final c = RadioCountry.fromJson(const {
        'name': 'Spain',
        'countrycode': 'es',
        'stationcount': 7,
      });
      final map = c.toMap();
      expect(map['name'], 'Spain');
      expect(map['cc'], 'ES');
      expect(map['sc'], 7);
    });
  });

  group('Place', () {
    test('fromJson compone la etiqueta nombre, región, país', () {
      final p = Place.fromJson(const {
        'name': 'Guissona',
        'admin1': 'Cataluña',
        'country': 'España',
        'latitude': 41.785,
        'longitude': 1.289,
        'timezone': 'Europe/Madrid',
        'population': 7000,
      });
      expect(p.label, 'Guissona, Cataluña, España');
      expect(p.latitude, 41.785);
      expect(p.longitude, 1.289);
      expect(p.timezone, 'Europe/Madrid');
      expect(p.population, 7000);
    });

    test('fromJson omite partes vacías de la etiqueta', () {
      final p = Place.fromJson(const {
        'name': 'Nowhere',
        'admin1': ' ',
        'latitude': 1.0,
        'longitude': 2.0,
      });
      expect(p.label, 'Nowhere');
      expect(p.country, isNull);
    });

    test('toMap/fromMap hacen un viaje de ida y vuelta', () {
      final p = Place.fromJson(const {
        'name': 'Lleida',
        'admin1': 'Cataluña',
        'country': 'España',
        'latitude': 41.6176,
        'longitude': 0.62,
        'timezone': 'Europe/Madrid',
        'population': 140000,
      });
      final restored = Place.fromMap(p.toMap());
      expect(restored.label, p.label);
      expect(restored.name, p.name);
      expect(restored.country, p.country);
      expect(restored.admin1, p.admin1);
      expect(restored.latitude, p.latitude);
      expect(restored.longitude, p.longitude);
      expect(restored.timezone, p.timezone);
      expect(restored.population, p.population);
    });

    test('toString devuelve la etiqueta', () {
      final p = Place.fromJson(const {
        'name': 'X',
        'latitude': 0.0,
        'longitude': 0.0,
      });
      expect(p.toString(), 'X');
    });
  });
}
