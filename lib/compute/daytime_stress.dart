// DAYTIME STRESS MONITOR, 0–3 (v118).
//
// What it is: AUTONOMIC ACTIVATION AGAINST YOUR OWN BASELINE, minute by minute
// through the waking day — heart rate above your sleeping resting rate, and
// heart-rate variability below your own still-daytime level — while you are
// still. It is not a psychological stress test and it never says why.
//
// SOURCES (tiers as in research_notes/gaps/stress_load_healthspan_coaching.md):
//  * STRUCTURE — WHOOP's stress patent family (US20240188865A1 / -896A1):
//    a once-per-minute update; an HR weight that rises toward 1 as HR nears
//    the resting rate with the HRV weight = 1 − HR weight; motion used to
//    attribute elevated HR to exercise; a non-linear scaling that puts most
//    estimates at the low end; minutes spent per stress zone. 0–3 with bands
//    0–1 / 1–2 / 2–3 and "3 = your peak" (WHOOP podcast 215, named staff).
//  * PHYSIOLOGY — acute mental stress lowers HRV and raises HR (Castaldo et al.
//    2015 meta-analysis, 12 studies, 758 adults). HRV in motion is not
//    trustworthy on wrist PPG, so only still minutes are scored.
//  * EXERCISE GATE — %HRR ≈ %VO2R (Swain 1997): a minute at ≥ 30 % HRR while
//    moving is activity, not stress.
//
// OURS (labelled, starting values to fit on this wearer — §1.3 of the note):
//  * the HR→HRV hand-over: w_H = 1/(1 + e^((HR − RHR − 15)/4));
//  * the post-exercise tail: excluded until HR is back within 30 % of the way
//    from resting to where the session ended, at most 30 min;
//  * the 0–3 map: 3·(S̃ − p5)/(p99 − p5) on the PRIOR 14 days' own spread
//    (never narrower than [kStressMinSpan]), so your 14-day peak reads 3 and
//    a calm still minute sits low;
//  * a minute counts as still at ≥ 75 % still seconds;
//  * a day publishes a score only with ≥ 60 scored minutes (a "confident"
//    number off twenty minutes was the open honesty bug this replaces).
//
// Light-movement minutes (walking around the house) are NOT scored: the
// published fix for them is a personal additional-heart-rate regression
// (Psychophysiology 2025, PubMed 39562517) that needs its own validation first.
//
// Pure and isolate-safe.

import 'dart:math' as math;

/// Days of personal reference before a score publishes.
const int kStressRefMinDays = 3;

/// Still minutes across the reference window before a score publishes.
const int kStressRefMinMinutes = 600;

/// Scored minutes in a day before the day's score publishes.
const int kStressMinScoredMinutes = 60;

/// A minute is "still" when this share of its seconds are still.
const double kStressStillShare = 0.75;

/// HR→HRV hand-over midpoint (bpm above resting) and width (bpm). Ours.
const double kStressHandoverBpm = 15;
const double kStressHandoverWidth = 4;

/// Reference window (days).
const int kStressRefDays = 14;

/// The narrowest 0→3 span allowed, in the composite's z units (ours). The
/// z's are already divided by the wearer's own spread; a tighter span would
/// stretch a few tenths of noise across the whole scale.
const double kStressMinSpan = 2.0;

/// What one day contributes to LATER days' reference (persisted per day).
class StressDaySummary {
  final double? hMed, hMad, xMed, xMad, sP05, sP99;
  final int nStill;
  const StressDaySummary({
    this.hMed,
    this.hMad,
    this.xMed,
    this.xMad,
    this.sP05,
    this.sP99,
    this.nStill = 0,
  });
}

/// The prior days' summaries, one list per field (oldest first).
class StressHistory {
  final List<double> hMed, hMad, xMed, xMad, sP05, sP99, nStill;
  const StressHistory({
    this.hMed = const [],
    this.hMad = const [],
    this.xMed = const [],
    this.xMad = const [],
    this.sP05 = const [],
    this.sP99 = const [],
    this.nStill = const [],
  });
}

double? _median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _mad(List<double> xs) {
  final m = _median(xs);
  if (m == null) return null;
  return 1.4826 * _median([for (final x in xs) (x - m).abs()])!;
}

