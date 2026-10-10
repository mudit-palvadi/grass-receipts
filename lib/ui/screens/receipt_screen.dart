/// The one screen this app has.
///
/// Three states, matching the three things the machine's window can say:
///
///  * **idle** — a big button saying TOUCHING GRASS. One tap and the phone is
///    supposed to go in a pocket, so nothing else is on screen.
///  * **outside** — a clock, a step counter, and nothing to read. This screen
///    exists to be ignored; if it is interesting the app has failed.
///  * **receipt** — the printed receipt, with a share button underneath.
///
/// Setup (model install, token entry) is a separate screen reached from the
/// idle state, because it is a thing that happens once and never again.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/receipt.dart';
import '../../services/gemma_runtime.dart';
import '../../services/receipt_service.dart';
import '../../services/walk_session.dart';
import '../widgets/printer_chassis.dart';
import '../widgets/receipt_kit.dart';
import '../widgets/receipt_paper.dart';

/// The one colour that means "go": the go-outside button, the download button,
/// and the machine's status dot once a receipt is printed.
const Color kAccent = Color(0xFF5FC98A);

/// Ink for the blank strip of paper still in the machine.
const Color kPaperBlankInk = Color(0xFFCDBFB2);

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final GemmaRuntime _runtime = GemmaRuntime();
  final ReceiptService _receipts = const ReceiptService();
  final WalkSession _walk = WalkSession();

  WalkPhase _phase = WalkPhase.idle;
  Receipt? _receipt;
  String _status = 'Waiting for someone to go outside';
  String? _error;

  int _steps = 0;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _runtime.initialise().then((_) {
      if (mounted) setState(() {});
    });
    _runtime.changes.listen((state) {
      if (!mounted) return;
      setState(() {
        _error = state.status == ModelStatus.failed ? state.message : null;
      });
    });
    _walk.phaseChanges.listen((phase) {
      if (!mounted) return;
      setState(() => _phase = phase);
    });
    _walk.stepChanges.listen((steps) {
      if (!mounted) return;
      setState(() => _steps = steps);
    });
    _walk.elapsedChanges.listen((seconds) {
      if (!mounted) return;
      setState(() => _elapsed = seconds);
    });
  }

  @override
  void dispose() {
    _walk.dispose();
    _runtime.dispose();
    super.dispose();
  }

  bool get _modelReady => _runtime.state.status == ModelStatus.ready;

  Future<void> _onTouchGrass() async {
    HapticFeedback.mediumImpact();

    // Android 10+ gates the step counter behind a runtime permission. Without
    // asking, the first walk of the session silently prints "0x STEPS" and no
    // error ever surfaces. Denied is not fatal: the receipt just drops the
    // measured-step line, which is the honest outcome.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.activityRecognition.request();
      if (!mounted) return;
      setState(() {
        _error = status.isDenied || status.isPermanentlyDenied
            ? 'Step counting needs the "physical activity" permission. '
                'The receipt still prints, minus the step line.'
            : null;
      });
    }

    setState(() => _receipt = null);
    await _walk.start();
  }

  Future<void> _onImBack() async {
    final facts = _walk.stop();
    if (facts == null) return;

    setState(() {
      _status = 'Printing your receipt';
      _receipt = null;
    });

    final receipt = await _receipts.printReceipt(
      facts: facts,
      spec: _runtime.spec,
    );
    if (!mounted) return;
    setState(() {
      _receipt = receipt;
      _status = receipt.usedFallback
          ? 'Receipt printed (model was not at its best)'
          : 'Receipt printed';
    });
  }

  void _reset() {
    _walk.reset();
    setState(() {
      _receipt = null;
      _steps = 0;
      _elapsed = 0;
      _status = 'Waiting for someone to go outside';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101015),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _title(),
                  const SizedBox(height: 20),
                  ..._body(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return Column(
      children: [
        Text(
          'GRASS RECEIPTS',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 3,
                color: const Color(0xFFF2F2F5),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'step outside. press the button. press it again.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8E8E9C),
              ),
        ),
      ],
    );
  }

  List<Widget> _body() {
    if (!_modelReady) return [_setup()];
    if (_phase == WalkPhase.idle) return [_idle()];
    if (_phase == WalkPhase.outside) return [_outside()];
    return [_printed()];
  }

  // --- idle -----------------------------------------------------------------

  Widget _idle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrinterChassis(
          stage: PrinterStage.idle,
          statusText: 'Waiting for someone to go outside',
          // A blank strip so the machine reads as a printer with paper in it.
          paper: const _BlankPaper(),
          trailing: _modelChip(),
        ),
        const SizedBox(height: 22),
        _actionButton(
          label: 'TOUCHING GRASS',
          onPressed: _onTouchGrass,
          color: const Color(0xFF5FC98A),
          foreground: const Color(0xFF0D1F15),
        ),
        const SizedBox(height: 10),
        Text(
          'tap when you leave. tap again when you are back.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6E6E7C),
              ),
        ),
      ],
    );
  }

  // --- outside --------------------------------------------------------------

  Widget _outside() {
    final minutes = (_elapsed / 60).floor();
    final seconds = (_elapsed % 60).toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF26262C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3D3D48), width: 1.5),
          ),
          child: Column(
            children: [
              Text(
                'NOW GOING OUTSIDE',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                      color: const Color(0xFFE8B84B),
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '$minutes:$seconds',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: const Color(0xFFF2F2F5),
                      fontWeight: FontWeight.w300,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _steps == 0 && !_walk.stepSensorAvailable
                    ? 'STEP SENSOR UNAVAILABLE'
                    : '$_steps STEPS',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: const Color(0xFF8E8E9C),
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'put the phone in your pocket',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6E6E7C),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _actionButton(
          label: "I'M BACK",
          onPressed: _onImBack,
          color: const Color(0xFF5FC98A),
          foreground: const Color(0xFF0D1F15),
        ),
      ],
    );
  }

  // --- printed --------------------------------------------------------------

  Widget _printed() {
    final receipt = _receipt;

    // While the model is still writing there is no paper yet. The machine sits
    // with its window spinning and an empty slot, which is the whole wait.
    if (receipt == null) {
      return PrinterChassis(
        stage: PrinterStage.printing,
        statusText: _status,
        paper: const _EmptyPaper(),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrinterChassis(
          stage: PrinterStage.done,
          statusText: _status,
          // The receipt feeds out of the slot in steps rather than appearing
          // already printed. This is the one piece of motion in the app.
          paper: PrintingReveal(receipt: receipt, animate: true),
        ),
        if (receipt.usedFallback) ...[
          const SizedBox(height: 14),
          _fallbackNotice(receipt.rejected),
        ],
        const SizedBox(height: 22),
        _actionButton(
          label: 'AGAIN',
          onPressed: _reset,
          color: kAccent,
          foreground: const Color(0xFF0D1F15),
        ),
      ],
    );
  }

  Widget _fallbackNotice(ReceiptRejection? rejection) {
    final reason = switch (rejection) {
      ReceiptRejection.tooFewLines => 'the model returned too few lines',
      ReceiptRejection.missingVerdict => 'the model did not name a walk type',
      ReceiptRejection.missingNature => 'the model returned no nature line',
      ReceiptRejection.natureWithoutMinutes =>
        'the nature line ignored the minutes',
      ReceiptRejection.missingQuantity => 'an item line had no quantity',
      ReceiptRejection.tooLong => 'a line was too long for the roll',
      ReceiptRejection.missingFooter => 'the model skipped the review',
      ReceiptRejection.duplicateItem => 'the model repeated itself',
      ReceiptRejection.unavailable || null => 'the model was unavailable',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2438),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4A3F63)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFB9A6E0), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Template receipt printed: $reason. Your steps and minutes '
              'are still the real ones.',
              style: const TextStyle(color: Color(0xFFD8CDEF), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // --- setup -----------------------------------------------------------------

  Widget _setup() {
    final state = _runtime.state;
    final busy = state.isBusy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ONE TIME SETUP',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 2,
                color: const Color(0xFF8E8E9C),
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'The receipt is written by a language model running on this phone, '
          'so the model has to live here first.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6E6E7C),
              ),
        ),
        const SizedBox(height: 18),
        _ModelPicker(
          selected: _runtime.spec,
          onSelected: (spec) {
            setState(() => _runtime.setSpec(spec));
          },
        ),
        const SizedBox(height: 14),
        if (_runtime.spec.requiresToken)
          _TokenField(runtime: _runtime)
        else
          const SizedBox.shrink(),
        const SizedBox(height: 14),
        if (busy)
          Column(
            children: [
              LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 8),
              Text(
                '${(state.progress * 100).round()}% of '
                '${_runtime.spec.sizeMb} MB',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF8E8E9C),
                  fontSize: 12,
                ),
              ),
            ],
          )
        else
          _actionButton(
            label: 'DOWNLOAD THE MODEL',
            onPressed: () => _runtime.ensureModelInstalled(),
            color: const Color(0xFF5FC98A),
            foreground: const Color(0xFF0D1F15),
          ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFE07A7A), fontSize: 12),
          ),
        ],      ],
    );
  }

  Widget _modelChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _runtime.spec.label.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 1,
          color: Color(0xFF7A7A88),
        ),
      ),
    );
  }

  Widget _actionButton({    required String label,
    required VoidCallback? onPressed,
    required Color color,
    required Color foreground,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

/// The strip of blank paper sitting in the machine before anything is
/// printed. It is what makes the machine read as a printer rather than a box.
class _BlankPaper extends StatelessWidget {
  const _BlankPaper();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const TornPaperClipper(),
      child: Container(
        height: 160,
        color: kPaperColor,
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          // Dashed rules of the same kind the receipt uses, so the blank strip
          // is visibly the same paper the receipt will be printed on.
          children: const [
            DashedReceiptRule(height: 10, color: kPaperBlankInk),
            DashedReceiptRule(height: 10, color: kPaperBlankInk),
            DashedReceiptRule(height: 10, color: kPaperBlankInk),
            DashedReceiptRule(height: 10, color: kPaperBlankInk),
            DashedReceiptRule(height: 10, color: kPaperBlankInk),
          ],
        ),
      ),
    );
  }
}

