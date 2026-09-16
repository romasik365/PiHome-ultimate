import 'dart:convert';

import 'package:http/http.dart' as http;

class ForecastDay {
  final String day;
  final int max;
  final int min;
  final String icon;

  ForecastDay({
    required this.day,
    required this.max,
    required this.min,
    required this.icon,
  });
}

class WeatherData {
  final String temp;
  final String icon;
  final String description;
  final String humidity;
  final String wind;
  final List<ForecastDay> forecast;

  WeatherData({
    required this.temp,
    required this.icon,
    required this.description,
    required this.humidity,
    required this.wind,
    required this.forecast,
  });
}

class WeatherService {
  /// Cliente HTTP inyectable para pruebas (si es null se usa el global).
  static http.Client? debugClient;

  /// Clima actual y previsión de 3 días para cualquier punto del planeta.
  ///
  /// [temperatureUnit]: 'C' (defecto) o 'F'.
  /// [windUnit]: 'kmh' (defecto), 'mph' o 'ms'.
  static Future<WeatherData> fetchWeather({
    required double latitude,
    required double longitude,
    String timezone = 'Europe/Madrid',
    String temperatureUnit = 'C',
    String windUnit = 'kmh',
  }) async {
    final tempUnit = temperatureUnit.toUpperCase() == 'F'
        ? 'fahrenheit'
        : 'celsius';
    final windParam = _windParam(windUnit);
    final url = Uri.parse(
      "https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude"
      "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
      "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      "&temperature_unit=$tempUnit&wind_speed_unit=$windParam"
      "&timezone=${Uri.encodeComponent(timezone)}",
    );

    const headers = {'User-Agent': 'PiHomeSmartDisplay/1.0'};
    final client = debugClient;
    final response =
        await (client != null
                ? client.get(url, headers: headers)
                : http.get(url, headers: headers))
            .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return parseWeatherResponse(
        jsonDecode(response.body) as Map<String, dynamic>,
        temperatureUnit: temperatureUnit,
        windUnit: windUnit,
      );
    } else {
      throw Exception("Error al cargar clima (${response.statusCode})");
    }
  }

  /// Convierte la respuesta JSON de Open-Meteo en [WeatherData].
  ///
  /// Función pura (sin red) para poder probarla con datos de ejemplo.
  static WeatherData parseWeatherResponse(
    Map<String, dynamic> data, {
    String temperatureUnit = 'C',
    String windUnit = 'kmh',
  }) {
    final windParam = _windParam(windUnit);
    final current = data['current'] as Map<String, dynamic>;
    final temp = (current['temperature_2m'] as num).round();
    final code = (current['weather_code'] as num).toInt();
    final daily = data['daily'] as Map<String, dynamic>;

    final List<ForecastDay> forecastList = [];
    const daysNames = ["Hoy", "Mañana", "Pasado"];
    final maxList = (daily['temperature_2m_max'] as List?) ?? [];
    final minList = (daily['temperature_2m_min'] as List?) ?? [];
    final codeList = (daily['weather_code'] as List?) ?? [];
    final daysCount = [
      3,
      maxList.length,
      minList.length,
      codeList.length,
    ].reduce((a, b) => a < b ? a : b);

    for (int i = 0; i < daysCount; i++) {
      forecastList.add(
        ForecastDay(
          day: daysNames[i],
          max: (maxList[i] as num).round(),
          min: (minList[i] as num).round(),
          icon: _getWeatherIcon((codeList[i] as num).toInt()),
        ),
      );
    }

    final tempSuffix = temperatureUnit.toUpperCase() == 'F' ? '°F' : '°C';
    final windSuffix = switch (windParam) {
      'mph' => 'mph',
      'ms' => 'm/s',
      _ => 'km/h',
    };
    final windValue = windParam == 'ms'
        ? (current['wind_speed_10m'] as num).toStringAsFixed(1)
        : (current['wind_speed_10m'] as num).round().toString();

    return WeatherData(
      temp: "$temp$tempSuffix",
      icon: _getWeatherIcon(code),
      description: _getWeatherDescription(code),
      humidity: "${current['relative_humidity_2m']}%",
      wind: "$windValue $windSuffix",
      forecast: forecastList,
    );
  }

  /// Normaliza la unidad de viento a los valores que acepta Open-Meteo.
  static String _windParam(String windUnit) => switch (windUnit.toLowerCase()) {
    'mph' => 'mph',
    'ms' => 'ms',
    _ => 'kmh',
  };

  /// Compatibilidad: clima de Guissona (Lleida).
  static Future<WeatherData> fetchGuissonaWeather() =>
      fetchWeather(latitude: 41.785, longitude: 1.289);

  static String _getWeatherIcon(int code) {
    if (code == 0) return "☀️";
    if (code <= 3) return "⛅";
    if (code <= 48) return "🌫️";
    if (code <= 67) return "🌧️";
    if (code <= 77) return "❄️";
    if (code <= 82) return "🌦️";
    return "⛈️";
  }

  static String _getWeatherDescription(int code) {
    if (code == 0) return "Despejado";
    if (code <= 3) return "Parcialmente nublado";
    if (code <= 48) return "Niebla";
    if (code <= 67) return "Lluvia";
    if (code <= 77) return "Nieve";
    if (code <= 82) return "Chubascos";
    return "Tormenta";
  }
}
