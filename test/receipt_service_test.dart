/// Tests for the parts of a receipt that decide whether it is honest.
///
/// The point of these is not coverage. It is that the one rule this project
/// cares about — the model never decides a number — is enforced by a test
/// rather than by a hope. Everything here runs without the 500 MB model.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grass_receipts/models/receipt.dart';
import 'package:grass_receipts/services/receipt_service.dart';

const ReceiptService service = ReceiptService();

final DateTime kStarted = DateTime.utc(2026, 10, 9, 16, 4);
final DateTime kEnded = DateTime.utc(2026, 10, 9, 16, 47);

final WalkFacts kFacts = WalkFacts(
  startedAt: kStarted,
  endedAt: kEnded,
  steps: 1234,
  stillMinutes: 7,
  stepSensorAvailable: true,
);

WalkFacts factsWith({
  bool? stepSensorAvailable,
  int? steps,
  int? stillMinutes,
  DateTime? startedAt,
  int? outMinutes,
}) =>
    WalkFacts(
      startedAt: startedAt ?? kStarted,
      endedAt: kStarted.add(Duration(minutes: outMinutes ?? 43)),
      steps: steps ?? 1234,
      stillMinutes: stillMinutes ?? 7,
      stepSensorAvailable: stepSensorAvailable ?? true,
    );

