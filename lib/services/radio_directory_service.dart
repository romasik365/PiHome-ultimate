import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/radio_station.dart';
import 'app_storage.dart';

/// Directorio público de emisoras de radio (`radio-browser.info`) con
/// **caché en disco**. No requiere clave de API.
class RadioDirectoryService {
  /// Lista de países (con número de emisoras).
  final DirectoryCountryNotifier countries = DirectoryCountryNotifier();

  /// Emisoras verificadas de un país (cacheadas en memoria).
  final Map<String, List<Station>> _cacheByCountry = {};

  /// Carga la lista de países (usa caché si existe y sigue vigente).
  Future<List<RadioCountry>> loadCountries() async {
    final cached = await RadioCache.read<List<dynamic>>('countries.json');
    if (cached != null) {
      final list = cached
          .map((e) => RadioCountry.fromJson(e as Map<String, dynamic>))
          .toList();
      countries.value = list;
      _refreshCountries(list);
      return list;
    }
    return _refreshCountries([]);
  }

  /// Carga las emisoras verdaderas (`lastcheckok == 1`) de un país.
  Future<List<Station>> loadStations(String countryCode) async {
    final key = countryCode.toUpperCase();
    if (_cacheByCountry.containsKey(key)) return _cacheByCountry[key]!;

    final cached = await RadioCache.read<List<dynamic>>('stations_$key.json');
    if (cached != null) {
      final list = cached
          .map((e) => Station.fromJson(e as Map<String, dynamic>))
          .where((s) => s.url.isNotEmpty)
          .toList();
      _cacheByCountry[key] = list;
      _refreshStations(key);
      return list;
    }
    final list = await _refreshStations(key);
    return list;
  }

  static const _baseUrl = 'https://de1.api.radio-browser.info/json';

  /// Revalidación silenciosa de la lista de países.
  Future<List<RadioCountry>> _refreshCountries(
    List<RadioCountry> current,
  ) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/countries'), headers: _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          final list =
              data
                  .map((e) => RadioCountry.fromJson(e as Map<String, dynamic>))
                  .where((c) => c.stationCount > 0)
                  .toList()
                ..sort((a, b) => b.stationCount.compareTo(a.stationCount));
          await RadioCache.write(
            'countries.json',
            list.map((c) => c.toMap()).toList(),
          );
          countries.value = list;
          return list;
        }
      }
    } catch (_) {}
    return current;
  }

  /// Revalidación silenciosa de emisoras de un país.
  Future<List<Station>> _refreshStations(String key) async {
    try {
      // CORREGIDO: el endpoint correcto es /stations/search con countrycode
      // como parámetro (la ruta /stations/bycountrycode?countrycode=... no
      // existe y devolvía 0 emisoras). hidebroken=true filtra las caídas.
      final res = await http
          .get(
            Uri.parse(
              '$_baseUrl/stations/search'
              '?countrycode=$key&order=clickcount&reverse=true'
              '&limit=200&hidebroken=true',
            ),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          final list = data
              .map((e) => Station.fromJson(e as Map<String, dynamic>))
              .where((s) => s.lastCheckOk && s.url.isNotEmpty)
              .toList();
          // CORREGIDO: solo se cachea si la lista NO está vacía, para que un
          // fallo puntual de red no deje el directorio a 0 durante 24 h.
          if (list.isNotEmpty) {
            await RadioCache.write(
              'stations_$key.json',
              list.map((s) => s.toMap()).toList(),
            );
            _cacheByCountry[key] = list;
            return list;
          }
        }
      }
      return _cacheByCountry[key] ?? [];
    } catch (_) {
      return _cacheByCountry[key] ?? [];
    }
  }

  static Map<String, String> _headers() => {
    'User-Agent': 'PiHomeSmartDisplay/1.0',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  /// Normaliza texto para búsqueda tolerante a acentos y mayúsculas.
  /// "España" y "Espana" producen el mismo resultado.
  static String normalizeSearch(String s) {
    const accented = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
    const plain = 'aaaaaeeeeiiiioooouuuuncAAAAEEEEIIIIOOOOUUUUNC';
    final sb = StringBuffer();
    for (final ch in s.toLowerCase().runes) {
      final c = String.fromCharCode(ch);
      final idx = accented.indexOf(c);
      sb.write(idx >= 0 ? plain[idx] : c);
    }
    return sb.toString();
  }
}

/// Helpers de caché en disco reutilizables por [RadioDirectoryService].
/// Se separan en una clase estática para no inflar de tamaño el servicio.
class RadioCache {
  static const cacheTtl = Duration(hours: 24);

  static Future<T?> read<T>(String name) async {
    try {
      final file = AppStorage.configFile(name);
      if (file == null || !await file.exists()) return null;
      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified) > cacheTtl) return null;
      final raw = await file.readAsString();
      return jsonDecode(raw) as T?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String name, dynamic data) async {
    try {
      final file = AppStorage.configFile(name);
      if (file == null) return;
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }
}

/// Un país del directorio de radio.
class RadioCountry {
  final String name;
  final String countryCode;
  final int stationCount;

  RadioCountry({
    required this.name,
    required this.countryCode,
    required this.stationCount,
  });

  factory RadioCountry.fromJson(Map<String, dynamic> j) {
    final n = j['name'] as String? ?? '';
    return RadioCountry(
      name: n.trim().isEmpty ? 'Desconocido' : n,
      countryCode: (j['countrycode'] as String? ?? '').toUpperCase().trim(),
      stationCount: (j['stationcount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'cc': countryCode,
    'sc': stationCount,
  };

  @override
  String toString() => name;
}

/// Notificador simple para la lista de países (sin `provider`).
class DirectoryCountryNotifier extends ValueNotifier<List<RadioCountry>> {
  DirectoryCountryNotifier() : super([]);
}
