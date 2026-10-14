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

// ── workouts with rests ─────────────────────────────────────────────────────

/// A minute counts toward a session when its mean HR is at least this share of
/// heart-rate reserve above rest — well under the detector's 45% "work" floor,
/// so the rests between sets and drills keep the session open.
const double kSessionActiveFraction = 0.35;

/// Below-active minutes (or minutes with no reading) a session may hold
/// before it closes: a rest between efforts, not the end of the workout.
const int kSessionMaxGapMin = 5;

/// The shortest session proposed, minutes, first hard minute to last.
const int kSessionMinMin = 20;

/// Of a session's minutes with a reading, at least this share must be at the
/// detector's own work floor — real exertion, not just a raised heart rate.
const double kSessionWorkShare = 0.30;

/// A session replaces bouts the other passes found inside it only when it is
/// at least this much longer than them, in minutes. A steady run comes out of
/// both passes at almost the same length and keeps its original bout.
const int kSessionReplaceMarginMin = 30;

/// Workouts with rests in them — intervals, practice, circuits, a lift with
/// conditioning — which the analytics detector cannot see.
///
/// The detector grows a span only while HR stays above its floor (rest + 45%
/// of reserve) with dips of at most 90 s. A session that rests between efforts
/// drops under that floor every few minutes, so it shatters into pieces under
/// the 12-minute minimum and nothing is proposed. Reported: a 2h20 session
/// averaging ~115 bpm with peaks of 150 came back as one 15-minute bout.
///
/// This pass works per minute instead: minutes at or above
/// [kSessionActiveFraction] of reserve hold a session open across rests of up
/// to [kSessionMaxGapMin] minutes; the session is then trimmed to its first and
/// last minute at the detector's own work floor, and kept only when it lasts
/// [kSessionMinMin]+ minutes, [kSessionWorkShare] of it is at work level, and
/// — when the band reported motion — the wrist moved like exercise (the
/// detector's own [ana.AutoWorkoutDetector.motionConfirmMean]).
///
/// Returns [found] with these sessions merged in: a session overlapping
/// nothing is added; one that overlaps found bouts replaces them only when it
/// is [kSessionReplaceMarginMin]+ minutes longer than their combined span.
/// Suggestions only, like every bout: nothing is logged until confirmed.
List<ana.DetectedWorkout> withIntermittentWorkouts({
  required List<int> hrTs,
  required List<int> hrBpm,
  required List<ana.DetectedWorkout> found,
  int? restingBpm,
  int? maxBpm,
  List<ana.MotionPoint>? motion,
  List<ana.SavedWorkoutSpan> savedSpans = const [],
}) {
  final n = hrTs.length;
  if (n == 0 || n != hrBpm.length) return found;
  final rhr = restingBpm ?? ana.AutoWorkoutDetector.defaultRestingHR;
  final hrMax = maxBpm ?? ana.AutoWorkoutDetector.defaultMaxHR;
  if (hrMax <= rhr) return found;
  final work = math.max(
    rhr + ana.AutoWorkoutDetector.elevatedMarginBPM,
    (rhr + ana.AutoWorkoutDetector.hrrFloorFraction * (hrMax - rhr)).round(),
  );
  final active = rhr + kSessionActiveFraction * (hrMax - rhr);

  // Mean HR per epoch minute; a minute needs half its seconds to count.
  final sum = <int, int>{}, cnt = <int, int>{};
  for (var k = 0; k < n; k++) {
    final m = hrTs[k] ~/ 60;
    sum[m] = (sum[m] ?? 0) + hrBpm[k];
    cnt[m] = (cnt[m] ?? 0) + 1;
  }
  final minutes = [for (final m in cnt.keys) if (cnt[m]! >= 30) m]..sort();
  if (minutes.isEmpty) return found;
  double mean(int m) => sum[m]! / cnt[m]!;

  // Runs of active minutes, a rest of up to kSessionMaxGapMin allowed.
  final runs = <(int, int)>[];
  int? runStart, lastActive;
  for (final m in minutes) {
    if (mean(m) < active) continue;
    if (lastActive != null && m - lastActive - 1 > kSessionMaxGapMin) {
      runs.add((runStart!, lastActive));
      runStart = null;
    }
    runStart ??= m;
    lastActive = m;
  }
  if (runStart != null) runs.add((runStart, lastActive!));

  final motionByTs = motion == null || motion.isEmpty ? null : motion;
  final out = [...found];
  for (final (r0, r1) in runs) {
    // Trim to the first and last minute at work level.
    final inRun = [for (final m in minutes) if (m >= r0 && m <= r1) m];
    final hard = [for (final m in inRun) if (mean(m) >= work) m];
    if (hard.isEmpty) continue;
    final s = hard.first, e = hard.last;
    final lenMin = e - s + 1;
    if (lenMin < kSessionMinMin || lenMin > kLongWorkoutMaxMin) continue;
    final present = [for (final m in inRun) if (m >= s && m <= e) m];
    if (hard.length / present.length < kSessionWorkShare) continue;
    final start = s * 60, end = e * 60 + 59;

    if (motionByTs != null) {
      var mSum = 0.0, mCnt = 0;
      for (final p in motionByTs) {
        if (p.ts >= start && p.ts <= end) {
          mSum += p.intensity;
          mCnt++;
        }
      }
      if (mCnt == 0 ||
          mSum / mCnt < ana.AutoWorkoutDetector.motionConfirmMean) {
        continue;
      }
    }
    if (savedSpans.any((w) => w.startSec <= end && start <= w.endSec)) {
      continue;
    }

    final overlapping = [
      for (final f in out)
        if (f.startSec <= end && start <= f.endSec) f,
    ];
    if (overlapping.isNotEmpty) {
      final fs = overlapping.map((f) => f.startSec).reduce(math.min);
      final fe = overlapping.map((f) => f.endSec).reduce(math.max);
      if ((end - start) - (fe - fs) < kSessionReplaceMarginMin * 60) continue;
      out.removeWhere(overlapping.contains);
    }

    var bSum = 0, bCnt = 0, peak = 0, first = end, last = start;
    for (var k = 0; k < n; k++) {
      final t = hrTs[k];
      if (t < start || t > end) continue;
      bSum += hrBpm[k];
      bCnt++;
      if (hrBpm[k] > peak) peak = hrBpm[k];
      if (t < first) first = t;
      if (t > last) last = t;
    }
    if (bCnt == 0) continue;
    out.add(ana.DetectedWorkout(
      startSec: first,
      endSec: last,
      avgBpm: (bSum / bCnt).round(),
      peakBpm: peak,
      durationMin: (last - first) ~/ 60,
    ));
  }
  out.sort((a, b) => a.startSec.compareTo(b.startSec));
  return out;
}
