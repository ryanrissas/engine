// SLEEP STAGES, v118: a per-night, physiology-anchored hidden Markov model.
//
// WHY THIS REPLACES THE RULE STAGER'S STAGES. The analytics rule stager
// (`cardio_stager.dart`) reports, in its own comments, a held-out 4-class
// Cohen's κ of 0.132 against sleep-lab scoring and 11 % wake sensitivity. On
// the same public sleep-lab corpus (DREAMT, 100 nights, used here for
// EVALUATION ONLY — no weights, means or matrices from it ship), this model
// scores a median κ of ≈ 0.22 (≈ 0.26 under age 40). Engine's target for a
// lab-trained model (a later build, once a licensed corpus is in hand) is
// κ ≥ 0.45, against WHOOP 3.0's 0.44 in healthy young adults (Miller 2022)
// and WHOOP 4.0's 0.37 (Schyvens 2025). This is the step between.
//
// HOW IT WORKS (every constant is OURS unless cited):
//  * 30-s epochs over the in-bed window. Features: wrist movement (sum of
//    arm-angle change, van Hees 2015 z-angle — scale-free, so the gravity
//    vector's ~4.6 % gain error cancels), mean heart rate, ln RMSSD, ln HF
//    power and ln LF/HF over ±2.5 min of beats (Task Force 1996 bands), and
//    the heart rate's 5-min variability. Each is scaled against the night's
//    own spread ((x − p50)/(p95 − p5), Altini & Kinnunen 2021).
//  * Four states with physiology-anchored starting means (Tobaldini et al.
//    2013, Front Physiol 4:294: HR and LF/HF lowest and vagal HF highest in
//    deep NREM; REM brings HR rise, vagal withdrawal and fluctuation; wake
//    brings movement and HR rise).
//  * Transitions from typical bout lengths (wake 3, light 10, deep 12, REM
//    15 min) with the AASM structural zeros: no wake → deep, no deep → REM,
//    no REM → deep.
//  * A time-of-night prior: deep likelier early, REM later (Ohayon 2004;
//    Altini 2021 uses the same decay/linear terms).
//  * The means and spreads are then FITTED TO THE WEARER'S OWN NIGHT by EM
//    (Baum–Welch), held toward the anchors so a state keeps its meaning, and
//    the night is decoded by Viterbi.
//
// Seconds the base segmentation marked 'unobserved' stay unobserved. Pure and
// isolate-safe.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

const int kStagerEpochSec = 30;

/// Fewest observed epochs (1 h) before this restages a night.
const int kStagerMinEpochs = 120;

const List<String> _labels = ['wake', 'light', 'deep', 'rem'];

// Starting means per state, in night-scaled units, over
// [motion, HR, ln RMSSD, ln HF, ln LF/HF, HR 5-min SD].
const List<List<double>> _mu0 = [
  [1.5, 0.5, 0.0, -0.2, 0.3, 0.6], // wake
  [-0.2, 0.0, 0.0, 0.0, 0.0, 0.0], // light
  [-0.4, -0.4, 0.2, 0.4, -0.5, -0.4], // deep
  [-0.4, 0.2, -0.1, -0.3, 0.4, 0.4], // REM
];
const double _var0 = 0.15;

/// How many epochs' worth of evidence the anchors are worth in the EM.
const double _anchorEpochs = 10;
const int _emIterations = 8;

/// Base share of wake in the time prior (the rest is shaped by time of night).
const double _wakePrior = 0.15;

List<List<double>> _transitions() {
  const bout = [3.0, 10.0, 12.0, 15.0]; // minutes
  const exits = <Map<int, double>>[
    {1: 0.95, 3: 0.05}, // wake → light / REM (never deep)
    {0: 0.3, 2: 0.4, 3: 0.3}, // light → anything
    {1: 0.9, 0: 0.1}, // deep → light / wake (never REM)
    {1: 0.7, 0: 0.3}, // REM → light / wake (never deep)
  ];
  final t = List.generate(4, (_) => List<double>.filled(4, 0));
  for (var s = 0; s < 4; s++) {
    final stay = 1 - (kStagerEpochSec / 60) / bout[s];
    t[s][s] = stay;
    for (final ex in exits[s].entries) {
      t[s][ex.key] = (1 - stay) * ex.value;
    }
  }
  return [
    for (final row in t) [for (final p in row) math.log(p + 1e-12)],
  ];
}

