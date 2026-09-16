import 'dart:ui';

/// Ajustes de la pantalla inteligente.
///
/// Son inmutables: para modificar algo se usa [copyWith] y la pantalla
/// principal los vuelve a aplicar y a persistir.
class AppSettings {
  const AppSettings({
    required this.accentColor,
    required this.nightMode,
    required this.showSeconds,
    required this.showDate,
    required this.use24Hour,
    required this.fontFamily,
    required this.clockFontSize,
    required this.dateFontSize,
    required this.cardTextScale,
    required this.cardHeight,
    required this.clockWeight,
    required this.locationLabel,
    required this.weatherLabel,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.weatherRefreshMinutes,
    required this.stationIndex,
    required this.volume,
    required this.alarmEnabled,
    required this.alarmHour,
    required this.alarmMinute,
    required this.sunriseEnabled,
    required this.sunriseMinutesBefore,
    required this.screensaverEnabled,
    required this.screensaverMinutes,
    required this.temperatureUnit,
    required this.windUnit,
    required this.autoplayRadio,
    required this.alarmSound,
    required this.alarmDays,
    required this.sunriseDurationSeconds,
    required this.sunriseColor,
    required this.snoozeMinutes,
    required this.screensaverDoubleTap,
    required this.windowWidth,
    required this.windowHeight,
    required this.languageCode,
    required this.savedLocations,
    required this.favouriteStations,
    this.wifiSsid,
    this.wifiPassword,
    required this.wifiEnabled,
    required this.bluetoothEnabled,
    required this.pairedBluetoothIds,
    required this.showConnectivityIcons,
    required this.bootAnimation,
    required this.bootMinDurationMs,
  });

  /// Color de acento de la interfaz.
  final Color accentColor;

  /// Modo noche (paleta roja tenue).
  final bool nightMode;

  /// Muestra los segundos en el reloj.
  final bool showSeconds;

  /// Muestra la línea de fecha bajo el reloj.
  final bool showDate;

  /// Formato de 24 horas (si es false, 12 h con AM/PM).
  final bool use24Hour;

  /// Familia tipográfica. Cadena vacía = la fuente por defecto de Flutter.
  final String fontFamily;

  /// Tamaño base del reloj.
  final double clockFontSize;

  /// Tamaño de la fecha.
  final double dateFontSize;

  /// Multiplicador del texto de tarjetas y badges.
  final double cardTextScale;

  /// Alto de la fila de tarjetas inferiores.
  final double cardHeight;

  /// Grosor del reloj (100 = muy fino, 900 = muy grueso).
  final int clockWeight;

  /// Texto del badge superior (por ejemplo "📍 Guissona, Lleida").
  final String locationLabel;

  /// Nombre que aparece en el diálogo de pronóstico.
  final String weatherLabel;

  final double latitude;
  final double longitude;
  final String timezone;

  /// Cada cuántos minutos se refresca el clima.
  final int weatherRefreshMinutes;

  /// Emisora de radio inicial.
  final int stationIndex;

  /// Volumen inicial de la radio (0.0 - 1.0).
  final double volume;

  final bool alarmEnabled;
  final int alarmHour;
  final int alarmMinute;

  /// Simulador de amanecer.
  final bool sunriseEnabled;
  final int sunriseMinutesBefore;

  /// Reposo automático tras inactividad.
  final bool screensaverEnabled;
  final int screensaverMinutes;

  /// Nuevas opciones de personalización adicional
  /// -------------------------------------------

  /// Unidad de temperatura: 'C' o 'F'.
  final String temperatureUnit;

  /// Unidad de viento: 'kmh', 'mph' o 'ms'.
  final String windUnit;

  /// Reproduce la radio al arrancar la app.
  final bool autoplayRadio;

  /// Sonido de alarma: 'radio' o 'beep' (también acepta 'buzzer').
  final String alarmSound;

  /// Días de la semana activos para la alarma (lunes=1 … domingo=7).
  final List<int> alarmDays;

  /// Duración del efecto de amanecer en segundos.
  final int sunriseDurationSeconds;

  /// Color de inicio del amanecer.
  final Color sunriseColor;

  /// Minutos de posposición de la alarma (en vez de los fijos 5).
  final int snoozeMinutes;

  /// Requiere doble toque para salir del reposo (evita apagones accidentales).
  final bool screensaverDoubleTap;

  /// Tamaño de ventana: ancho x alto.
  final double windowWidth;
  final double windowHeight;

  /// Idioma de la interfaz.
  final String languageCode;

