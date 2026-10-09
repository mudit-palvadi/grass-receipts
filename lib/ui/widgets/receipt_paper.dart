/// The printer, and the paper coming out of it.
///
/// The chassis is a dark rounded slab with a slot at the bottom; the paper
/// emerges from that slot and ends in a torn edge
/// (see ui/widgets/receipt_kit.dart).
///
/// The whole point of the machine is the *timing*: the receipt does not appear
/// finished. It also never becomes a scrolling document — a receipt is a
/// fixed-size strip, so the widget is sized to its content and centered.
library;

import 'package:flutter/material.dart';

import '../../models/receipt.dart';
import '../widgets/receipt_kit.dart';

/// Background tint of the receipt paper. Slightly warm so it does not read as
/// pure white, and one step off the chassis so the seam is visible.
const Color kPaperColor = Color(0xFFF4F1EA);
const Color kPaperInk = Color(0xFF16161A);

/// A receipt printed on thermal paper.
///
/// Renders [Receipt] as a fixed-width monospace strip: header, itemised lines
/// with dashed rules between sections, and a footer of review and signoff.
/// Widths are deliberately conservative so the text fits a real 32-column roll.
class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({super.key, required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final facts = receipt.facts;
    final textTheme = Theme.of(context).textTheme;

    return ClipPath(
      clipper: const TornPaperClipper(),
      child: Container(
        color: kPaperColor,
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GRASS TOUCHED',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: kPaperInk,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'RECEIPT NO. ${receipt.number}',
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: kPaperInk.withValues(alpha: 0.65),
              ),
            ),
            const DashedReceiptRule(height: 14, color: kPaperInk),
            _factRow('WENT OUTSIDE', _time(facts.startedAt)),
            _factRow('CAME BACK', _time(facts.endedAt)),
            _factRow('TIME BAND', facts.timeBand),
            const DashedReceiptRule(height: 14, color: kPaperInk),
            for (final line in receipt.lines) _itemRow(line),
            const DashedReceiptRule(height: 14, color: kPaperInk),
            _totalRow(),
            const SizedBox(height: 10),
            _footer('YOUR REVIEW', receipt.review),
            const SizedBox(height: 6),
            _footer('SIGNOFF', receipt.signoff),
            const SizedBox(height: 14),
            Center(
              child: Text(
                kReceiptFooter,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: kPaperInk.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime at) {
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    final suffix = at.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $suffix';
  }

  Widget _factRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _ink(11, weight: FontWeight.w700)),
            const Spacer(),
            Text(value, style: _ink(11)),
          ],
        ),
      );

  Widget _itemRow(ReceiptLine line) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '${line.qty}x ${line.item}',
          style: _ink(12, weight: FontWeight.w600),
        ),
      );

  Widget _totalRow() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          children: [
            Text('TOTAL', style: _ink(12, weight: FontWeight.w700)),
            const Spacer(),
            Text(Receipt.price, style: _ink(12, weight: FontWeight.w700)),
          ],
        ),
      );

  Widget _footer(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _ink(10, weight: FontWeight.w700, dim: true)),
          Text(value, style: _ink(11)),
        ],
      );
}

/// Monospace ink, with the paper's contrast baked in.
///
/// A function rather than a `const` TextStyle subclass: [kPaperInk]
/// `.withValues()` is not a compile-time constant, so a const constructor can
/// never build this. One non-const TextStyle per line is not worth optimising
/// for on a screen with two dozen of them.
TextStyle _ink(double size, {FontWeight weight = FontWeight.w400, bool dim = false}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
    fontWeight: weight,
    color: dim ? kPaperInk.withValues(alpha: 0.55) : kPaperInk,
    height: 1.35,
  );
}

/// Printed at the very bottom, so a receipt found on a desk is attributable.
const String kReceiptFooter =
    'GENERATED ON DEVICE. NO SERVER, NO ACCOUNT, NO SIGNAL.';