List<List<double>> _timePrior(int n) {
  final out = <List<double>>[];
  for (var i = 0; i < n; i++) {
    final t = n <= 1 ? 0.0 : i / (n - 1);
    final p = [
      _wakePrior,
      0.55,
      0.20 * 2.2 * math.exp(-2.5 * t),
      0.15 * (0.4 + 1.4 * t),
    ];
    final s = p.reduce((a, b) => a + b);
    out.add([for (final v in p) math.log(v / s)]);
  }
  return out;
}

double _lse(List<double> xs) {
  var m = double.negativeInfinity;
  for (final x in xs) {
    if (x > m) m = x;
  }
  if (m == double.negativeInfinity) return m;
  var s = 0.0;
  for (final x in xs) {
    s += math.exp(x - m);
  }
  return m + math.log(s);
}

List<double?> _scaled(List<double?> v) {
  final present = [for (final x in v) ?x];
  if (present.length < 10) return List<double?>.filled(v.length, null);
  final lo = ana.percentile(present, 5)!;
  final med = ana.percentile(present, 50)!;
  final hi = ana.percentile(present, 95)!;
  final span = math.max(hi - lo, 1e-9);
  return [for (final x in v) x == null ? null : (x - med) / span];
}

List<double?> _rollMean(List<double?> v, int w) {
  final h = w ~/ 2;
  return [
    for (var i = 0; i < v.length; i++)
      () {
        var s = 0.0, n = 0;
        for (var j = math.max(0, i - h); j <= math.min(v.length - 1, i + h); j++) {
          final x = v[j];
          if (x != null) {
            s += x;
            n++;
          }
        }
        return n == 0 ? null : s / n;
      }(),
  ];
}

List<double?> _rollSd(List<double?> v, int w) {
  final h = w ~/ 2;
  return [
    for (var i = 0; i < v.length; i++)
      () {
        final xs = <double>[];
        for (var j = math.max(0, i - h); j <= math.min(v.length - 1, i + h); j++) {
          final x = v[j];
          if (x != null) xs.add(x);
        }
        if (xs.length < 3) return null;
        final m = xs.reduce((a, b) => a + b) / xs.length;
        var s = 0.0;
        for (final x in xs) {
          s += (x - m) * (x - m);
        }
        return math.sqrt(s / (xs.length - 1));
      }(),
  ];
}

