import 'dart:async';

import 'package:flutter/material.dart';

/// Reloj (y fecha) que se actualiza **solo él** cada segundo.
///
/// Antes el tick de 1 s llamaba a `setState` en la pantalla completa: en la
/// Raspberry Pi 3B eso reconstruía y volvía a pintar todo el panel (gradiente
/// de fondo, tarjetas, badges, sombras) cada segundo, con el texto del reloj
/// re-rasterizado a cada vuelta. Con el reloj aislado el resto del árbol no se
/// toca y, además, va dentro de un [RepaintBoundary]: es la única capa que se
/// vuelve a pintar. Es la diferencia entre un panel fluido y uno a tirones en
/// el Pi 3B, donde cada píxel cuenta.
class ClockText extends StatefulWidget {
  const ClockText({
    super.key,
    required this.use24Hour,
    required this.showSeconds,
    this.timeStyle,
    this.dateStyle,
    this.dateGap = 4,
  });

  /// Formato de 24 h (si es false se añade " AM"/" PM").
  final bool use24Hour;

  /// Muestra los segundos (repinta cada segundo; sin ellos, cada minuto).
  final bool showSeconds;

  /// Estilo del reloj. Si es null se usa uno neutro.
  final TextStyle? timeStyle;

  /// Estilo de la fecha. Si es null la fecha no se muestra.
  final TextStyle? dateStyle;

  /// Separación entre el reloj y la fecha.
  final double dateGap;

  /// Formatea la hora según los ajustes. Función pura (probable).
  static String formatTime(
    DateTime now, {
    required bool use24Hour,
    required bool showSeconds,
  }) {
    final hourValue = use24Hour
        ? now.hour
        : (now.hour % 12 == 0 ? 12 : now.hour % 12);
    final h = hourValue.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final suffix = use24Hour ? '' : (now.hour < 12 ? ' AM' : ' PM');
    return showSeconds ? '$h:$m:$s$suffix' : '$h:$m$suffix';
  }

  /// Fecha en castellano ("Lunes, 1 de Enero"). Función pura (probable).
  static String formatDate(DateTime now) {
    const weekdays = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return '${weekdays[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}';
  }

  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(ClockText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al cambiar el formato en Ajustes hay que repintar ya, sin esperar al
    // siguiente segundo.
    if (oldWidget.use24Hour != widget.use24Hour ||
        oldWidget.showSeconds != widget.showSeconds) {
      _refresh(force: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  /// Repinta sólo cuando el texto cambia (con `showSeconds: false` esto deja el
  /// reloj repintándose una vez por minuto en lugar de 60 veces).
  void _refresh({bool force = false}) {
    final now = DateTime.now();
    final changed =
        force ||
        ClockText.formatTime(
              now,
              use24Hour: widget.use24Hour,
              showSeconds: widget.showSeconds,
            ) !=
            ClockText.formatTime(
              _now,
              use24Hour: widget.use24Hour,
              showSeconds: widget.showSeconds,
            ) ||
        ClockText.formatDate(now) != ClockText.formatDate(_now);
    if (changed && mounted) setState(() => _now = now);
  }

  @override
  Widget build(BuildContext context) {
    final dateStyle = widget.dateStyle;
    return RepaintBoundary(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text(
                ClockText.formatTime(
                  _now,
                  use24Hour: widget.use24Hour,
                  showSeconds: widget.showSeconds,
                ),
                style: widget.timeStyle,
              ),
            ),
          ),
          if (dateStyle != null) ...[
            SizedBox(height: widget.dateGap),
            Text(ClockText.formatDate(_now), style: dateStyle),
          ],
        ],
      ),
    );
  }
}
