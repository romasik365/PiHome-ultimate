import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/radio_station.dart';
import '../services/app_log.dart';
import '../services/bluetooth_service.dart';
import '../services/geocoding_service.dart';
import '../services/radio_directory_service.dart';
import '../services/radio_service.dart';
import '../services/wifi_service.dart';
import '../widgets/virtual_keyboard.dart';

/// Pantalla de ajustes con **estilo Android** (Material 3): una lista de
/// secciones y paginas de detalle por seccion. Todos los cambios se aplican
/// en vivo mediante [SettingsScreen.onChanged] y la pantalla principal no
/// cambia de diseno.
class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final RadioService radio;
  final ValueChanged<AppSettings> onChanged;
  final VoidCallback? onPreviewSunrise;
  final VoidCallback? onPreviewScreensaver;
  final VoidCallback? onRefreshWeather;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.radio,
    required this.onChanged,
    this.onPreviewSunrise,
    this.onPreviewScreensaver,
    this.onRefreshWeather,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

typedef DetailBuilder = Widget Function(
  BuildContext context,
  AppSettings draft,
  ValueChanged<AppSettings> apply,
);

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<Color> _palette = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
  ];

  static const List<Color> _sunrisePalette = [
    Color(0xFFF97316),
    Color(0xFFFB923C),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFF472B6),
    Color(0xFF8B5CF6),
  ];

  static const List<String> _fonts = [
    '',
    'Roboto',
    'Arial',
    'Segoe UI',
    'Helvetica',
    'Verdana',
    'Tahoma',
    'Trebuchet MS',
    'Georgia',
    'Times New Roman',
    'Courier New',
    'Consolas',
    'DejaVu Sans',
    'Liberation Sans',
    'Noto Sans',
    'Ubuntu',
  ];

  static String _fontLabel(String f) =>
      f.isEmpty ? 'Predeterminada (Roboto)' : f;

  late AppSettings _current;

  @override
  void initState() {
    super.initState();
    _current = widget.settings;
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _current = widget.settings;
    }
  }

  void _handleChanged(AppSettings next) {
    setState(() => _current = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final s = _current;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _tile(
            Icons.monitor_outlined,
            Colors.indigo,
            'Pantalla',
            'Acento, noche, reposo y tarjetas',
            _pantallaBody,
          ),
          _tile(
            Icons.text_fields_outlined,
            Colors.teal,
            'Tipografía',
            '${_fontLabel(s.fontFamily)} · reloj ${s.clockFontSize.round()} px',
            _tipografiaBody,
          ),
          _tile(
            Icons.schedule_outlined,
            Colors.deepOrange,
            'Reloj y fecha',
            _clockSubtitle(s),
            _relojBody,
          ),
          _tile(
            Icons.cloud_outlined,
            Colors.lightBlue,
            'Clima',
            '${s.weatherLabel} · cada ${s.weatherRefreshMinutes} min',
            _climaBody,
          ),
          _tile(
            Icons.radio_outlined,
            Colors.purple,
            'Radio',
            '${widget.radio.currentStation.name} · ${widget.radio.stations.length} emisoras',
            _radioBody,
          ),
          _tile(
            Icons.wifi_outlined,
            Colors.blue,
            'Red Wi-Fi',
            _wifiSubtitle(_current),
            _wifiBody,
            routeName: '/settings/wifi',
          ),
          _tile(
            Icons.bluetooth_outlined,
            Colors.cyan,
            'Bluetooth',
            _bluetoothSubtitle(_current),
            _bluetoothBody,
            routeName: '/settings/bluetooth',
          ),
          _tile(
            Icons.alarm_outlined,
            Colors.amber,
            'Alarma y amanecer',
            _alarmSubtitle(s),
            _alarmaBody,
          ),
          _tile(
            Icons.receipt_long_outlined,
            Colors.blueGrey,
            'Diagnóstico',
            'Registro de actividad y errores',
            _logsBody,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Restablecer todos los ajustes'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Restablecer ajustes'),
                    content: const Text(
                      'Se perderán todas las personalizaciones. ¿Continuar?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Restablecer'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  // NUEVO: al restablecer, los campos de texto se reconstruyen
                  // con los valores por defecto (si no, seguirian mostrando lo
                  // que habia escrito el usuario).
                  for (final ctl in _textCtrls.values) {
                    ctl.dispose();
                  }
                  _textCtrls.clear();
                  _handleChanged(AppSettings.defaults());
                }
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    Color color,
    String title,
    String subtitle,
    DetailBuilder builder, {
    String? routeName,
  }) {
    void open() {
      // Se registra la ruta para que los iconos de la barra superior puedan
      // abrir directamente WiFi/BT con pushNamed.
      final page = _DetailPage(
        title: title,
        settings: _current,
        onChanged: _handleChanged,
        builder: builder,
      );
      if (routeName != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            settings: RouteSettings(name: routeName),
            builder: (_) => page,
          ),
        );
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      }
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: open,
    );
  }

  String _clockSubtitle(AppSettings s) {
    return [
      s.use24Hour ? '24 h' : '12 h',
      s.showSeconds ? 'con segundos' : 'sin segundos',
      if (!s.showDate) 'sin fecha',
    ].join(' · ');
  }

  String _alarmSubtitle(AppSettings s) {
    if (!s.alarmEnabled) return 'Desactivada';
    final time =
        '${s.alarmHour.toString().padLeft(2, '0')}:${s.alarmMinute.toString().padLeft(2, '0')}';
    final all = [1, 2, 3, 4, 5, 6, 7].every(s.alarmDays.contains);
    final days = all ? 'todos los días' : '${s.alarmDays.length} día(s)/semana';
    return '$time · $days${s.sunriseEnabled ? ' · amanecer' : ''}';
  }

  // ---------- Cuerpos de cada seccion ----------

  Widget _pantallaBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return ListView(
      children: [
        _header('Color de acento'),
        _colorWrap(
          _palette,
          d.accentColor,
          (c) => apply(d.copyWith(accentColor: c)),
        ),
        _header('Modo y reposo'),
        _sw(
          'Modo noche',
          'Paleta roja de bajo brillo',
          d.nightMode,
          (v) => apply(d.copyWith(nightMode: v)),
        ),
        _sw(
          'Reposo automático',
          'Pantalla de reposo al no tocar nada',
          d.screensaverEnabled,
          (v) => apply(d.copyWith(screensaverEnabled: v)),
        ),
        _slider(
          context,
          'Minutos hasta el reposo',
          d.screensaverMinutes.toDouble(),
          1,
          60,
          59,
          '${d.screensaverMinutes} min',
          (v) => apply(d.copyWith(screensaverMinutes: v.round())),
        ),
        _sw(
          'Despertar con doble toque',
          'Si lo desactivas basta un toque',
          d.screensaverDoubleTap,
          (v) => apply(d.copyWith(screensaverDoubleTap: v)),
        ),
        ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: const Text('Probar el reposo ahora'),
          onTap: widget.onPreviewScreensaver,
        ),
        _header('Tarjetas inferiores'),
        _slider(
          context,
          'Alto de las tarjetas',
          d.cardHeight,
          90,
          160,
          70,
          '${d.cardHeight.round()} px',
          (v) => apply(d.copyWith(cardHeight: v)),
        ),
        _slider(
          context,
          'Texto de las tarjetas',
          d.cardTextScale,
          0.8,
          1.6,
          16,
          '${(d.cardTextScale * 100).round()} %',
          (v) => apply(d.copyWith(cardTextScale: v)),
        ),
        _header('Barra superior'),
        _sw(
          'Iconos Wi-Fi / Bluetooth',
          'Si lo desactivas se ocultan de la pantalla principal',
          d.showConnectivityIcons,
          (v) => apply(d.copyWith(showConnectivityIcons: v)),
        ),
        _header('Animación de arranque'),
        _sw(
          'Mostrar animación de arranque',
          'Logotipo latiendo mientras el sistema se inicia',
          d.bootAnimation,
          (v) => apply(d.copyWith(bootAnimation: v)),
        ),
        if (d.bootAnimation)
          _slider(
            context,
            'Duración mínima',
            d.bootMinDurationMs.toDouble(),
            400,
            3000,
            100,
            '${(d.bootMinDurationMs / 1000).toStringAsFixed(1)} s',
            (v) => apply(d.copyWith(bootMinDurationMs: v.round())),
          ),
        _header('Tamaño de la ventana'),
        _slider(
          context,
          'Ancho',
          d.windowWidth,
          600,
          1920,
          null,
          '${d.windowWidth.round()} px',
          (v) => apply(d.copyWith(windowWidth: v)),
        ),
        _slider(
          context,
          'Alto',
          d.windowHeight,
          400,
          1200,
          null,
          '${d.windowHeight.round()} px',
          (v) => apply(d.copyWith(windowHeight: v)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _tipografiaBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return ListView(
      children: [
        _header('Fuente'),
        _drop<String>(
          context,
          'Familia tipográfica',
          d.fontFamily,
          _fonts,
          _fontLabel,
          (f) => apply(d.copyWith(fontFamily: f)),
        ),
        _drop<int>(
          context,
          'Grosor del reloj',
          d.clockWeight,
          const [100, 200, 300, 400, 500, 600, 700, 800],
          (w) => 'w$w',
          (w) => apply(d.copyWith(clockWeight: w)),
        ),
        _header('Tamaños'),
        _slider(
          context,
          'Tamaño del reloj',
          d.clockFontSize,
          60,
          190,
          130,
          '${d.clockFontSize.round()} px',
          (v) => apply(d.copyWith(clockFontSize: v)),
        ),
        _slider(
          context,
          'Tamaño de la fecha',
          d.dateFontSize,
          10,
          34,
          24,
          '${d.dateFontSize.round()} px',
          (v) => apply(d.copyWith(dateFontSize: v)),
        ),
        _header('Vista previa'),
        _preview(context, d),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _preview(BuildContext context, AppSettings d) {
    final now = TimeOfDay.now();
    final h12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final time = d.use24Hour
        ? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
        : '${h12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? 'AM' : 'PM'}';
    final weight = FontWeight.values.firstWhere(
      (w) => w.value == d.clockWeight,
      orElse: () => FontWeight.w200,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              time,
              style: TextStyle(
                fontSize: d.clockFontSize * 0.32,
                fontWeight: weight,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Miércoles, 14 de Septiembre',
              style: TextStyle(fontSize: d.dateFontSize * 0.8),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _miniCard('CLIMA', '18°C ☀️', d.cardTextScale),
                _miniCard('STREAMING', 'Kiss FM', d.cardTextScale),
                _miniCard('ALARMA', '07:00', d.cardTextScale),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniCard(String title, String value, double scale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 9 * scale,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _relojBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return ListView(
      children: [
        _header('Formato'),
        _sw(
          'Mostrar segundos',
          null,
          d.showSeconds,
          (v) => apply(d.copyWith(showSeconds: v)),
        ),
        _sw(
          'Formato de 24 horas',
          'Desactívalo para usar AM/PM',
          d.use24Hour,
          (v) => apply(d.copyWith(use24Hour: v)),
        ),
        _sw(
          'Mostrar la fecha',
          null,
          d.showDate,
          (v) => apply(d.copyWith(showDate: v)),
        ),
        _header('Textos en pantalla'),
        _text(
          'Etiqueta de ubicación',
          d.locationLabel,
          (v) => apply(d.copyWith(locationLabel: v)),
        ),
        _text(
          'Nombre del clima',
          d.weatherLabel,
          (v) => apply(d.copyWith(weatherLabel: v)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _climaBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return ListView(
      children: [
        _WeatherBody(draft: d, apply: apply),
        _header('Unidades'),
        _drop<String>(
          context,
          'Temperatura',
          d.temperatureUnit,
          const ['C', 'F'],
          (u) => u == 'F' ? 'Fahrenheit (°F)' : 'Celsius (°C)',
          (u) => apply(d.copyWith(temperatureUnit: u)),
        ),
        _drop<String>(
          context,
          'Viento',
          d.windUnit,
          const ['kmh', 'mph', 'ms'],
          (u) => u == 'mph'
              ? 'Millas/h (mph)'
              : u == 'ms'
              ? 'Metros/s (m/s)'
              : 'Kilómetros/h (km/h)',
          (u) => apply(d.copyWith(windUnit: u)),
        ),
        _header('Actualización'),
        _slider(
          context,
          'Cada cuántos minutos',
          d.weatherRefreshMinutes.toDouble(),
          5,
          120,
          23,
          '${d.weatherRefreshMinutes} min',
          (v) => apply(d.copyWith(weatherRefreshMinutes: v.round())),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Actualizar el clima ahora'),
          onTap: widget.onRefreshWeather,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ---------- Subtítulos auxiliares ----------

  String _wifiSubtitle(AppSettings s) {
    if (!s.wifiEnabled) return 'Desactivado';
    return s.wifiSsid != null
        ? 'Conectado a ${s.wifiSsid}'
        : 'Activado, sin red';
  }

  String _bluetoothSubtitle(AppSettings s) {
    if (!s.bluetoothEnabled) return 'Desactivado';
    return 'Activado · ${s.pairedBluetoothIds.length} emparejados';
  }

  // ---------- Cuerpos: radio, WiFi, Bluetooth ----------

  Widget _radioBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return _RadioBodyEnhanced(draft: d, apply: apply, radio: widget.radio);
  }

  Widget _wifiBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return _WifiBody(draft: d, apply: apply, wifiService: WifiService());
  }

  Widget _bluetoothBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return _BluetoothBody(
      draft: d,
      apply: apply,
      btService: BluetoothService(),
    );
  }

  Widget _logsBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    return const _LogsBody();
  }

  Widget _alarmaBody(
    BuildContext context,
    AppSettings d,
    ValueChanged<AppSettings> apply,
  ) {
    const dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return ListView(
      children: [
        _header('Alarma'),
        _sw(
          'Alarma activada',
          'Suena con la emisora seleccionada',
          d.alarmEnabled,
          (v) => apply(d.copyWith(alarmEnabled: v)),
        ),
        ListTile(
          leading: const Icon(Icons.access_time),
          title: const Text('Hora de la alarma'),
          trailing: Text(
            '${d.alarmHour.toString().padLeft(2, '0')}:${d.alarmMinute.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: d.alarmHour, minute: d.alarmMinute),
            );
            if (picked != null) {
              apply(
                d.copyWith(alarmHour: picked.hour, alarmMinute: picked.minute),
              );
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (var i = 1; i <= 7; i++)
                FilterChip(
                  label: Text(dayLabels[i - 1]),
                  selected: d.alarmDays.contains(i),
                  onSelected: (on) {
                    final days = [...d.alarmDays];
                    on ? days.add(i) : days.remove(i);
                    days.sort();
                    apply(d.copyWith(alarmDays: days));
                  },
                ),
            ],
          ),
        ),
        _drop<String>(
          context,
          'Sonido',
          d.alarmSound,
          const ['radio', 'beep'],
          (s) => s == 'beep' ? 'Pitido local' : 'Emisora de radio',
          (s) => apply(d.copyWith(alarmSound: s)),
        ),
        _slider(
          context,
          'Minutos para posponer',
          d.snoozeMinutes.toDouble(),
          1,
          30,
          29,
          '${d.snoozeMinutes} min',
          (v) => apply(d.copyWith(snoozeMinutes: v.round())),
        ),
        _header('Simulador de amanecer'),
        _sw(
          'Activar amanecer',
          'Ilumina la pantalla antes de la alarma',
          d.sunriseEnabled,
          (v) => apply(d.copyWith(sunriseEnabled: v)),
        ),
        _slider(
          context,
          'Minutos antes de la alarma',
          d.sunriseMinutesBefore.toDouble(),
          1,
          45,
          44,
          '${d.sunriseMinutesBefore} min',
          (v) => apply(d.copyWith(sunriseMinutesBefore: v.round())),
        ),
        _slider(
          context,
          'Duración del efecto',
          d.sunriseDurationSeconds.toDouble(),
          5,
          60,
          null,
          '${d.sunriseDurationSeconds} s',
          (v) => apply(d.copyWith(sunriseDurationSeconds: v.round())),
        ),
        _colorWrap(
          _sunrisePalette,
          d.sunriseColor,
          (c) => apply(d.copyWith(sunriseColor: c)),
        ),
        ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: const Text('Probar el efecto amanecer'),
          onTap: widget.onPreviewSunrise,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ---------- Widgets reutilizables ----------

  Widget _header(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _sw(
    String title,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _slider(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    int? divisions,
    String valueLabel,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              Text(
                valueLabel,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _drop<T>(
    BuildContext context,
    String label,
    T value,
    List<T> items,
    String Function(T) labelOf,
    ValueChanged<T> onChanged,
  ) {
    final selected = items.contains(value) ? value : items.first;
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: DropdownButton<T>(
        value: selected,
        underline: const SizedBox.shrink(),
        items: items
            .map((e) => DropdownMenuItem<T>(value: e, child: Text(labelOf(e))))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  final Map<String, TextEditingController> _textCtrls = {};

  Widget _text(String label, String value, ValueChanged<String> onChanged) {
    final ctl = _textCtrls.putIfAbsent(
      label,
      () => TextEditingController(text: value),
    );
    if (ctl.text != value && !FocusScope.of(context).hasFocus) {
      ctl.text = value;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: ctl,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final ctl in _textCtrls.values) {
      ctl.dispose();
    }
    super.dispose();
  }

  Widget _colorWrap(
    List<Color> palette,
    Color selected,
    ValueChanged<Color> onPick,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: palette.map((c) {
          final isSel = c.toARGB32() == selected.toARGB32();
          return GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? Colors.white : Colors.transparent,
                  width: 3,
                ),
                boxShadow: isSel
                    ? [
                        BoxShadow(
                          color: c.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: isSel
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------- Pagina de detalle generica ----------

/// Subpagina de una seccion: mantiene un borrador local de [AppSettings] y
/// aplica cada cambio en vivo a traves de [onChanged].
class _DetailPage extends StatefulWidget {
  final String title;
  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  final DetailBuilder builder;

  const _DetailPage({
    required this.title,
    required this.settings,
    required this.onChanged,
    required this.builder,
  });

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> {
  late AppSettings _draft = widget.settings;

  @override
  void didUpdateWidget(covariant _DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _draft = widget.settings;
    }
  }

  void _apply(AppSettings next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: widget.builder(context, _draft, _apply),
    );
  }
}

// ---------- Clima: busqueda de localidades ----------

/// Buscador de localidades (opcion A): caja de busqueda con resultados en
/// vivo de la API de Open-Meteo + ubicaciones guardadas + modo avanzado con
/// lat/lon/zona horaria.
class _WeatherBody extends StatefulWidget {
  final AppSettings draft;
  final ValueChanged<AppSettings> apply;

  const _WeatherBody({required this.draft, required this.apply});

  @override
  State<_WeatherBody> createState() => _WeatherBodyState();
}

class _WeatherBodyState extends State<_WeatherBody> {
  final TextEditingController _searchCtl = TextEditingController();
  List<Place> _results = [];
  bool _searching = false;
  String? _error;
  bool _advanced = false;

  /// CORREGIDO: debounce para no lanzar una petición HTTP por cada tecla.
  Timer? _debounce;
  Timer? _advDebounce;
  late final TextEditingController _latCtl;
  late final TextEditingController _lonCtl;
  late final TextEditingController _tzCtl;

  @override
  void initState() {
    super.initState();
    _latCtl = TextEditingController(text: widget.draft.latitude.toString());
    _lonCtl = TextEditingController(text: widget.draft.longitude.toString());
    _tzCtl = TextEditingController(text: widget.draft.timezone);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _advDebounce?.cancel();
    _searchCtl.dispose();
    _latCtl.dispose();
    _lonCtl.dispose();
    _tzCtl.dispose();
    super.dispose();
  }

  /// Se llama en cada tecla: espera 350 ms sin escribir antes de buscar.
  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _performSearch(query),
    );
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().length < 2) return;
    final places = await GeocodingService.search(query: query);
    if (!mounted) return;
    setState(() {
      _results = places;
      _error = places.isEmpty ? 'Sin resultados para "$query"' : null;
      _searching = false;
    });
  }

  void _pickPlace(Place p) {
    _latCtl.text = p.latitude.toString();
    _lonCtl.text = p.longitude.toString();
    _tzCtl.text = p.timezone ?? 'Europe/Madrid';
    widget.apply(
      widget.draft.copyWith(
        latitude: p.latitude,
        longitude: p.longitude,
        timezone: p.timezone ?? 'Europe/Madrid',
        weatherLabel: p.name,
        locationLabel: '📍 ${p.name}',
      ),
    );
    FocusScope.of(context).unfocus();
    setState(() => _results = []);
  }

  List<Map<String, dynamic>> get _saved => widget.draft.savedLocations;

  void _saveCurrent() {
    final d = widget.draft;
    final entry = {
      'label': d.weatherLabel,
      'lat': d.latitude,
      'lon': d.longitude,
      'tz': d.timezone,
    };
    if (_saved.any((m) => m['label'] == entry['label'])) return;
    widget.apply(d.copyWith(savedLocations: [..._saved, entry]));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Buscar localidad'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              hintText: 'Escribe una ciudad o pueblo…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(_error!, style: const TextStyle(fontSize: 12)),
          ),
        for (final p in _results)
          ListTile(
            dense: true,
            leading: const Icon(Icons.location_on_outlined, size: 20),
            title: Text(p.name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(p.label, style: const TextStyle(fontSize: 11)),
            onTap: () => _pickPlace(p),
          ),
        _section('Ubicaciones guardadas'),
        if (_saved.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Aún no has guardado ninguna ubicación.',
              style: TextStyle(fontSize: 12),
            ),
          )
        else
          for (final m in _saved)
            ListTile(
              dense: true,
              leading: const Icon(Icons.bookmark_border, size: 20),
              title: Text(
                '${m['label']}',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                '${m['lat']}, ${m['lon']}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => widget.apply(
                  d.copyWith(
                    savedLocations: _saved
                        .where((e) => e['label'] != m['label'])
                        .toList(),
                  ),
                ),
              ),
              onTap: () {
                _latCtl.text = '${m['lat']}';
                _lonCtl.text = '${m['lon']}';
                _tzCtl.text = '${m['tz']}';
                widget.apply(
                  d.copyWith(
                    latitude: (m['lat'] as num).toDouble(),
                    longitude: (m['lon'] as num).toDouble(),
                    timezone: '${m['tz']}',
                    weatherLabel: '${m['label']}',
                    locationLabel: '📍 ${m['label']}',
                  ),
                );
              },
            ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextButton.icon(
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Guardar la ubicación actual'),
            onPressed: _saveCurrent,
          ),
        ),
        _section('Ubicación actual'),
        ListTile(
          dense: true,
          leading: const Icon(Icons.place, size: 20),
          title: Text(d.weatherLabel, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            'lat ${d.latitude.toStringAsFixed(4)} · lon ${d.longitude.toStringAsFixed(4)} · ${d.timezone}',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Modo avanzado', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            'Editar coordenadas a mano',
            style: TextStyle(fontSize: 11),
          ),
          value: _advanced,
          onChanged: (v) => setState(() => _advanced = v),
        ),
        if (_advanced) ...[
          _advField(
            'Latitud',
            _latCtl,
            (v) => _num(
              v,
              (x) => widget.apply(widget.draft.copyWith(latitude: x)),
            ),
          ),
          _advField(
            'Longitud',
            _lonCtl,
            (v) => _num(
              v,
              (x) => widget.apply(widget.draft.copyWith(longitude: x)),
            ),
          ),
          _advField(
            'Zona horaria',
            _tzCtl,
            (v) => widget.apply(widget.draft.copyWith(timezone: v)),
          ),
        ],
      ],
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _advField(
    String label,
    TextEditingController ctl,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: ctl,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void _num(String text, ValueChanged<double> apply) {
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value != null) {
      _advDebounce?.cancel();
      _advDebounce = Timer(const Duration(milliseconds: 400), () {
        apply(value);
      });
    }
  }
}

// ---------- Radio: directorio por paises ----------

/// Directorio de emisoras por paises: elige pais, ve las emisoras mas
/// escuchadas y marca con las que quieres en la rotacion de la tarjeta
/// STREAMING (opcion A: los favoritos sustituyen a las de fabrica).
class _RadioBody extends StatefulWidget {
  final RadioService radio;

  const _RadioBody({required this.radio});

  @override
  State<_RadioBody> createState() => _RadioBodyState();
}

class _RadioBodyState extends State<_RadioBody> {
  List<RadioCountry> _countries = [];
  List<Station> _stations = [];
  String? _selectedCountry;
  bool _loadingCountries = true;
  bool _loadingStations = false;
  String? _error;
  final TextEditingController _filterCtl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  @override
  void dispose() {
    _filterCtl.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    setState(() => _loadingCountries = true);
    try {
      final list = await widget.radio.directory.loadCountries();
      if (!mounted) return;
      setState(() {
        _countries = list;
        _loadingCountries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCountries = false;
        _error = 'No se pudo cargar el directorio: $e';
      });
    }
  }

  Future<void> _loadStations(String cc) async {
    setState(() {
      _selectedCountry = cc;
      _loadingStations = true;
      _error = null;
    });
    try {
      final list = await widget.radio.directory.loadStations(cc);
      if (!mounted) return;
      setState(() {
        _stations = list;
        _loadingStations = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStations = false;
        _error = 'No se pudieron cargar las emisoras: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _miniHeader('Países', primary),
        if (_loadingCountries)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_countries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error ?? 'No se pudo conectar al directorio de radios. Comprueba tu conexión.',
              style: const TextStyle(fontSize: 12),
            ),
          )
        else
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _countries.length,
              itemBuilder: (ctx, i) {
                final c = _countries[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('${c.name} (${c.stationCount})'),
                    selected: c.countryCode == _selectedCountry,
                    onSelected: (_) => _loadStations(c.countryCode),
                  ),
                );
              },
            ),
          ),
        if (_selectedCountry != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _filterCtl,
              decoration: const InputDecoration(
                hintText: 'Filtrar por nombre o género…',
                prefixIcon: Icon(Icons.filter_list),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
          if (_loadingStations)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            ..._stationList(),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Restaurar emisoras de fábrica'),
            onPressed: () {
              widget.radio.resetToDefaults();
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _miniHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: color,
        ),
      ),
    );
  }

  List<Widget> _stationList() {
    final list = _filtered;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          '${list.length} emisoras verificadas',
          style: const TextStyle(fontSize: 11),
        ),
      ),
      for (final st in list.take(40))
        ListTile(
          dense: true,
          leading: const Icon(Icons.radio, size: 20),
          title: Text(
            st.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            [
              st.tags,
              st.codec,
              if (st.bitrate > 0) '${st.bitrate} kbps',
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  widget.radio.isFavorited(st)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 20,
                  color: widget.radio.isFavorited(st) ? Colors.redAccent : null,
                ),
                onPressed: () {
                  widget.radio.toggleFavorite(st);
                  setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow, size: 20),
                onPressed: () {
                  widget.radio.playStation(st);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      if (list.length > 40)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Usa el filtro para ver más…',
            style: TextStyle(fontSize: 11),
          ),
        ),
    ];
  }

  List<Station> get _filtered {
    if (_filter.isEmpty) return _stations;
    return _stations
        .where(
          (s) =>
              s.name.toLowerCase().contains(_filter) ||
              s.tags.toLowerCase().contains(_filter),
        )
        .toList();
  }
}

// ---------------------------------------------------------------------------
// NUEVO: Radio mejorada con favoritas y directorio por país
// ---------------------------------------------------------------------------

class _RadioBodyEnhanced extends StatefulWidget {
  final AppSettings draft;
  final ValueChanged<AppSettings> apply;
  final RadioService radio;

  const _RadioBodyEnhanced({
    required this.draft,
    required this.apply,
    required this.radio,
  });

  @override
  State<_RadioBodyEnhanced> createState() => _RadioBodyEnhancedState();
}

class _RadioBodyEnhancedState extends State<_RadioBodyEnhanced> {
  String _countrySearch = '';
  List<RadioCountry> _countries = [];
  List<Station> _stations = [];
  bool _loadingCountries = false;
  bool _loadingStations = false;
  String? _selectedCountryCode;
  String? _selectedCountryName;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    setState(() => _loadingCountries = true);
    try {
      final list = await widget.radio.directory.loadCountries();
      if (mounted) {
        setState(() {
          _countries = list;
          _loadingCountries = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  List<RadioCountry> get _filteredCountries {
    if (_countrySearch.isEmpty) return [];
    final q = RadioDirectoryService.normalizeSearch(_countrySearch);
    return _countries
        .where((c) {
          final name = RadioDirectoryService.normalizeSearch(c.name);
          return name.contains(q);
        })
        .take(8)
        .toList();
  }

  Future<void> _selectCountry(RadioCountry country) async {
    setState(() {
      _selectedCountryCode = country.countryCode;
      _selectedCountryName = country.name;
      _loadingStations = true;
      _stations = [];
      _countrySearch = '';
    });
    try {
      final list = await widget.radio.directory.loadStations(
        country.countryCode,
      );
      if (mounted) {
        setState(() {
          _stations = list;
          _loadingStations = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  void _toggleFavourite(Station station) {
    final favs = List<String>.from(widget.draft.favouriteStations);
    if (favs.contains(station.name)) {
      favs.remove(station.name);
      widget.apply(widget.draft.copyWith(favouriteStations: favs));
    } else {
      if (favs.length >= 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ya tienes 4 favoritas. Quita una antes de añadir otra.',
            ),
          ),
        );
        return;
      }
      favs.add(station.name);
      widget.apply(widget.draft.copyWith(favouriteStations: favs));
    }
  }

  void _removeFavourite(String name) {
    final favs = List<String>.from(widget.draft.favouriteStations)
      ..remove(name);
    widget.apply(widget.draft.copyWith(favouriteStations: favs));
  }

  Future<void> _openKeyboard() async {
    final result = await showVirtualKeyboard(
      context,
      initial: _countrySearch,
      hint: 'Buscar país...',
    );
    if (result != null && mounted) {
      setState(() {
        _countrySearch = result;
        _selectedCountryCode = null;
        _selectedCountryName = null;
        _stations = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final favs = d.favouriteStations;
    final favFull = favs.length >= 4;
    final names = widget.radio.stations.map((s) => s.name).toList();
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    Widget sectionHeader(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: primary,
        ),
      ),
    );

    return ListView(
      children: [
        // ── FAVORITAS ──────────────────────────────────────────
        sectionHeader('Favoritas (${favs.length}/4)'),
        if (favs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'No hay emisoras favoritas.',
              style: TextStyle(fontSize: 13),
            ),
          )
        else
          ...favs.map(
            (name) => ListTile(
              leading: const Icon(Icons.favorite, color: Colors.red, size: 20),
              title: Text(name, style: const TextStyle(fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Quitar de favoritas',
                onPressed: () => _removeFavourite(name),
              ),
            ),
          ),
        if (favFull)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text(
              'Quita una favorita para poder añadir otra.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),

        // ── REPRODUCCIÓN ───────────────────────────────────────
        sectionHeader('Reproducción'),
        SwitchListTile(
          title: const Text(
            'Reproducir al arrancar',
            style: TextStyle(fontSize: 14),
          ),
          subtitle: const Text(
            'La radio empieza sola al abrir la app',
            style: TextStyle(fontSize: 12),
          ),
          value: d.autoplayRadio,
          onChanged: (v) => widget.apply(d.copyWith(autoplayRadio: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Volumen', style: TextStyle(fontSize: 14)),
                  Text(
                    '${(d.volume * 100).round()} %',
                    style: TextStyle(
                      color: primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                value: d.volume.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                divisions: 40,
                onChanged: (v) {
                  widget.apply(d.copyWith(volume: v));
                  widget.radio.setVolume(v);
                },
              ),
            ],
          ),
        ),
        ListTile(
          title: const Text('Emisora inicial', style: TextStyle(fontSize: 14)),
          trailing: DropdownButton<String>(
            value: names.contains(widget.radio.currentStation.name)
                ? widget.radio.currentStation.name
                : names.first,
            underline: const SizedBox.shrink(),
            items: names
                .map(
                  (n) => DropdownMenuItem(
                    value: n,
                    child: Text(n, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (name) {
              if (name != null) {
                widget.apply(d.copyWith(stationIndex: names.indexOf(name)));
              }
            },
          ),
        ),

        // ── DIRECTORIO POR PAÍS ────────────────────────────────
        sectionHeader('Directorio por país'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: InkWell(
            onTap: _openKeyboard,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _countrySearch.isEmpty
                          ? 'Toca para buscar un país...'
                          : _countrySearch,
                      style: TextStyle(
                        fontSize: 15,
                        color: _countrySearch.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_outlined, size: 20),
                ],
              ),
            ),
          ),
        ),
        if (_countrySearch.isNotEmpty && _selectedCountryCode == null) ...[
          if (_loadingCountries)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_filteredCountries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No se encontró ningún país.',
                style: TextStyle(fontSize: 13),
              ),
            )
          else
            ..._filteredCountries.map(
              (c) => ListTile(
                dense: true,
                leading: const Icon(Icons.flag_outlined, size: 18),
                title: Text(c.name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '${c.stationCount} emisoras',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => _selectCountry(c),
              ),
            ),
        ],
        if (_selectedCountryName != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.flag, size: 16),
                const SizedBox(width: 8),
                Text(
                  _selectedCountryName!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _selectedCountryCode = null;
                    _selectedCountryName = null;
                    _stations = [];
                    _countrySearch = '';
                  }),
                  child: const Text('Cambiar'),
                ),
              ],
            ),
          ),
          if (_loadingStations)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_stations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No se encontraron emisoras.',
                style: TextStyle(fontSize: 13),
              ),
            )
          else
            ..._stations.take(30).map((station) {
              final isFav = favs.contains(station.name);
              return ListTile(
                dense: true,
                title: Text(
                  station.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    station.tags,
                    station.codec,
                    if (station.bitrate > 0) '${station.bitrate} kbps',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? Colors.red : null,
                    size: 20,
                  ),
                  tooltip: isFav
                      ? 'Quitar de favoritas'
                      : (favFull ? 'Máximo 4 favoritas' : 'Añadir a favoritas'),
                  onPressed: () => _toggleFavourite(station),
                ),
              );
            }),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// NUEVO: Ajustes Wi-Fi
// ---------------------------------------------------------------------------

/// Construye el cuerpo de la página Wi-Fi. Público para las rutas nombradas
/// `/settings/wifi` (los iconos de la barra superior lo usan).
Widget buildWifiSettingsBody(
  BuildContext context,
  AppSettings d,
  ValueChanged<AppSettings> apply,
) => _WifiBody(draft: d, apply: apply, wifiService: WifiService());

/// Construye el cuerpo de la página Bluetooth. Público para las rutas
/// nombradas `/settings/bluetooth`.
Widget buildBluetoothSettingsBody(
  BuildContext context,
  AppSettings d,
  ValueChanged<AppSettings> apply,
) => _BluetoothBody(draft: d, apply: apply, btService: BluetoothService());

class _WifiBody extends StatefulWidget {
  final AppSettings draft;
  final ValueChanged<AppSettings> apply;
  final WifiService wifiService;

  const _WifiBody({
    required this.draft,
    required this.apply,
    required this.wifiService,
  });

  @override
  State<_WifiBody> createState() => _WifiBodyState();
}

class _WifiBodyState extends State<_WifiBody> {
  List<WifiNetwork>? _networks;
  bool _scanning = false;
  String? _connecting;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.draft.wifiEnabled) _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final nets = await widget.wifiService.scan();
      if (mounted) {
        setState(() {
          _networks = nets;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _connect(WifiNetwork net) async {
    String password = '';
    if (net.secured) {
      final pwd = await showVirtualKeyboard(
        context,
        hint: 'Contraseña de ${net.ssid}',
        obscure: true,
        initial: net.ssid == widget.draft.wifiSsid
            ? (widget.draft.wifiPassword ?? '')
            : '',
      );
      if (pwd == null) return;
      password = pwd;
    }
    setState(() => _connecting = net.ssid);
    final ok = await widget.wifiService.connect(net.ssid, password: password);
    if (!mounted) return;
    setState(() => _connecting = null);
    if (ok) {
      widget.apply(
        widget.draft.copyWith(
          wifiSsid: net.ssid,
          wifiPassword: net.secured ? password : null,
          wifiEnabled: true,
        ),
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Conectado a ${net.ssid}')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al conectar a ${net.ssid}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Wi-Fi activado'),
          value: d.wifiEnabled,
          onChanged: (v) {
            widget.apply(d.copyWith(wifiEnabled: v));
            widget.wifiService.toggle(v);
            if (v) _scan();
          },
        ),
        if (d.wifiEnabled) ...[
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Buscar redes'),
            onTap: _scanning ? null : _scan,
            trailing: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (_networks != null)
            ..._networks!.map((net) {
              final isConnected = net.ssid == d.wifiSsid;
              return ListTile(
                leading: Icon(
                  net.secured ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 20,
                ),
                title: Text(net.ssid),
                subtitle: Text(
                  '${net.signalStrength}%  ·  ${net.secured ? "Segura" : "Abierta"}',
                ),
                trailing: _connecting == net.ssid
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : isConnected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: isConnected ? null : () => _connect(net),
              );
            }),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// NUEVO: Ajustes Bluetooth
// ---------------------------------------------------------------------------

class _BluetoothBody extends StatefulWidget {
  final AppSettings draft;
  final ValueChanged<AppSettings> apply;
  final BluetoothService btService;

  const _BluetoothBody({
    required this.draft,
    required this.apply,
    required this.btService,
  });

  @override
  State<_BluetoothBody> createState() => _BluetoothBodyState();
}

class _BluetoothBodyState extends State<_BluetoothBody> {
  List<BluetoothDevice>? _devices;
  bool _scanning = false;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    if (widget.draft.bluetoothEnabled) _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
    });
    try {
      final devs = await widget.btService.scan();
      if (mounted) {
        setState(() {
          _devices = devs;
          _scanning = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connectDevice(BluetoothDevice dev) async {
    setState(() => _connecting = dev.mac);
    bool ok;
    if (!dev.paired) {
      ok = await widget.btService.pair(dev.mac);
      if (ok) ok = await widget.btService.connect(dev.mac);
    } else {
      ok = await widget.btService.connect(dev.mac);
    }
    if (!mounted) return;
    setState(() => _connecting = null);
    if (ok) {
      final newIds = List<String>.from(widget.draft.pairedBluetoothIds);
      if (!newIds.contains(dev.mac)) newIds.add(dev.mac);
      widget.apply(widget.draft.copyWith(pairedBluetoothIds: newIds));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Conectado a ${dev.name}')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al conectar a ${dev.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Bluetooth activado'),
          value: d.bluetoothEnabled,
          onChanged: (v) {
            widget.apply(d.copyWith(bluetoothEnabled: v));
            widget.btService.toggle(v);
            if (v) _scan();
          },
        ),
        if (d.bluetoothEnabled) ...[
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Buscar dispositivos'),
            onTap: _scanning ? null : _scan,
            trailing: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          if (_devices != null)
            ..._devices!.map((dev) {
              final isPaired = d.pairedBluetoothIds.contains(dev.mac);
              return ListTile(
                leading: Icon(
                  isPaired ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: isPaired ? Colors.blue : null,
                ),
                title: Text(dev.name),
                subtitle: Text(dev.mac + (isPaired ? '  ·  Emparejado' : '')),
                trailing: _connecting == dev.mac
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : isPaired
                    ? const Icon(Icons.check_circle, color: Colors.blue)
                    : null,
                onTap: isPaired ? null : () => _connectDevice(dev),
              );
            }),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Página de diagnóstico: muestra el registro de actividad y errores de la app
/// y permite refrescarlo, copiarlo o borrarlo.
///
/// Es clave en un kiosco sin consola: si algo falla, aquí queda la traza y la
/// ruta del fichero de log.
class _LogsBody extends StatefulWidget {
  const _LogsBody();

  @override
  State<_LogsBody> createState() => _LogsBodyState();
}

class _LogsBodyState extends State<_LogsBody> {
  List<String> _lines = const [];
  int _maxLines = 200;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _lines = AppLog.readTail(maxLines: _maxLines));
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar el registro'),
        content: const Text(
          'Se eliminarán todos los ficheros de log. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    AppLog.clear();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _lines.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Text(
            'REGISTRO DE ACTIVIDAD',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        SelectableText(
          'Fichero: ${AppLog.logFilePath()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Refrescar'),
            ),
            OutlinedButton.icon(
              onPressed: isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: _lines.join('\n')),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Registro copiado')),
                      );
                    },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
            OutlinedButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Borrar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButton<int>(
          value: _maxLines,
          items: const [50, 200, 500, 1000]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v líneas')))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            _maxLines = v;
            _reload();
          },
        ),
        const SizedBox(height: 12),
        if (isEmpty)
          const Text('Todavía no hay actividad registrada.')
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: SelectableText(
              _lines.join('\n'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
