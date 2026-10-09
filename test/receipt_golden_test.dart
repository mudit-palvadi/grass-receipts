/// Captures the receipt as a PNG.
///
/// Not coverage for its own sake. A DEV post needs a picture of the thing, and
/// a screenshot needs a device — so the receipt is rendered here instead, and
/// the same command reproduces it on any machine. It also guards the geometry
/// of the torn edge and the paper: a change that moves a tooth depth, a dash
/// width or a padding fails here.
///
/// Regenerate with:
///
///   flutter test --update-goldens test/receipt_golden_test.dart
///
/// Note the surface size is set explicitly rather than relying on the default
/// 800x600, which clips a six-line receipt mid-footer. The PNG in this
/// directory is the picture used in the write-up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grass_receipts/models/receipt.dart';
import 'package:grass_receipts/ui/widgets/printer_chassis.dart';
import 'package:grass_receipts/ui/widgets/receipt_paper.dart';

final DateTime kStartedAt = DateTime.utc(2026, 10, 9, 16, 4);
final DateTime kEndedAt = DateTime.utc(2026, 10, 9, 16, 47);

/// The receipt the app would print for a real 43-minute walk.
///
/// Lines sit at the 32-column limit, so the golden is also a check that the
/// widest legal receipt still fits the paper.
Receipt sampleReceipt() => Receipt(
      lines: const [
        ReceiptLine(qty: 1234, item: 'STEPS, ON YOUR GOOD LEG'),
        ReceiptLine(qty: 43, item: 'MINUTES AWAY FROM THE SCREEN'),
        ReceiptLine(qty: 7, item: 'MINUTES OF DOING NOTHING AT ALL'),
        ReceiptLine(qty: 3, item: 'BIRD THAT SAW YOU'),
        ReceiptLine(qty: 1, item: 'BENCH OCCUPIED, BRIEFLY'),
        ReceiptLine(qty: 1, item: 'BREEZE, MILD, SUSPICIOUS'),
      ],
      review: '3 stars. Great breeze, no wifi.',
      signoff: 'Come back tomorrow. Grass misses you.',
      facts: WalkFacts(
        startedAt: kStartedAt,
        endedAt: kEndedAt,
        steps: 1234,
        stillMinutes: 7,
      ),
    );

/// Tall enough for the whole receipt plus the machine above it.
const Size kSurface = Size(420, 1600);

void main() {
  testWidgets('receipt golden', (tester) async {
    await tester.binding.setSurfaceSize(kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF101015),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ReceiptPaper(receipt: sampleReceipt()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ReceiptPaper),
      matchesGoldenFile('receipt.png'),
    );
  });

  testWidgets('printer golden', (tester) async {
    await tester.binding.setSurfaceSize(kSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF101015),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PrinterChassis(
              stage: PrinterStage.done,
              statusText: 'Receipt printed',
              paper: ReceiptPaper(receipt: sampleReceipt()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PrinterChassis),
      matchesGoldenFile('printer.png'),
    );
  });
}
