import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

// Importamos nuestros módulos separados
import 'models/app_settings.dart';
import 'services/alarm_logic.dart';
import 'services/app_log.dart';
import 'services/beep_service.dart';
import 'services/bluetooth_service.dart';
import 'services/connectivity_service.dart';
import 'services/weather_service.dart';
import 'services/radio_service.dart';
import 'services/settings_store.dart';
import 'services/wifi_service.dart';
import 'screens/settings_screen.dart';
import 'widgets/app_bootstrap.dart';
import 'widgets/boot_screen.dart';
import 'widgets/connectivity_icons.dart';
import 'widgets/interactive_card.dart';

/// Arranque de la app.
///
/// Todo el trabajo corre dentro de un [runZonedGuarded]: así cualquier error
/// asíncrono no capturado queda registrado en el log de disco en vez de
/// provocar un cierre silencioso del kiosco.
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    AppLog.install();
    AppLog.info('Arrancando PiHome Ultimate');
    // Sin `await`: los errores del respaldo asíncrono siguen cayendo en la
    // zona y quedan registrados igualmente.
    unawaited(_bootstrap());
  }, (error, stack) => AppLog.error('Error no capturado', error, stack));
}

Future<void> _bootstrap() async {
  // La gestión de ventana sólo existe en escritorio: si la plataforma no la
  // soporta (p. ej. al lanzar en un navegador) se ignora, para que la app siga
  // arrancando en lugar de quedarse en pantalla en blanco.
  try {
    await windowManager.ensureInitialized();
  } catch (error) {
    AppLog.warn('Sin gestión de ventana: $error');
  }

  AppSettings settings;
  try {
    settings = await SettingsStore.load();
  } catch (error, stack) {
    AppLog.error('No se pudieron cargar los ajustes', error, stack);
    settings = AppSettings.defaults();
  }

  // NUEVO: el tamaño de ventana configurado por el usuario (si es válido).
  final winW = settings.windowWidth.round().clamp(400, 3840);
  final winH = settings.windowHeight.round().clamp(300, 2160);

  WindowOptions windowOptions = WindowOptions(
    size: Size(winW.toDouble(), winH.toDouble()),
    minimumSize: const Size(400, 300),
    maximumSize: const Size(3840, 2160),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: "PiHome Ultimate - Modular",
  );

  try {
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (error) {
    AppLog.warn('No se pudo configurar la ventana: $error');
  }

  AppLog.info('Ajustes cargados (ventana ${winW}x$winH)');
  // AppBootstrap envuelve la app: si ocurre un error fatal, sustituye la
  // interfaz por una pantalla de error con botón de reinicio en vez de dejar
  // la pantalla en blanco (crítico en un kiosco sin teclado ni consola).
  runApp(
    AppBootstrap(
      accentColor: settings.accentColor,
      appBuilder: (key) => SmartDisplayApp(key: key, initialSettings: settings),
    ),
  );
}

/// Raíz de la app: guarda los ajustes para poder aplicar la tipografía a toda
/// la interfaz (ThemeData) y los persiste en disco cuando cambian.
class SmartDisplayApp extends StatefulWidget {
  final AppSettings initialSettings;

  const SmartDisplayApp({super.key, required this.initialSettings});

  @override
  State<SmartDisplayApp> createState() => _SmartDisplayAppState();
}

class _SmartDisplayAppState extends State<SmartDisplayApp> {
  late AppSettings _settings;
  Timer? _saveTimer;

  /// Mientras es true se muestra la animación de arranque sobre la pantalla
  /// principal. Se apaga cuando el [BootScreen] termina (cargas + duración
  /// mínima) o si el usuario desactivó la animación en los ajustes.
  late bool _showBoot;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _showBoot = _settings.bootAnimation;
  }

  void _applySettings(AppSettings next) {
    setState(() => _settings = next);
    // Se guarda con un pequeño retardo para no escribir en disco en cada
    // movimiento de los sliders.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      SettingsStore.save(_settings);
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    SettingsStore.saveSync(_settings);
    super.dispose();
  }

  /// Construye la pantalla principal y, si procede, superpone la animación de
  /// arranque. Se usa un [Stack] para que la pantalla principal ya esté montada
  /// (y cargando servicios) debajo del boot, evitando un salto al terminar.
  Widget _buildHome() {
    final main = SmartDisplayScreen(
      settings: _settings,
      onSettingsChanged: _applySettings,
    );
    if (!_showBoot) return main;

    return Stack(
      children: [
        main,
        BootScreen(
          accent: _settings.accentColor,
          minDuration: Duration(milliseconds: _settings.bootMinDurationMs),
          // Los ajustes ya se cargaron antes de runApp; este futuro representa
          // el resto del arranque y puede extenderse en el futuro.
          onReady: Future<void>.delayed(Duration.zero),
          onFinished: () {
            if (mounted) setState(() => _showBoot = false);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final font = _settings.fontFamily;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: font.isEmpty ? null : font,
      ),
      home: _buildHome(),
      // Rutas nombradas para que los iconos de la barra superior abran
      // directamente la página de WiFi/Bluetooth con un toque.
      onGenerateRoute: (routeSettings) {
        if (routeSettings.name == '/settings/wifi' ||
            routeSettings.name == '/settings/bluetooth') {
          final isBt = routeSettings.name == '/settings/bluetooth';
          return MaterialPageRoute(
            settings: routeSettings,
            builder: (ctx) => Scaffold(
              appBar: AppBar(title: Text(isBt ? 'Bluetooth' : 'Red Wi-Fi')),
              body: isBt
                  ? buildBluetoothSettingsBody(ctx, _settings, _applySettings)
                  : buildWifiSettingsBody(ctx, _settings, _applySettings),
            ),
          );
        }
        return null;
      },
    );
  }
}

class SmartDisplayScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final WifiService? wifiService;
  final BluetoothService? bluetoothService;
  final ConnectivityService? connectivityService;

  const SmartDisplayScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.wifiService,
    this.bluetoothService,
    this.connectivityService,
  });

  @override
  State<SmartDisplayScreen> createState() => _SmartDisplayScreenState();
}

