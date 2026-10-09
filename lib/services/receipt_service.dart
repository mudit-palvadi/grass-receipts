/// Turning measured facts into a receipt, on device.
///
/// Specification: the challenge prompt for Hacktoberfest Open-Source AI
/// Challenge Week 1 ("Touch Grass", https://dev.to/challenges/hacktoberfest-week1-2026-10-05).
///
/// The single most important property of this file is that **Gemma never gets to
/// decide a number.** Sensors measure steps and minutes; the model supplies only
/// the item names, the review and the signoff. The two measured lines are built
/// here and handed back unmodified, so a model that says "1x STEPS" cannot
/// overwrite the pedometer. A 1B model will occasionally ignore the format, and
/// an invented quantity is worse than a dull one: the joke dies on contact with
/// a number the walker knows is wrong.
///
/// That rule is why the output is line-based (`ITEM: ...`) rather than JSON. A
/// 1B model emits valid JSON reliably enough on a laptop and unreliably on a
/// phone, and a strict parse failure means a fallback receipt. Heads Up made
/// the same trade for the same reason and it held up under live use.
///
/// Prompt construction, parsing and validation are pure and side-effect free so
/// they can be unit tested without the ~557 MB model. Only [printReceipt]
/// touches the inference engine.
library;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:grass_receipts/models/receipt.dart';

/// Shortest and longest receipt we will print. A 32-column thermal roll is
/// roughly 32 characters wide, so every item — including its `3x ` prefix —
/// is capped to fit one line.
const int maxItemLength = 32;

/// Below this many ITEM lines the receipt looks like a failure, not a receipt.
const int minItemLines = 3;
const int maxItemLines = 7;

/// The review and signoff are printed without a quantity prefix, so they get
/// a little more room than an item line.
const int maxFooterLength = 40;

class ReceiptService {
  const ReceiptService();

  // --- Prompt ---------------------------------------------------------------

  /// Builds the receipt prompt from [facts].
  ///
  /// Every number the model is asked to print is stated as a fact in the
  /// prompt, and the model is explicitly told the measured lines are already
  /// written. The style rules matter more than the format rules: without
  /// examples, a 1B model produces "OUTDOOR ACTIVITY COMPLETED" nonsense.
  String buildPrompt(WalkFacts facts) {
    final factsBlock = <String>[
      'DURATION: ${facts.minutes} minutes, starting in the ${facts.timeBand}',
      if (facts.stepSensorAvailable) 'STEPS: ${facts.steps}',
      'STILL: ${facts.stillMinutes} minutes of standing or sitting without moving',
    ].join('\n');

    return '''
You are a thermal receipt printer that went to comedy school.
Turn one person's walk into a receipt for goods and services they did not buy.

Measured facts (never invent a different number):
$factsBlock

Rules:
- ALL CAPS, dry, deadpan, faintly absurd. Think receipt for a feeling.
- 4 to 6 item lines. Each is a thing the customer was charged for.
- Do NOT write a line for the steps or the duration. Those are already printed.
- Keep every line under $maxItemLength characters, including the "3x " prefix.
- Every price is \$0.00. Never a number other than zero.
- Never mention weather, calories, or the model itself.

Reply in exactly this format and nothing else:
ITEM: BIRD THAT SAW YOU
ITEM: BENCH OCCUPIED, BRIEFLY
ITEM: ONE (1) SMALL MOMENT OF PERSPECTIVE
REVIEW: 3 stars. Great breeze, no wifi.
SIGNOFF: Come back tomorrow. Grass misses you.
''';
  }

  // --- Parsing and validation ----------------------------------------------

