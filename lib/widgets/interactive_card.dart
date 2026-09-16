import 'dart:ui';

import 'package:flutter/material.dart';

class InteractiveCard extends StatefulWidget {
  final Widget child;
  final Color cardBg;
  final Color cardBorder;
  final VoidCallback? onTap;

  const InteractiveCard({
    super.key,
    required this.child,
    required this.cardBg,
    required this.cardBorder,
    this.onTap,
  });

  @override
  State<InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<InteractiveCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isClickable = widget.onTap != null;
    return MouseRegion(
      cursor: isClickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: isClickable
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onTap: widget.onTap,
        onTapDown: isClickable ? (_) => setState(() => _pressed = true) : null,
        onTapUp: isClickable ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: isClickable
            ? () => setState(() => _pressed = false)
            : null,
        child: AnimatedScale(
          scale: (isClickable && _pressed) ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.cardBorder),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge de la barra superior. [fontSize] permite escalar el texto desde los
/// ajustes de tipografía.
Widget buildBadge(
  String text,
  Color bg,
  Color border,
  Color textColor, [
  double fontSize = 11,
]) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
