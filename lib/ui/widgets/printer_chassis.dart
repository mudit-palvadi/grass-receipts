/// The printer machine the paper comes out of.
///
/// Only the parts that make the illusion work: a dark rounded slab, a recessed
/// status window, and a slot at the bottom that the paper appears to emerge
/// from. The window reads one of three states, which is what makes the wait
/// before the receipt arrive feel like printing rather than loading.
library;

import 'package:flutter/material.dart';

/// The dark recessed window the status line sits in.
const Color kWindowColor = Color(0xFF14141A);
const Color kWindowInk = Color(0xFFEDEDF2);

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

  /// The receipt, already fed through [PrinterSlot].
  final Widget paper;

  /// Optional widget shown under the window, e.g. a model chip.
  final Widget? trailing;

  static String labelFor(PrinterStage stage) => switch (stage) {
        PrinterStage.idle => 'Waiting for someone to go outside',
        PrinterStage.printing => 'Printing your receipt',
        PrinterStage.done => 'Receipt printed',
      };

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
          offset: const Offset(0, -4),
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
          // A soft drop shadow and a bottom lip, which is what separates
          // "machine" from "dark rectangle".
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
      PrinterStage.printing => const Color(0xFFE8B84B),
      PrinterStage.done => const Color(0xFF5FC98A),
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
          _StatusDot(color: accent, spinning: stage == PrinterStage.printing),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning != oldWidget.spinning) {
      if (widget.spinning) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.spinning) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.35),
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
        boxShadow: [
          // An inner shadow, cheaply: a dark line plus a lighter line below.
          BoxShadow(
            color: kSlotColor,
            blurRadius: 1,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
