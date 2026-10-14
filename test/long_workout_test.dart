// A session past the analytics detector's two-hour cap is still proposed.
//
// Reported: a 2½-hour session at a high heart rate produced no "did you work
// out?" suggestion — AutoWorkoutDetector drops any merged span over
// maxWorkoutMin (120) as lifestyle activity.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/long_workout.dart';

const int _t0 = 1791900000; // a day's first second

/// A day at [rest] bpm with one session of [minutes] at [hr] starting at
/// [startMin], arm motion on during it.
({List<int> ts, List<int> bpm, List<ana.MotionPoint> motion}) _day({
  required int startMin,
  required int minutes,
  int hr = 150,
  int rest = 68,
  int dayMin = 16 * 60,
}) {
  final ts = <int>[], bpm = <int>[];
  final motion = <ana.MotionPoint>[];
  for (var i = 0; i < dayMin * 60; i++) {
    final inBout = i >= startMin * 60 && i < (startMin + minutes) * 60;
    ts.add(_t0 + i);
    // A little variation so nothing sits exactly on a threshold.
    bpm.add(inBout ? hr + (i % 7) - 3 : rest + (i % 5) - 2);
    motion.add(ana.MotionPoint(_t0 + i, inBout ? 0.35 : 0.02));
  }
  return (ts: ts, bpm: bpm, motion: motion);
}

List<ana.DetectedWorkout> _base(
        ({List<int> ts, List<int> bpm, List<ana.MotionPoint> motion}) d) =>
    ana.AutoWorkoutDetector.detect(
      hrTs: d.ts,
      hrBpm: d.bpm,
      restingBpm: 55,
      maxBpm: 195,
      motion: d.motion,
    );

void main() {
  _intermittentTests();

  test('the whole-day detector drops a 150-min session (the bug)', () {
    final d = _day(startMin: 300, minutes: 150);
    expect(_base(d), isEmpty);
  });

  test('a 150-min session comes back as one workout', () {
    final d = _day(startMin: 300, minutes: 150);
    final long = recoverLongWorkouts(
      hrTs: d.ts,
      hrBpm: d.bpm,
      found: _base(d),
      restingBpm: 55,
      maxBpm: 195,
      motion: d.motion,
    );
    expect(long, hasLength(1));
    final w = long.single;
    // Within a minute of the real edges either side.
    expect((w.startSec - (_t0 + 300 * 60)).abs(), lessThan(60));
    expect((w.endSec - (_t0 + 450 * 60)).abs(), lessThan(60));
    expect(w.durationMin, inInclusiveRange(148, 150));
    expect(w.avgBpm, inInclusiveRange(145, 155));
    expect(w.peakBpm, greaterThanOrEqualTo(w.avgBpm));
  });

  test('a session under two hours is left to the whole-day pass', () {
    final d = _day(startMin: 300, minutes: 45);
    final base = _base(d);
    expect(base, hasLength(1));
    expect(
      recoverLongWorkouts(
        hrTs: d.ts,
        hrBpm: d.bpm,
        found: base,
        restingBpm: 55,
        maxBpm: 195,
        motion: d.motion,
      ),
      isEmpty,
    );
  });

  test('a span already logged is never proposed', () {
    final d = _day(startMin: 300, minutes: 150);
    expect(
      recoverLongWorkouts(
        hrTs: d.ts,
        hrBpm: d.bpm,
        found: const [],
        restingBpm: 55,
        maxBpm: 195,
        motion: d.motion,
        savedSpans: [
          ana.SavedWorkoutSpan(_t0 + 300 * 60, _t0 + 450 * 60),
        ],
      ),
      isEmpty,
    );
  });

  test('a still wrist at the same heart rate is not a workout', () {
    final d = _day(startMin: 300, minutes: 150);
    final still = [
      for (final p in d.motion) ana.MotionPoint(p.ts, 0.02),
    ];
    // The session's onset is a real ~80 bpm jump, which the detector accepts
    // in place of motion (cycling, rowing), so flatten the onset too: a slow
    // drift up, like a fever, is what must stay unproposed.
    final bpm = [
      for (var i = 0; i < d.ts.length; i++)
        i >= 240 * 60 && i < 300 * 60
            ? 68 + ((i - 240 * 60) * 82 ~/ (60 * 60))
            : d.bpm[i],
    ];
    expect(
      recoverLongWorkouts(
        hrTs: d.ts,
        hrBpm: bpm,
        found: const [],
        restingBpm: 55,
        maxBpm: 195,
        motion: still,
      ),
      isEmpty,
    );
  });
}