  /// Localidades guardadas para el selector rápido de clima.
  final List<Map<String, dynamic>> savedLocations;

  /// Emisoras favoritas del Smart Display (máximo 4).
  final List<String> favouriteStations;

  /// Wi-Fi: SSID y contraseña guardados (nullable).
  final String? wifiSsid;
  final String? wifiPassword;
  final bool wifiEnabled;

  /// Bluetooth: habilitado y lista de MACs emparejadas.
  final bool bluetoothEnabled;
  final List<String> pairedBluetoothIds;

  /// Muestra los iconos WiFi/BT en la barra superior.
  /// Modos: true = siempre visibles, false = ocultos.
  final bool showConnectivityIcons;

  /// Muestra la animación de arranque (logotipo latiendo) al abrir la app.
  final bool bootAnimation;

  /// Duración mínima de la boot animation en ms (evita el parpadeo si la
  /// carga es muy rápida). Se respeta aunque las cargas terminen antes.
  final int bootMinDurationMs;

  factory AppSettings.defaults() => AppSettings(
    accentColor: const Color(0xFF6366F1),
    nightMode: false,
    showSeconds: false,
    showDate: true,
    use24Hour: true,
    fontFamily: '',
    clockFontSize: 125,
    dateFontSize: 16,
    cardTextScale: 1.0,
    cardHeight: 116,
    clockWeight: 200,
    locationLabel: '📍 Guissona, Lleida',
    weatherLabel: 'Guissona',
    latitude: 41.785,
    longitude: 1.289,
    timezone: 'Europe/Madrid',
    weatherRefreshMinutes: 20,
    stationIndex: 0,
    volume: 0.8,
    alarmEnabled: true,
    alarmHour: 7,
    alarmMinute: 0,
    sunriseEnabled: true,
    sunriseMinutesBefore: 10,
    screensaverEnabled: false,
    screensaverMinutes: 10,

    // Valores por defecto de las nuevas opciones.
    temperatureUnit: 'C',
    windUnit: 'kmh',
    autoplayRadio: false,
    alarmSound: 'radio',
    alarmDays: [1, 2, 3, 4, 5],
    sunriseDurationSeconds: 30,
    sunriseColor: const Color(0xFFF59E0B),
    snoozeMinutes: 5,
    screensaverDoubleTap: false,
    windowWidth: 800,
    windowHeight: 480,
    languageCode: 'es',
    savedLocations: [],
    favouriteStations: const ['Kiss FM', 'Los 40', 'Cadena SER', 'Europa FM'],
    wifiSsid: null,
    wifiPassword: null,
    wifiEnabled: false,
    bluetoothEnabled: false,
    pairedBluetoothIds: const [],
    showConnectivityIcons: true,
    bootAnimation: true,
    bootMinDurationMs: 1200,
  );

