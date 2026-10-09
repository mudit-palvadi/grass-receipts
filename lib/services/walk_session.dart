/// Measures a walk, and nothing else.
///
/// The phone is in a pocket for the whole outing, so this class is what makes
/// the receipt's numbers real. One pedometer fact drives the design and is easy
/// to get wrong, straight from the plugin's own README:
///
///  `stepCountStream` reports steps **since boot**, not since the listener was
///  attached. Counting the absolute value would print every step taken since
///  the phone was last restarted, so the first event is kept as a baseline and
///  the receipt prints the difference.
///
/// The step sensor is also absent on some phones (the README names Samsung).
/// That is not a failure state to shout about: [WalkFacts.stepSensorAvailable]
/// goes false and the receipt simply drops its measured-step line.
///
/// "Minutes of standing still" is derived from the same stream — a gap of
/// [kStillGapSeconds] between step events. The pedestrian-status sensor could
/// report this directly, but it is absent on phones the step stream works on,
/// so it is deliberately not used: one source that always exists beats two that
/// do not always agree.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';

import '../../models/receipt.dart';

/// Where a walk currently is.
enum WalkPhase {
  /// Not outside yet. No streams running.
  idle,

  /// Outside. Sensors streaming, steps accumulating.
  outside,

  /// Stopped, facts captured, receipt not yet printed.
  done,
}

class WalkSession {
  WalkPhase _phase = WalkPhase.idle;
  WalkPhase get phase => _phase;

  final StreamController<WalkPhase> _phaseChanges =
      StreamController<WalkPhase>.broadcast();
  Stream<WalkPhase> get phaseChanges => _phaseChanges.stream;

  final StreamController<int> _stepChanges =
      StreamController<int>.broadcast();

  /// Steps counted so far, for the live counter on the grass screen.
  Stream<int> get stepChanges => _stepChanges.stream;

  final StreamController<int> _elapsedChanges =
      StreamController<int>.broadcast();

  /// Seconds outside so far, for the live clock on the grass screen.
  Stream<int> get elapsedChanges => _elapsedChanges.stream;

  StreamSubscription<StepCount>? _stepsSub;
  Timer? _ticker;

  DateTime? _startedAt;

  /// Baseline, from the first step event. -1 until that event arrives.
  int _stepsAtStart = -1;
  int _steps = 0;

  /// When the last step event arrived, or null if none has yet.
  DateTime? _lastStepAt;
  int _stillRunSeconds = 0;
  int _longestStillSeconds = 0;
  bool _stepSensorAvailable = true;

  bool get stepSensorAvailable => _stepSensorAvailable;

  int get steps => _steps;

  /// Rounded whole minutes, for `WalkFacts.stillMinutes`.
  int get longestStillMinutes => (_longestStillSeconds / 60).round();

  /// A gap between step events this long counts as standing still.
  ///
  /// Long enough that waiting at a crossing does not register as a rest, short
  /// enough that actually sitting down does.
  static const int kStillGapSeconds = 10;

  /// Starts measuring. Safe to call once per outing.
  ///
  /// Never throws when a sensor is missing: that is a normal phone, not a
  /// failure, and the receipt has to come out either way.
  Future<void> start() async {
    if (_phase != WalkPhase.idle) return;

    _startedAt = DateTime.now();
    _stepsAtStart = -1;
    _steps = 0;
    _lastStepAt = null;
    _stillRunSeconds = 0;
    _longestStillSeconds = 0;
    _stepSensorAvailable = true;

    /// pedometer 4.x exposes these as plain `Stream` getters, not futures, so
    /// there is nothing to await. Both are guarded anyway: a device with no
    /// step sensor either errors the stream or never emits, and neither should
    /// cost the customer their receipt.
    _stepsSub = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepSensorError,
      cancelOnError: false,
    );

    // One timer drives the clock and the still-run accounting together. The
    // pedometer emits at most once a second, which is not precise enough to
    // measure "longest stretch without moving" on its own.
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);

    _phase = WalkPhase.outside;
    _phaseChanges.add(_phase);
  }

  void _onStepCount(StepCount event) {
    if (_stepsAtStart < 0) {
      _stepsAtStart = event.steps;
      return;
    }
    final delta = event.steps - _stepsAtStart;
    if (delta < 0) return; // A reboot resets the counter mid-walk.

    _lastStepAt = DateTime.now();
    if (delta != _steps) {
      _steps = delta;
      _stepChanges.add(_steps);
    }
  }

  void _onStepSensorError(Object error) {
    if (_stepSensorAvailable) {
      debugPrint('WalkSession: step sensor unavailable: $error');
    }
    _stepSensorAvailable = false;
  }

  /// Grows or resets the still-run from the ticker's clock.
  void _accountForStill() {
    final started = _startedAt;
    if (started == null) return;

    // No steps yet means no evidence of anything, so no still-run either.
    if (_steps == 0 || _lastStepAt == null) {
      _stillRunSeconds = 0;
      return;
    }

    final gap = DateTime.now().difference(_lastStepAt!).inSeconds;
    if (gap >= kStillGapSeconds) {
      _stillRunSeconds += 1;
      if (_stillRunSeconds > _longestStillSeconds) {
        _longestStillSeconds = _stillRunSeconds;
      }
    } else {
      _stillRunSeconds = 0;
    }
  }

  void _onTick(Timer _) {
    if (_phase != WalkPhase.outside) return;
    _accountForStill();
    _elapsedChanges.add(DateTime.now().difference(_startedAt!).inSeconds);
  }

  /// Stops measuring and returns the facts.
  WalkFacts? stop() {
    if (_phase == WalkPhase.idle) return null;

    _ticker?.cancel();
    _ticker = null;
    _stepsSub?.cancel();
    _stepsSub = null;

    final facts = WalkFacts(
      startedAt: _startedAt!,
      endedAt: DateTime.now(),
      steps: _steps,
      stillMinutes: longestStillMinutes,
      stepSensorAvailable: _stepSensorAvailable,
    );

    _phase = WalkPhase.done;
    _phaseChanges.add(_phase);
    return facts;
  }

  /// Clears the session so the next outing starts clean.
  void reset() {
    _phase = WalkPhase.idle;
    _phaseChanges.add(_phase);
  }

  void dispose() {
    _ticker?.cancel();
    _stepsSub?.cancel();
    for (final controller in [
      _phaseChanges,
      _stepChanges,
      _elapsedChanges,
    ]) {
      unawaited(controller.close());
    }
  }
}
