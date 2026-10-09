/// The receipt feeding out of the printer.
///
/// This is the one piece of motion in the app that has to feel mechanical
/// rather than smooth. A thermal printer does not slide its paper, it advances
/// it: the head prints a line, the roller ticks, the paper jumps. Slow easing
/// in one continuous glide reads as a web page loading. So the feed is driven
/// in discrete steps, and the number of steps is tied to the number of lines on
/// the paper rather than being a fixed count.
///
/// Three pieces of the illusion:
///
///  1. **The slot shadow travels with the leading edge.** While printing, a
///     blurred dark bar sits on the paper just below the slot. The paper is
///     otherwise uniformly lit, so this is what makes the top of the paper
///     read as *inside* the machine instead of pinned to the chassis.
///  2. **The paper advances in jumps**, driven by [PrintingReveal] below.
///  3. **The torn edge is not revealed early.** The clip is a rectangle, not
///     the paper's own torn shape, so the teeth only appear at the very end.
///
/// All of it runs under `prefers-reduced-motion` in spirit: [animate] false
/// jumps straight to the finished receipt.
library;

import 'package:flutter/material.dart';

import '../../models/receipt.dart';
import 'receipt_paper.dart';

/// The dark recessed window the status line sits in.
const Color kWindowColor = Color(0xFF14141A);

/// The machine itself.
const Color kChassisColor = Color(0xFF26262C);
const Color kChassisEdge = Color(0xFF3D3D48);

/// The dark slit the paper comes through.
const Color kSlotColor = Color(0xFF0D0D10);

/// What the machine is doing, shown on its window.
enum PrinterStage {
  /// Waiting for walkers.
  idle,

  /// The model is writing the receipt.
  printing,

  /// Paper is out, receipt printed.
  done,
}

extension PrinterStageLabel on PrinterStage {
  String get label => switch (this) {
        PrinterStage.idle => 'Waiting for someone to go outside',
        PrinterStage.printing => 'Printing your receipt',
        PrinterStage.done => 'Receipt printed',
      };
}

/// How long the paper takes to feed out, in milliseconds per line.
///
/// A real roll moves a few centimetres a second. Six lines at 110ms each is
/// about a second and a half of total feed, which is long enough to watch and
/// short enough that no one reaches for the phone.
const int kFeedMillisPerLine = 110;

/// The absolute floor on feed duration, for a receipt with only two lines.
const int kFeedMillisFloor = 900;

/// The machine shell: window, slot, and a place for paper to sit.
class PrinterChassis extends StatelessWidget {
  const PrinterChassis({
    super.key,
    required this.stage,
    required this.statusText,
    required this.paper,
    this.trailing,
  });

  final PrinterStage stage;

  /// What the window reads. Defaults to a label derived from [stage].
  final String statusText;

  /// The receipt, already fed through [PrintingReveal].
  final Widget paper;

  /// Optional widget shown under the window, e.g. a model chip.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Machine(
          stage: stage,
          statusText: statusText,
          trailing: trailing,
        ),
        // A hair of spacing, then the slot. The paper's top edge is tucked
        // under the machine so it looks fed through the slot rather than
        // sitting below it.
        Transform.translate(
          offset: const Offset(0, -6),
          child: paper,
        ),
      ],
    );
  }
}

class _Machine extends StatelessWidget {
  const _Machine({
    required this.stage,
    required this.statusText,
    this.trailing,
  });

  final PrinterStage stage;
  final String statusText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kChassisColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kChassisEdge, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Window(stage: stage, statusText: statusText),
          if (trailing != null) ...[
            const SizedBox(height: 8),
            trailing!,
          ],
          const SizedBox(height: 12),
          const _Slot(),
        ],
      ),
    );
  }
}

/// The dark recessed window with the status line.
class _Window extends StatelessWidget {
  const _Window({required this.stage, required this.statusText});

  final PrinterStage stage;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final accent = switch (stage) {
      PrinterStage.idle => const Color(0xFF8A8A99),
      PrinterStage.printing || PrinterStage.done => const Color(0xFF5FC98A),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kWindowColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          _StatusDot(
            color: accent,
            spinning: stage == PrinterStage.printing,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                statusText,
                key: ValueKey(statusText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  letterSpacing: 0.3,
                  color: accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small dot that spins while printing and goes solid green when done.
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.spinning});

  final Color color;
  final bool spinning;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  /// Created eagerly in [initState].
  ///
  /// A `late final` initialised in the field declaration would look tidier and
  /// is wrong: the field runs on first *access*, and when this dot never spins
  /// that first access is `dispose()`. Which then creates a ticker on an
  /// already-deactivated element and throws "Looking up a deactivated widget's
  /// ancestor is unsafe".
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.spinning) _controller!.repeat();
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning == oldWidget.spinning) return;
    final controller = _controller;
    if (controller == null) return;
    if (widget.spinning) {
      controller.repeat();
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!widget.spinning || controller == null) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return RotationTransition(
      turns: controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// The dark slit the paper comes through.
class _Slot extends StatelessWidget {
  const _Slot();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      width: 200,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: kSlotColor,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Feeds the receipt out of the printer in discrete steps.
///
/// The controller drives how much of the paper has appeared. [Align] with an
/// animated `heightFactor` reveals the paper from its top edge downwards, in
/// place, which is how a roll actually feeds: the header prints first and the
/// torn edge appears last. The fraction is then snapped to [kFeedSteps] whole
/// steps, so the paper holds still, jumps a line, holds still. A single
/// continuous glide reads as a web page loading; the jumps are the printer.
class PrintingReveal extends StatelessWidget {
  const PrintingReveal({
    super.key,
    required this.receipt,
    required this.animate,
  });

  final Receipt receipt;

  /// When false the paper is simply there, immediately. Honoured for anyone
  /// with motion sensitivity on.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return ReceiptPaper(receipt: receipt);
    return _PaperFeed(receipt: receipt);
  }
}

/// How many jumps the feed is divided into.
///
/// Not the receipt's line count: the paper has to travel its own height, and
/// enough steps make that travel read as a roller rather than an easing curve.
const int kFeedSteps = 14;

class _PaperFeed extends StatefulWidget {
  const _PaperFeed({required this.receipt});

  final Receipt receipt;

  @override
  State<_PaperFeed> createState() => _PaperFeedState();
}

class _PaperFeedState extends State<_PaperFeed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Roughly the real thing: a roll moves a few centimetres a second, and a
    // handful of lines takes about a second and a half to watch.
    duration: const Duration(milliseconds: 1700),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final shown = _stepped(_controller.value);
          return Align(
            alignment: Alignment.topCenter,
            heightFactor: shown,
            child: _PaperWithLeadingShadow(
              shown: shown,
              receipt: widget.receipt,
            ),
          );
        },
      ),
    );
  }

  /// Snaps the linear feed to whole steps, so the paper advances rather than
  /// sliding. Clamped, because a controller can overshoot on reverse.
  double _stepped(double t) =>
      ((t * kFeedSteps).ceil() / kFeedSteps).clamp(0.0, 1.0);
}

/// The paper, with a shadow along its leading edge while it is still inside the
/// machine.
///
/// The dark band tracks the bottom of the revealed region, which is where the
/// paper is passing through the slot. It fades as the feed completes, so a
/// finished receipt is evenly lit rather than permanently in shadow.
class _PaperWithLeadingShadow extends StatelessWidget {
  const _PaperWithLeadingShadow({
    required this.shown,
    required this.receipt,
  });

  final double shown;
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ReceiptPaper(receipt: receipt),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.22 * (1 - shown)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
