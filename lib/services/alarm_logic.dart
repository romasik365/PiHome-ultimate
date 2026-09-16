/// Lógica pura de la alarma, extraída de la pantalla principal para poder
/// probarla con tests unitarios.
library;

/// Devuelve la próxima ocurrencia de la alarma a partir de [now], o `null`
/// si la alarma está desactivada o no tiene días activos.
///
/// [days] usa la convención de [DateTime.weekday]: lunes = 1 … domingo = 7.
/// Si la alarma de hoy ya ha pasado (o es exactamente ahora), se busca el
/// siguiente día válido dentro de la semana.
DateTime? nextAlarmTime(
  DateTime now, {
  required bool enabled,
  required int hour,
  required int minute,
  required List<int> days,
}) {
  if (!enabled || days.isEmpty) return null;
  final daySet = days.toSet();
  for (var offset = 0; offset <= 7; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    if (!daySet.contains(day.weekday)) continue;
    final t = DateTime(day.year, day.month, day.day, hour, minute);
    // La ocurrencia de hoy sólo vale si aún está en el futuro.
    if (offset == 0 && !now.isBefore(t)) continue;
    return t;
  }
  return null;
}

/// Clave única de una ocurrencia concreta de la alarma (día + hora).
///
/// Se usa para no disparar dos veces la misma alarma aunque el tick del
/// reloj se repita dentro del mismo minuto.
String alarmOccurrenceKey(DateTime t) =>
    '${t.year}-${t.month}-${t.day} ${t.hour}:${t.minute}';

/// ¿Debe sonar la alarma en esta comprobación del reloj?
///
/// Reglas:
///   * Si ya se ha comprobado antes ([previous] != null), suena cuando el reloj
///     **cruza** la hora programada entre las dos comprobaciones (así un tick
///     perdido no la salta).
///   * Si es la primera comprobación ([previous] == null, la app acaba de
///     arrancar), sólo suena si arranca dentro de [grace] después de la hora.
///
/// Así, abrir la app a las 09:00 con la alarma puesta a las 07:00 ya NO la
/// dispara: antes el overlay "¡BUENOS DÍAS!" aparecía nada más arrancar y
/// bloqueaba toda la pantalla.
bool alarmCrossedTime(
  DateTime? previous,
  DateTime now,
  DateTime alarmTime, {
  Duration grace = const Duration(minutes: 2),
}) {
  if (previous == null) {
    return !now.isBefore(alarmTime) && now.difference(alarmTime) < grace;
  }
  return previous.isBefore(alarmTime) && !now.isBefore(alarmTime);
}