/// 16 h at rest with a 140-min interval session from minute 300: 4 min at
/// 132 bpm, 2 min resting at 100, repeated — practice, a circuit, intervals.
({List<int> ts, List<int> bpm, List<ana.MotionPoint> motion}) _intervalDay(
    {double motionInSession = 0.3}) {
  final ts = <int>[], bpm = <int>[];
  final motion = <ana.MotionPoint>[];
  for (var i = 0; i < 16 * 3600; i++) {
    final m = i ~/ 60;
    final inSession = m >= 300 && m < 440;
    final h = inSession ? ((m - 300) % 6 < 4 ? 132 : 100) : 62;
    ts.add(_t0 + i);
    bpm.add(h + (i % 5) - 2);
    motion.add(ana.MotionPoint(_t0 + i, inSession ? motionInSession : 0.02));
  }
  return (ts: ts, bpm: bpm, motion: motion);
}

List<ana.DetectedWorkout> _all(
    ({List<int> ts, List<int> bpm, List<ana.MotionPoint> motion}) d) {
  final base = ana.AutoWorkoutDetector.detect(
      hrTs: d.ts, hrBpm: d.bpm, restingBpm: 45, maxBpm: 192, motion: d.motion);
  final long = recoverLongWorkouts(
      hrTs: d.ts,
      hrBpm: d.bpm,
      found: base,
      restingBpm: 45,
      maxBpm: 192,
      motion: d.motion);
  return withIntermittentWorkouts(
      hrTs: d.ts,
      hrBpm: d.bpm,
      found: [...base, ...long],
      restingBpm: 45,
      maxBpm: 192,
      motion: d.motion);
}

void _intermittentTests() {
  group('workouts with rests', () {
    test('the whole-day detector shatters an interval session (the bug)', () {
      final d = _intervalDay();
      expect(
          ana.AutoWorkoutDetector.detect(
              hrTs: d.ts,
              hrBpm: d.bpm,
              restingBpm: 45,
              maxBpm: 192,
              motion: d.motion),
          isEmpty);
    });

    test('it comes back as one session, trimmed to the hard minutes', () {
      final w = _all(_intervalDay()).single;
      expect(w.startSec, _t0 + 300 * 60);
      expect((w.endSec - (_t0 + 440 * 60)).abs(), lessThan(60));
      expect(w.durationMin, inInclusiveRange(138, 140));
      expect(w.avgBpm, inInclusiveRange(115, 125));
    });

    test('a still wrist at the same heart rate is not a workout', () {
      expect(_all(_intervalDay(motionInSession: 0.02)), isEmpty);
    });

    test('a steady run keeps the bout the detector found, edges and all', () {
      final d = _day(startMin: 300, minutes: 40);
      final base = _base(d);
      expect(base, hasLength(1));
      final all = withIntermittentWorkouts(
          hrTs: d.ts,
          hrBpm: d.bpm,
          found: base,
          restingBpm: 55,
          maxBpm: 195,
          motion: d.motion);
      expect(all, hasLength(1));
      expect(all.single.startSec, base.single.startSec);
      expect(all.single.endSec, base.single.endSec);
    });

    test('a logged session is never proposed again', () {
      final d = _intervalDay();
      final base = ana.AutoWorkoutDetector.detect(
          hrTs: d.ts, hrBpm: d.bpm, restingBpm: 45, maxBpm: 192, motion: d.motion);
      expect(
        withIntermittentWorkouts(
          hrTs: d.ts,
          hrBpm: d.bpm,
          found: base,
          restingBpm: 45,
          maxBpm: 192,
          motion: d.motion,
          savedSpans: [ana.SavedWorkoutSpan(_t0 + 320 * 60, _t0 + 330 * 60)],
        ),
        isEmpty,
      );
    });
  });
}
