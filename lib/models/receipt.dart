/// What the phone measured, and what the model said about it.
///
/// The whole design of this project rests on one rule carried over from Heads
/// Up: **Gemma never gets to decide the numbers.** Measured facts (steps,
/// minutes) are ours; the model only supplies the comedy. That is why
/// [Receipt.facts] and the generated [ReceiptLine] quantities are validated
/// against [WalkFacts] and why a template fallback exists.
library;

/// The measured part of a walk. Everything here came from a sensor or a clock,
/// never from the model.
class WalkFacts {
  const WalkFacts({
    required this.startedAt,
    required this.endedAt,
    required this.steps,
    required this.stillMinutes,
    this.stepSensorAvailable = true,
  });

  /// When the big button was tapped on the way out.
  final DateTime startedAt;

  /// When it was tapped on the way back.
  final DateTime endedAt;

  /// Steps taken while outside. A snapshot difference, not a running total —
  /// Android's counter reports steps since boot (pedometer README), so counting
  /// the absolute value would report every step since the phone was restarted.
  final int steps;

  /// The longest single stretch of standing or sitting perfectly still.
  final int stillMinutes;

  /// False when the device has no step sensor (pedometer README names some
  /// Samsung phones). The receipt then simply drops its measured-step line
  /// rather than printing "0x STEPS".
  final bool stepSensorAvailable;

  int get minutes => endedAt.difference(startedAt).inMinutes;

  /// A broad description of when the walk happened, for the receipt header.
  String get timeBand {
    final hour = startedAt.hour;
    if (hour >= 5 && hour < 9) return 'EARLY BIRD';
    if (hour >= 9 && hour < 12) return 'MID MORNING';
    if (hour >= 12 && hour < 15) return 'LUNCH BREAK';
    if (hour >= 15 && hour < 18) return 'LATE AFTERNOON';
    if (hour >= 18 && hour < 21) return 'GOLDEN HOUR';
    return 'AFTER DARK';
  }
}

/// One itemised line on the receipt.
class ReceiptLine {
  const ReceiptLine({required this.qty, required this.item, this.measured = false});

  /// How many. Always computed by the app when [measured] is true.
  final int qty;

  /// The joke, in caps, the way a thermal printer renders it.
  final String item;

  /// True for lines whose quantity the app derived from [WalkFacts]. The model
  /// is never allowed to set one of these.
  final bool measured;

  String get formatted => '${qty}x $item';
}

/// Why model output was thrown away, for counting in the write-up.
///
/// A fallback is not a crash, it is data: how often a 1B model produced
/// something unusable is exactly the kind of honest number this project should
/// be able to quote.
enum ReceiptRejection {
  /// Fewer than [ReceiptService.minItemLines] ITEM lines came back.
  tooFewLines,

  /// A line was too long to print on a 32-column receipt.
  tooLong,

  /// The REVIEW or SIGNOFF line was missing.
  missingFooter,

  /// Two lines said the same thing.
  duplicateItem,

  /// The model was not loaded or inference threw.
  unavailable,
}

/// A finished receipt.
class Receipt {
  const Receipt({
    required this.lines,
    required this.review,
    required this.signoff,
    required this.facts,
    this.rejected,
  });

  /// Builds the template receipt used whenever model output is rejected.
  ///
  /// It is deliberately dull but complete: a receipt with a blank item list is
  /// a broken joke, and this project has exactly one screen to get right.
  factory Receipt.template(WalkFacts facts) {
    final lines = <ReceiptLine>[
      if (facts.stepSensorAvailable)
        ReceiptLine(
          qty: facts.steps,
          item: 'STEPS, ON YOUR GOOD LEG',
          measured: true,
        ),
      ReceiptLine(
        qty: facts.minutes,
        item: 'MINUTES AWAY FROM THE SCREEN',
        measured: true,
      ),
      if (facts.stillMinutes > 2)
        ReceiptLine(
          qty: facts.stillMinutes,
          item: 'MINUTES OF DOING NOTHING AT ALL',
          measured: true,
        ),
    ];
    return Receipt(
      lines: lines,
      review: 'Receipt printer unavailable. Walk happened anyway.',
      signoff: 'Come back tomorrow. Grass misses you.',
      facts: facts,
      rejected: ReceiptRejection.unavailable,
    );
  }

  final List<ReceiptLine> lines;

  /// The receipt's one-star-to-five review of the customer's outing.
  final String review;

  /// The closing line, always "come back tomorrow".
  final String signoff;

  /// The measured facts this receipt describes.
  final WalkFacts facts;

  /// Null when the model's output was accepted.
  final ReceiptRejection? rejected;

  bool get usedFallback => rejected != null;

  /// The receipt number: one per walk, so the joke lands on the twelfth outing
  /// the same way it does on the first.
  int get number => 1 + (facts.steps % 97);

  /// Every line costs nothing. Paying for grass is exactly the wrong idea.
  static const String price = r'$0.00';
}
