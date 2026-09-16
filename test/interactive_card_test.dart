import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_display/widgets/interactive_card.dart';

void main() {
  testWidgets('InteractiveCard muestra el hijo y responde al toque', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: InteractiveCard(
                cardBg: Colors.black,
                cardBorder: Colors.white,
                onTap: () => taps++,
                child: const Text('Dentro'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Dentro'), findsOneWidget);
    await tester.tap(find.text('Dentro'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('InteractiveCard sin onTap no falla al tocarla', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: InteractiveCard(
                cardBg: Colors.black,
                cardBorder: Colors.white,
                child: Text('Solo vista'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Solo vista'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('buildBadge renderiza el texto con el tamaño pedido', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildBadge('Hola', Colors.black, Colors.white, Colors.red, 20),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Hola'));
    expect(text.style?.fontSize, 20);
    expect(text.style?.color, Colors.red);
  });
}
