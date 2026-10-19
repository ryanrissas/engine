// A SECOND respiratory-rate estimator from beat timing: Schäfer & Kratky's
// "count-adv" (Ann Biomed Eng 36:476, 2008), the time-domain RSA method that
// paper found best of the ones it compared. The exact steps follow the
// open-source RRest toolbox's `CtA.m` (Charlton et al., peterhcharlton/rrest):
//
//   1. the RR tachogram (the FM signal) resampled to 5 Hz;
//   2. band-passed, keeping 0.0665–1 Hz;
//   3. 32-s windows;
//   4. local maxima and minima, and the absolute amplitude difference between
//      each consecutive pair of extrema;
//   5. threshold = 0.3 × the third quartile of those differences;
//   6. repeatedly delete the extrema pair with the smallest difference while
//      it is ≤ the threshold;
//   7. trim so the series starts and ends on a maximum;
//   8. breaths = (extrema − 1) / 2, rate = 60 / mean breath duration.
//
// OUR CHOICES (labelled): the band-pass is a centred 15-s moving-average
// detrend (high-pass, −3 dB near 0.03 Hz, so 0.0665 Hz passes) followed by a
// 3-tap moving average (low-pass, first null at 1.67 Hz) — a cheap
// approximation of RRest's filters, documented as one. Windows step by 16 s.
// A window is used only when the beats inside it are contiguous (no gap
// longer than one beat + 0.5 s) and cover ≥ 80 % of it, and only when its
// rate sits under the tachogram's own Nyquist (0.5 / median NN, DeBoer 1984)
// and inside 6–30 br/min, the band the RSA estimator searches. The nightly
// value is the median over windows.
//
// It is never the headline on its own: the night's rate is the analytics
// Lomb–Scargle RSA estimate, and this one only CORROBORATES it through the
// existing Karlen SD-gate fusion (`fuseRespRate`, gate 2 br/min). When RSA
// withholds, nothing is published.
//
// Pure and isolate-safe.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

const double kCountAdvFs = 5.0; // Hz
const double kCountAdvWindowSec = 32;
const double kCountAdvStepSec = 16;
const double kCountAdvMinCoverage = 0.8;

/// Fewest usable windows for a nightly value (~8 min of breathing).
const int kCountAdvMinWindows = 30;

double? _q(List<double> xs, double p) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final h = (s.length - 1) * p;
  final lo = h.floor(), hi = h.ceil();
  return s[lo] + (s[hi] - s[lo]) * (h - lo);
}

/// Rate (br/min) of one already-filtered 5 Hz window, or null.
double? countAdvWindowRate(List<double> y) {
  if (y.length < 5) return null;
  // Extrema: index and whether it is a maximum.
  final idx = <int>[];
  final isMax = <bool>[];
  for (var i = 1; i < y.length - 1; i++) {
    if (y[i] > y[i - 1] && y[i] >= y[i + 1]) {
      idx.add(i);
      isMax.add(true);
    } else if (y[i] < y[i - 1] && y[i] <= y[i + 1]) {
      idx.add(i);
      isMax.add(false);
    }
  }
  if (idx.length < 3) return null;
  List<double> diffs() => [
        for (var k = 0; k + 1 < idx.length; k++)
          (y[idx[k + 1]] - y[idx[k]]).abs(),
      ];
  final q3 = _q(diffs(), 0.75);
  if (q3 == null || q3 <= 0) return null;
  final thresh = 0.3 * q3;
  while (idx.length >= 3) {
    final d = diffs();
    var m = 0;
    for (var k = 1; k < d.length; k++) {
      if (d[k] < d[m]) m = k;
    }
    if (d[m] > thresh) break;
    idx.removeRange(m, m + 2);
    isMax.removeRange(m, m + 2);
  }
  // Start and end on a maximum.
  while (idx.isNotEmpty && !isMax.first) {
    idx.removeAt(0);
    isMax.removeAt(0);
  }
  while (idx.isNotEmpty && !isMax.last) {
    idx.removeLast();
    isMax.removeLast();
  }
  if (idx.length < 3) return null;
  final breaths = (idx.length - 1) / 2;
  final durSec = (idx.last - idx.first) / kCountAdvFs;
  if (durSec <= 0) return null;
  final rate = 60 / (durSec / breaths);
  return (rate >= 4 && rate <= 60) ? rate : null;
}

List<double> _movingAvg(List<double> x, int half) {
  final n = x.length;
  final out = List<double>.filled(n, 0);
  final pre = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    pre[i + 1] = pre[i] + x[i];
  }
  for (var i = 0; i < n; i++) {
    final a = math.max(0, i - half), b = math.min(n, i + half + 1);
    out[i] = (pre[b] - pre[a]) / (b - a);
  }
  return out;
}

