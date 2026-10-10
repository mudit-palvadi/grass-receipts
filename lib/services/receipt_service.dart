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

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gemma/flutter_gemma.dart'
    hide ModelSpec; // Ours, not flutter_gemma's.
import 'package:grass_receipts/models/receipt.dart';
import 'package:grass_receipts/services/gemma_runtime.dart' show ModelSpec;

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
  /// The model is asked for three things a template cannot produce from the
  /// same facts: a verdict on the walk's shape, item lines with quantities it
  /// chooses, and a nature line that has to quote the measured minutes. The
  /// style rules matter more than the format rules — without examples, a 1B
  /// model produces "OUTDOOR ACTIVITY COMPLETED" nonsense.
  String buildPrompt(WalkFacts facts) {
    final factsBlock = <String>[
      'DURATION: ${facts.minutes} minutes, starting in the ${facts.timeBand}',
      if (facts.stepSensorAvailable) 'STEPS: ${facts.steps}',
      'STILL: ${facts.stillMinutes} minutes of standing or sitting without moving',
    ].join('\n');

    // The scale bound is given to the model *and* enforced in parseOutput. One
    // rule, easy to explain: nothing happened more times than there were
    // minutes to happen in.
    final maxQty = 1 + facts.minutes;

    return '''
You are a thermal receipt printer that went to comedy school.
Turn one person's walk into a receipt for goods and services they did not buy.

Measured facts (never invent a different number):
$factsBlock

Rules:
- ALL CAPS, dry, deadpan, faintly absurd. Think receipt for a feeling.
- WALKTYPE must be exactly one of: ${kWalkTypes.join(', ')}.
- 4 to 6 item lines. Each is a thing the customer was charged for.
- Every item line starts with a quantity and x, like "3x BIRD THAT SAW YOU".
  Choose the quantity yourself from the facts. It must be between 1 and $maxQty.
- Do NOT write a line for the steps or the duration. Those are already printed.
- Keep every line under $maxItemLength characters, including the quantity.
- Every price is \$0.00. Never a number other than zero.
- NATURE is one line about what being offline achieved for the natural world.
  It must start with "${facts.minutes} MINUTES".
- Never mention weather, calories, or the model itself.

Reply in exactly this format and nothing else:
WALKTYPE: ESCAPE
ITEM: 3x BIRD THAT SAW YOU
ITEM: 1x BENCH OCCUPIED, BRIEFLY
ITEM: 1x ONE (1) SMALL MOMENT OF PERSPECTIVE
REVIEW: 3 stars. Great breeze, no wifi.
SIGNOFF: Come back tomorrow. Grass misses you.
NATURE: 43 MINUTES OFF THE GRID. THE BIRDS WON.
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
  /// Three rules are enforced here that a template receipt does not need:
  ///
  ///  1. **The model's chosen quantity is bounded, not trusted.** It may write
  ///     `3x BIRD THAT SAW YOU`, and the 3 survives if 1 <= 3 <= 1 + minutes.
  ///     We cannot know the number is *right*; we can know it is impossible.
  ///  2. **The verdict must be one the model was allowed to reach.**
  ///  3. **The nature line must quote the measured minutes.** Otherwise the
  ///     model can write a nature fact unconnected to the walk, which is
  ///     exactly the decoration this change was meant to remove.
  Receipt? parseOutput(String raw, WalkFacts facts) {
    final verdict = _parseVerdict(raw, facts);
    if (verdict == null) return null;

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

    final maxQty = 1 + facts.minutes;
    final seen = <String>{};
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
      final match = _quantity.firstMatch(item);
      if (match == null) return null; // no quantity, so no line to print.

      final qty = int.tryParse(match.group(1)!);
      if (qty == null || qty < 1 || qty > maxQty) return null;

      final name = item.substring(match.end).trim();
      if (name.isEmpty) return null;
      // The "999x " prefix takes up to 5 characters of the 32-column roll.
      if (match.group(0)!.length + name.length > maxItemLength) return null;

      final key = name.toLowerCase();
      if (!seen.add(key)) return null;
      lines.add(ReceiptLine(qty: qty, item: name.toUpperCase()));
    }

    final review = field(raw, 'REVIEW');
    final signoff = field(raw, 'SIGNOFF');
    if (review == null || signoff == null) return null;

    // No quantity prefix on these, so the whole line is the text.
    if (review.length > maxFooterLength) return null;
    if (signoff.length > maxFooterLength) return null;

    return Receipt(
      lines: lines,
      review: review,
      signoff: signoff,
      facts: facts,
      verdict: verdict,
    );
  }

  /// A leading `<n>x ` on an item line, which is how the model states its
  /// chosen quantity.
  static final RegExp _quantity = RegExp(r'^(\d{1,2})x\s+', caseSensitive: false);

  /// Reads WALKTYPE and NATURE, or null when either breaks a rule.
  ReceiptVerdict? _parseVerdict(String raw, WalkFacts facts) {
    final walkType = field(raw, 'WALKTYPE')?.toUpperCase().trim();
    if (walkType == null) return null;
    if (!kWalkTypes.contains(walkType)) return null;

    final nature = field(raw, 'NATURE');
    if (nature == null) return null;
    if (nature.length > maxFooterLength) return null;

    // The nature line has to quote the measured minutes. A line that says
    // "43 MINUTES" about a 6-minute walk is the decoration this rule exists to
    // stop, and quoting the number is what ties it to the walk.
    if (!_quotesNumber(nature, facts.minutes)) return null;

    return ReceiptVerdict(walkType: walkType, nature: nature);
  }

  /// Whether [text] contains [n] as a whole number, not as a digit inside a
  /// larger one.
  ///
  /// Built by concatenation because `'${facts.minutes}'` inside a regex literal
  /// reads as interpolation and silently becomes empty.
  static bool _quotesNumber(String text, int n) =>
      RegExp('(^|[^0-9])$n([^0-9]|\$)').hasMatch(text);

  /// Classifies why [parseOutput] rejected something, for the log and the
  /// write-up's fallback-rate table.
  ///
  /// Order matters: the first rule the output broke is the reason reported, so a
  /// missing WALKTYPE reads as a shape failure rather than a content one.
  ReceiptRejection classifyRejection(String raw, WalkFacts facts) {
    final items = RegExp(
      r'^\s*ITEM\s*:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).allMatches(raw).length;
    if (items < minItemLines || items > maxItemLines) {
      return ReceiptRejection.tooFewLines;
    }
    final walkType = field(raw, 'WALKTYPE')?.toUpperCase().trim();
    if (walkType == null || !kWalkTypes.contains(walkType)) {
      return ReceiptRejection.missingVerdict;
    }
    final nature = field(raw, 'NATURE');
    if (nature == null) return ReceiptRejection.missingNature;
    if (nature.length > maxFooterLength) return ReceiptRejection.tooLong;
    if (!_quotesNumber(nature, facts.minutes)) {
      return ReceiptRejection.natureWithoutMinutes;
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
  /// Kept separate from [printReceipt] because the retry reuses the same chat:
  /// `addQueryChunk` returns `Future<void>` (not a success flag), and closing
  /// between turns would lose the conversation context the retry needs.
  ///
  /// Returns text only. A thinking model streams `ThinkingResponse` events as
  /// well as text, and those are dropped: `/no_think` is set at the chat level,
  /// but a small model ignores instructions inconsistently and one stray
  /// `` block is enough to break a line-based parse.
  Future<String> _turn(InferenceChat chat, String prompt) async {
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final buffer = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) buffer.write(response.token);
    }
    return _cleanModelOutput(buffer.toString());
  }

  /// Strips thinking markers a small model emits even when told not to.
  ///
  /// Channel and think markers are not content, and a receipt that prints
  /// `<|channel|>final` is worse than a template receipt. Runs on every turn,
  /// not just on rejection, because the failure is otherwise silent.
  ///
  /// The patterns are assembled from fragments rather than written inline,
  /// because a marker written literally in source is what makes a reader
  /// think the checker strips only one vendor's format.
  static final String _thinkOpen = '<' 'think' '>';
  static final String _thinkClose = '<' '/' 'think' '>';
  static final RegExp _thinkBlock = RegExp(
    '${RegExp.escape(_thinkOpen)}[\\s\\S]*?${RegExp.escape(_thinkClose)}',
  );
  static final RegExp _channelMarker = RegExp(r'<\|[^|>]*\|>');

  static String _cleanModelOutput(String raw) {
    final withoutThink = raw.replaceAll(_thinkBlock, '');
    final withoutChannels = withoutThink.replaceAll(_channelMarker, '');
    return withoutChannels.trim();
  }

  /// Runs inference for one receipt.
  ///
  /// Never throws: any failure — model missing, inference error, unparseable
  /// output — comes back as [Receipt] with [Receipt.template] and [Receipt.rejected]
  /// set, because this app has exactly one screen and a blank one is a broken
  /// joke. Retries once with a format-only nudge before giving up, which is
  /// cheap and rescues most of the 1B model's fumbles.
  ///
  /// [spec] decides which model is asked, and the only thing that varies is
  /// which of the three it writes with.
  Future<Receipt> printReceipt({
    required WalkFacts facts,
    required ModelSpec spec,
  }) async {
    try {
      if (!await isModelLoaded()) {
        debugPrint('ReceiptService: no model loaded, template receipt');
        return Receipt.template(facts);
      }

      final model = await FlutterGemma.getActiveModel();

      // The chat API, not the raw session. It is the layer that knows about
      // thinking models: for Qwen3 with isThinking false it appends `/no_think`
      // to the prompt, which suppresses the `thought` blocks a 0.6B Qwen3
      // otherwise spends its whole output budget on. The raw session has no
      // `modelType` parameter, so it cannot do this at all.
      final chat = await model.createChat(
        isThinking: false,
        modelType: spec.modelType,
        maxOutputTokens: 512,
      );
      try {
        final first = await _turn(chat, buildPrompt(facts));
        final parsed = parseOutput(first, facts);
        if (parsed != null) return parsed;

        // One retry with the format restated and the style rules stripped, so
        // the model spends its second attempt on shape rather than on jokes.
        final second = await _turn(chat, _formatNudge(buildPrompt(facts)));
        final retryParsed = parseOutput(second, facts);
        if (retryParsed != null) return retryParsed;

        final fallback = Receipt.template(facts);
        final rejection = classifyRejection(second, facts);
        debugPrint('ReceiptService: rejected ($rejection) on both attempts. '
            'raw: ${_snippet(second)}');
        return Receipt(
          lines: fallback.lines,
          review: fallback.review,
          signoff: fallback.signoff,
          facts: facts,
          verdict: fallback.verdict,
          rejected: rejection,
        );
      } finally {
        await chat.close();
      }
    } catch (e, stack) {
      debugPrint('ReceiptService: inference threw: $e\n$stack');
      return Receipt.template(facts);
    }
  }

  /// Trimmed model output for the log.
  ///
  /// A full 512-token rejection is ninety per cent noise; the first few lines
  /// plus the last are enough to see which rule the output broke, and this is
  /// what tells you whether to fix the prompt or accept the fallback rate.
  static String _snippet(String raw) {
    final lines =
        raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.length <= 4) return raw.trim();
    return '${lines.take(3).join(' | ')} ... ${lines.last}';
  }

  /// The prompt used on the retry, with the comedy rules removed.
  static String _formatNudge(String originalPrompt) =>
      'Your last reply was not the required format. Reply with 4 to 6 ITEM '
      'lines in ALL CAPS (no line longer than 32 characters), then one REVIEW '
      'line, then one SIGNOFF line. Nothing else.\n\n$originalPrompt';

  /// Runs one prompt turn and returns the model's raw draft, unvalidated.
  ///
  /// Exposed for the developer screen: seeing what the model actually produced
  /// is the only way to tell a prompt problem from a genuine fallback-rate
  /// problem. This is how the Qwen3 thinking-block bug was found.
  Future<String> draftReceiptText({
    required WalkFacts facts,
    required ModelSpec spec,
  }) async {
    final chat = await FlutterGemma.getActiveModel().then(
      (model) => model.createChat(
        isThinking: false,
        modelType: spec.modelType,
        maxOutputTokens: 512,
      ),
    );
    try {
      return await _turn(chat, buildPrompt(facts));
    } finally {
      await chat.close();
    }
  }
}
