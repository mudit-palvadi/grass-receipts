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

  /// How the receipt refers to the walk's length in prose.
  ///
  /// A walk shorter than a minute cannot be called "0 MINUTES" without reading
  /// like a bug rather than a joke, so it gets a phrase instead — and the
  /// prompt's example has to use whichever form applies, or a small model will
  /// quietly copy the example and print the wrong number.
  String get minutesLabel =>
      minutes == 0 ? 'LESS THAN A MINUTE' : '$minutes MINUTES';

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
  /// Fewer than the minimum item lines came back.
  tooFewLines,

  /// WALKTYPE missing, or a verdict the model was not allowed to reach.
  missingVerdict,

  /// NATURE line missing.
  missingNature,

  /// NATURE did not quote the measured minutes, so it was decoration.
  natureWithoutMinutes,

  /// A line too long for a 32-column receipt, or a quantity impossible for
  /// the walk.
  tooLong,

  /// An item line carried no quantity, so there was nothing to print.
  missingQuantity,

  /// The REVIEW or SIGNOFF line was missing.
  missingFooter,

  /// Two lines said the same thing.
  duplicateItem,

  /// The model was not loaded or inference threw.
  unavailable,
}

/// What the receipt says about the walk, beyond the numbers.
///
/// The model supplies all three, and all three are things a template could not
/// produce from the same facts:
///
///  * [walkType] — its verdict on the walk's shape.
///  * [nature] — what the offline minutes did for the natural world.
///  * the item lines and quantities.
class ReceiptVerdict {
  const ReceiptVerdict({
    required this.walkType,
    required this.nature,
  });

  /// The model's read of the walk, one of [kWalkTypes].
  final String walkType;

  /// One line about what being offline for the measured minutes achieved.
  final String nature;
}

/// The verdicts the model is allowed to reach, and the ones a rules engine
/// reaches instead on a fallback receipt — one canonical list, because the
/// prompt's example is derived from [Receipt.verdictFor], and an example the
/// model is not allowed to copy is a trap rather than a demonstration.
///
/// Closed on purpose: a free-text classification cannot be validated, printed
/// or compared against the facts.
const List<String> kWalkTypes = [
  'STEP OUT',
  'ERRAND',
  'A SIT',
  'LOOP',
  'A PROPER WALK',
  'WANDER',
  'ESCAPE',
  'COMMUTE',
];

/// A finished receipt.
class Receipt {
  const Receipt({
    required this.lines,
    required this.review,
    required this.signoff,
    required this.facts,
    required this.verdict,
    this.rejected,
  });

  /// Builds the template receipt used whenever model output is rejected.
  ///
  /// It is deliberately dull but complete: a receipt with a blank item list is
  /// a broken joke, and this project has exactly one screen to get right. The
  /// verdict and nature line are derived from the facts rather than invented,
  /// so a fallback receipt still says something true about the walk.
  factory Receipt.template(WalkFacts facts) {
    final verd = verdictFor(facts);
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
      verdict: verd,
      rejected: ReceiptRejection.unavailable,
    );
  }

  /// The verdict a rules engine would reach, for the template receipt.
  ///
  /// Deliberately crude — one long still stretch means a sit, a long walk means
  /// a loop — because the point of a fallback is to be honest, not clever. It
  /// is also the yardstick the model's own verdict is read against: when the
  /// model calls a 45-minute walk with two long stops a "COMMUTE", that is
  /// visible rather than hidden.
  static ReceiptVerdict verdictFor(WalkFacts facts) {
    final walkType = switch (facts) {
      WalkFacts(minutes: <= 2) => 'STEP OUT',
      WalkFacts(minutes: final m) when facts.stillMinutes > m / 2 => 'A SIT',
      WalkFacts(minutes: >= 45) => 'A PROPER WALK',
      WalkFacts(minutes: >= 20) => 'LOOP',
      _ => 'ERRAND',
    };
    return ReceiptVerdict(walkType: walkType, nature: templateNature(facts));
  }

  /// The nature line the template prints: the minutes, stated plainly.
  static String templateNature(WalkFacts facts) =>
      '${facts.minutes} min off the grid. ${facts.minutes} min of you not '
      'being anywhere near it.';

  final List<ReceiptLine> lines;

  /// A one-star-to-five review of the customer's outing.
  final String review;

  /// The closing line, always "come back tomorrow".
  final String signoff;

  /// The walk's type and its effect on the natural world, as the model judged.
  final ReceiptVerdict verdict;

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