class _SmartDisplayScreenState extends State<SmartDisplayScreen> {
  // Estado propio de la pantalla (el resto vive en los ajustes)
  bool _isScreensaver = false;
  bool _isAlarmRinging = false;
  bool _isPreviewingSunrise = false;
  DateTime _lastInteraction = DateTime.now();

  // Estado de la alarma (temporal, en memoria: no se persiste).
  /// Instante hasta el que se ha pospuesto la alarma (snooze). No modifica la
  /// hora programada en los ajustes.
  DateTime? _snoozedUntil;

  /// Clave de la última ocurrencia de alarma ya disparada (evita repetirla).
  String? _lastAlarmKey;

  /// Última comprobación del reloj; sirve para detectar el cruce de la hora de
  /// la alarma (ver [alarmCrossedTime]).
  DateTime? _lastAlarmCheck;

  // Estado del simulador de amanecer real (el previo a la alarma).
  bool _isSunriseActive = false;

  /// Instante de la alarma hacia la que progresa el amanecer actual.
  DateTime? _sunriseEnd;

  // Servicios
  final RadioService _radio = RadioService();
  final BeepService _beep = BeepService();
  late final ConnectivityService _connectivity;
  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  ConnectivityStatus _connStatus = const ConnectivityStatus();
  WeatherData? _weather;

  // Temporizadores
  late Timer _clockTimer;
  late Timer _weatherTimer;
  Timer? _idleTimer;
  Timer? _sunrisePreviewTimer;
  Timer? _windowResizeTimer;
  String _timeString = "";
  String _dateString = "";

  late AppSettings _currentSettings;

  /// Atajo a los ajustes actuales.
  AppSettings get _settings => _currentSettings;

  /// Notifica un cambio de ajustes (se aplica y se persiste en la app raíz).
  void _updateSettings(AppSettings next) {
    setState(() => _currentSettings = next);
    widget.onSettingsChanged(next);
  }

  /// Grosor tipográfico del reloj según los ajustes.
  FontWeight get _clockWeight => FontWeight.values.firstWhere(
    (w) => w.value == _settings.clockWeight,
    orElse: () => FontWeight.w200,
  );

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
    _connectivity =
        widget.connectivityService ??
        ConnectivityService(
          wifi: widget.wifiService,
          bluetooth: widget.bluetoothService,
        );
    _connectivitySub = _connectivity.stream.listen((status) {
      if (mounted) setState(() => _connStatus = status);
    });