  AppSettings copyWith({
    Color? accentColor,
    bool? nightMode,
    bool? showSeconds,
    bool? showDate,
    bool? use24Hour,
    String? fontFamily,
    double? clockFontSize,
    double? dateFontSize,
    double? cardTextScale,
    double? cardHeight,
    int? clockWeight,
    String? locationLabel,
    String? weatherLabel,
    double? latitude,
    double? longitude,
    String? timezone,
    int? weatherRefreshMinutes,
    int? stationIndex,
    double? volume,
    bool? alarmEnabled,
    int? alarmHour,
    int? alarmMinute,
    bool? sunriseEnabled,
    int? sunriseMinutesBefore,
    bool? screensaverEnabled,
    int? screensaverMinutes,
    String? temperatureUnit,
    String? windUnit,
    bool? autoplayRadio,
    String? alarmSound,
    List<int>? alarmDays,
    int? sunriseDurationSeconds,
    Color? sunriseColor,
    int? snoozeMinutes,
    bool? screensaverDoubleTap,
    double? windowWidth,
    double? windowHeight,
    String? languageCode,
    List<Map<String, dynamic>>? savedLocations,
    List<String>? favouriteStations,
    String? wifiSsid,
    String? wifiPassword,
    bool clearWifiPassword = false,
    bool? wifiEnabled,
    bool? bluetoothEnabled,
    List<String>? pairedBluetoothIds,
    bool? showConnectivityIcons,
    bool? bootAnimation,
    int? bootMinDurationMs,
  }) {
    return AppSettings(
      accentColor: accentColor ?? this.accentColor,
      nightMode: nightMode ?? this.nightMode,
      showSeconds: showSeconds ?? this.showSeconds,
      showDate: showDate ?? this.showDate,
      use24Hour: use24Hour ?? this.use24Hour,
      fontFamily: fontFamily ?? this.fontFamily,
      clockFontSize: clockFontSize ?? this.clockFontSize,
      dateFontSize: dateFontSize ?? this.dateFontSize,
      cardTextScale: cardTextScale ?? this.cardTextScale,
      cardHeight: cardHeight ?? this.cardHeight,
      clockWeight: clockWeight ?? this.clockWeight,
      locationLabel: locationLabel ?? this.locationLabel,
      weatherLabel: weatherLabel ?? this.weatherLabel,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timezone: timezone ?? this.timezone,
      weatherRefreshMinutes:
          weatherRefreshMinutes ?? this.weatherRefreshMinutes,
      stationIndex: stationIndex ?? this.stationIndex,
      volume: volume ?? this.volume,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarmHour: alarmHour ?? this.alarmHour,
      alarmMinute: alarmMinute ?? this.alarmMinute,
      sunriseEnabled: sunriseEnabled ?? this.sunriseEnabled,
      sunriseMinutesBefore: sunriseMinutesBefore ?? this.sunriseMinutesBefore,
      screensaverEnabled: screensaverEnabled ?? this.screensaverEnabled,
      screensaverMinutes: screensaverMinutes ?? this.screensaverMinutes,
      temperatureUnit: temperatureUnit ?? this.temperatureUnit,
      windUnit: windUnit ?? this.windUnit,
      autoplayRadio: autoplayRadio ?? this.autoplayRadio,
      alarmSound: alarmSound ?? this.alarmSound,
      alarmDays: alarmDays ?? this.alarmDays,
      sunriseDurationSeconds:
          sunriseDurationSeconds ?? this.sunriseDurationSeconds,
      sunriseColor: sunriseColor ?? this.sunriseColor,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      screensaverDoubleTap: screensaverDoubleTap ?? this.screensaverDoubleTap,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      languageCode: languageCode ?? this.languageCode,
      savedLocations: savedLocations ?? this.savedLocations,
      favouriteStations: favouriteStations ?? this.favouriteStations,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiPassword: clearWifiPassword
          ? null
          : (wifiPassword ?? this.wifiPassword),
      wifiEnabled: wifiEnabled ?? this.wifiEnabled,
      bluetoothEnabled: bluetoothEnabled ?? this.bluetoothEnabled,
      pairedBluetoothIds: pairedBluetoothIds ?? this.pairedBluetoothIds,
      showConnectivityIcons:
          showConnectivityIcons ?? this.showConnectivityIcons,
      bootAnimation: bootAnimation ?? this.bootAnimation,
      bootMinDurationMs: bootMinDurationMs ?? this.bootMinDurationMs,
    );
  }

  Map<String, Object> toMap() => {
    'accent': accentColor.toARGB32(),
    'night': nightMode,
    'secs': showSeconds,
    'date': showDate,
    'h24': use24Hour,
    'font': fontFamily,
    'clockSize': clockFontSize,
    'dateSize': dateFontSize,
    'cardScale': cardTextScale,
    'cardH': cardHeight,
    'weight': clockWeight,
    'loc': locationLabel,
    'wlabel': weatherLabel,
    'lat': latitude,
    'lon': longitude,
    'tz': timezone,
    'wrefresh': weatherRefreshMinutes,
    'station': stationIndex,
    'vol': volume,
    'alarm': alarmEnabled,
    'ah': alarmHour,
    'am': alarmMinute,
    'sun': sunriseEnabled,
    'sunMin': sunriseMinutesBefore,
    'saver': screensaverEnabled,
    'saverMin': screensaverMinutes,
    'tempUnit': temperatureUnit,
    'windUnit': windUnit,
    'autoplay': autoplayRadio,
    'alarmSound': alarmSound,
    'alarmDays': alarmDays,
    'sunDuration': sunriseDurationSeconds,
    'sunColor': sunriseColor.toARGB32(),
    'snoozeMin': snoozeMinutes,
    'saverTap2': screensaverDoubleTap,
    'winW': windowWidth,
    'winH': windowHeight,
    'lang': languageCode,
    'savedLocations': savedLocations,
    'favourites': favouriteStations,
    'wifiSsid': wifiSsid ?? '',
    // SEGURIDAD: la contraseña WiFi es solo de sesión (memoria), nunca se
    // persiste en settings.json en texto plano. nmcli ya la guarda en el
    // keyring del sistema al conectar.
    'wifiEnabled': wifiEnabled,
    'btEnabled': bluetoothEnabled,
    'btIds': pairedBluetoothIds,
    'showConnIcons': showConnectivityIcons,
    'bootAnim': bootAnimation,
    'bootMinMs': bootMinDurationMs,
  };

