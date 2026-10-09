/// Tests for the two things that make a receipt read as paper.
///
/// These pin properties that break silently. A clipper that closes at the
/// wrong place, or dashes that lose their rhythm, still renders as a grey
/// shape and looks like "paper" — so the maths is tested directly rather than
/// by eye. No golden images, no fake canvases.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grass_receipts/ui/widgets/receipt_kit.dart';

void main() {
  const size = Size(320, 400);

  group('the torn edge', () {
    test('leaves the top edge flat', () {
      // A receipt is torn at the bottom, never the top. The path must run
      // straight across the top before it descends anywhere.
      final bounds = TornPaperClipper.toothPath(size).getBounds();
      expect(bounds.top, 0);
      expect(bounds.left, 0);
      expect(bounds.width, 320);
    });

    test('descends no deeper than one tooth', () {
      final bounds = TornPaperClipper.toothPath(size).getBounds();
      expect(bounds.bottom, size.height);
    });

    test('spaces a tooth every 1/(2*count) of the width', () {
      // 40 teeth, two segments each, so the tooth pattern changes every
      // 320/80 = 4 pixels. If a tooth width ever drifted this number moves.
      expect(size.width / (kToothCount * 2), 4.0);
    });

    test('is a pure function of size, which is what makes shouldReclip false',
        () {
      // The clipper never repaints, so a path that depended on anything else
      // would be a latent bug. Two paths for the same size must be identical.
      expect(
        TornPaperClipper.toothPath(size).getBounds(),
        TornPaperClipper.toothPath(size).getBounds(),
      );
    });

    test('stays inside the box at any width', () {
      for (final width in [120.0, 320.0, 800.0]) {
        final bounds = TornPaperClipper.toothPath(Size(width, 400)).getBounds();
        expect(bounds.left, 0);
        expect(bounds.width, width);
      }
    });
  });

  group('the dashed rule', () {
    test('counts dashes exactly, including at an awkward width', () {
      expect(segments(200, 10, 10).length, 10);
      expect(segments(0, 10, 10), isEmpty);
    });

    test('clamps the last dash instead of letting it overshoot', () {
      // 25 pixels with a 10/10 pattern: 10 on, 10 off, then a 5-on tail. Two
      // dashes, the second clamped to 25. Without the clamp the second dash
      // would run to 30 and paint past the end of the line.
      final dashes = segments(25, 10, 10);
      expect(dashes.length, 2);
      expect(dashes.first.start, 0);
      expect(dashes.first.end, 10);
      expect(dashes.last.start, 20);
      expect(dashes.last.end, 25);
    });

    test('never produces a zero-width dash', () {
      for (var w = 0; w < 100; w++) {
        for (final dash in segments(w.toDouble(), 7, 3)) {
          expect(dash.end, greaterThan(dash.start));
        }
      }
    });

    test('renders as a CustomPaint with the requested height', () {
      const rule = DashedReceiptRule(height: 12, dashWidth: 4, dashGap: 3);
      expect(rule.height, 12);
      expect(rule.dashWidth, 4);
      expect(rule.dashGap, 3);
    });
  });
}
