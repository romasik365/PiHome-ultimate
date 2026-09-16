import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';

/// Pantalla de error de último recurso.
///
/// Se muestra cuando algo falla de forma irrecuperable en el arranque o en la
/// construcción del árbol de widgets, en lugar de dejar la pantalla en blanco.
/// Ofrece el error de forma legible, la ruta del log y un botón para volver a
/// intentar montar la aplicación.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRestart,
    this.accentColor = const Color(0xFF22D3EE),
  });

  /// Error capturado (normalmente una `FlutterError` o `Exception`).
  final Object error;

  /// Traza asociada, si se conoce.
  final StackTrace? stackTrace;

  /// Vuelve a intentar arrancar la aplicación. Si es `null` sólo se muestra
  /// el botón de copiar detalles.
  final VoidCallback? onRestart;

  /// Color de acento para que combine con el tema del usuario.
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final details = StringBuffer('$error');
    if (stackTrace != null) details.write('\n\n$stackTrace');

    return Material(
      color: const Color(0xFF0B0F14),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.error_outline, color: accentColor, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Algo ha ido mal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'La aplicación ha encontrado un error inesperado. '
                  'Puedes reintentar o copiar los detalles para revisarlos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    '$error',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'Log: ${AppLog.logFilePath()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (onRestart != null)
                      FilledButton.icon(
                        onPressed: onRestart,
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reiniciar'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _copyToClipboard(context, details.toString());
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar detalles'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Detalles copiados al portapapeles')),
    );
  }
}
