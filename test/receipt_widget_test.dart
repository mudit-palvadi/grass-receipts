/// Renders the receipt in a phone-shaped box and checks nothing overflows.
///
/// A receipt is a fixed-width strip of paper, which means its text has to fit.
/// The 32-column rule in `receipt_service.dart` enforces the string lengths,
/// but only this test can prove that a receipt with the longest legal strings
/// still lays out. A long item line otherwise fails as a yellow-and-black
/// overflow stripe on screen, which is a bug you only find by running the app.
///
/// Also covers the idle screen, because that is the first thing anyone sees and
/// `FlutterGemma.initialize()` failing in a test environment is the realistic
/// path there (no plugin registered).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grass_receipts/models/receipt.dart';
import 'package:grass_receipts/ui/screens/receipt_screen.dart';
import 'package:grass_receipts/ui/widgets/receipt_paper.dart';

final DateTime kStartedAt = DateTime.utc(2026, 10, 9, 16, 4);
final DateTime kEndedAt = DateTime.utc(2026, 10, 9, 16, 47);

WalkFacts facts({bool stepSensor = true}) => WalkFacts(
      startedAt: kStartedAt,
      endedAt: kEndedAt,
      steps: 1234,
      stillMinutes: 7,
      stepSensorAvailable: stepSensor,
    );

/// The receipt a working model would return, with lines at the length limits.
///
/// The model supplies the verdict and the item quantities itself, so those are
/// the parts whose widths matter: a quantity the model chose is part of the
/// 32-column roll, not decoration around it.
Receipt modelReceipt() => Receipt(
      lines: const [
        ReceiptLine(qty: 1234, item: 'STEPS, ON YOUR GOOD LEG'),
        ReceiptLine(qty: 43, item: 'MINUTES AWAY FROM THE SCREEN'),
        // Exactly 29 characters: the most an item can be and still fit
        // 32 columns once its "999x " prefix is counted.
        ReceiptLine(qty: 999, item: '29X AN EXTRAORDINARILY LONG NAME'),
        ReceiptLine(qty: 1, item: 'SHORT ONE'),
      ],
      review: 'A review that runs to thirty nine chars ok',
      signoff: 'Come back tomorrow. Grass misses you.',
      facts: facts(),
      verdict: const ReceiptVerdict(
        walkType: 'ESCAPE',
        nature: '43 MINUTES OFF THE GRID. THE BIRDS WON.',
      ),
    );

void main() {
  group('the receipt fits on a phone', () {
    final cases = <String, Receipt>{
      'a model receipt at the length limits': modelReceipt(),
      'the template receipt': Receipt.template(facts()),
      'the template receipt with no step sensor':
          Receipt.template(facts(stepSensor: false)),
    };

    cases.forEach((name, receipt) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  child: ReceiptPaper(receipt: receipt),
                ),
              ),
            ),
          ),
        );

        // An overflow stripes the screen with yellow and black; this is the
        // assertion that catches it.
        expect(tester.takeException(), isNull);
        expect(find.byType(ReceiptPaper), findsOne);
      });
    });
  });

  group('what the receipt says', () {
    testWidgets('prints the measured step count, not a placeholder',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptPaper(receipt: Receipt.template(facts())),
            ),
          ),
        ),
      );

      expect(find.textContaining('1234x STEPS'), findsOne);
      expect(find.text('43x MINUTES AWAY FROM THE SCREEN'), findsOne);
      expect(find.textContaining(r'$0.00'), findsOne);
      expect(find.text('GRASS TOUCHED'), findsOne);
      // The last line the printer says is the signoff. There is no
      // "generated on device" footer: a legal notice on the bottom of a joke
      // is the machine explaining itself.
      expect(
        find.text('GENERATED ON DEVICE. NO SERVER, NO ACCOUNT, NO SIGNAL.'),
        findsNothing,
      );
    });

    testWidgets('shows the time band and both clock times', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptPaper(receipt: Receipt.template(facts())),
            ),
          ),
        ),
      );

      expect(find.text('LATE AFTERNOON'), findsOne);
      expect(find.text('4:04 PM'), findsOne);
      expect(find.text('4:47 PM'), findsOne);
    });

    testWidgets('drops the step line only when there is no step sensor',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptPaper(
                receipt: Receipt.template(facts(stepSensor: false)),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('STEPS'), findsNothing);
      // Not "contains MINUTES": the still-time line also contains it.
      expect(
        find.text('43x MINUTES AWAY FROM THE SCREEN'),
        findsOne,
      );
    });

    testWidgets('a model receipt prints what the model wrote', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptPaper(receipt: modelReceipt()),
            ),
          ),
        ),
      );

      // The long line survives a 32-column receipt unchanged.
      expect(find.text('999x 29X AN EXTRAORDINARILY LONG NAME'), findsOne);
      expect(find.text('1x SHORT ONE'), findsOne);
    });
  });

  group('the first screen', () {
    testWidgets('shows the one-time setup with three models', (tester) async {
      // FlutterGemma.initialize() has no plugin registered here and fails, so
      // this doubles as a test that a failed engine init does not crash the
      // app: it must fall through to setup and offer the models.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReceiptScreen())),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ONE TIME SETUP'), findsOne);
      expect(find.text('DOWNLOAD THE MODEL'), findsOne);

      // The default model is ungated, which is the property the README claims.
      expect(find.textContaining('Qwen3 0.6B'), findsOne);
      expect(find.textContaining('SmolLM2'), findsOne);
      expect(find.textContaining('Gemma 3 1B'), findsOne);
    });

    testWidgets('shows no receipt before any walk happens', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReceiptScreen())),
      );

      expect(find.text('GRASS TOUCHED'), findsNothing);
      expect(find.text('STEPS, ON YOUR GOOD LEG'), findsNothing);
    });
  });
}
