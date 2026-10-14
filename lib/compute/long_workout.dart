import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

/// The longest session [recoverLongWorkouts] will propose, minutes. Past this
/// a sustained elevation is a day on your feet, not a session to review.
const int kLongWorkoutMaxMin = 360;

/// Window length and step for the windowed pass, seconds. The window must sit
/// under the detector's own [ana.AutoWorkoutDetector.maxWorkoutMin] so its
/// length cap can never trip inside one window; the 50% overlap means a bout
/// cut at one window's edge is whole in the next.
const int _windowS = 100 * 60;
const int _stepS = 50 * 60;

/// Workouts LONGER than the detector's two-hour cap, which it drops outright.
///
/// The analytics detector refuses any merged span over
/// [ana.AutoWorkoutDetector.maxWorkoutMin] (120 min) as "lifestyle activity".
/// That rule was calibrated on a sedentary user's three-hour evening at a
/// steady 131 bpm, and it also drops every real session past two hours — a
/// 2½-hour practice at a high heart rate produced no suggestion at all. The
/// rule lives in the sibling package, so this is orchestration around it, not
/// a second detector: the SAME `detect` runs over overlapping windows shorter
/// than its cap (every other gate — the %HRR floor, the mean-above-floor test,
/// motion or a real HR onset, saved-session exclusion — still applies inside
/// each window), and the pieces are stitched back with the detector's own
/// merge gap.
///
/// Only a stitched span longer than the cap is returned — i.e. exactly what
/// the whole-day pass dropped for length. Anything overlapping a bout that
/// pass already found ([found]) is left to it, so a day with no long session
/// comes out exactly as before. Suggestions only: nothing is logged until the
/// user confirms it.
List<ana.DetectedWorkout> recoverLongWorkouts({
  required List<int> hrTs,
  required List<int> hrBpm,
  required List<ana.DetectedWorkout> found,
  int? restingBpm,
  int? maxBpm,
  List<ana.MotionPoint>? motion,
  List<ana.SavedWorkoutSpan> savedSpans = const [],
}) {
  final n = hrTs.length;
  if (n == 0 || n != hrBpm.length) return const [];
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) => hrTs[a].compareTo(hrTs[b]));
  final ts = [for (final i in order) hrTs[i]];
  final bpm = [for (final i in order) hrBpm[i]];
  final first = ts.first, last = ts.last;
  // Too short a day to hold anything the whole-day pass could have dropped.
  if (last - first <= ana.AutoWorkoutDetector.maxWorkoutMin * 60) {
    return const [];
  }
  final mo = motion == null || motion.isEmpty
      ? null
      : ([...motion]..sort((a, b) => a.ts.compareTo(b.ts)));

  // Each window carries the detector's onset look-back before it, so a bout
  // that starts at the window's edge can still show its HR onset.
  const lead = ana.AutoWorkoutDetector.onsetLookbackS;
  final pieces = <ana.DetectedWorkout>[];
  for (var w = first; w <= last; w += _stepS) {
    final lo = w - lead, hi = w + _windowS;
    final wTs = <int>[], wBpm = <int>[];
    for (var k = 0; k < n; k++) {
      if (ts[k] >= lo && ts[k] < hi) {
        wTs.add(ts[k]);
        wBpm.add(bpm[k]);
      }
    }
    if (wTs.length < 60) continue;
    pieces.addAll(ana.AutoWorkoutDetector.detect(
      hrTs: wTs,
      hrBpm: wBpm,
      restingBpm: restingBpm,
      maxBpm: maxBpm,
      motion: mo == null
          ? null
          : [for (final p in mo) if (p.ts >= lo && p.ts < hi) p],
      savedSpans: savedSpans,
    ));
    if (hi > last) break;
  }
  if (pieces.isEmpty) return const [];

  // Stitch overlapping pieces, and pieces closer than the detector's own
  // merge gap — the same rule the whole-day pass merges its spans by.
  pieces.sort((a, b) => a.startSec.compareTo(b.startSec));
  final spans = <(int, int, String)>[];
  var s = pieces.first.startSec,
      e = pieces.first.endSec,
      sport = pieces.first.sport;
  for (final p in pieces.skip(1)) {
    if (p.startSec - e < ana.AutoWorkoutDetector.mergeGapS) {
      e = math.max(e, p.endSec);
    } else {
      spans.add((s, e, sport));
      s = p.startSec;
      e = p.endSec;
      sport = p.sport;
    }
  }
  spans.add((s, e, sport));

  final out = <ana.DetectedWorkout>[];
  for (final (start, end, sport) in spans) {
    final len = end - start;
    if (len <= ana.AutoWorkoutDetector.maxWorkoutMin * 60) continue;
    if (len > kLongWorkoutMaxMin * 60) continue;
    if (found.any((f) => f.startSec <= end && start <= f.endSec)) continue;
    var sum = 0, cnt = 0, peak = 0;
    for (var k = 0; k < n; k++) {
      if (ts[k] < start || ts[k] > end) continue;
      sum += bpm[k];
      cnt++;
      if (bpm[k] > peak) peak = bpm[k];
    }
    if (cnt == 0) continue;
    out.add(ana.DetectedWorkout(
      startSec: start,
      endSec: end,
      avgBpm: (sum / cnt).round(),
      peakBpm: peak,
      durationMin: len ~/ 60,
      sport: sport,
    ));
  }
  return out;
}
