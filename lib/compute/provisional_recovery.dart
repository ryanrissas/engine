// A PROVISIONAL recovery for a wearer's first two weeks.
//
// WHOOP shows a first, "calibrating" recovery after about four nights
// ("scores greyed out over the first 4 days", WHOOP Podcast 040, 2019) and
// refines it as the baseline grows. Engine's readiness composite needed 14
// nights of baseline per input before it scored at all — about three weeks of
// nothing for a new wearer.
//
// From [kProvisionalRecoveryNights] nights of baseline on BOTH autonomic
// inputs (HRV and resting HR) the same composite is computed against the
// short baseline, then its z is SHRUNK toward 0 in proportion to how short the
// baseline is (n / 14): a robust z on four nights is mostly noise, and the
// analytics file documents what an unshrunk one did ("[58, 58, 59] bpm … a
// published score of 99.949"). At 4 nights a z of 2 reads as 0.57 (≈ 64 %),
// at 13 nights as 1.86. The quantised-dispersion guard and every other
// refusal inside the composite still apply.
//
// The result is labelled `provisional` everywhere it travels. At 14 nights the
// ordinary composite takes over and this never runs again.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

/// Nights of baseline (HRV and resting HR both) before a provisional recovery.
const int kProvisionalRecoveryNights = 4;

/// The provisional composite, or null when the ordinary one should stand
/// ([full] present, or not refused for a short baseline) or the baseline is
/// too short even for this.
///
/// [hrvNights]/[rhrNights] are the two autonomic baselines' lengths.
ana.Metric<ana.Readiness>? provisionalReadiness(
  ana.Metric<ana.Readiness> full,
  List<ana.ReadinessInput> inputs, {
  required int hrvNights,
  required int rhrNights,
  double minWeightSum = ana.readinessCompositeMinWeight,
}) {
  if (full.present) return null;
  if (!(full.note ?? '').startsWith('need_baseline:')) return null;
  final n = math.min(hrvNights, rhrNights);
  if (n < kProvisionalRecoveryNights ||
      n >= ana.readinessCompositeMinBaseline) {
    return null;
  }
  final short = ana.readinessComposite(
    inputs,
    minBaseline: kProvisionalRecoveryNights,
    minWeightSum: minWeightSum,
  );
  if (!short.present) return null;
  final shrink = n / ana.readinessCompositeMinBaseline;
  final rawZ = short.value!.compositeZ;
  // The pre-calibration map (`calibratedReadinessScore` below 14 prior z's).
  final score = 100 / (1 + math.exp(-rawZ * shrink));
  return ana.Metric<ana.Readiness>(
    // The RAW z travels as `compositeZ`: it is what later nights calibrate
    // their spread against, and the shrink is a display decision about THIS
    // night, not a fact about the z.
    value: ana.Readiness(score, rawZ, calibrationNights: 0),
    confidence: math.min(short.confidence, 0.3),
    tier: ana.Tier.estimate,
    inputs_used: short.inputs_used,
    drivers: short.drivers,
    note: 'provisional:nights=$n,need=${ana.readinessCompositeMinBaseline},'
        'shrink=${shrink.toStringAsFixed(3)} — ${short.note}',
  );
}
