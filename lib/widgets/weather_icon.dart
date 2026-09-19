import 'package:flutter/material.dart';

/// Icono del clima que **no depende de la fuente del sistema**.
///
/// La app se diseño con emojis de tiempo (sol, sol con nube, lluvia...). El
/// motor los busca en las fuentes del sistema operativo, pero la Raspberry Pi
/// (Debian minimo) no tiene ninguna que los incluya: no hay DejaVu ni Noto
/// Color Emoji, asi que se dibujaba el cuadradito "tofu" (□) que aparecia en la
/// pantalla del kiosco.
///
/// [WeatherService] devuelve ahora una **clave estable y ASCII** ('sunny',
/// 'rain'...) y este widget la traduce a un [Icon] de MaterialIcons, que viaja
/// incluido en el bundle y por tanto se ve igual en Windows, Linux y flutter-pi
/// sin depender de nada instalado en el sistema.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon(this.kind, {super.key, this.size = 20, this.color});

  /// Clave devuelta por `WeatherService` ('sunny', 'partly', 'fog', 'rain',
  /// 'snow', 'showers', 'storm'). Tambien acepta los emojis antiguos (escritos
  /// como escapes Unicode para que el fichero siga siendo ASCII puro) de modo
  /// que los ajustes o datos ya guardados con la version anterior se siguen
  /// viendo con el icono correcto.
  final String kind;

  final double size;

  /// Color explicito; si es null se usa el propio de cada tipo de tiempo.
  final Color? color;

  /// Normaliza la clave: quita el selector de variacion (U+FE0F) y convierte
  /// los emojis heredados a su clave ASCII.
  static String normalize(String kind) {
    final plain = kind.replaceAll('\uFE0F', '').trim();
    return switch (plain) {
      '\u2600' => 'sunny', // sol
      '\u26C5' => 'partly', // sol con nube
      '\u{1F32B}' => 'fog', // niebla
      '\u{1F327}' => 'rain', // lluvia
      '\u2744' => 'snow', // copo de nieve
      '\u{1F326}' => 'showers', // chubascos
      '\u26C8' => 'storm', // tormenta
      _ => plain,
    };
  }

  /// Icono de MaterialIcons para cada tipo de tiempo.
  static IconData dataFor(String kind) => switch (normalize(kind)) {
    'sunny' => Icons.wb_sunny,
    'partly' => Icons.wb_cloudy,
    'fog' => Icons.foggy,
    'rain' => Icons.grain,
    'showers' => Icons.water_drop,
    'snow' => Icons.ac_unit,
    'storm' => Icons.thunderstorm,
    _ => Icons.cloud,
  };

  /// Color de cada tipo de tiempo (para que se distingan sin necesidad de texto).
  static Color colorFor(String kind) => switch (normalize(kind)) {
    'sunny' => const Color(0xFFFFC107),
    'partly' => const Color(0xFFB0BEC5),
    'fog' => const Color(0xFF90A4AE),
    'rain' => const Color(0xFF64B5F6),
    'showers' => const Color(0xFF4FC3F7),
    'snow' => const Color(0xFF81D4FA),
    'storm' => const Color(0xFF9575CD),
    _ => const Color(0xFFB0BEC5),
  };

  /// Claves que representan tiempo conocido.
  static const Set<String> keys = {
    'sunny',
    'partly',
    'fog',
    'rain',
    'showers',
    'snow',
    'storm',
  };

  /// ¿La clave corresponde a un tipo de tiempo conocido?
  static bool isKnown(String kind) => keys.contains(normalize(kind));

  @override
  Widget build(BuildContext context) {
    return Icon(
      dataFor(kind),
      size: size,
      color: color ?? colorFor(kind),
      semanticLabel: kind,
    );
  }
}
