/// The parts of the receipt that make it read as paper.
///
/// The visual language is a thermal receipt, and only three details carry it:
/// the torn zigzag bottom edge, the dashed rule, and monospace text. All three
/// are worth writing by hand in Flutter rather than pulling in a package,
/// because each is about fifteen lines and none of them has a dependency that
/// is worth carrying.
///
/// The zigzag maths comes from the Polymer "Receipt Printer" experiment
/// (https://www.dqnamo.com/experiments/receipt-printer), which builds it as a
/// `clip-path: polygon()` with alternating teeth. That source is unlicensed, so
/// this is a reimplementation of the technique rather than a port of its code —
/// the maths is three lines and the idea is older than either of us.
library;

import 'package:flutter/material.dart';
/// Depth of each tooth down the bottom edge, in logical pixels.
///
/// Four is enough to read as a tear and small enough not to eat the last line
/// of the receipt.
const double kToothDepth = 4;

/// How many teeth across the full width of the paper.
const int kToothCount = 40;

/// Clips the bottom edge of the paper into a torn sawtooth.
///
/// A `CustomClipper` rather than a `ShapeDecoration` because the path has to be
/// the same width as the widget it clips, and the teeth alternate between the
/// full height and height minus [kToothDepth].
class TornPaperClipper extends CustomClipper<Path> {
  const TornPaperClipper();

  /// Builds the sawtooth path. Public so it can be unit tested without pumping
  /// a widget: [shouldReclip] always returns false, so what matters is that
  /// [getClip] is pure and depends only on [size].
  static Path toothPath(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - kToothDepth);

    // Right to left, so the teeth line up with the way a receipt is torn.
    const steps = kToothCount * 2;
    for (var i = 0; i < steps; i++) {
      final x = size.width * (steps - i) / steps;
      final y = (i % 2 == 0) ? size.height : size.height - kToothDepth;
      path.lineTo(x, y);
    }

    path.close();
    return path;
  }

  @override
  Path getClip(Size size) => toothPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// A dashed horizontal rule, the way a receipt divides its sections.
class DashedReceiptRule extends StatelessWidget {
  const DashedReceiptRule({
    super.key,
    this.height = 12,
    this.dashWidth = 4,
    this.dashGap = 3,
    this.thickness = 1,
    this.color = const Color(0xFF1A1A1A),
  });

  final double height;
  final double dashWidth;
  final double dashGap;
  final double thickness;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(
        dashWidth: dashWidth,
        dashGap: dashGap,
        thickness: thickness,
        color: color,
      ),
      size: Size(double.infinity, height),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({
    required this.dashWidth,
    required this.dashGap,
    required this.thickness,
    required this.color,
  });

  final double dashWidth;
  final double dashGap;
  final double thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;

    // Draw down the middle of the allotted height, so a taller widget spaces
    // its rule rather than pushing it to the top edge.
    final y = size.height / 2;
    for (final dash in segments(size.width, dashWidth, dashWidth)) {
      canvas.drawLine(
        Offset(dash.start, y),
        Offset(dash.end, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) =>
      old.dashWidth != dashWidth ||
      old.dashGap != dashGap ||
      old.thickness != thickness ||
      old.color != color;
}

/// One [start, end) interval of the rule.
class Dash {
  const Dash(this.start, this.end);

  final double start;
  final double end;
}

/// Splits a line [width] into dashes of [dashWidth] separated by [dashGap].
///
/// Pure, so a test can count dashes without rendering anything. The final dash
/// is clamped to the width, which keeps the count exact at any screen width
/// instead of dropping an underlength tail dash.
List<Dash> segments(double width, double dashWidth, double dashGap) {
  if (width <= 0 || dashWidth <= 0) return const [];

  final dashes = <Dash>[];
  var x = 0.0;
  var drawing = true;
  while (x < width) {
    final run = drawing ? dashWidth : dashGap;
    if (drawing) {
      dashes.add(Dash(x, x + run > width ? width : x + run));
    }
    x += run;
    drawing = !drawing;
  }
  return dashes;
}
