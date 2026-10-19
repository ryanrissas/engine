// MUSCULAR LOAD — what a lift cost, from the sets the user typed.
//
// Why it exists: heart-rate strain under-reads lifting. In resistance training
// session-RPE agrees with 1RM-based criteria (Day et al. 2004, ICC 0.88) but
// correlates only weakly with HR-based load (Alexiou & Coutts 2008: Edwards
// r = 0.52, Banister r = 0.25) — and WHOOP itself says cardiac strain "can
// underestimate strength-training exertion". So a lift needs a second number.
//
// WHAT IS PUBLISHED, AND WHAT IS OURS (every choice labelled):
//
//  * STRUCTURE — WHOOP's musculoskeletal-strain patent (US 2024/0041355 A1):
//    per-rep load = (effective load / V_max) · intensity, where V_max is the
//    user's own μ + 2σ of past workout volumes, and volume "incorporates
//    effective mass". Summed over the session, unbounded, as in the patent.
//
//  * EFFECTIVE MASS — ours. L_eff = bar load + c·bodyweight, with c the share
//    of body mass that moves in the lift, from de Leva 1996 (J Biomech
//    29:1223) male segment fractions: squat ≈ 0.89 (all but shanks and feet),
//    pull-up ≈ 0.95 (all but forearms and hands), deadlift ≈ 0.65, push-up ≈
//    0.65 (ground-reaction share, Ebben 2011 JSCR), presses ≈ 0.10 (the arms),
//    machines and isolation 0. An exercise not in the table keeps only its bar
//    load; a BODYWEIGHT set of an exercise not in the table has no load at all
//    and is left out (never counted as zero).
//
//  * INTENSITY — WHOOP's per-rep intensity needs a gyro-fused IMU this band
//    does not stream. Ours: proximity to failure from the set's RPE (reps in
//    reserve = 10 − RPE, Zourdos 2016 / Helms 2016), f = 1 / (1 + 0.5·RIR), so
//    a set to failure counts 1.0 and four in reserve 0.33. A set whose RPE the
//    user did NOT set (the picker's untouched default, or an older set we
//    cannot tell) is counted at f = 0.5 and flagged — never as measured.
//
//  * SESSION-RPE — Foster et al. 2001 (J Strength Cond Res 15:109): load =
//    CR-10 session rating × minutes, in arbitrary units. Used when no sets
//    were logged, and as the bridge into day strain below.
//
//  * DAY STRAIN WITH LIFTING — nothing vetted publishes a fusion; WHOOP says
//    only that it "aligned muscular load with the existing Strain algorithm".
//    Ours, personal: over the wearer's cardio sessions that have both a
//    rating and heart rate, k = median(weighted HR minutes / (sRPE · min)).
//    For a lift, the load heart rate missed is M = max(0, k·sRPE·min − W_HR),
//    and day strain = the same saturating map over (day's weighted minutes +
//    ΣM) — so it never adds strains linearly and never exceeds 21. Needs
//    [kMinCalibrationSessions] rated cardio sessions; below that, absent.
//
// Pure and isolate-safe.

import 'dart:math' as math;

import 'reserve_strain.dart'
    show kStrainLogScale, kStrainNormMinutes, strainFromLoad;

/// Share of body mass moved per rep (de Leva 1996 segment fractions; ours).
const Map<String, double> kBodyMassShare = {
  'back_squat': 0.89,
  'front_squat': 0.89,
  'lunge': 0.89,
  'split_squat': 0.89,
  'goblet_squat': 0.89,
  'box_jump': 0.89,
  'pull_up': 0.95,
  'chin_up': 0.95,
  'push_up': 0.65,
  'deadlift': 0.65,
  'romanian_deadlift': 0.65,
  'bench_press': 0.10,
  'incline_db_press': 0.10,
  'overhead_press': 0.10,
  'barbell_row': 0.10,
  'hanging_leg_raise': 0.40,
  'cable_fly': 0.0,
  'triceps_pushdown': 0.0,
  'overhead_extension': 0.0,
  'lat_pulldown': 0.0,
  'barbell_curl': 0.0,
  'leg_press': 0.0,
};

/// Effort weight for a set the user did not rate.
const double kUnratedEffort = 0.5;

/// Rated cardio sessions needed before day strain with lifting is fitted.
const int kMinCalibrationSessions = 8;

/// Past sessions needed for the personal V_max (μ + 2σ).
const int kMinVmaxSessions = 4;

class StrengthSetIn {
  final String exerciseKey;
  final int? reps;
  final double? loadKg; // null = bodyweight
  final int? rpe;

  /// True only when the user set [rpe] themselves.
  final bool rpeRated;
  const StrengthSetIn({
    required this.exerciseKey,
    this.reps,
    this.loadKg,
    this.rpe,
    this.rpeRated = false,
  });
}

/// f(RIR) for a rated set; [kUnratedEffort] otherwise.
({double f, bool rated}) effortFactor(int? rpe, {required bool rated}) {
  if (!rated || rpe == null || rpe < 1 || rpe > 10) {
    return (f: kUnratedEffort, rated: false);
  }
  final rir = (10 - rpe).clamp(0, 9);
  return (f: 1 / (1 + 0.5 * rir), rated: true);
}

