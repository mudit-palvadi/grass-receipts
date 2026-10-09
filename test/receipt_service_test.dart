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
      expect(receipt.usedFallback, isFalse);
    });

    test('never lets the model take over the measured line', () {
      // A model that writes its own step count is allowed to — as an unmeasured
      // line. What it may not do is overwrite the pedometer's number.
      final receipt = service.parseOutput(
        wellFormed.replaceFirst(
          'ITEM: BIRD THAT SAW YOU',
          'ITEM: 999X STEPS, SOMEHOW',
        ),
        kFacts,
      )!;

      expect(receipt.lines.first.measured, isTrue);
      expect(receipt.lines.first.qty, 1234);
      // The model's own "999" line lands third, after the two measured lines,
      // and is flagged as unmeasured so a reader can tell which is which.
      expect(receipt.lines[2].measured, isFalse);
      expect(receipt.lines[2].item, '999X STEPS, SOMEHOW');
    });
  });

  group('rejecting output that must not be shown', () {
    test('too few item lines', () {
      expect(service.parseOutput('ITEM: A\nITEM: B\n', kFacts), isNull);
      expect(
        service.classifyRejection('ITEM: A\nITEM: B\n'),
        ReceiptRejection.tooFewLines,
      );
    });

    test('a missing review line', () {
      final noReview =
          wellFormed.replaceFirst(RegExp(r'REVIEW:.*\n'), '');
      final rejection = service.classifyRejection(noReview);
      expect(rejection, ReceiptRejection.missingFooter);
    });

    test('a line too long for a 32-column roll', () {
      final tooLong = wellFormed.replaceFirst(
        'ITEM: BIRD THAT SAW YOU',
        'ITEM: AN EXTRAORDINARILY LONG DESCRIPTION OF ONE (1) UNACCUSTOMED '
            'MOMENT OF PERSPECTIVE',
      );
      expect(service.parseOutput(tooLong, kFacts), isNull);
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
ITEM: BIRD THAT SAW YOU
ITEM: BENCH OCCUPIED, BRIEFLY
ITEM: ONE (1) MOMENT OF PERSPECTIVE
ITEM: BREEZE, MILD, SUSPICIOUS
ITEM: DOG WHO DECIDED YOU WERE OK
REVIEW: 3 stars. Great breeze, no wifi.
SIGNOFF: Come back tomorrow. Grass misses you.
''';

const String duplicated = '''
ITEM: BIRD THAT SAW YOU
ITEM: BENCH OCCUPIED, BRIEFLY
ITEM: ONE (1) MOMENT OF PERSPECTIVE
ITEM: BIRD THAT SAW YOU
REVIEW: 3 stars.
SIGNOFF: Come back tomorrow.
''';
