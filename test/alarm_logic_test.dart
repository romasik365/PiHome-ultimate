import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/services/alarm_logic.dart';

void main() {
  // 14/09/2026 es lunes, 08:00.
  final monday8 = DateTime(2026, 9, 14, 8, 0);
  const weekdays = [1, 2, 3, 4, 5];

  test('la fecha de referencia es un lunes', () {
    expect(monday8.weekday, DateTime.monday);
  });

  test('devuelve la alarma de hoy si todavía no ha pasado', () {
    final t = nextAlarmTime(
      monday8,
      enabled: true,
      hour: 9,
      minute: 30,
      days: weekdays,
    );
    expect(t, DateTime(2026, 9, 14, 9, 30));
  });

  test('salta a mañana si la alarma de hoy ya pasó', () {
    final t = nextAlarmTime(
      monday8,
      enabled: true,
      hour: 7,
      minute: 0,
      days: weekdays,
    );
    expect(t, DateTime(2026, 9, 15, 7, 0)); // martes
  });

  test('la alarma a la misma hora exacta cuenta como pasada', () {
    final t = nextAlarmTime(
      DateTime(2026, 9, 14, 7, 0),
      enabled: true,
      hour: 7,
      minute: 0,
      days: weekdays,
    );
    expect(t, DateTime(2026, 9, 15, 7, 0));
  });

  test('salta los días no activos (de viernes al lunes siguiente)', () {
    final friday20 = DateTime(2026, 9, 18, 20, 0); // viernes
    expect(friday20.weekday, DateTime.friday);
    final t = nextAlarmTime(
      friday20,
      enabled: true,
      hour: 7,
      minute: 0,
      days: [DateTime.monday],
    );
    expect(t, DateTime(2026, 9, 21, 7, 0)); // lunes siguiente
  });

  test('null si la alarma está desactivada o no tiene días', () {
    expect(
      nextAlarmTime(
        monday8,
        enabled: false,
        hour: 7,
        minute: 0,
        days: weekdays,
      ),
      isNull,
    );
    expect(
      nextAlarmTime(monday8, enabled: true, hour: 7, minute: 0, days: []),
      isNull,
    );
  });

  test('alarmOccurrenceKey distingue ocurrencias por día y hora', () {
    final a = alarmOccurrenceKey(DateTime(2026, 9, 14, 7, 0));
    final b = alarmOccurrenceKey(DateTime(2026, 9, 15, 7, 0));
    final c = alarmOccurrenceKey(DateTime(2026, 9, 14, 7, 1));
    expect(a, isNot(b));
    expect(a, isNot(c));
    expect(a, alarmOccurrenceKey(DateTime(2026, 9, 14, 7, 0, 45)));
  });
}
