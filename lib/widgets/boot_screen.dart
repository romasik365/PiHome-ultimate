import 'package:flutter/material.dart';

/// Pantalla de arranque con el logotipo de texto "PiHome Ultimate" latiendo
/// (heartbeat) mientras el sistema y los widgets se cargan en segundo plano.
///
/// No usa assets ni dependencias externas: el latido es un pulso de escala
/// + brillo (glow) driven por un [AnimationController] en repeat(reverse).
///
/// Cuando [onReady] se resuelve (cargas completadas) se dispara un fade-out
/// hacia la pantalla principal. [minDuration] evita que el boot sea un
/// parpadeo si la carga es muy rápida.
class BootScreen extends StatefulWidget {
  final Color accent;
  final String title;
  final String subtitle;
  final Future<void> onReady;
  final Duration minDuration;
  final Duration fadeOut;
  final VoidCallback? onFinished;

  const BootScreen({
    super.key,
    required this.accent,
    this.title = 'PiHome Ultimate',
    this.subtitle = 'Iniciando sistema…',
    required this.onReady,
    this.minDuration = const Duration(milliseconds: 1200),
    this.fadeOut = const Duration(milliseconds: 450),
    this.onFinished,
  });

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _glow;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Ritmo de latido ~700 ms: sube y baja de forma continua.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    // Curva orgánica tipo "bum-bum" (easeOutBack da un pequeño rebote).
    final curved = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(curved);
    _glow = Tween<double>(begin: 12.0, end: 34.0).animate(curved);

    _waitReadyAndLeave();
  }

  /// Espera a que las cargas terminen Y a la duración mínima, luego hace
  /// el fade-out y avisa a [BootScreen.onFinished].
  Future<void> _waitReadyAndLeave() async {
    await Future.wait([
      widget.onReady,
      Future<void>.delayed(widget.minDuration),
    ]);
    if (!mounted) return;
    setState(() => _leaving = true);
    await Future<void>.delayed(widget.fadeOut);
    if (!mounted) return;
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _leaving ? 0.0 : 1.0,
      duration: widget.fadeOut,
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logotipo de texto con latido de escala + glow pulsante.
            ScaleTransition(
              scale: _scale,
              child: AnimatedBuilder(
                animation: _glow,
                builder: (context, child) => Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: widget.accent,
                    shadows: [
                      Shadow(
                        color: widget.accent.withValues(alpha: 0.55),
                        blurRadius: _glow.value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 2,
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