/// The slot with nothing coming out of it yet.
///
/// Deliberately the width of the slot and almost no height: a wide blank block
/// while the model thinks reads as a bug, whereas a narrow stub reads as a
/// printer between jobs.
class _EmptyPaper extends StatelessWidget {
  const _EmptyPaper();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const TornPaperClipper(),
      child: Container(
        height: 26,
        width: 200,
        color: kPaperColor,
      ),
    );
  }
}

/// Picks which open-weight model writes the receipts.
///
/// Hand-rolled rather than `RadioListTile`: its `groupValue`/`onChanged` shape
/// is deprecated in current Flutter, and this whole row is one line plus a note
/// that does not need a radio's affordances.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.selected, required this.onSelected});

  final ModelSpec selected;
  final ValueChanged<ModelSpec> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final spec in ModelSpec.all)
          InkWell(
            onTap: () => onSelected(spec),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    spec.id == selected.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: spec.id == selected.id
                        ? const Color(0xFF5FC98A)
                        : const Color(0xFF5E5E6C),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${spec.label}  ·  ${spec.sizeMb} MB',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFE8E8EE),
                          ),
                        ),
                        Text(
                          spec.note,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7A7A88),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A field for a Hugging Face token, held in memory for one download.
///
/// Takes the runtime directly instead of looking one up with
/// `findAncestorStateOfType`, which silently returns null when the widget moves
/// in the tree and is not worth the coupling.
class _TokenField extends StatefulWidget {
  const _TokenField({required this.runtime});

  final GemmaRuntime runtime;

  @override
  State<_TokenField> createState() => _TokenFieldState();
}

class _TokenFieldState extends State<_TokenField> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      obscureText: _obscure,
      onChanged: widget.runtime.setToken,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: Color(0xFFE8E8EE),
      ),
      decoration: InputDecoration(
        labelText: 'HUGGING FACE TOKEN',
        labelStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Color(0xFF7A7A88),
        ),
        helperText: 'Read access to the Gemma repo. Held in memory only.',
        helperStyle: const TextStyle(fontSize: 10, color: Color(0xFF5E5E6C)),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: const Color(0xFF7A7A88),
            size: 18,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF3D3D48)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF5FC98A)),
        ),
      ),
    );
  }
}