    _radio
        .init(
          onStateChanged: () {
            if (mounted) setState(() {});
          },
        )
        .then((_) {
          // NUEVO 1: stationIndex seguro + autoplay al arrancar (opcion A).
          _syncStation();
          if (_settings.autoplayRadio && mounted) {
            _radio.play();
          }
        });
    _radio.setVolume(_settings.volume);

    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTime(),
    );

    _loadWeather();
    _weatherTimer = Timer.periodic(
      Duration(minutes: _settings.weatherRefreshMinutes.clamp(1, 240)),
      (_) => _loadWeather(),
    );

    _idleTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkIdle(),
    );

    // Conectividad: servicio unificado (Stream) + respaldo en ajustes.
    // - En Linux: nmcli/bluetoothctl en vivo cada 30s.
    // - Fuera de Linux: los métodos devuelven null/[] y se mantiene el
    //   respaldo de ajustes (SSID guardado, emparejados).
    // - Si faltan herramientas/permisos marca unknown (icono atenuado).
    _connectivity.setPairedKnown(_settings.pairedBluetoothIds.length);
    _connectivity.start();
  }

  /// Ajusta la emisora a la guardada en los ajustes.
  /// NUEVO 1: con favoritos, el indice puede quedar fuera de rango tras
  /// cambiar la lista; se corrige (clamp) y se persiste la correccion.
  void _syncStation() {
    if (_radio.stations.isEmpty) {
      _radio.resetToDefaults();
    }
    final target = _settings.stationIndex.clamp(0, _radio.stations.length - 1);
    if (target != _radio.currentStationIndex) {
      _radio.changeStation(target - _radio.currentStationIndex);
    }
    if (target != _settings.stationIndex) {
      _updateSettings(_settings.copyWith(stationIndex: target));
    }
  }

  /// Persiste la emisora actual cuando el usuario la cambia con las flechas,
  /// para que al reiniciar la app arranque con la última elegida.
  void _persistStation() {
    if (_radio.currentStationIndex != _settings.stationIndex) {
      _updateSettings(
        _settings.copyWith(stationIndex: _radio.currentStationIndex),
      );
    }
  }

  /// Reposo automático tras N minutos sin tocar la pantalla.
  void _checkIdle() {
    if (!_settings.screensaverEnabled ||
        _isScreensaver ||
        _isAlarmRinging ||
        _isSunriseActive) {
      return;
    }
    final idle = DateTime.now().difference(_lastInteraction);
    if (idle.inMinutes >= _settings.screensaverMinutes) {
      setState(() => _isScreensaver = true);
    }
  }

  /// Cualquier toque reinicia el contador de inactividad.
  void _registerInteraction() => _lastInteraction = DateTime.now();

  @override
  void didUpdateWidget(covariant SmartDisplayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentSettings = widget.settings;
    final old = oldWidget.settings;
    final now = _settings;

    // Si el nº de emparejados cambia (ajustes), se actualiza el respaldo.
    if (old.pairedBluetoothIds.length != now.pairedBluetoothIds.length) {
      _connectivity.setPairedKnown(now.pairedBluetoothIds.length);
    }

    if (old.volume != now.volume) _radio.setVolume(now.volume);
    if (old.stationIndex != now.stationIndex) _syncStation();

    // CORREGIDO: el tamaño de ventana se aplica con debounce para no saturar
    // llamadas nativas durante el arrastre de los sliders.
    if (old.windowWidth != now.windowWidth ||
        old.windowHeight != now.windowHeight) {
      _debouncedApplyWindowSize(now);
    }

    if (old.showSeconds != now.showSeconds ||
        old.use24Hour != now.use24Hour ||
        old.showDate != now.showDate) {
      _updateTime();
    }

    if (old.weatherRefreshMinutes != now.weatherRefreshMinutes ||
        old.latitude != now.latitude ||
        old.longitude != now.longitude ||
        old.timezone != now.timezone ||
        old.temperatureUnit != now.temperatureUnit ||
        old.windUnit != now.windUnit) {
      _weatherTimer.cancel();
      _weatherTimer = Timer.periodic(
        Duration(minutes: now.weatherRefreshMinutes.clamp(1, 240)),
        (_) => _loadWeather(),
      );
      _loadWeather();
    }
  }

  void _debouncedApplyWindowSize(AppSettings s) {
    _windowResizeTimer?.cancel();
    _windowResizeTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(_applyWindowSize(s));
    });
  }

  /// Redimensiona la ventana según los ajustes. En plataformas sin gestión
  /// de ventana (web, móvil) la llamada falla y se ignora silenciosamente.
  Future<void> _applyWindowSize(AppSettings s) async {
    try {
      final w = s.windowWidth.round().clamp(400, 3840).toDouble();
      final h = s.windowHeight.round().clamp(300, 2160).toDouble();
      await windowManager.setSize(Size(w, h));
    } catch (_) {}
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _weatherTimer.cancel();
    _idleTimer?.cancel();
    _sunrisePreviewTimer?.cancel();
    _windowResizeTimer?.cancel();
    _connectivitySub?.cancel();
    // Pausa el chequeo periódico siempre (evita Timers pendientes al salir);
    // sólo se libera el servicio si lo creó esta pantalla (no el inyectado).
    _connectivity.pause();
    if (widget.connectivityService == null) _connectivity.dispose();
    _beep.dispose();
    _radio.dispose();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    try {
      final data = await WeatherService.fetchWeather(
        latitude: _settings.latitude,
        longitude: _settings.longitude,
        timezone: _settings.timezone,
        temperatureUnit: _settings.temperatureUnit,
        windUnit: _settings.windUnit,
      );
      if (mounted) setState(() => _weather = data);
    } catch (_) {}
  }

  void _updateTime() {
    final now = DateTime.now();
    final hourValue = _settings.use24Hour
        ? now.hour
        : (now.hour % 12 == 0 ? 12 : now.hour % 12);
    final h = hourValue.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final suffix = _settings.use24Hour ? "" : (now.hour < 12 ? " AM" : " PM");
    final newTime = _settings.showSeconds ? "$h:$m:$s$suffix" : "$h:$m$suffix";

    const weekdays = [
      "Lunes",
      "Martes",
      "Miércoles",
      "Jueves",
      "Viernes",
      "Sábado",
      "Domingo",
    ];
    const months = [
      "Enero",
      "Febrero",
      "Marzo",
      "Abril",
      "Mayo",
      "Junio",
      "Julio",
      "Agosto",
      "Septiembre",
      "Octubre",
      "Noviembre",
      "Diciembre",
    ];
    final newDate =
        "${weekdays[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}";

    // CORREGIDO: antes la alarma sólo sonaba si el tick caía exactamente en
    // el segundo 0 del minuto; si se perdía ese tick, no sonaba nunca.
    _checkAlarm(now);
    _checkSunrise(now);

    if (newTime != _timeString || newDate != _dateString) {
      setState(() {
        _timeString = newTime;
        _dateString = newDate;
      });
    }
  }

  /// Comprueba si debe sonar la alarma (programada o pospuesta).
  ///
  /// Suena cuando el reloj **cruza** la hora programada (así un tick perdido no
  /// la salta) o si la app arranca dentro de la ventana de gracia. La clave de
  /// ocurrencia evita repetirla. Antes bastaba con que `ahora >= hora`, de modo
  /// que abrir la app a las 09:00 con la alarma a las 07:00 disparaba la alarma
  /// nada más arrancar y tapaba toda la pantalla.
  void _checkAlarm(DateTime now) {
    if (_isAlarmRinging) return;

    // Snooze: temporal y en memoria; la alarma programada no se toca.
    final snooze = _snoozedUntil;
    if (snooze != null) {
      _lastAlarmCheck = now;
      if (!now.isBefore(snooze)) {
        _snoozedUntil = null;
        _triggerAlarm();
      }
      return;
    }

    // Se guarda la comprobación anterior para detectar el cruce de hora.
    final previous = _lastAlarmCheck;
    _lastAlarmCheck = now;

    if (!_settings.alarmEnabled || !_settings.alarmDays.contains(now.weekday)) {
      return;
    }
    final alarmTime = DateTime(
      now.year,
      now.month,
      now.day,
      _settings.alarmHour,
      _settings.alarmMinute,
    );
    if (!alarmCrossedTime(previous, now, alarmTime)) return;
    final key = alarmOccurrenceKey(alarmTime);
    if (_lastAlarmKey == key) return;
    _lastAlarmKey = key;
    _triggerAlarm();
  }

  /// Activa o desactiva el simulador de amanecer real: empieza
  /// [AppSettings.sunriseMinutesBefore] minutos antes de la próxima alarma.
  void _checkSunrise(DateTime now) {
    if (_isPreviewingSunrise || _isAlarmRinging) return;
    var active = false;
    if (_settings.sunriseEnabled) {
      final next = nextAlarmTime(
        now,
        enabled: _settings.alarmEnabled,
        hour: _settings.alarmHour,
        minute: _settings.alarmMinute,
        days: _settings.alarmDays,
      );
      if (next != null) {
        final start = next.subtract(
          Duration(minutes: _settings.sunriseMinutesBefore.clamp(1, 120)),
        );
        if (!now.isBefore(start) && now.isBefore(next)) {
          active = true;
          _sunriseEnd = next;
        }
      }
    }
    if (active != _isSunriseActive) {
      setState(() => _isSunriseActive = active);
    }
  }

  void _triggerAlarm() {
    setState(() {
      _isAlarmRinging = true;
      _isScreensaver = false;
      _isSunriseActive = false;
    });
    if (_settings.alarmSound == 'beep') {
      // Pitido local sintetizado (ver BeepService), en bucle hasta apagarla.
      _beep.start();
    } else {
      _radio.play();
    }
  }

  void _stopAlarm() {
    _snoozedUntil = null;
    // Al atender la alarma se reinicia el reposo: sin esto, si la pantalla
    // llevaba horas "inactiva" el reposo volvía a activarse en el siguiente
    // tick (20 s) nada más apagarla.
    _registerInteraction();
    setState(() => _isAlarmRinging = false);
    _beep.stop();
    _radio.stop();
  }

  /// CORREGIDO: posponer ya no sobrescribe la hora de la alarma en los
  /// ajustes; guarda sólo un instante temporal hasta el que volver a sonar.
  void _snoozeAlarm() {
    _snoozedUntil = DateTime.now().add(
      Duration(minutes: _settings.snoozeMinutes.clamp(1, 60)),
    );
    _registerInteraction();
    setState(() => _isAlarmRinging = false);
    _beep.stop();
    _radio.stop();
  }

  /// Abre el panel de ajustes con aplicación en vivo.
  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: _settings,
          radio: _radio,
          onChanged: _updateSettings,
          onPreviewSunrise: _previewSunrise,
          onPreviewScreensaver: () => setState(() => _isScreensaver = true),
          onRefreshWeather: _loadWeather,
        ),
      ),
    );
  }

  /// Efecto amanecer de prueba (usa la duracion configurada, max. 30 s en prueba).
  void _previewSunrise() {
    _sunrisePreviewTimer?.cancel();
    setState(() => _isPreviewingSunrise = true);
    _sunrisePreviewTimer = Timer(
      Duration(seconds: _settings.sunriseDurationSeconds.clamp(5, 30)),
      () {
        if (mounted) setState(() => _isPreviewingSunrise = false);
      },
    );
  }

  // Modales
  void _openGlassModal(Widget content) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Cerrar",
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (_, anim, _, _) {
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 14 * anim.value,
            sigmaY: 14 * anim.value,
          ),
          child: FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                child: Container(
                  width: 480,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141E).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _settings.accentColor.withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showVolumeSleepModal() {
    _openGlassModal(
      StatefulBuilder(
        builder: (ctx, setModalState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "🔊 Volumen y Apagado",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "Nivel de Volumen: ${(_radio.volume * 100).round()}%",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Row(
                children: [
                  const Icon(Icons.volume_mute, color: Colors.grey, size: 20),
                  Expanded(
                    child: Slider(
                      value: _radio.volume,
                      activeColor: _settings.accentColor,
                      onChanged: (val) {
                        _updateSettings(_settings.copyWith(volume: val));
                        setModalState(() {});
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white, size: 20),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Temporizador de Sueño",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_radio.sleepMinutesLeft > 0)
                    Text(
                      "Se apaga en: ${_radio.sleepMinutesLeft} min",
                      style: TextStyle(
                        color: _settings.accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [0, 15, 30, 45, 60].map((mins) {
                  // CORREGIDO: se compara con los minutos CONFIGURADOS, no con
                  // los restantes (que decrecen y deseleccionaban el botón).
                  final isSelected = (_radio.sleepTimerSetting == mins);
                  return GestureDetector(
                    onTap: () {
                      setModalState(() {
                        _radio.setSleepTimer(
                          mins,
                          onTick: () {
                            if (mounted) setState(() {});
                            // El temporizador sigue vivo tras cerrar el modal:
                            // si ya no existe, no se puede repintar (antes
                            // lanzaba "setState() called after dispose()").
                            if (ctx.mounted) setModalState(() {});
                          },
                          onExpire: () {
                            if (mounted) setState(() {});
                          },
                        );
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _settings.accentColor
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        mins == 0 ? "Off" : "$mins m",
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAlarmSunriseModal() {
    _openGlassModal(
      StatefulBuilder(
        builder: (ctx, setModalState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "⏰ Alarma y Despertador",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  "Hora de la alarma",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  _settings.alarmSound == 'beep'
                      ? "Sonará con el pitido local"
                      : "Sonará con ${_radio.currentStation.name}",
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _settings.accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _settings.accentColor),
                  ),
                  child: Text(
                    "${_settings.alarmHour.toString().padLeft(2, '0')}:${_settings.alarmMinute.toString().padLeft(2, '0')}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: _settings.alarmHour,
                      minute: _settings.alarmMinute,
                    ),
                    builder: (context, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: _settings.accentColor,
                          surface: const Color(0xFF181824),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    _updateSettings(
                      _settings.copyWith(
                        alarmHour: picked.hour,
                        alarmMinute: picked.minute,
                      ),
                    );
                    if (ctx.mounted) setModalState(() {});
                  }
                },
              ),
              const Divider(color: Colors.white12, height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  "Simulador de Amanecer 🌅",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  "Ilumina la pantalla ${_settings.sunriseMinutesBefore} min antes",
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                value: _settings.sunriseEnabled,
                activeThumbColor: _settings.accentColor,
                onChanged: (val) {
                  _updateSettings(_settings.copyWith(sunriseEnabled: val));
                  setModalState(() {});
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.wb_sunny_outlined, size: 16),
                  label: const Text("Probar Efecto Amanecer (5 seg)"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber,
                    side: const BorderSide(color: Colors.amber),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _previewSunrise();
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showForecastDialog() {
    _openGlassModal(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "📍 Pronóstico · ${_settings.weatherLabel}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            "Humedad: ${_weather?.humidity ?? '--'} · Viento: ${_weather?.wind ?? '--'}",
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children:
                (_weather?.forecast ??
                        [
                          ForecastDay(day: 'Hoy', max: 24, min: 12, icon: '☀️'),
                          ForecastDay(
                            day: 'Mañana',
                            max: 22,
                            min: 11,
                            icon: '⛅',
                          ),
                          ForecastDay(
                            day: 'Pasado',
                            max: 25,
                            min: 13,
                            icon: '☀️',
                          ),
                        ])
                    .map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.day,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.icon,
                              style: const TextStyle(fontSize: 26),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "${item.max}°",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${item.min}°",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                    .toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final night = _settings.nightMode;
    final scale = _settings.cardTextScale;
    final bgColor1 = night ? const Color(0xFF140505) : const Color(0xFF1E1B4B);
    final bgColor2 = night ? const Color(0xFF000000) : const Color(0xFF09090B);
    final textColor = night ? const Color(0xFFEF4444) : Colors.white;
    final textMuted = night ? const Color(0xFF7F1D1D) : const Color(0xFF94A3B8);
    final currentAccent = night
        ? const Color(0xFFDC2626)
        : _settings.accentColor;
    final cardBorder = night
        ? const Color(0x33EF4444)
        : Colors.white.withValues(alpha: 0.12);
    final cardBg = night
        ? const Color(0x66140505)
        : Colors.white.withValues(alpha: 0.05);

    return Scaffold(
      backgroundColor: Colors.black,
      // El Listener ENVUELVE todo el contenido para registrar cualquier toque
      // como actividad. Antes era un hijo del Stack y sólo veía los toques en
      // zonas vacías (las tarjetas, los textos y los badges se quedaban con el
      // evento), así que el reposo podía activarse mientras el usuario seguía
      // pulsando botones... y al despertar del reposo no reiniciaba el contador.
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _registerInteraction(),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.6),
                  radius: 1.2,
                  colors: [bgColor1, bgColor2],
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 18.0,
                vertical: 12.0,
              ),
              child: Column(
                children: [
                  // 1. Barra Superior
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: buildBadge(
                                _settings.locationLabel,
                                cardBg,
                                cardBorder,
                                textMuted,
                                11 * scale,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Iconos WiFi/BT extraídos a su propio widget:
                            // siempre visibles, atenuados si no hay conexión,
                            // tap abre ajustes, long-press muestra detalle.
                            ConnectivityIcons(
                              status: _connStatus,
                              settings: _settings,
                              scale: scale,
                              accent: currentAccent,
                              muted: textMuted,
                              onSettingsChanged: _updateSettings,
                              radio: _radio,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              _registerInteraction();
                              setState(() => _isScreensaver = true);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: buildBadge(
                              "💤 Reposo",
                              cardBg,
                              cardBorder,
                              Colors.amberAccent,
                              11 * scale,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              _registerInteraction();
                              _updateSettings(
                                _settings.copyWith(nightMode: !night),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: buildBadge(
                              night ? "☀️ Día" : "🌙 Noche",
                              cardBg,
                              cardBorder,
                              textColor,
                              11 * scale,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              _registerInteraction();
                              _openSettings();
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: buildBadge(
                              "⚙️ Ajustes",
                              cardBg,
                              cardBorder,
                              textColor,
                              11 * scale,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // 2. Reloj Central
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text(
                              _timeString,
                              style: TextStyle(
                                fontSize:
                                    _settings.clockFontSize *
                                    (_settings.showSeconds ? 0.84 : 1.0),
                                fontWeight: _clockWeight,
                                color: textColor,
                                letterSpacing: -2,
                                shadows: [
                                  Shadow(
                                    color: currentAccent.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 25,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_settings.showDate)
                          Text(
                            _dateString,
                            style: TextStyle(
                              fontSize: _settings.dateFontSize,
                              color: textMuted,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 3. Tarjetas Inferiores
                  SizedBox(
                    height: _settings.cardHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Clima
                        Expanded(
                          flex: 10,
                          child: InteractiveCard(
                            cardBg: cardBg,
                            cardBorder: cardBorder,
                            onTap: _showForecastDialog,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "CLIMA",
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 10 * scale,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    Text(
                                      "Pronóstico ›",
                                      style: TextStyle(
                                        color: currentAccent,
                                        fontSize: 10 * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  "${_weather?.temp ?? '--°C'} ${_weather?.icon ?? '☀️'}",
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 21 * scale,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _weather?.description ?? "Cargando clima...",
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 12 * scale,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Radio
                        Expanded(
                          flex: 12,
                          child: InteractiveCard(
                            cardBg: cardBg,
                            cardBorder: cardBorder,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "STREAMING",
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 10 * scale,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: _showVolumeSleepModal,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.volume_up,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                            if (_radio.sleepMinutesLeft >
                                                0) ...[
                                              const SizedBox(width: 3),
                                              Text(
                                                "${_radio.sleepMinutesLeft} m",
                                                style: TextStyle(
                                                  color: _settings.accentColor,
                                                  fontSize: 9 * scale,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    InkWell(
                                      onTap: () => setState(() {
                                        _radio.changeStation(-1);
                                        _persistStation();
                                      }),
                                      customBorder: const CircleBorder(),
                                      child: const Icon(
                                        Icons.arrow_left,
                                        color: Colors.grey,
                                        size: 22,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        _radio.currentStation.name,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 13 * scale,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => setState(() {
                                        _radio.changeStation(1);
                                        _persistStation();
                                      }),
                                      customBorder: const CircleBorder(),
                                      child: const Icon(
                                        Icons.arrow_right,
                                        color: Colors.grey,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  height: 32,
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: currentAccent,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () async {
                                      await _radio.toggle();
                                      setState(() {});
                                    },
                                    child: _radio.isLoading
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            _radio.isPlaying
                                                ? "⏹ Detener"
                                                : "▶ Reproducir",
                                            style: TextStyle(
                                              fontSize: 12 * scale,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Alarma
                        Expanded(
                          flex: 10,
                          child: InteractiveCard(
                            cardBg: cardBg,
                            cardBorder: cardBorder,
                            onTap: _showAlarmSunriseModal,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "ALARMA",
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 10 * scale,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    if (_settings.sunriseEnabled)
                                      const Icon(
                                        Icons.wb_sunny_rounded,
                                        size: 12,
                                        color: Colors.amber,
                                      ),
                                  ],
                                ),
                                Text(
                                  "${_settings.alarmHour.toString().padLeft(2, '0')}:${_settings.alarmMinute.toString().padLeft(2, '0')}",
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 22 * scale,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _settings.sunriseEnabled
                                      ? "Amanecer activo ›"
                                      : "Normal ›",
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 11 * scale,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // AMANECER (preview manual o efecto real previo a la alarma).
            // CORREGIDO: antes era un AnimatedContainer cuya decoración ya
            // venía "terminada", así que aparecía de golpe sin animar. Ahora
            // _SunriseOverlay interpola la opacidad de 0 a 1 durante todo el
            // tiempo que queda hasta la alarma (o la duración de la prueba).
            if (_isPreviewingSunrise || _isSunriseActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: _SunriseOverlay(
                    color: _settings.sunriseColor,
                    preview: _isPreviewingSunrise,
                    duration: _isPreviewingSunrise
                        ? Duration(
                            seconds: _settings.sunriseDurationSeconds.clamp(
                              5,
                              30,
                            ),
                          )
                        : null,
                    progress: !_isPreviewingSunrise && _sunriseEnd != null
                        ? (() {
                            final totalSec =
                                _settings.sunriseMinutesBefore.clamp(1, 120) *
                                60;
                            final remSec = _sunriseEnd!
                                .difference(DateTime.now())
                                .inSeconds;
                            return (1.0 - (remSec / totalSec)).clamp(0.0, 1.0);
                          })()
                        : null,
                  ),
                ),
              ),

            // REPOSO NOCTURNO
            // NUEVO 5: toque simple o doble toque para despertar.
            if (_isScreensaver)
              GestureDetector(
                onTap: _settings.screensaverDoubleTap
                    ? null
                    : () => setState(() => _isScreensaver = false),
                onDoubleTap: _settings.screensaverDoubleTap
                    ? () => setState(() => _isScreensaver = false)
                    : null,
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _timeString,
                          style: TextStyle(
                            fontSize: _settings.clockFontSize * 0.8,
                            fontWeight: _clockWeight,
                            color: const Color(0xFF550A0A),
                            letterSpacing: -2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Toca para despertar",
                          style: TextStyle(
                            color: Color(0xFF330505),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ALARMA DESPERTADOR
            if (_isAlarmRinging)
              Container(
                color: Colors.black.withValues(alpha: 0.94),
                width: double.infinity,
                height: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "☀️ ¡BUENOS DÍAS!",
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "${_settings.alarmHour.toString().padLeft(2, '0')}:${_settings.alarmMinute.toString().padLeft(2, '0')}",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 80 * scale,
                        fontWeight: _clockWeight,
                      ),
                    ),
                    Text(
                      _settings.alarmSound == 'beep'
                          ? "Sonando: pitido local"
                          : "Sonando: ${_radio.currentStation.name}",
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _snoozeAlarm,
                          child: Text(
                            "Posponer ${_settings.snoozeMinutes} min",
                          ),
                        ),
                        const SizedBox(width: 20),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _stopAlarm,
                          child: const Text(
                            "Apagar Alarma",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Overlay del simulador de amanecer: interpola un degradado cálido de
/// transparente a plena luz durante [duration].
///
/// Es un [StatefulWidget] para que el [Tween] sea una instancia estable:
/// así los `setState` del reloj (cada segundo) reconstruyen el árbol sin
/// reiniciar la animación.
class _SunriseOverlay extends StatefulWidget {
  final Color color;
  final bool preview;
  final Duration? duration;
  final double? progress;

  const _SunriseOverlay({
    required this.color,
    required this.preview,
    this.duration,
    this.progress,
  });

  @override
  State<_SunriseOverlay> createState() => _SunriseOverlayState();
}

class _SunriseOverlayState extends State<_SunriseOverlay> {
  final Tween<double> _tween = Tween<double>(begin: 0, end: 1);

  @override
  Widget build(BuildContext context) {
    if (widget.progress != null) {
      return _buildDecorated(widget.progress!);
    }
    final dur = widget.duration ?? const Duration(seconds: 5);
    final duration = dur < const Duration(seconds: 5)
        ? const Duration(seconds: 5)
        : dur;
    return TweenAnimationBuilder<double>(
      tween: _tween,
      duration: duration,
      curve: Curves.easeIn,
      builder: (context, t, _) => _buildDecorated(t),
    );
  }

  Widget _buildDecorated(double t) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            const Color(0xFFFFF7ED).withValues(alpha: 0.90 * t),
            widget.color.withValues(alpha: 0.75 * t),
            Colors.black.withValues(alpha: 0.15 + 0.75 * t),
          ],
        ),
      ),
      child: widget.preview
          ? const Center(
              child: Text(
                "🌅 Simulando Amanecer...",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                ),
              ),
            )
          : null,
    );
  }
}