  /// Reconstruye los ajustes desde JSON tolerando claves ausentes o corruptas.
  factory AppSettings.fromMap(Map<String, dynamic> map) {
    final d = AppSettings.defaults();

    double dbl(String key, double fallback) {
      final v = map[key];
      return v is num ? v.toDouble() : fallback;
    }

    int integer(String key, int fallback) {
      final v = map[key];
      return v is num ? v.round() : fallback;
    }

    bool boolean(String key, bool fallback) {
      final v = map[key];
      return v is bool ? v : fallback;
    }

    String text(String key, String fallback) {
      final v = map[key];
      return v is String ? v : fallback;
    }

    return AppSettings(
      accentColor: Color(integer('accent', d.accentColor.toARGB32())),
      nightMode: boolean('night', d.nightMode),
      showSeconds: boolean('secs', d.showSeconds),
      showDate: boolean('date', d.showDate),
      use24Hour: boolean('h24', d.use24Hour),
      fontFamily: text('font', d.fontFamily),
      clockFontSize: dbl('clockSize', d.clockFontSize),
      dateFontSize: dbl('dateSize', d.dateFontSize),
      cardTextScale: dbl('cardScale', d.cardTextScale),
      cardHeight: dbl('cardH', d.cardHeight),
      clockWeight: integer('weight', d.clockWeight),
      locationLabel: text('loc', d.locationLabel),
      weatherLabel: text('wlabel', d.weatherLabel),
      latitude: dbl('lat', d.latitude),
      longitude: dbl('lon', d.longitude),
      timezone: text('tz', d.timezone),
      weatherRefreshMinutes: integer('wrefresh', d.weatherRefreshMinutes),
      stationIndex: integer('station', d.stationIndex),
      volume: dbl('vol', d.volume),
      alarmEnabled: boolean('alarm', d.alarmEnabled),
      alarmHour: integer('ah', d.alarmHour),
      alarmMinute: integer('am', d.alarmMinute),
      sunriseEnabled: boolean('sun', d.sunriseEnabled),
      sunriseMinutesBefore: integer('sunMin', d.sunriseMinutesBefore),
      screensaverEnabled: boolean('saver', d.screensaverEnabled),
      screensaverMinutes: integer('saverMin', d.screensaverMinutes),

      // Nuevas opciones de personalización.
      temperatureUnit: text('tempUnit', d.temperatureUnit),
      windUnit: text('windUnit', d.windUnit),
      autoplayRadio: boolean('autoplay', d.autoplayRadio),
      alarmSound: () {
        final sound = text('alarmSound', d.alarmSound);
        return sound == 'buzzer' ? 'beep' : sound;
      }(),
      alarmDays: () {
        final v = map['alarmDays'];
        if (v is List) {
          return v.map((e) => (e as num).toInt()).toList();
        }
        return List<int>.from(d.alarmDays);
      }(),
      sunriseDurationSeconds: integer('sunDuration', d.sunriseDurationSeconds),
      sunriseColor: Color(integer('sunColor', d.sunriseColor.toARGB32())),
      snoozeMinutes: integer('snoozeMin', d.snoozeMinutes),
      screensaverDoubleTap: boolean('saverTap2', d.screensaverDoubleTap),
      windowWidth: dbl('winW', d.windowWidth),
      windowHeight: dbl('winH', d.windowHeight),
      languageCode: text('lang', d.languageCode),
      savedLocations: () {
        final v = map['savedLocations'];
        if (v is List) {
          return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        return d.savedLocations;
      }(),
      favouriteStations: () {
        final v = map['favourites'];
        if (v is List) return v.map((e) => e.toString()).toList();
        return List<String>.from(d.favouriteStations);
      }(),
      wifiSsid: () {
        final v = map['wifiSsid'];
        return v is String && v.isNotEmpty ? v : null;
      }(),
      wifiPassword: null,
      wifiEnabled: boolean('wifiEnabled', false),
      bluetoothEnabled: boolean('btEnabled', false),
      pairedBluetoothIds: () {
        final v = map['btIds'];
        if (v is List) return v.map((e) => e.toString()).toList();
        return List<String>.from(d.pairedBluetoothIds);
      }(),
      showConnectivityIcons: boolean('showConnIcons', true),
      bootAnimation: boolean('bootAnim', d.bootAnimation),
      bootMinDurationMs: integer('bootMinMs', d.bootMinDurationMs),
    );
  }
}
