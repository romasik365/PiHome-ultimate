import 'package:flutter/material.dart';

import '../services/app_log.dart';
import 'error_screen.dart';

/// Raíz de la aplicación que envuelve la app real.
///
/// Instala los manejadores globales de error y, si ocurre un fallo
/// irrecuperable, sustituye la interfaz por una [ErrorScreen] con botón de
/// reinicio en lugar de dejar la pantalla en blanco. Al reiniciar se vuelve a
/// construir la app desde cero con [key] nueva, forzando `initState` limpio.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.appBuilder,
    this.accentColor = const Color(0xFF22D3EE),
  });

  /// Construye la aplicación real. Recibe la [Key] que hay que aplicar para que
  /// un reinicio la remonte por completo.
  final Widget Function(Key key) appBuilder;

  /// Color de acento de la pantalla de error.
  final Color accentColor;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Object? _fatalError;
  StackTrace? _fatalStack;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    // `main()` ya enganchó los manejadores; aquí sólo se registra el callback
    // que sustituye la interfaz por la pantalla de error cuando haga falta.
    AppLog.install(onFatal: _handleFatal);
  }

  void _handleFatal(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    // Evita reconstrucciones repetidas si el error se repite en bucle.
    if (identical(_fatalError, error)) return;
    setState(() {
      _fatalError = error;
      _fatalStack = stackTrace;
    });
  }

  void _restart() {
    AppLog.info('Reinicio solicitado por el usuario tras un error fatal');
    setState(() {
      _fatalError = null;
      _fatalStack = null;
      _attempt++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _fatalError;
    if (error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0F14),
          body: ErrorScreen(
            error: error,
            stackTrace: _fatalStack,
            onRestart: _restart,
            accentColor: widget.accentColor,
          ),
        ),
      );
    }
    return widget.appBuilder(ValueKey<int>(_attempt));
  }
}
