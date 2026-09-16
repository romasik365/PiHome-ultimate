/// Emisora de radio.
///
/// Se usa tanto para las emisoras de fábrica como para las que se añaden desde
/// el directorio online ([RadioDirectoryService]), que además guarda el país,
/// los géneros y metadatos como el códec y el bitrate.
class Station {
  final String name;
  final String url;

  /// Código ISO de 2 letras del país (por ejemplo "ES").
  final String countryCode;

  /// Géneros separados por comas, tal y como los devuelve el directorio.
  final String tags;

  /// 1 si la emisora responde en la última comprobación, 0 si no.
  final bool lastCheckOk;

  /// Códec de audio (mp3, aac, etc.).
  final String codec;

  /// Bitrate en kbps.
  final int bitrate;

  const Station({
    required this.name,
    required this.url,
    this.countryCode = '',
    this.tags = '',
    this.lastCheckOk = true,
    this.codec = '',
    this.bitrate = 0,
  });

  /// Etiqueta corta para la interfaz (nombre + país si se conoce).
  String get displayName => countryCode.isEmpty ? name : '$name · $countryCode';

  /// Fábrica desde el JSON del directorio `radio-browser.info`.
  factory Station.fromJson(Map<String, dynamic> j) => Station(
    name: (j['name'] as String? ?? '').trim(),
    url: (j['url'] as String? ?? '').trim(),
    countryCode: (j['countrycode'] as String? ?? '').toUpperCase().trim(),
    tags: (j['tags'] as String? ?? '').trim(),
    lastCheckOk: (j['lastcheckok'] as int? ?? 0) == 1,
    codec: (j['codec'] as String? ?? '').trim(),
    bitrate: (j['bitrate'] as int?) ?? 0,
  );

  Map<String, Object> toMap() => {
    'n': name,
    'u': url,
    'c': countryCode,
    't': tags,
    'ok': lastCheckOk ? 1 : 0,
    'cd': codec,
    'br': bitrate,
  };

  factory Station.fromMap(Map<String, dynamic> map) => Station(
    name: map['n'] is String ? map['n'] as String : '',
    url: map['u'] is String ? map['u'] as String : '',
    countryCode: map['c'] is String ? (map['c'] as String).toUpperCase() : '',
    tags: map['t'] is String ? map['t'] as String : '',
    lastCheckOk: map['ok'] == 1,
    codec: map['cd'] is String ? map['cd'] as String : '',
    bitrate: map['br'] is num ? (map['br'] as num).toInt() : 0,
  );

  @override
  String toString() => 'Station($name, $url)';
}
