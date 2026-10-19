// THE nightly HRV on the method WHOOP's data-science lead described publicly
// (WHOOP Community, "HRV extreme spikes", post by the Lead of WHOOP's Data
// Science team, Aug 13 2025):
//
//   "we calculate HRV in overlapping 5-minute windows (stepping forward every
//    30 seconds) throughout your entire sleep. We remove periods of wake, then
//    take a weighted average of the remaining windows. The weights are higher
//    for intervals that occur during likely slow-wave sleep."
//
// The metric inside each window is RMSSD — what the WHOOP validation studies
// compute from its beat intervals (Bellenger et al., Sensors 2021).
//
// EACH WINDOW IS SCORED BY THE ANALYTICS ESTIMATOR ITSELF
// (`sleepSessionRmssdDetail` over that one window), so the beat cleaning, the
// Malik ectopic rule, the 20-difference floor and the duplicated-beat guard
// are exactly the ones the consecutive-window headline used. The windowing and
// the weighting are the only change — not a looser cleaner in disguise.
//
// WHOOP does not publish the weights. OURS (an inference, labelled as one): a
// window counts double when it is mostly NREM by our stager AND its mean heart
// rate sits in the lowest third of the night's windows. Slow-wave sleep is the
// night's lowest, steadiest heart rate; our own light/deep split is the
// weakest part of the app, so the weight does not lean on it alone.
//
// Pure and isolate-safe. The caller keeps the whole-night analytics estimator
// as the gate: this replaces its number only when that estimator was present.

import 'package:openstrap_analytics/onehz.dart' as ana;

/// Length of one RMSSD window.
const int kNightHrvWindowSec = 300;

/// How far each window steps past the last.
const int kNightHrvStepSec = 30;

/// Weight of a likely slow-wave window relative to any other.
const double kNightHrvSlowWaveWeight = 2.0;

class _Window {
  final double rmssd;
  final double meanRrMs;
  final double nremFraction; // −1 when no stages were supplied
  const _Window(this.rmssd, this.meanRrMs, this.nremFraction);
}

/// The nightly RMSSD (ms) on WHOOP's described method, or null when no window
/// qualifies.
///
/// [rrMs]/[rrTsMs] are the night's beat intervals and their end times (epoch
/// ms, ascending). [startSec]/[endSec] bound the sleep session (epoch s).
/// [stagesPerSec] is the per-second stage label from [startSec]
/// ('wake' | 'light' | 'deep' | 'rem' | 'nrem'); empty means none, and then
/// no window is dropped as wake and the slow-wave weight rests on heart rate
/// alone.
double? overlappingNightRmssd({
  required List<double> rrMs,
  required List<double> rrTsMs,
  required int startSec,
  required int endSec,
  List<String> stagesPerSec = const [],
}) {
  if (rrMs.isEmpty ||
      rrMs.length != rrTsMs.length ||
      endSec - startSec < kNightHrvWindowSec) {
    return null;
  }
  final windows = <_Window>[];
  var lo = 0; // first beat that can fall in the current window
  for (var w = startSec;
      w + kNightHrvWindowSec <= endSec;
      w += kNightHrvStepSec) {
    final wEnd = w + kNightHrvWindowSec;

    // Wake removed: a window mostly awake is not a sleep window.
    var nremFrac = -1.0;
    if (stagesPerSec.isNotEmpty) {
      var wake = 0, nrem = 0, known = 0;
      for (var s = w - startSec; s < wEnd - startSec; s++) {
        if (s < 0 || s >= stagesPerSec.length) continue;
        known++;
        final l = stagesPerSec[s];
        if (l == 'wake') {
          wake++;
        } else if (l == 'light' || l == 'deep' || l == 'nrem') {
          nrem++;
        }
      }
      if (known > 0 && wake * 2 > known) continue;
      nremFrac = known == 0 ? -1 : nrem / known;
    }

    // The window's beats, with a second of margin either side: the estimator
    // buckets on the rounded second, so it does its own exact cut.
    while (lo < rrTsMs.length && rrTsMs[lo] < (w - 1) * 1000.0) {
      lo++;
    }
    var hi = lo;
    while (hi < rrTsMs.length && rrTsMs[hi] < (wEnd + 1) * 1000.0) {
      hi++;
    }
    if (hi - lo < 2) continue;
    final rr = rrMs.sublist(lo, hi);
    final ts = rrTsMs.sublist(lo, hi);
    final m = ana.sleepSessionRmssdDetail(rr, ts,
        startSec: w, endSec: wEnd, windowSec: kNightHrvWindowSec);
    if (!m.present) continue;
    var sum = 0.0, n = 0;
    for (final r in rr) {
      if (r >= 300 && r <= 2000) {
        sum += r;
        n++;
      }
    }
    if (n == 0) continue;
    windows.add(_Window(m.value!.rmssd, sum / n, nremFrac));
  }
  if (windows.isEmpty) return null;

  // Likely slow-wave: the lowest third of the night's heart rate (the longest
  // mean intervals), and mostly NREM when stages are known.
  final rrSorted = [for (final w in windows) w.meanRrMs]..sort();
  final slowRr = rrSorted[
      (rrSorted.length * 2 / 3).floor().clamp(0, rrSorted.length - 1)];
  var weighted = 0.0, totalWeight = 0.0;
  for (final w in windows) {
    final slow = w.meanRrMs >= slowRr &&
        (w.nremFraction < 0 || w.nremFraction >= 0.5);
    final weight = slow ? kNightHrvSlowWaveWeight : 1.0;
    weighted += weight * w.rmssd;
    totalWeight += weight;
  }
  return weighted / totalWeight;
}