void main() {
  group('the prompt asks for the facts it was given', () {
    test('states every measured fact, so the model has nothing to invent', () {
      final prompt = service.buildPrompt(kFacts);

      expect(prompt, contains('DURATION: 43 minutes'));
      expect(prompt, contains('STEPS: 1234'));
      expect(prompt, contains('STILL: 7 minutes'));
      expect(prompt, contains('LATE AFTERNOON'));
    });

    test('prices everything at zero', () {
      // "\$" is the escaped dollar in the Dart source; the model must see a
      // plain "$0.00", and a malformed escape here would print a blank price.
      expect(service.buildPrompt(kFacts), contains('\$0.00'));
    });

    test('omits steps entirely when the device has no step sensor', () {
      final prompt = service.buildPrompt(factsWith(stepSensorAvailable: false));
      expect(prompt, isNot(contains('STEPS:')));
    });
  });

  group('parsing good output', () {
    test('keeps the measured lines and adds what the model wrote', () {
      final receipt = service.parseOutput(wellFormed, kFacts)!;

      expect(receipt.lines.first.qty, 1234);
      expect(receipt.lines.first.item, 'STEPS, ON YOUR GOOD LEG');
      expect(receipt.lines.first.measured, isTrue);

      // The measured duration line comes second, before anything the model
      // wrote, so the eye lands on the real numbers.
      expect(receipt.lines[1].qty, 43);
      expect(receipt.lines[1].item, 'MINUTES AWAY FROM THE SCREEN');

      expect(receipt.lines.length, 7);
      expect(receipt.review, '3 stars. Great breeze, no wifi.');
      expect(receipt.signoff, 'Come back tomorrow. Grass misses you.');
      expect(receipt.verdict.walkType, 'ESCAPE');
      expect(receipt.verdict.nature, '43 MINUTES OFF THE GRID. THE BIRDS WON.');
      expect(receipt.usedFallback, isFalse);
    });

    test("keeps the model's chosen quantity, since it answered for it", () {
      // The model is no longer stuck writing "1x" everywhere. Its quantities
      // survive parse, which is what makes them its own claim rather than
      // something the app faked.
      final receipt = service.parseOutput(wellFormed, kFacts)!;
      final birds = receipt.lines
          .firstWhere((l) => l.item == 'BIRD THAT SAW YOU');

      expect(birds.qty, 3);
      expect(birds.measured, isFalse);
    });

    test('cannot fake a measured line, in either direction', () {
      // A model that claims 999 steps is caught by the quantity bound (999 >
      // 1 + 43 minutes), so the fake never reaches the receipt at all.
      final hugeClaim = wellFormed.replaceFirst(
        'ITEM: 3x BIRD THAT SAW YOU',
        'ITEM: 999X STEPS, SOMEHOW',
      );
      expect(service.parseOutput(hugeClaim, kFacts), isNull);

      // A claim inside the bound survives — as an unmeasured line, after the
      // two real ones. The reader can tell which is which.
      final smallClaim = wellFormed.replaceFirst(
        'ITEM: 3x BIRD THAT SAW YOU',
        'ITEM: 12x STEPS, SOMEHOW',
      );
      final receipt = service.parseOutput(smallClaim, kFacts)!;
      expect(receipt.lines.first.measured, isTrue);
      expect(receipt.lines.first.qty, 1234);
      expect(receipt.lines[2].measured, isFalse);
      expect(receipt.lines[2].qty, 12);
      // The name is stored without its prefix, so the widget renders "12x NAME"
      // and the quantity is a number rather than a string to be re-parsed.
      expect(receipt.lines[2].item, 'STEPS, SOMEHOW');
    });
  });

  group('the quantity is verified, not trusted', () {
    test('rejects a quantity impossible for the length of the walk', () {
      // The bound is 1 + 43 = 44, so 45 is one too many.
      final absurd = wellFormed.replaceFirst(
        'ITEM: 3x BIRD THAT SAW YOU',
        'ITEM: 45x BIRD THAT SAW YOU',
      );
      expect(service.parseOutput(absurd, kFacts), isNull);
    });

    test('accepts a quantity at the upper bound', () {
      // 1 + 43 minutes = 44, so this is the largest allowed.
      final boundary = wellFormed.replaceFirst(
        'ITEM: 3x BIRD THAT SAW YOU',
        'ITEM: 44x BIRD THAT SAW YOU',
      );
      final receipt = service.parseOutput(boundary, factsWith(outMinutes: 43))!;
      expect(receipt.lines[2].qty, 44);
    });

    test('scales the bound with the walk, so a short walk cannot claim much',
        () {
      // A ten-minute walk allows at most 11.
      final absurd = wellFormed.replaceFirst(
        'ITEM: 3x BIRD THAT SAW YOU',
        'ITEM: 20x BIRD THAT SAW YOU',
      );
      expect(service.parseOutput(absurd, factsWith(outMinutes: 10)), isNull);
    });

    test('rejects an item line with no quantity at all', () {
      final bare = wellFormed.replaceFirst(
        'ITEM: 3x BIRD THAT SAW YOU',
        'ITEM: BIRD THAT SAW YOU',
      );
      expect(service.parseOutput(bare, kFacts), isNull);
    });
  });

  group('the verdict and nature line', () {
    test('rejects a walk type the model was not allowed to reach', () {
      final invented = wellFormed.replaceFirst(
        'WALKTYPE: ESCAPE',
        'WALKTYPE: A LIFE-CHANGING ODYSSEY',
      );
      expect(service.parseOutput(invented, kFacts), isNull);
      expect(
        service.classifyRejection(invented, kFacts),
        ReceiptRejection.missingVerdict,
      );
    });

    test('rejects a nature line that ignores the measured minutes', () {
      // "43 MINUTES" on a 43-minute walk is right; the same line on a
      // 6-minute walk is decoration, and that is what this catches.
      final receipt = service.parseOutput(wellFormed, kFacts);
      expect(receipt, isNotNull);
      expect(
        service.parseOutput(wellFormed, factsWith(outMinutes: 6)),
        isNull,
      );
    });

    test('rejects a nature line that quotes the right digits wrongly', () {
      // 430 contains 43, but "430 MINUTES" is not "43 minutes", so the
      // whole-number match has to reject it.
      final embedded = wellFormed.replaceFirst(
        '43 MINUTES OFF THE GRID',
        '430 MINUTES OFF THE GRID',
      );
      expect(service.parseOutput(embedded, kFacts), isNull);
      expect(
        service.classifyRejection(embedded, kFacts),
        ReceiptRejection.natureWithoutMinutes,
      );
    });

    test('asks for a phrase instead of a number on a sub-minute walk', () {
      // A 20-second walk has no minutes to quote, so the prompt must not ask
      // for "0 MINUTES" and the check must accept the phrase instead. This is
      // the bug that made the first device run print a template receipt: the
      // model copied the hardcoded "43" out of the example.
      final prompt = service.buildPrompt(factsWith(outMinutes: 0));

      expect(prompt, contains('LESS THAN A MINUTE'));
      expect(prompt, isNot(contains('0 MINUTES')));

      // A sub-minute walk also has maxQty 1, so its fixture is its own.
      final subMinute = '''
WALKTYPE: STEP OUT
ITEM: 1x THE FRONT DOOR
ITEM: 1x COLD AIR, BRIEFLY
ITEM: 1x A CHANGE OF MIND
REVIEW: 2 stars. Did not get far.
SIGNOFF: Come back tomorrow. Grass misses you.
NATURE: LESS THAN A MINUTE OFF THE GRID.
''';
      expect(service.parseOutput(subMinute, factsWith(outMinutes: 0)),
          isNotNull);
      // "0 MINUTES" on a 0-minute walk must not pass: the phrase is the form.
      expect(
        service.parseOutput(
          subMinute.replaceFirst('LESS THAN A MINUTE', '0 MINUTES'),
          factsWith(outMinutes: 0),
        ),
        isNull,
      );
    });

    test('rejects a missing nature line', () {
      final noNature =
          wellFormed.replaceFirst(RegExp(r'NATURE:.*\n'), '');
      expect(
        service.classifyRejection(noNature, kFacts),
        ReceiptRejection.missingNature,
      );
    });
  });

  group('rejecting output that must not be shown', () {
    test('too few item lines', () {
      expect(service.parseOutput('ITEM: A\nITEM: B\n', kFacts), isNull);
      expect(
        service.classifyRejection('ITEM: A\nITEM: B\n', kFacts),
        ReceiptRejection.tooFewLines,
      );
    });

    test('a missing review line', () {
      final noReview =
          wellFormed.replaceFirst(RegExp(r'REVIEW:.*\n'), '');
      final rejection = service.classifyRejection(noReview, kFacts);
      expect(rejection, ReceiptRejection.missingFooter);
    });

    test('a line too long for a 32-column roll', () {
      final tooLong = wellFormed.replaceFirst(
        'ITEM: 3x BIRD THAT SAW YOU',
        'ITEM: 3x AN EXTRAORDINARILY LONG DESCRIPTION OF ONE (1) '
            'UNACCUSTOMED MOMENT OF PERSPECTIVE',
      );
      expect(service.parseOutput(tooLong, kFacts), isNull);
      expect(
        service.classifyRejection(tooLong, kFacts),
        ReceiptRejection.tooLong,
      );
    });

    test('duplicate items', () {
      expect(service.parseOutput(duplicated, kFacts), isNull);
    });
  });

  group('the template receipt', () {
    test('is complete and dull, never blank', () {
      final receipt = Receipt.template(kFacts);

      expect(receipt.lines.length, greaterThanOrEqualTo(2));
      expect(receipt.lines.first.qty, 1234);
      expect(receipt.review, isNotEmpty);
      expect(receipt.signoff, isNotEmpty);
      expect(receipt.usedFallback, isTrue);
    });

    test('drops the step line only when there is no step sensor', () {
      final receipt = Receipt.template(factsWith(stepSensorAvailable: false));
      expect(receipt.lines.any((l) => l.item.contains('STEPS')), isFalse);
      expect(receipt.lines.any((l) => l.item.contains('MINUTES')), isTrue);
    });

    test('adds the still line only when the customer actually stood still', () {
      expect(
        Receipt.template(factsWith(stillMinutes: 1)).lines.any(
          (l) => l.item.contains('DOING NOTHING'),
        ),
        isFalse,
      );
      expect(
        Receipt.template(factsWith(stillMinutes: 9)).lines.any(
          (l) => l.item.contains('DOING NOTHING'),
        ),
        isTrue,
      );
    });

    test('still has a verdict and nature line after a fallback', () {
      // A fallback receipt must not lose the one thing that makes it a
      // judgement rather than a readout. The verdict is derived, not invented.
      final receipt = Receipt.template(kFacts);
      expect(receipt.verdict.walkType, isNotEmpty);
      expect(receipt.verdict.nature, isNotEmpty);

      // 7 minutes still out of 43 is not a sit; 43 minutes is not a loop but a
      // proper walk. The boundaries are asserted rather than assumed.
      expect(receipt.verdict.walkType, 'LOOP');
      expect(
        Receipt.template(factsWith(outMinutes: 45, stillMinutes: 1))
            .verdict
            .walkType,
        'A PROPER WALK',
      );
      expect(
        Receipt.template(factsWith(outMinutes: 5, stillMinutes: 4))
            .verdict
            .walkType,
        'A SIT',
      );
      expect(
        Receipt.template(factsWith(outMinutes: 1, stillMinutes: 0))
            .verdict
            .walkType,
        'STEP OUT',
      );
    });
  });

  group('walk facts', () {
    test('minutes are the wall-clock difference', () {
      expect(kFacts.minutes, 43);
    });

    test('time band describes when the walk started', () {
      expect(kFacts.timeBand, 'LATE AFTERNOON');
      expect(factsWith(startedAt: DateTime.utc(2026, 10, 9, 7, 0)).timeBand,
          'EARLY BIRD');
      expect(factsWith(startedAt: DateTime.utc(2026, 10, 9, 23, 0)).timeBand,
          'AFTER DARK');
    });
  });
}

const String wellFormed = '''
WALKTYPE: ESCAPE
ITEM: 3x BIRD THAT SAW YOU
ITEM: 1x BENCH OCCUPIED, BRIEFLY
ITEM: 1x ONE (1) MOMENT OF PERSPECTIVE
ITEM: 2x BREEZE, MILD, SUSPICIOUS
ITEM: 1x A SENSE OF VICTORY
REVIEW: 3 stars. Great breeze, no wifi.
SIGNOFF: Come back tomorrow. Grass misses you.
NATURE: 43 MINUTES OFF THE GRID. THE BIRDS WON.
''';

const String duplicated = '''
WALKTYPE: ESCAPE
ITEM: 3x BIRD THAT SAW YOU
ITEM: 1x BENCH OCCUPIED, BRIEFLY
ITEM: 1x ONE (1) MOMENT OF PERSPECTIVE
ITEM: 3x BIRD THAT SAW YOU
REVIEW: 3 stars.
SIGNOFF: Come back tomorrow.
NATURE: 43 MINUTES OFFLINE. NOTHING SCROLLED.
''';