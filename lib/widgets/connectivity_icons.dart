import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/connectivity_service.dart';

/// Iconos de estado WiFi/Bluetooth de la barra superior.
///
/// Siempre visibles (salvo [AppSettings.showConnectivityIcons]==false):
/// color de acento si hay conexión, atenuado si no.
/// Toque = abre la página de Ajustes; largo = diálogo de detalle.
class ConnectivityIcons extends StatelessWidget {
  final ConnectivityStatus status;
  final AppSettings settings;
  final double scale;
  final Color accent;
  final Color muted;
  final ValueChanged<AppSettings>? onSettingsChanged;
  final dynamic radio;

  const ConnectivityIcons({
    super.key,
    required this.status,
    required this.settings,
    required this.scale,
    required this.accent,
    required this.muted,
    this.onSettingsChanged,
    this.radio,
  });

  /// Icono WiFi según intensidad 0-100 (null = genérico).
  static IconData wifiIconForSignal(int? signal, bool connected) {
    if (!connected) return Icons.wifi_off;
    if (signal == null) return Icons.wifi;
    if (signal <= 25) return Icons.wifi_1_bar;
    if (signal <= 55) return Icons.wifi_2_bar;
    return Icons.wifi;
  }

  @override
  Widget build(BuildContext context) {
    if (!settings.showConnectivityIcons) return const SizedBox.shrink();
    // Respaldo documentado en WifiService.currentSsid(): si el chequeo en vivo
    // no aporta nada ("desconocido": herramienta ausente, fuera de Linux o sin
    // permisos) se usa el SSID guardado en los ajustes. Si el chequeo sí sabe
    // que NO hay red (`wifiUnknown == false` y `wifiSsid == null`) manda eso.
    final String? wifiSsid = status.wifiUnknown
        ? (status.wifiSsid ?? settings.wifiSsid)
        : status.wifiSsid;
    final wifiOn = settings.wifiEnabled && wifiSsid != null;
    final btConnected = settings.bluetoothEnabled && status.hasBtConnected;
    final btPairedOnly =
        settings.bluetoothEnabled &&
        !status.hasBtConnected &&
        !status.btUnknown &&
        status.hasBtPairedOnly;

    final wifiTooltip = !settings.wifiEnabled
        ? 'Wi-Fi desactivado'
        : wifiOn
        ? 'Wi-Fi: $wifiSsid'
        : status.wifiUnknown
        ? 'Wi-Fi desconocido'
        : 'Wi-Fi sin conexión';
    final btNames = status.btConnected.map((d) => d.name).join(', ');
    final btTooltip = !settings.bluetoothEnabled
        ? 'Bluetooth desactivado'
        : btConnected
        ? 'Bluetooth: $btNames'
        : btPairedOnly
        ? 'Bluetooth emparejado, sin conectar'
        : status.btUnknown
        ? 'Bluetooth desconocido'
        : 'Bluetooth sin conexión';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TappableStatus(
          tooltip: wifiTooltip,
          onTap: () => ConnectivityIconsActions.openWifi(context),
          onLongPress: () => ConnectivityIconsActions.showWifiDetail(
            context,
            wifiTooltip,
            status.wifiSignal,
          ),
          child: Tooltip(
            message: wifiTooltip,
            child: Icon(
              wifiIconForSignal(status.wifiSignal, wifiOn),
              size: 16 * scale,
              color: wifiOn ? accent : muted.withValues(alpha: 0.45),
              semanticLabel: wifiTooltip,
            ),
          ),
        ),
        const SizedBox(width: 4),
        _TappableStatus(
          tooltip: btTooltip,
          onTap: () => ConnectivityIconsActions.openBt(context),
          onLongPress: () => ConnectivityIconsActions.showBtDetail(
            context,
            btTooltip,
            btNames,
          ),
          child: Tooltip(
            message: btTooltip,
            child: Icon(
              btConnected
                  ? Icons.bluetooth_connected
                  : btPairedOnly
                  ? Icons.bluetooth
                  : Icons.bluetooth_disabled,
              size: 16 * scale,
              color: btConnected
                  ? accent
                  : btPairedOnly
                  ? muted
                  : muted.withValues(alpha: 0.45),
              semanticLabel: btTooltip,
            ),
          ),
        ),
      ],
    );
  }
}

/// Acciones de los iconos, separadas para poder testear sin Navigator.
class ConnectivityIconsActions {
  static void Function(BuildContext)? openWifiOverride;
  static void Function(BuildContext)? openBtOverride;

  static void openWifi(BuildContext context) {
    if (openWifiOverride != null) return openWifiOverride!(context);
    Navigator.pushNamed(context, '/settings/wifi');
  }

  static void openBt(BuildContext context) {
    if (openBtOverride != null) return openBtOverride!(context);
    Navigator.pushNamed(context, '/settings/bluetooth');
  }

  static void showWifiDetail(
    BuildContext context,
    String summary,
    int? signal,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wi-Fi'),
        content: Text('$summary${signal != null ? '\nSeñal: $signal%' : ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  static void showBtDetail(BuildContext context, String summary, String names) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bluetooth'),
        content: Text(names.isEmpty ? summary : '$summary\n$names'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _TappableStatus extends StatelessWidget {
  final Widget child;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TappableStatus({
    required this.child,
    required this.tooltip,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }
}
