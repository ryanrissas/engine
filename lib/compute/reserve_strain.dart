// THE 0–21 STRAIN, on the structure WHOOP published in its strain patent
// (US 10,182,726 B2, priority 2012, granted 2019):
//
//   1. every minute's heart rate becomes a heart-rate-reserve fraction
//        v = (HR − RHR) / (HRmax − RHR), clamped to [0, 1];
//   2. each minute is weighted by a STRICTLY INCREASING function of v (the
//      patent's example is a step table 0 / 1 / 18 / 42 by reserve band);
//   3. the weighted minutes are summed over the window;
//   4. the sum is normalised by the most it could ever be — the top weight
//      for 24 hours — so 1.0 means "24 hours at max heart rate";
//   5. that fraction goes through a monotone saturating map and is
//      multiplied by 21.
//
// WHOOP publishes the structure, not the constants. The two free constants
// here are FITTED to the reference values WHOOP itself has published:
//   1 h walk ≈ 6.5 and 1 h run ≈ 12.0 (WHOOP Strain Coach, 2019),
//   a 45-min run 12–15 (WHOOP, "How WHOOP detects and labels activities",
//   2026), an average member day ≈ 11 (2019), 24 h at max = 21 (by design).
// The fit lands within ~0.5 strain of every anchor. The heart-rate reserve
// each anchor corresponds to (walk ≈ 35 %, run ≈ 72 %, hard run ≈ 82 %) is OUR
// assumption, not WHOOP's — this is an inferred reproduction of the published
// scale, not WHOOP's production model.
//
// Two departures from the patent's example, both deliberate:
//   * The weight is a smooth exponential rather than a step table, so a run
//     hovering on a band edge cannot jump the score by a whole category. The
//     shape is the same — near-zero at rest, rising steeply toward max.
//   * The map is logarithmic (WHOOP's own word for the scale), not arctan:
//     an arctan centred anywhere cannot fit a walk at 6.5 and a run at 12.
//
// WHAT THIS REPLACED: a Banister TRIMP above the user's own "quiet waking"
// level. That number needed three prior days before it showed anything, could
// FALL during a quiet afternoon, and discarded most time in the lower zones —
// so a lifting or baseball session (mostly Zone 1–2 on a wrist) read near 5
// where WHOOP's published scale puts it near 10. The Banister TRIMP is still
// computed and stored as the training-load number behind fitness/fatigue; it
// is just no longer the headline 0–21.
//
// Needs only resting HR and a max HR. No sex constant, no baseline days: it
// scores from the first day there is a resting heart rate. Monotone: strain
// can only build through a window.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

/// Steepness of the minute weight over heart-rate reserve. Fitted (see file
/// header). At this value the weight doubles about every 7 points of reserve:
/// a minute at 35 % weighs ~0.1 % of a minute at max, one at 72 % ~5.6 %.
const double kStrainWeightCurvature = 10.3;

/// Scale of the logarithmic 0–21 map. Fitted (see file header).
const double kStrainLogScale = 1.585e6;

/// Minutes in the normalising window: "24 hours at max heart rate".
const double kStrainNormMinutes = 1440;

/// Weight of one minute at heart-rate-reserve fraction [hrr]: 0 at rest, 1 at
/// max, strictly increasing between.
double strainMinuteWeight(double hrr) {
  final v = hrr.clamp(0.0, 1.0);
  return (math.exp(kStrainWeightCurvature * v) - 1) /
      (math.exp(kStrainWeightCurvature) - 1);
}

/// Map a weighted-minute load onto 0–21. 1440 weighted minutes (a full day at
/// max) is 21.
double strainFromLoad(double weightedMinutes) {
  final n = (weightedMinutes / kStrainNormMinutes).clamp(0.0, 1.0);
  return 21 * math.log(1 + kStrainLogScale * n) / math.log(1 + kStrainLogScale);
}

/// Reserve fraction of [hr] between [restingHr] and [maxHr]. Null when the
/// anchors cannot define a reserve.
double? _hrr(double hr, double restingHr, double maxHr) {
  final span = maxHr - restingHr;
  if (!(span > 0)) return null;
  return ((hr - restingHr) / span).clamp(0.0, 1.0);
}

bool _anchorsOk(double? restingHr, double? maxHr) =>
    restingHr != null &&
    maxHr != null &&
    restingHr > 0 &&
    maxHr > restingHr + 20;

/// The weighted-minute load of a per-minute HR series ([hrPerMin], one value
/// per minute, ≤ 0 = no reading). Null without usable anchors.
double? strainLoad(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
}) {
  if (!_anchorsOk(restingHr, maxHr)) return null;
  var load = 0.0;
  for (final hr in hrPerMin) {
    if (!(hr > 0)) continue;
    load += strainMinuteWeight(_hrr(hr, restingHr!, maxHr!)!);
  }
  return load;
}

/// THE headline 0–21 strain of a per-minute HR series, as a [ana.Metric].
/// Absent — never 0 — without anchors or without a single valid minute.
ana.Metric<double> reserveStrainMetric(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
}) {
  const inputs = ['hr_1hz', 'resting_hr', 'max_hr'];
  if (!_anchorsOk(restingHr, maxHr)) {
    return const ana.Metric<double>.absent(
      tier: ana.Tier.estimate,
      inputs_used: inputs,
      note: 'need_input:name=resting_hr',
    );
  }
  final valid = hrPerMin.where((h) => h > 0).length;
  if (valid == 0) {
    return const ana.Metric<double>.absent(
      tier: ana.Tier.estimate,
      inputs_used: inputs,
      note: 'need_input:name=hr_samples',
    );
  }
  final load = strainLoad(hrPerMin, restingHr: restingHr, maxHr: maxHr)!;
  return ana.Metric<double>(
    value: strainFromLoad(load),
    // Coverage of the window, not a claim about the model: a day with only a
    // few hours of HR has a strain, but a lower-confidence one.
    confidence: (valid / hrPerMin.length).clamp(0.0, 1.0),
    tier: ana.Tier.estimate,
    inputs_used: inputs,
    note: 'reserve_strain_v1',
  );
}

/// The headline value, or null. Convenience for callers that store a scalar.
double? reserveStrain(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
}) {
  final m = reserveStrainMetric(hrPerMin, restingHr: restingHr, maxHr: maxHr);
  return m.present ? m.value : null;
}

/// Cumulative strain after each minute — monotone non-decreasing, and the last
/// point IS [reserveStrain] of the same series. Null without anchors.
List<double>? reserveStrainCurve(
  List<double> hrPerMin, {
  required double? restingHr,
  required double? maxHr,
}) {
  if (!_anchorsOk(restingHr, maxHr) || hrPerMin.isEmpty) return null;
  var load = 0.0;
  return [
    for (final hr in hrPerMin)
      strainFromLoad(load += hr > 0
          ? strainMinuteWeight(_hrr(hr, restingHr!, maxHr!)!)
          : 0),
  ];
}