/// Per-second 4-class labels over the window, or null when the night is too
/// thinly observed to restage (the caller keeps the base labels).
///
/// [hr]/[accel] are per second from window onset (HR 0 = none); [rrMs]/[rrTsMs]
/// are beats with absolute end times (ms); [baseStages4] is the base
/// segmentation's per-second labels over the same window.
List<String>? restageNight({
  required List<double> hr,
  required List<ana.AccelSample> accel,
  required List<double> rrMs,
  required List<double> rrTsMs,
  required int onsetSec,
  required List<String> baseStages4,
}) {
  final len = baseStages4.length;
  if (len == 0) return null;
  final nE = (len + kStagerEpochSec - 1) ~/ kStagerEpochSec;

  // ── epoch features ────────────────────────────────────────────────────────
  final mot = List<double?>.filled(nE, null);
  final hrE = List<double?>.filled(nE, null);
  final observed = List<bool>.filled(nE, false);
  double? prevAngle;
  for (var e = 0; e < nE; e++) {
    var motSum = 0.0, motN = 0, hrSum = 0.0, hrN = 0, obs = 0;
    for (var s = e * kStagerEpochSec;
        s < math.min(len, (e + 1) * kStagerEpochSec);
        s++) {
      if (baseStages4[s] != 'unobserved') obs++;
      if (s < hr.length && hr[s] > 0) {
        hrSum += hr[s];
        hrN++;
      }
      if (s < accel.length && accel[s].valid) {
        final a = accel[s];
        final h = math.sqrt(a.x * a.x + a.y * a.y);
        if (h > 0 || a.z != 0) {
          final ang = math.atan2(a.z, h) * 180 / math.pi;
          if (prevAngle != null) {
            motSum += (ang - prevAngle).abs();
            motN++;
          }
          prevAngle = ang;
        }
      }
    }
    observed[e] = obs * 2 >= kStagerEpochSec;
    if (motN >= 10) mot[e] = math.log(1 + motSum);
    if (hrN >= 10) hrE[e] = hrSum / hrN;
  }
  if (observed.where((o) => o).length < kStagerMinEpochs) return null;

  // Beats: physiologic gate, then a local-median ectopic rule (|Δ| > 20 %).
  final bt = <double>[], bv = <double>[];
  for (var i = 0; i < rrMs.length && i < rrTsMs.length; i++) {
    final v = rrMs[i];
    if (v < 300 || v > 2000) continue;
    bt.add(rrTsMs[i] / 1000.0);
    bv.add(v);
  }
  final keepT = <double>[], keepV = <double>[];
  for (var i = 0; i < bv.length; i++) {
    final a0 = math.max(0, i - 5), a1 = math.min(bv.length, i + 6);
    final win = bv.sublist(a0, a1)..sort();
    final med = win[win.length ~/ 2];
    if ((bv[i] - med).abs() <= 0.2 * med) {
      keepT.add(bt[i]);
      keepV.add(bv[i]);
    }
  }
  final lnRm = List<double?>.filled(nE, null);
  final lnHf = List<double?>.filled(nE, null);
  final lnLfHf = List<double?>.filled(nE, null);
  final grid = ana.freqGrid(0.04, 0.40, 48);
  var lo = 0;
  // Spectral features every second epoch (±2.5 min windows overlap heavily;
  // the neighbour takes the same value), time-domain every epoch.
  for (var e = 0; e < nE; e++) {
    final mid = onsetSec + e * kStagerEpochSec + kStagerEpochSec / 2;
    while (lo < keepT.length && keepT[lo] < mid - 150) {
      lo++;
    }
    var hi = lo;
    while (hi < keepT.length && keepT[hi] < mid + 150) {
      hi++;
    }
    if (hi - lo < 60) continue;
    var ss = 0.0, n = 0;
    for (var k = lo + 1; k < hi; k++) {
      // Successive only when no beat is missing between them.
      if ((keepT[k] - keepT[k - 1]) * 1000 > 1.5 * keepV[k]) continue;
      final d = keepV[k] - keepV[k - 1];
      ss += d * d;
      n++;
    }
    if (n >= 30) lnRm[e] = math.log(math.sqrt(ss / n));
    if (e.isOdd && e > 0) {
      lnHf[e] = lnHf[e - 1];
      lnLfHf[e] = lnLfHf[e - 1];
      continue;
    }
    final ls = ana.lombScargle(
        keepT.sublist(lo, hi), keepV.sublist(lo, hi), grid);
    if (ls == null) continue;
    final lf = ls.bandPower(0.04, 0.15), hf = ls.bandPower(0.15, 0.40);
    if (lf > 0 && hf > 0) {
      lnHf[e] = math.log(hf);
      lnLfHf[e] = math.log(lf / hf);
    }
  }

  // Motion keeps its own scale (a still night stays readable); the rest are
  // scaled against the night.
  final motPresent = [for (final x in mot) ?x];
  List<double?> motS = List<double?>.filled(nE, null);
  if (motPresent.length >= 10) {
    final med = ana.percentile(motPresent, 50)!;
    final span = math.max(
        ana.percentile(motPresent, 95)! - ana.percentile(motPresent, 5)!,
        1e-9);
    motS = [for (final x in mot) x == null ? null : (x - med) / span];
  }
  final feats = <List<double?>>[
    motS,
    _scaled(_rollMean(hrE, 3)),
    _scaled(_rollMean(lnRm, 5)),
    _scaled(_rollMean(lnHf, 5)),
    _scaled(_rollMean(lnLfHf, 5)),
    _scaled(_rollSd(hrE, 11)),
  ];
  const d = 6;
  final x = [
    for (var e = 0; e < nE; e++) [for (var k = 0; k < d; k++) feats[k][e]],
  ];

  // ── HMM: EM on this night, then Viterbi ───────────────────────────────────
  final lT = _transitions();
  final lp = _timePrior(nE);
  final mu = [for (final r in _mu0) [...r]];
  final va = List.generate(4, (_) => List<double>.filled(d, _var0));

  List<List<double>> emis() => [
        for (var e = 0; e < nE; e++)
          [
            for (var s = 0; s < 4; s++)
              () {
                var l = 0.0;
                for (var k = 0; k < d; k++) {
                  final v = x[e][k];
                  if (v == null) continue;
                  final z = v - mu[s][k];
                  l += -0.5 * (z * z / va[s][k] + math.log(va[s][k]));
                }
                return l;
              }(),
          ],
      ];

  for (var it = 0; it < _emIterations; it++) {
    final b = emis();
    final la = List.generate(nE, (_) => List<double>.filled(4, 0));
    final lb = List.generate(nE, (_) => List<double>.filled(4, 0));
    for (var s = 0; s < 4; s++) {
      la[0][s] = b[0][s] + lp[0][s];
    }
    for (var e = 1; e < nE; e++) {
      for (var s = 0; s < 4; s++) {
        la[e][s] = _lse([for (var r = 0; r < 4; r++) la[e - 1][r] + lT[r][s]]) +
            b[e][s] +
            lp[e][s];
      }
    }
    for (var e = nE - 2; e >= 0; e--) {
      for (var s = 0; s < 4; s++) {
        lb[e][s] = _lse([
          for (var r = 0; r < 4; r++) lT[s][r] + b[e + 1][r] + lp[e + 1][r] + lb[e + 1][r],
        ]);
      }
    }
    // Posteriors → anchored means and spreads, per feature over epochs that
    // carry it.
    final sw = List.generate(4, (_) => List<double>.filled(d, 0));
    final sx = List.generate(4, (_) => List<double>.filled(d, 0));
    final sxx = List.generate(4, (_) => List<double>.filled(d, 0));
    for (var e = 0; e < nE; e++) {
      final g = [for (var s = 0; s < 4; s++) la[e][s] + lb[e][s]];
      final z = _lse(g);
      for (var s = 0; s < 4; s++) {
        final w = math.exp(g[s] - z);
        for (var k = 0; k < d; k++) {
          final v = x[e][k];
          if (v == null) continue;
          sw[s][k] += w;
          sx[s][k] += w * v;
          sxx[s][k] += w * v * v;
        }
      }
    }
    for (var s = 0; s < 4; s++) {
      for (var k = 0; k < d; k++) {
        final w = sw[s][k] + _anchorEpochs;
        final m = (sx[s][k] + _anchorEpochs * _mu0[s][k]) / w;
        final m2 = (sxx[s][k] +
                _anchorEpochs * (_mu0[s][k] * _mu0[s][k] + _var0)) /
            w;
        mu[s][k] = m;
        va[s][k] = (m2 - m * m).clamp(0.03, 1.0);
      }
    }
  }

  final b = emis();
  final dp = List.generate(nE, (_) => List<double>.filled(4, 0));
  final bp = List.generate(nE, (_) => List<int>.filled(4, 0));
  for (var s = 0; s < 4; s++) {
    dp[0][s] = b[0][s] + lp[0][s];
  }
  for (var e = 1; e < nE; e++) {
    for (var s = 0; s < 4; s++) {
      var best = double.negativeInfinity, arg = 0;
      for (var r = 0; r < 4; r++) {
        final v = dp[e - 1][r] + lT[r][s];
        if (v > best) {
          best = v;
          arg = r;
        }
      }
      dp[e][s] = best + b[e][s] + lp[e][s];
      bp[e][s] = arg;
    }
  }
  final path = List<int>.filled(nE, 0);
  var bestLast = double.negativeInfinity;
  for (var s = 0; s < 4; s++) {
    if (dp[nE - 1][s] > bestLast) {
      bestLast = dp[nE - 1][s];
      path[nE - 1] = s;
    }
  }
  for (var e = nE - 1; e > 0; e--) {
    path[e - 1] = bp[e][path[e]];
  }

  return [
    for (var s = 0; s < len; s++)
      baseStages4[s] == 'unobserved'
          ? 'unobserved'
          : _labels[path[s ~/ kStagerEpochSec]],
  ];
}
