import 'dart:convert';

import 'package:http/http.dart' as http;

/// Servicio de búsqueda de localidades a través de la API pública de
/// geocodificación de Open-Meteo (sin clave de API).
class GeocodingService {
  static const _baseUrl = 'https://geocoding-api.open-meteo.com/v1/search';

  /// Busca localidades cuyo nombre contenga [query].
  static Future<List<Place>> search({
    required String query,
    int limit = 20,
    String language = 'es',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final uri = Uri.parse(
      '$_baseUrl?name=${Uri.encodeQueryComponent(trimmed)}&count=$limit&language=$language&format=json',
    );
    try {
      final res = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'PiHomeSmartDisplay/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['results'] is List) {
          return (data['results'] as List)
              .map((e) => Place.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => (b.population ?? 0).compareTo(a.population ?? 0));
        }
      }
    } catch (_) {}
    return [];
  }
}

/// Un resultado de búsqueda de localidad.
final class Place {
  final String label; // "Guisona, Cataluña, España"
  final String name; // nombre principal
  final String? country;
  final String? admin1;
  final double latitude;
  final double longitude;
  final String? timezone;
  final int? population;

  const Place({
    required this.label,
    required this.name,
    this.country,
    this.admin1,
    required this.latitude,
    required this.longitude,
    this.timezone,
    this.population,
  });

  factory Place.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] as String? ?? '').trim();
    final country = j['country'] as String?;
    final admin1 = j['admin1'] as String?;
    final parts = <String>[name];
    if (admin1 != null && admin1.trim().isNotEmpty) parts.add(admin1.trim());
    if (country != null && country.trim().isNotEmpty) {
      parts.add(country.trim());
    }
    return Place(
      label: parts.join(', '),
      name: name,
      country: country,
      admin1: admin1,
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
      timezone: j['timezone'] as String?,
      population: j['population'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
    'n': name,
    'c': country,
    'a1': admin1,
    'lat': latitude,
    'lon': longitude,
    'tz': timezone,
    'pop': population,
    'lbl': label,
  };

  factory Place.fromMap(Map<String, dynamic> m) {
    final name = (m['n'] as String? ?? '');
    final country = m['c'] as String?;
    final admin1 = m['a1'] as String?;
    return Place(
      label: (m['lbl'] as String? ?? ''),
      name: name,
      country: country,
      admin1: admin1,
      latitude: (m['lat'] as num? ?? 0.0).toDouble(),
      longitude: (m['lon'] as num? ?? 0.0).toDouble(),
      timezone: m['tz'] as String?,
      population: m['pop'] as int?,
    );
  }

  @override
  String toString() => label;
}