/// The night's count-adv rate from cleaned NN intervals [nnMs] and their beat
/// times [nnTimesMs] (ms), as an analytics [ana.RespEstimate] so it can enter
/// [ana.fuseRespRate]. Absent — never 0 — when too few windows qualify.
ana.Metric<ana.RespEstimate> countAdvRespRate(
  List<double> nnMs,
  List<double> nnTimesMs,
) {
  const inputs = ['rr_cleaned', 'beat_times'];
  ana.Metric<ana.RespEstimate> absent(String note) =>
      ana.Metric<ana.RespEstimate>.absent(
          tier: ana.Tier.high, inputs_used: inputs, note: note);
  if (nnMs.length < 60 || nnMs.length != nnTimesMs.length) {
    return absent('count_adv: too few beats');
  }
  final sortedNn = [...nnMs]..sort();
  final medNnSec = sortedNn[sortedNn.length ~/ 2] / 1000;
  final ceilingBrpm = math.min(30.0, 60 * 0.5 / medNnSec);

  // Contiguous runs of beats.
  final runs = <List<int>>[];
  var start = 0;
  for (var i = 1; i <= nnMs.length; i++) {
    final broken = i == nnMs.length ||
        nnTimesMs[i] - nnTimesMs[i - 1] > nnMs[i] + 500;
    if (broken) {
      if (i - start >= 10) runs.add([start, i]);
      start = i;
    }
  }

  final rates = <double>[];
  var windows = 0;
  for (final r in runs) {
    final t0 = nnTimesMs[r[0]] / 1000, t1 = nnTimesMs[r[1] - 1] / 1000;
    if (t1 - t0 < kCountAdvWindowSec) continue;
    // Resample the tachogram onto a 5 Hz grid (linear between beats).
    final n = ((t1 - t0) * kCountAdvFs).floor() + 1;
    final y = List<double>.filled(n, 0);
    var k = r[0];
    for (var g = 0; g < n; g++) {
      final t = t0 + g / kCountAdvFs;
      while (k + 1 < r[1] - 1 && nnTimesMs[k + 1] / 1000 < t) {
        k++;
      }
      final ta = nnTimesMs[k] / 1000, tb = nnTimesMs[math.min(k + 1, r[1] - 1)] / 1000;
      final ya = nnMs[k], yb = nnMs[math.min(k + 1, r[1] - 1)];
      y[g] = tb > ta ? ya + (yb - ya) * ((t - ta) / (tb - ta)).clamp(0.0, 1.0) : ya;
    }
    final trend = _movingAvg(y, (7.5 * kCountAdvFs).round());
    final hp = [for (var g = 0; g < n; g++) y[g] - trend[g]];
    final bp = _movingAvg(hp, 1);
    final w = (kCountAdvWindowSec * kCountAdvFs).round();
    final step = (kCountAdvStepSec * kCountAdvFs).round();
    for (var s = 0; s + w <= n; s += step) {
      windows++;
      // Coverage: Σ NN of the beats inside the window over its length.
      final ws = t0 + s / kCountAdvFs, we = ws + kCountAdvWindowSec;
      var covered = 0.0;
      for (var b = r[0]; b < r[1]; b++) {
        final tb = nnTimesMs[b] / 1000;
        if (tb > ws && tb <= we) covered += nnMs[b] / 1000;
      }
      if (covered < kCountAdvMinCoverage * kCountAdvWindowSec) continue;
      final rate = countAdvWindowRate(bp.sublist(s, s + w));
      if (rate == null || rate < 6 || rate > ceilingBrpm) continue;
      rates.add(rate);
    }
  }
  if (rates.length < kCountAdvMinWindows) {
    return absent('count_adv: ${rates.length} usable 32-s windows of '
        '$windows, need $kCountAdvMinWindows');
  }
  rates.sort();
  final med = rates[rates.length ~/ 2];
  return ana.Metric<ana.RespEstimate>(
    value: ana.RespEstimate(med, med / 60, null, 'count_adv'),
    confidence: (rates.length / 225).clamp(0.2, 0.8),
    tier: ana.Tier.high,
    inputs_used: inputs,
    note: 'count-adv (Schäfer & Kratky 2008) median of ${rates.length} '
        '32-s windows',
  );
}

/// The night's rate: RSA corroborated by count-adv through the Karlen gate.
/// RSA absent ⇒ absent (count-adv never stands alone). Agreement within
/// [gateBrpm] ⇒ the inverse-variance fusion; disagreement ⇒ RSA at lowered
/// confidence (the analytics rule).
({double? brpm, double confidence, String decision, double? countAdvBrpm})
    fusedNightRespRate(
  ana.Metric<ana.RespEstimate> rsa,
  ana.Metric<ana.RespEstimate> countAdv, {
  double gateBrpm = 2.0,
}) {
  final cta = countAdv.value?.brpm;
  if (!rsa.present) {
    return (brpm: null, confidence: 0, decision: 'none', countAdvBrpm: cta);
  }
  final f = ana.fuseRespRate(rsa, countAdv, sdGateBrpm: gateBrpm);
  final v = f.value;
  final decision = switch (v?.decision) {
    'fused' => 'fused',
    'disagree' => 'disagree',
    _ => 'rsa_only',
  };
  return (
    brpm: v?.brpm ?? rsa.value!.brpm,
    confidence: f.present ? f.confidence : rsa.confidence,
    decision: decision,
    countAdvBrpm: cta,
  );
}