double? _quantile(List<double> xs, double q) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final pos = (s.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

List<double> _tail(List<double> xs, int n) =>
    xs.length <= n ? xs : xs.sublist(xs.length - n);

double _zAngle(double x, double y, double z) {
  final d = math.sqrt(x * x + y * y);
  return math.atan2(z, d) * 180 / math.pi;
}

class _Minute {
  final int minute; // epoch minute
  final double hr;
  final double still; // share of still seconds
  final double? lnRmssd;
  _Minute(this.minute, this.hr, this.still, this.lnRmssd);
}

/// The result: the bundle block, this day's summary for the history, and the
/// day score (null when it did not publish).
typedef DaytimeStressResult = ({
  Map<String, dynamic> block,
  StressDaySummary summary,
  double? dayScore,
});

Map<String, dynamic> _absent(String note) => {
      'value': '—',
      'confidence': 0,
      'tier': 'relative',
      'inputs_used': const ['hr_1hz', 'rr_still', 'gravity', 'resting_hr'],
      'note': note,
    };

/// Score the waking day.
///
/// [tsSec]/[hr]/[ax]/[ay]/[az] are the day's 1 Hz substrate (hr 0 = none;
/// a zero gravity vector = absent). [rrMs]/[rrTsMs] are its beats.
/// [excludeSpans] are sleep and nap windows (epoch s, [start, end)).
/// [exerciseSpans] are saved sessions and detected workouts. [restingHr] is
/// the 14-night sleeping resting HR, [maxHr] the training max. [quietCutG] is
/// the family's stillness cut (|‖g‖ − 1|), null for an unknown strap.
DaytimeStressResult daytimeStress({
  required List<int> tsSec,
  required List<int> hr,
  required List<double> ax,
  required List<double> ay,
  required List<double> az,
  required List<double> rrMs,
  required List<double> rrTsMs,
  required List<(int, int)> excludeSpans,
  required List<(int, int)> exerciseSpans,
  required double? restingHr,
  required double? maxHr,
  required double? quietCutG,
  StressHistory history = const StressHistory(),
}) {
  const empty = StressDaySummary();
  if (quietCutG == null) {
    return (
      block: _absent('need_input:name=device_family_stillness_cut'),
      summary: empty,
      dayScore: null,
    );
  }
  if (restingHr == null || maxHr == null || maxHr <= restingHr + 20) {
    return (
      block: _absent('need_input:name=resting_hr'),
      summary: empty,
      dayScore: null,
    );
  }
  bool inSpans(int t, List<(int, int)> spans) {
    for (final s in spans) {
      if (t >= s.$1 && t < s.$2) return true;
    }
    return false;
  }

  // ── per second: still? ────────────────────────────────────────────────
  final stillSec = <int>{};
  final hrByMin = <int, List<int>>{};
  final secByMin = <int, int>{};
  final stillByMin = <int, int>{};
  double? prevAngle;
  for (var i = 0; i < tsSec.length; i++) {
    final t = tsSec[i];
    if (inSpans(t, excludeSpans)) {
      prevAngle = null;
      continue;
    }
    final m = t ~/ 60;
    final x = ax[i], y = ay[i], z = az[i];
    final present = !(x == 0 && y == 0 && z == 0);
    if (hr[i] > 0) (hrByMin[m] ??= <int>[]).add(hr[i]);
    if (!present) {
      prevAngle = null;
      continue;
    }
    secByMin[m] = (secByMin[m] ?? 0) + 1;
    final mag = math.sqrt(x * x + y * y + z * z);
    final ang = _zAngle(x, y, z);
    final steady = prevAngle == null || (ang - prevAngle).abs() < 5;
    prevAngle = ang;
    if ((mag - 1).abs() <= quietCutG && steady) {
      stillSec.add(t);
      stillByMin[m] = (stillByMin[m] ?? 0) + 1;
    }
  }

  // ── per still minute: trailing-5-min ln RMSSD over still beats ────────
  // Successive differences whose two beats both sit in still seconds, beat
  // plausibility 300–2000 ms and the 20 % Malik ectopic rule.
  final sqByMin = <int, List<double>>{};
  double? prev;
  for (var k = 0; k < rrMs.length; k++) {
    final t = rrTsMs[k] ~/ 1000;
    final v = rrMs[k];
    if (!stillSec.contains(t) || v < 300 || v > 2000) {
      prev = null;
      continue;
    }
    if (prev != null && (v - prev).abs() <= 0.2 * prev) {
      final d = v - prev;
      (sqByMin[t ~/ 60] ??= <double>[]).add(d * d);
    }
    prev = v;
  }

  // ── exercise and its tail ─────────────────────────────────────────────
  double? minuteHr(int m) {
    final h = hrByMin[m];
    if (h == null || h.length < 30) return null;
    return h.reduce((a, b) => a + b) / h.length;
  }

  final excludedMin = <int>{};
  for (final s in exerciseSpans) {
    for (var m = s.$1 ~/ 60; m <= (s.$2 - 1) ~/ 60; m++) {
      excludedMin.add(m);
    }
    final endHr = minuteHr((s.$2 - 1) ~/ 60);
    final back = endHr == null ? null : restingHr + 0.3 * (endHr - restingHr);
    for (var k = 0; k < 30; k++) {
      final m = s.$2 ~/ 60 + k;
      final h = minuteHr(m);
      if (back != null && h != null && h <= back) break;
      excludedMin.add(m);
    }
  }

  final minutes = <_Minute>[];
  final keys = hrByMin.keys.toList()..sort();
  for (final m in keys) {
    if (excludedMin.contains(m)) continue;
    final h = minuteHr(m);
    if (h == null) continue;
    final secs = secByMin[m] ?? 0;
    if (secs < 30) continue; // no gravity to call it still or not
    final still = (stillByMin[m] ?? 0) / secs;
    final hrr = (h - restingHr) / (maxHr - restingHr);
    if (hrr >= 0.30 && still < kStressStillShare) continue; // activity
    if (still < kStressStillShare) continue; // moving: not scored (see header)
    // Trailing five minutes of still differences, ≥ 20 of them.
    final sq = <double>[
      for (var j = m - 4; j <= m; j++) ...?sqByMin[j],
    ];
    final ln = sq.length >= 20
        ? math.log(math.sqrt(sq.reduce((a, b) => a + b) / sq.length))
        : null;
    minutes.add(_Minute(m, h, still, ln));
  }

  // ── today's own summary (feeds LATER days only) ───────────────────────
  final hs = [
    for (final mm in minutes) (mm.hr - restingHr) / (maxHr - restingHr),
  ];
  final xs = [for (final mm in minutes) ?mm.lnRmssd];

  // ── the reference: the PRIOR days, never today ────────────────────────
  final hMedH = _tail(history.hMed, kStressRefDays);
  final refDays = hMedH.length;
  final refMinutes =
      _tail(history.nStill, kStressRefDays).fold<double>(0, (a, b) => a + b);
  final haveRef = refDays >= kStressRefMinDays &&
      refMinutes >= kStressRefMinMinutes &&
      history.xMed.isNotEmpty;
  final muH = haveRef ? _median(hMedH)! : _median(hs);
  final sdH = math.max(
      0.02,
      (haveRef
              ? _median(_tail(history.hMad, kStressRefDays))
              : _mad(hs)) ??
          0.02);
  final muX = haveRef
      ? _median(_tail(history.xMed, kStressRefDays))
      : _median(xs);
  final sdX = math.max(
      0.10,
      (haveRef
              ? _median(_tail(history.xMad, kStressRefDays))
              : _mad(xs)) ??
          0.10);

  // ── S per minute, smoothed (≈ 5-min EMA, reset across gaps) ──────────
  const alpha = 0.18126924692201818; // 1 − e^(−1/5)
  final sSmooth = <double>[];
  final hrOnly = <bool>[];
  double? ema;
  int? lastMin;
  for (final mm in minutes) {
    final zH = muH == null ? 0.0 : ((mm.hr - restingHr) / (maxHr - restingHr) - muH) / sdH;
    final zV = (mm.lnRmssd == null || muX == null)
        ? null
        : (muX - mm.lnRmssd!) / sdX;
    final wH = 1 /
        (1 +
            math.exp((mm.hr - restingHr - kStressHandoverBpm) /
                kStressHandoverWidth));
    final s = zV == null ? zH : wH * zH + (1 - wH) * zV;
    if (ema == null || lastMin == null || mm.minute - lastMin > 10) {
      ema = s;
    } else {
      ema = ema + alpha * (s - ema);
    }
    lastMin = mm.minute;
    sSmooth.add(ema);
    hrOnly.add(zV == null);
  }

  final summary = StressDaySummary(
    hMed: _median(hs),
    hMad: _mad(hs),
    xMed: _median(xs),
    xMad: _mad(xs),
    sP05: _quantile(sSmooth, 0.05),
    sP99: _quantile(sSmooth, 0.99),
    nStill: minutes.length,
  );

  if (!haveRef) {
    return (
      block: _absent('need_baseline:have=$refDays,need=$kStressRefMinDays,'
          'still_min=${refMinutes.round()},need_min=$kStressRefMinMinutes'),
      summary: summary,
      dayScore: null,
    );
  }
  final lo = _median(_tail(history.sP05, kStressRefDays));
  final hi = _median(_tail(history.sP99, kStressRefDays));
  if (lo == null || hi == null) {
    return (
      block: _absent('need_baseline:name=stress_spread'),
      summary: summary,
      dayScore: null,
    );
  }
  final span = math.max(kStressMinSpan, hi - lo);
  final scores = [
    for (final s in sSmooth) (3 * (s - lo) / span).clamp(0.0, 3.0).toDouble(),
  ];
  if (scores.length < kStressMinScoredMinutes) {
    return (
      block: _absent('need_input:name=still_minutes,have=${scores.length},'
          'need=$kStressMinScoredMinutes'),
      summary: summary,
      dayScore: null,
    );
  }

  var low = 0, med = 0, high = 0, run = 0, longest = 0;
  int? prevM;
  for (var i = 0; i < scores.length; i++) {
    final s = scores[i];
    if (s < 1) {
      low++;
    } else if (s < 2) {
      med++;
    } else {
      high++;
    }
    final contiguous = prevM != null && minutes[i].minute == prevM + 1;
    run = s >= 2 ? (contiguous ? run + 1 : 1) : 0;
    longest = math.max(longest, run);
    prevM = minutes[i].minute;
  }
  final mean = scores.reduce((a, b) => a + b) / scores.length;
  final bins = <int, List<double>>{};
  for (var i = 0; i < scores.length; i++) {
    (bins[minutes[i].minute ~/ 5] ??= <double>[]).add(scores[i]);
  }
  final binKeys = bins.keys.toList()..sort();
  final timeline = [
    for (final b in binKeys)
      {
        't': b * 300,
        's': double.parse(
            (bins[b]!.reduce((a, c) => a + c) / bins[b]!.length)
                .toStringAsFixed(2)),
      },
  ];
  double peak = 0;
  for (final b in binKeys) {
    final v = bins[b]!.reduce((a, c) => a + c) / bins[b]!.length;
    if (v > peak) peak = v;
  }
  final hrOnlyMin = hrOnly.where((e) => e).length;
  return (
    block: {
      'value': {
        'score': double.parse(mean.toStringAsFixed(2)),
        'peak': double.parse(peak.toStringAsFixed(2)),
        'low_min': low,
        'medium_min': med,
        'high_min': high,
        'longest_high_min': longest,
        'scored_min': scores.length,
        'hr_only_min': hrOnlyMin,
        'timeline': timeline,
      },
      'confidence': double.parse(
          (0.6 * math.min(1.0, scores.length / 240) *
                  (1 - 0.5 * hrOnlyMin / scores.length))
              .toStringAsFixed(3)),
      'tier': 'relative',
      'inputs_used': const ['hr_1hz', 'rr_still', 'gravity', 'resting_hr'],
      'note': 'still minutes only; activation vs your own 14-day baseline, '
          'not a psychological diagnosis',
      'method': 'stress_patent_structure_v1',
    },
    summary: summary,
    dayScore: mean,
  );
}

/// The resting reference: median of the last [kStressRefDays] nights' sleeping
/// resting HR, last night ([lastNight]) included when measured. Null with no
/// night at all — the score abstains rather than price HR against a guess.
double? stressRestingHr(List<double> priorNights, double? lastNight) {
  final all = [...priorNights, ?lastNight];
  return _median(_tail(all, kStressRefDays));
}
