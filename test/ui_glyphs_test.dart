import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/models/app_settings.dart';
import 'package:smart_display/services/weather_service.dart';
import 'package:smart_display/widgets/clock_text.dart';
import 'package:smart_display/widgets/weather_icon.dart';

/// Emojis escritos por puntos de código para que este fichero sea ASCII puro.
final _sunny = String.fromCharCodes([0x2600, 0xFE0F]); // sol + variación
final _partly = String.fromCharCodes([0x26C5]); // sol con nube
final _fog = String.fromCharCodes([0x1F32B, 0xFE0F]); // niebla
final _rain = String.fromCharCodes([0x1F327, 0xFE0F]); // lluvia
final _pin = String.fromCharCodes([0x1F4CD]); // chincheta de ubicación

void main() {
  group('WeatherIcon', () {
    test('normalize convierte los emojis heredados a claves ASCII', () {
      expect(WeatherIcon.normalize(_sunny), 'sunny');
      expect(WeatherIcon.normalize(_partly), 'partly');
      expect(WeatherIcon.normalize(_fog), 'fog');
      expect(WeatherIcon.normalize(_rain), 'rain');
      expect(WeatherIcon.normalize('sunny'), 'sunny');
      expect(WeatherIcon.normalize(' Desconocido '), 'Desconocido');
    });

    test('dataFor devuelve iconos de MaterialIcons (fuente del bundle)', () {
      expect(WeatherIcon.dataFor('sunny'), Icons.wb_sunny);
      expect(WeatherIcon.dataFor('partly'), Icons.wb_cloudy);
      expect(WeatherIcon.dataFor('fog'), Icons.foggy);
      expect(WeatherIcon.dataFor('rain'), Icons.grain);
      expect(WeatherIcon.dataFor('showers'), Icons.water_drop);
      expect(WeatherIcon.dataFor('snow'), Icons.ac_unit);
      expect(WeatherIcon.dataFor('storm'), Icons.thunderstorm);
      expect(WeatherIcon.dataFor('noseque'), Icons.cloud);
      // Los emojis heredados también acaban en un icono real.
      expect(WeatherIcon.dataFor(_rain), Icons.grain);
    });

    test('isKnown reconoce las claves del servicio', () {
      expect(WeatherIcon.isKnown('storm'), isTrue);
      expect(WeatherIcon.isKnown('noseque'), isFalse);
    });
  });

  group('WeatherService iconos', () {
    test('devuelve claves ASCII, no emojis', () {
      final data = WeatherService.parseWeatherResponse(sampleResponse());
      expect(data.icon, 'partly');
      expect(WeatherIcon.isKnown(data.icon), isTrue);
    });
  });

  group('ClockText', () {
    final now = DateTime(2026, 9, 18, 23, 46, 5);

    test('formatTime respeta 24 h y los segundos', () {
      expect(
        ClockText.formatTime(now, use24Hour: true, showSeconds: true),
        '23:46:05',
      );
      expect(
        ClockText.formatTime(now, use24Hour: true, showSeconds: false),
        '23:46',
      );
    });

    test('formatTime usa 12 h con AM/PM y la medianoche es 12', () {
      expect(
        ClockText.formatTime(now, use24Hour: false, showSeconds: false),
        '11:46 PM',
      );
      expect(
        ClockText.formatTime(
          DateTime(2026, 9, 18, 0, 5),
          use24Hour: false,
          showSeconds: false,
        ),
        '12:05 AM',
      );
    });

    test('formatDate formatea la fecha en castellano', () {
      expect(ClockText.formatDate(now), 'Viernes, 18 de Septiembre');
      expect(ClockText.formatDate(DateTime(2026, 1, 1)), 'Jueves, 1 de Enero');
    });
  });

  group('AppSettings.sanitizeLabel', () {
    test('quita el emoji de ubicación que traían los ajustes antiguos', () {
      expect(AppSettings.sanitizeLabel('$_pin Lleida'), 'Lleida');
      expect(AppSettings.sanitizeLabel('$_pin Lleida'), isNot(contains(_pin)));
    });

    test('conserva acentos, grado, punto medio y otros alfabetos', () {
      expect(
        AppSettings.sanitizeLabel('Córdoba, 18°C · Sur'),
        'Córdoba, 18°C · Sur',
      );
      // Cirílico: nombre de lugar en otro alfabeto no debe perderse.
      final kiev = String.fromCharCodes([0x41A, 0x438, 0x457, 0x432]);
      expect(AppSettings.sanitizeLabel(kiev), kiev);
    });

    test('normaliza espacios sobrantes', () {
      expect(AppSettings.sanitizeLabel('  A   B  '), 'A B');
    });

    test('fromMap sanea la etiqueta guardada con emoji', () {
      final map = AppSettings.defaults().toMap();
      map['loc'] = '$_pin Lleida';
      expect(AppSettings.fromMap(map).locationLabel, 'Lleida');
    });
  });
}

/// Respuesta de Open-Meteo mínima para el parser (código 2 = parcialmente nublado).
Map<String, dynamic> sampleResponse() => {
  'current': {
    'temperature_2m': 21.4,
    'relative_humidity_2m': 55,
    'weather_code': 2,
    'wind_speed_10m': 12.3,
  },
  'daily': {
    'weather_code': [2, 61, 0],
    'temperature_2m_max': [25.2, 20.6, 23.0],
    'temperature_2m_min': [12.4, 10.6, 11.0],
  },
};
