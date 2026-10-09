/// The receipt, printed on thermal paper.
///
/// A fixed-width monospace strip: header, measured facts, itemised lines with
/// dashed rules between sections, and a review and signoff at the foot. The
/// text widths are deliberately conservative so every line fits a real
/// 32-column roll — that limit is enforced in receipt_service.dart, and there
/// is a widget test that a receipt at the limit still lays out without
/// overflowing.
///
/// The last line the printer says is the signoff. There is no "generated on
/// device" footer: the receipt is a joke object, and a legal notice on the
/// bottom of it is the machine explaining itself.
library;

import 'package:flutter/material.dart';
import '../../models/receipt.dart';
import 'receipt_kit.dart';

/// Background tint of the receipt paper. Slightly warm so it does not read as
/// pure white, and one step off the chassis so the seam between them is visible.
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
                letterSpacing: 1.6,
                color: kPaperInk,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'RECEIPT NO. ${receipt.number}',
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 0.8,
                color: kPaperInk.withValues(alpha: 0.65),
              ),
            ),
            const DashedReceiptRule(height: 16, color: kPaperInk),
            _factRow('WENT OUTSIDE', _time(facts.startedAt)),
            _factRow('CAME BACK', _time(facts.endedAt)),
            _factRow('TIME BAND', facts.timeBand),
            const DashedReceiptRule(height: 16, color: kPaperInk),
            for (final line in receipt.lines) _itemRow(line),
            const DashedReceiptRule(height: 16, color: kPaperInk),
            _totalRow(),
            const SizedBox(height: 12),
            _footer('YOUR REVIEW', receipt.review),
            const SizedBox(height: 8),
            _footer('SIGNOFF', receipt.signoff),
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
        padding: const EdgeInsets.symmetric(vertical: 2),
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
        padding: const EdgeInsets.symmetric(vertical: 2),
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
TextStyle _ink(
  double size, {
  FontWeight weight = FontWeight.w400,
  bool dim = false,
}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
    fontWeight: weight,
    color: dim ? kPaperInk.withValues(alpha: 0.55) : kPaperInk,
    height: 1.35,
  );
}
