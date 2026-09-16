# PiHome Ultimate

Panel inteligente (reloj, clima, radio y alarma) pensado para funcionar como
**kiosco en una Raspberry Pi** sobre una pantalla de 800×480, y también en
escritorio (Windows / Linux) para desarrollo.

Hecho con **Flutter** y **Dart**, sin dependencias propietarias.

---

## Características

### Pantalla principal
- **Reloj y fecha** con tipografía, tamaño y segundos configurables.
- **Clima actual + previsión de 3 días** (Open-Meteo) con etiqueta de ubicación.
- **Radio por internet** con emisoras favoritas, cambio de emisora, volumen y
  **temporizador de apagado** (sleep timer).
- **Barra superior** con badge de ubicación e **iconos de conectividad**
  (Wi-Fi / Bluetooth) con intensidad de señal, emparejado vs. conectado y
  tooltip descriptivo.
- **Modo noche** (paleta roja para no deslumbrar) y **color de acento**
  personalizable.
- **Salvapantallas** por inactividad.

### Ajustes (pantalla completa)
Secciones: *Pantalla*, *Tipografía*, *Reloj y fecha*, *Clima*, *Radio*,
*Red Wi-Fi*, *Bluetooth*, *Alarma y amanecer*.
- **Alarma** con simulación de amanecer y repetición por días de la semana.
- **Gestión de Wi-Fi** (escaneo y conexión mediante `nmcli`).
- **Gestión de Bluetooth** (emparejamiento y conexión mediante `bluetoothctl`).
- **Teclado virtual** propio para introducir textos sin teclado físico.

### Robustez (importante en un kiosco sin consola)
- **Animación de arranque** (latido) con duración mínima configurable.
- **Registro de errores en disco** (`app.log`) con **rotación** a 1 MB × 3
  ficheros, para que un equipo encendido semanas no llene el disco.
- **Pantalla de error** con botón de reinicio: ante un fallo fatal se muestra
  una alternativa en lugar de una pantalla en blanco.
- Los errores no capturados se enganchan con `runZonedGuarded`,
  `FlutterError.onError` y `PlatformDispatcher.onError`.
- La app **nunca lanza excepciones por un fallo de disco**: si algo falla
  (ajustes corruptos, log sin permisos) se degrada a valores por defecto.

---

## Requisitos

- **Flutter** (canal `stable`) con Dart `^3.13.3`.
- **Linux**: `nmcli` (NetworkManager) para Wi-Fi y `bluetoothctl` (BlueZ) para
  Bluetooth. Si no están disponibles, esas secciones se degradan sin romper la
  app.
- **Windows**: funciona para desarrollo; las funciones de red Wi-Fi/Bluetooth
  muestran estado "desconocido" porque dependen de herramientas de Linux.

---

## Puesta en marcha

```bash
flutter pub get
flutter run -d windows     # desarrollo en Windows
flutter run -d linux       # desarrollo en Linux / Raspberry Pi
```

Compilar:

```bash
flutter build windows --release
flutter build linux --release
```

---

## Pruebas

```bash
flutter analyze
flutter test
flutter test --coverage          # informe en coverage/lcov.info
```

La batería cubre lógica de alarma, parseo de clima, servicio de radio,
modelos, servicios de conectividad, pantalla principal, todas las páginas de
ajustes, el arranque y el log.

> Los tests **aislan su configuración** en una carpeta temporal
> (`AppStorage.overrideDirectory`), de modo que nunca leen ni escriben los
> ficheros reales del usuario ni colisionan entre sí al ejecutarse en paralelo.

---

## Estructura del proyecto

```
lib/
├── main.dart                     # Arranque, ventana y raíz de la app
├── models/
│   ├── app_settings.dart         # Ajustes + serialización JSON
│   └── radio_station.dart        # Modelo de emisora
├── screens/
│   └── settings_screen.dart      # Pantalla de ajustes completa
├── services/
│   ├── alarm_logic.dart          # Cálculo de la próxima alarma
│   ├── app_log.dart              # Log en disco con rotación
│   ├── app_storage.dart          # Carpeta de configuración (punto único)
│   ├── beep_service.dart         # Pitido de alarma generado en local
│   ├── bluetooth_service.dart    # bluetoothctl
│   ├── connectivity_service.dart # Estado Wi-Fi/BT unificado (Stream)
│   ├── geocoding_service.dart    # GPS -> nombre de lugar
│   ├── radio_directory_service.dart # Directorio de emisoras + caché
│   ├── radio_service.dart        # Reproducción y favoritos
│   ├── settings_store.dart       # Persistencia de ajustes
│   ├── weather_service.dart      # Open-Meteo
│   └── wifi_service.dart         # nmcli
└── widgets/
    ├── app_bootstrap.dart        # Manejo global de errores -> ErrorScreen
    ├── boot_screen.dart          # Animación de arranque
    ├── connectivity_icons.dart   # Iconos Wi-Fi / Bluetooth
    ├── error_screen.dart         # Pantalla de error con reinicio
    ├── interactive_card.dart     # Tarjeta reutilizable
    └── virtual_keyboard.dart     # Teclado en pantalla
```

### Dónde se guardan los datos

| Qué | Dónde |
|---|---|
| Ajustes | Windows: `%APPDATA%\pi_home_ultimate\settings.json`<br>Linux: `$XDG_CONFIG_HOME/pi_home_ultimate/settings.json` (o `~/.config/...`) |
| Favoritos de radio | `.../pi_home_ultimate/favorites.json` |
| Log | `.../pi_home_ultimate/app.log` (+ `.1`, `.2`) |

> La **contraseña de Wi-Fi no se guarda** en `settings.json`: se pasa a `nmcli`,
> que la almacena en el llavero del sistema.

---

## Integración continua

`.github/workflows/ci.yml` ejecuta en `ubuntu-latest`:

1. `dart format --set-exit-if-changed`
2. `flutter analyze`
3. `flutter test` **tres veces** (para detectar fallos intermitentes) + cobertura
4. Subida del informe de cobertura como artefacto

---

## Estado del proyecto

Implementado: pantalla principal, ajustes completos, radio, clima, alarma,
conectividad, log con rotación, pantalla de error, CI y batería de pruebas.

Pendiente / siguiente paso: despliegue desatendido en Raspberry Pi
(servicio `systemd` y script de instalación) y pruebas de integración en
dispositivo real.

