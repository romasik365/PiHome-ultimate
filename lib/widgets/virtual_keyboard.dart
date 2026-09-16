import 'package:flutter/material.dart';

/// Muestra un teclado virtual en un BottomSheet modal.
/// Devuelve el texto introducido o null si el usuario cierra sin confirmar.
Future<String?> showVirtualKeyboard(
  BuildContext context, {
  String initial = '',
  String hint = '',
  bool obscure = false,
}) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _VirtualKeyboardSheet(initial: initial, hint: hint, obscure: obscure),
  );
}

class _VirtualKeyboardSheet extends StatefulWidget {
  final String initial;
  final String hint;
  final bool obscure;

  const _VirtualKeyboardSheet({
    required this.initial,
    required this.hint,
    required this.obscure,
  });

  @override
  State<_VirtualKeyboardSheet> createState() => _VirtualKeyboardSheetState();
}

class _VirtualKeyboardSheetState extends State<_VirtualKeyboardSheet> {
  late String _text;
  bool _shift = false;
  bool _symbols = false;
  bool _obscure = false;

  static const _row1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _row2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _row3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];
  static const _nums = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _syms1 = ['!', '@', '#', r'$', '%', '^', '&', '*', '(', ')'];
  static const _syms2 = ['-', '_', '=', '+', '[', ']', '{', '}', ';', "'"];
  static const _syms3 = [',', '.', '/', ':', '"', '<', '>', '?', '|', r'\'];

  @override
  void initState() {
    super.initState();
    _text = widget.initial;
    _obscure = widget.obscure;
  }

  void _tap(String key) {
    setState(() {
      _text += _shift ? key.toUpperCase() : key;
      _shift = false;
    });
  }

  void _backspace() {
    if (_text.isNotEmpty) {
      setState(() => _text = _text.substring(0, _text.length - 1));
    }
  }

  Widget _key(String label, {int flex = 1, VoidCallback? onTap, Color? bg}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: bg ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap ?? () => _tap(label),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayText = _obscure ? ('•' * _text.length) : _text;

    final r1 = _symbols ? _syms1 : _row1;
    final r2 = _symbols ? _syms2 : _row2;
    final r3 = _symbols ? _syms3 : _row3;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra de visualización del texto introducido
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayText.isEmpty ? widget.hint : displayText,
                    style: TextStyle(
                      fontSize: 18,
                      color: displayText.isEmpty
                          ? cs.onSurfaceVariant
                          : cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.obscure)
                  IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
              ],
            ),
          ),
          // Fila de números
          Row(children: _nums.map((k) => _key(k)).toList()),
          const SizedBox(height: 2),
          // Fila 1
          Row(
            children: r1
                .map((k) => _key(_shift ? k.toUpperCase() : k))
                .toList(),
          ),
          // Fila 2
          Row(
            children: r2
                .map((k) => _key(_shift ? k.toUpperCase() : k))
                .toList(),
          ),
          // Fila 3 con Shift y Backspace
          Row(
            children: [
              _key(
                '⇧',
                flex: 2,
                bg: _shift ? cs.primaryContainer : null,
                onTap: () => setState(() => _shift = !_shift),
              ),
              ...r3.map((k) => _key(_shift ? k.toUpperCase() : k)),
              _key('⌫', flex: 2, bg: cs.errorContainer, onTap: _backspace),
            ],
          ),
          // Fila inferior: ?123, espacio, OK
          Row(
            children: [
              _key(
                _symbols ? 'ABC' : '?123',
                flex: 2,
                onTap: () => setState(() {
                  _symbols = !_symbols;
                  _shift = false;
                }),
              ),
              _key(
                ' ',
                flex: 5,
                onTap: () => setState(() {
                  _text += ' ';
                  _shift = false;
                }),
              ),
              _key(
                'OK',
                flex: 2,
                bg: cs.primaryContainer,
                onTap: () => Navigator.pop(context, _text),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