  /// Extracts a single `FIELD: value` line, like Heads Up's field helper.
  static String? field(String raw, String name) {
    final match = RegExp(
      '^\\s*$name\\s*:\\s*(.+)\$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(raw);
    return match?.group(1)?.trim();
  }

  /// Parses raw model output into a receipt, or null when it must not be shown.
  ///
  /// [facts] supplies the two measured lines, which the model is not allowed to
  /// influence. Returns null on any rejection; [printReceipt] then falls back.
  Receipt? parseOutput(String raw, WalkFacts facts) {
    final items = RegExp(
      r'^\s*ITEM\s*:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    )
        .allMatches(raw)
        .map((m) => m.group(1)!.trim())
        .toList();

    if (items.length < minItemLines) return null;
    if (items.length > maxItemLines) return null;

    final review = field(raw, 'REVIEW');
    final signoff = field(raw, 'SIGNOFF');
    if (review == null || signoff == null) return null;

    final seen = <String>{};
    for (final item in items) {
      // The "3x " prefix takes 3 characters of the 32-column roll.
      if (item.length + 3 > maxItemLength) return null;
      final key = item.toLowerCase();
      if (!seen.add(key)) return null;
    }
    // No quantity prefix on these, so the whole line is the text.
    if (review.length > maxFooterLength) return null;
    if (signoff.length > maxFooterLength) return null;

    // The measured lines come first, so the eye lands on the real numbers.
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
    ];
    for (final item in items) {
      lines.add(ReceiptLine(qty: 1, item: item.toUpperCase()));
    }

    return Receipt(
      lines: lines,
      review: review,
      signoff: signoff,
      facts: facts,
    );
  }

  /// Classifies why [parseOutput] rejected something, for the log and the
  /// write-up's fallback-rate table.
  ReceiptRejection classifyRejection(String raw) {
    final items = RegExp(
      r'^\s*ITEM\s*:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).allMatches(raw).length;
    if (items < minItemLines || items > maxItemLines) {
      return ReceiptRejection.tooFewLines;
    }
    if (field(raw, 'REVIEW') == null || field(raw, 'SIGNOFF') == null) {
      return ReceiptRejection.missingFooter;
    }
    return ReceiptRejection.tooLong;
  }

  // --- Inference (needs the model on device) --------------------------------

  /// True once the engine has a model loaded.
  ///
  /// `getActiveModel()` returns a non-nullable model and *throws* when none is
  /// loaded, so absence is detected by catching rather than by a null check.
  Future<bool> isModelLoaded() async {
    try {
      await FlutterGemma.getActiveModel();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Runs one prompt turn and collects the streamed reply.
  ///
  /// Kept separate from [printReceipt] because the retry reuses the same session:
  /// `addQueryChunk` returns `Future<void>` (not a success flag), and closing
  /// the session between turns would lose the conversation context the retry
  /// needs. Verified against the flutter_gemma 1.11.4 interface.
  Future<String> _turn(
    InferenceModelSession session,
    String prompt,
  ) async {
    await session.addQueryChunk(Message.text(text: prompt, isUser: true));
    final buffer = StringBuffer();
    await for (final chunk in session.getResponseAsync()) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  /// Runs inference for one receipt.
  ///
  /// Never throws: any failure — model missing, inference error, unparseable
  /// output — comes back as [Receipt] with [Receipt.template] and [Receipt.rejected]
  /// set, because this app has exactly one screen and a blank one is a broken
  /// joke. Retries once with a format-only nudge before giving up, which is
  /// cheap and rescues most of the 1B model's fumbles.
  Future<Receipt> printReceipt({required WalkFacts facts}) async {
    try {
      if (!await isModelLoaded()) {
        return Receipt.template(facts);
      }

      final model = await FlutterGemma.getActiveModel(maxTokens: 512);
      final session = await model.createSession();
      try {
        final first = await _turn(session, buildPrompt(facts));
        final parsed = parseOutput(first, facts);
        if (parsed != null) return parsed;

        // One retry with the format restated and the style rules stripped, so
        // the model spends its second attempt on shape rather than on jokes.
        final second = await _turn(session, _formatNudge(buildPrompt(facts)));
        final retryParsed = parseOutput(second, facts);
        if (retryParsed != null) return retryParsed;

        final fallback = Receipt.template(facts);
        return Receipt(
          lines: fallback.lines,
          review: fallback.review,
          signoff: fallback.signoff,
          facts: facts,
          rejected: classifyRejection(second),
        );
      } finally {
        await session.close();
      }
    } catch (_) {
      return Receipt.template(facts);
    }
  }

  /// The prompt used on the retry, with the comedy rules removed.
  static String _formatNudge(String originalPrompt) =>
      'Your last reply was not the required format. Reply with 4 to 6 ITEM '
      'lines in ALL CAPS (no line longer than 32 characters), then one REVIEW '
      'line, then one SIGNOFF line. Nothing else.\n\n$originalPrompt';

  /// Runs one prompt turn and returns the model's raw draft, unvalidated.
  ///
  /// Exposed for the developer screen: seeing what the 1B model actually
  /// produced is the only way to tell a prompt problem from a genuine
  /// fallback-rate problem.
  Future<String> draftReceiptText(WalkFacts facts) async {
    final model = await FlutterGemma.getActiveModel(maxTokens: 512);
    final session = await model.createSession();
    try {
      return await _turn(session, buildPrompt(facts));
    } finally {
      await session.close();
    }
  }
}
