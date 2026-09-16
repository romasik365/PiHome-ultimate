import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smart_display/services/weather_service.dart';

/// Respuesta de ejemplo con la forma real de la API de Open-Meteo.
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

void main() {
  group('parseWeatherResponse', () {
    test('parsea el clima actual y la previsión de 3 días (C, km/h)', () {
      final w = WeatherService.parseWeatherResponse(sampleResponse());

      expect(w.temp, '21°C');
      expect(w.icon, '⛅');
      expect(w.description, 'Parcialmente nublado');
      expect(w.humidity, '55%');
      expect(w.wind, '12 km/h');

      expect(w.forecast, hasLength(3));
      expect(w.forecast[0].day, 'Hoy');
      expect(w.forecast[0].max, 25);
      expect(w.forecast[0].min, 12);
      expect(w.forecast[1].day, 'Mañana');
      expect(w.forecast[1].icon, '🌧️'); // código 61 = lluvia
      expect(w.forecast[2].day, 'Pasado');
      expect(w.forecast[2].icon, '☀️'); // código 0 = despejado
    });

    test('sufijo de Fahrenheit cuando temperatureUnit es F', () {
      final w = WeatherService.parseWeatherResponse(
        sampleResponse(),
        temperatureUnit: 'F',
      );
      expect(w.temp, '21°F');
    });

    test('viento en m/s conserva un decimal; en mph se redondea', () {
      final ms = WeatherService.parseWeatherResponse(
        sampleResponse(),
        windUnit: 'ms',
      );
      expect(ms.wind, '12.3 m/s');

      final mph = WeatherService.parseWeatherResponse(
        sampleResponse(),
        windUnit: 'mph',
      );
      expect(mph.wind, '12 mph');
    });

    test('códigos de clima extremos mapean a tormenta y nieve', () {
      Map<String, dynamic> withCode(int code) => {
        'current': {
          'temperature_2m': 0.0,
          'relative_humidity_2m': 90,
          'weather_code': code,
          'wind_speed_10m': 5.0,
        },
        'daily': {
          'weather_code': [code, code, code],
          'temperature_2m_max': [1.0, 1.0, 1.0],
          'temperature_2m_min': [0.0, 0.0, 0.0],
        },
      };
      expect(WeatherService.parseWeatherResponse(withCode(96)).icon, '⛈️');
      expect(
        WeatherService.parseWeatherResponse(withCode(96)).description,
        'Tormenta',
      );
      expect(WeatherService.parseWeatherResponse(withCode(73)).icon, '❄️');
      expect(WeatherService.parseWeatherResponse(withCode(45)).icon, '🌫️');
      expect(
        WeatherService.parseWeatherResponse(withCode(80)).description,
        'Chubascos',
      );
    });
  });

  group('fetchWeather (con cliente inyectado)', () {
    tearDown(() => WeatherService.debugClient = null);

    test('descarga y parsea con el cliente de pruebas', () async {
      Uri? requested;
      WeatherService.debugClient = MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode(sampleResponse()), 200);
      });

      final w = await WeatherService.fetchWeather(
        latitude: 41.785,
        longitude: 1.289,
        timezone: 'Europe/Madrid',
        temperatureUnit: 'F',
        windUnit: 'mph',
      );

      expect(w.temp, '21°F');
      expect(w.wind, '12 mph');
      expect(requested.toString(), contains('latitude=41.785'));
      expect(requested.toString(), contains('temperature_unit=fahrenheit'));
      expect(requested.toString(), contains('wind_speed_unit=mph'));
      expect(
        requested.toString(),
        contains('timezone=${Uri.encodeComponent('Europe/Madrid')}'),
      );
    });

    test('lanza excepción si el servidor responde con error', () async {
      WeatherService.debugClient = MockClient(
        (_) async => http.Response('ko', 500),
      );
      expect(
        () => WeatherService.fetchWeather(latitude: 0, longitude: 0),
        throwsException,
      );
    });
  });
}