/// Load moved per rep (kg), or null when it cannot be known.
double? effectiveLoadKg(StrengthSetIn s, {double? bodyKg}) {
  final share = kBodyMassShare[s.exerciseKey];
  final body = (share == null || share == 0 || bodyKg == null || bodyKg <= 0)
      ? null
      : share * bodyKg;
  if (s.loadKg == null) return body; // bodyweight set: body share or nothing
  return s.loadKg! + (body ?? 0);
}

class SessionLoad {
  /// Σ reps · effective load (kg) over the sets whose load is known.
  final double volumeKg;

  /// Σ reps · effective load · effort factor.
  final double effortVolumeKg;
  final int setsCounted;

  /// Sets with no knowable load (bodyweight, exercise not in the table).
  final int setsWithoutLoad;

  /// Counted sets whose effort the user did not rate.
  final int setsUnrated;

  /// Counted sets whose effective load includes a body-mass share.
  final int setsWithBodyShare;
  const SessionLoad({
    required this.volumeKg,
    required this.effortVolumeKg,
    required this.setsCounted,
    required this.setsWithoutLoad,
    required this.setsUnrated,
    required this.setsWithBodyShare,
  });
}

/// The session's volume and effort-weighted volume, or null when no set has a
/// knowable load.
SessionLoad? sessionLoad(List<StrengthSetIn> sets, {double? bodyKg}) {
  var vol = 0.0, eff = 0.0;
  var counted = 0, without = 0, unrated = 0, withBody = 0;
  for (final s in sets) {
    final reps = s.reps;
    if (reps == null || reps <= 0) continue;
    final l = effectiveLoadKg(s, bodyKg: bodyKg);
    if (l == null || l <= 0) {
      without++;
      continue;
    }
    final e = effortFactor(s.rpe, rated: s.rpeRated);
    vol += reps * l;
    eff += reps * l * e.f;
    counted++;
    if (!e.rated) unrated++;
    final share = kBodyMassShare[s.exerciseKey];
    if (share != null && share > 0 && bodyKg != null && bodyKg > 0) withBody++;
  }
  if (counted == 0) return null;
  return SessionLoad(
    volumeKg: vol,
    effortVolumeKg: eff,
    setsCounted: counted,
    setsWithoutLoad: without,
    setsUnrated: unrated,
    setsWithBodyShare: withBody,
  );
}

/// WHOOP's V_max: μ + 2σ of the user's past session volumes, or null below
/// [kMinVmaxSessions].
double? personalVmax(List<double> pastSessionVolumesKg) {
  final v = [for (final x in pastSessionVolumesKg) if (x > 0) x];
  if (v.length < kMinVmaxSessions) return null;
  final m = v.reduce((a, b) => a + b) / v.length;
  var ss = 0.0;
  for (final x in v) {
    ss += (x - m) * (x - m);
  }
  final sd = math.sqrt(ss / (v.length - 1));
  return m + 2 * sd;
}

/// Session muscular load (patent structure): Σ reps·L_eff·f / V_max. Null
/// without a V_max.
double? muscularLoad(SessionLoad? s, double? vmax) =>
    (s == null || vmax == null || vmax <= 0) ? null : s.effortVolumeKg / vmax;

/// Foster session-RPE load (AU), or null without a rating or a duration.
double? sessionRpeLoad(double? rpe, double? minutes) =>
    (rpe == null || minutes == null || rpe <= 0 || minutes <= 0)
        ? null
        : rpe * minutes;

/// The weighted HR minutes a strain value stands for — the exact inverse of
/// `strainFromLoad`, so a stored strain can be added to without its trace.
double? weightedMinutesFromStrain(double? strain) {
  if (strain == null || strain < 0) return null;
  final s = strain.clamp(0.0, 21.0);
  final n = (math.pow(1 + kStrainLogScale, s / 21) - 1) / kStrainLogScale;
  return n * kStrainNormMinutes;
}

class CardioSessionIn {
  final double strain;
  final double rpe;
  final double minutes;
  const CardioSessionIn(this.strain, this.rpe, this.minutes);
}

/// k = median(W_HR / (sRPE·min)) over rated cardio sessions, or null below
/// [kMinCalibrationSessions].
({double k, int n})? strainCalibration(List<CardioSessionIn> cardio) {
  final r = <double>[];
  for (final s in cardio) {
    final w = weightedMinutesFromStrain(s.strain);
    final l = sessionRpeLoad(s.rpe, s.minutes);
    if (w == null || l == null || w <= 0) continue;
    r.add(w / l);
  }
  if (r.length < kMinCalibrationSessions) return null;
  r.sort();
  final mid = r.length ~/ 2;
  final k = r.length.isOdd ? r[mid] : (r[mid - 1] + r[mid]) / 2;
  return (k: k, n: r.length);
}

/// Weighted minutes heart rate missed on a lift: max(0, k·sRPE·min − W_HR).
double? missingLoadMinutes({
  required double k,
  required double? rpe,
  required double? minutes,
  required double? sessionStrain,
}) {
  final l = sessionRpeLoad(rpe, minutes);
  final w = weightedMinutesFromStrain(sessionStrain);
  if (l == null || w == null) return null;
  return math.max(0.0, k * l - w);
}

/// Day strain with lifting: the strain map over (day's weighted minutes +
/// the lifts' missing minutes). Never below [dayStrain], never above 21.
double? dayStrainWithLifting(double? dayStrain, List<double> missingMinutes) {
  final w = weightedMinutesFromStrain(dayStrain);
  if (w == null) return null;
  final add = missingMinutes.fold(0.0, (a, b) => a + b);
  return strainFromLoad(w + add);
}
