// HEALTHSPAN — "Engine Age" and Pace of Aging (v118).
//
// WHAT IT IS. A guideline-adherence score expressed in years, on the
// structure WHOOP's Healthspan white paper describes: each habit Engine
// measures is turned into a mortality HAZARD RATIO from a published cohort,
// relative to a referent level (the level that scores as "your own age"),
// the log hazard ratios are summed, and the sum is converted to years with a
// Gompertz law of mortality (ln HR / b, b = the yearly rise in log mortality).
//
// WHAT IT IS NOT. A prediction of anyone's lifespan. Every cohort below is
// people aged roughly 40–70; at 23, mortality is dominated by external causes
// (NCHS 2021: q30 = 0.0026). The number says how your habits compare with the
// levels those studies tie to lower risk, scaled into years so it reads like
// WHOOP's. The UI carries that warning with the number, always.
//
// THE INPUTS — each measured, never inferred from another (AGENTS §3.3):
//   RHR    Zhang 2016, CMAJ 188:E53: HR 1.09 (1.07–1.12) per +10 bpm; when a
//          fitness term is present, Jensen 2013, Heart 99:882: 1.16 (1.10–1.22)
//          per +10 bpm adjusted for VO2max (so the two are not double counted).
//          Referent 60 bpm. Engine's RHR is the lowest-30-min SLEEPING rate,
//          lower than the clinic rate the cohorts measured, so this term reads
//          optimistic; the input row says so.
//   CRF    Kodama 2009, JAMA 301:2024: 0.87 (0.84–0.90) per +1 MET (3.5
//          mL/kg/min). ONLY from a TEST THE USER ENTERED (lab result, or a
//          Cooper 12-minute run: (d − 504.9)/44.73, Cooper 1968, JAMA 203:201),
//          dated, and only within 365 days. Never from resting HR — the old
//          k/RHR "VO2max" was deleted for being the RHR chart relabelled
//          (CV-02), and it stays deleted. Referent 44 mL/kg/min for men (WHOOP
//          white paper); no published referent for women was retrieved, so the
//          term abstains for anyone else rather than borrowing the men's.
//   MVPA   Arem 2015, JAMA Intern Med 175:959: leisure MET-h/week vs none —
//          <7.5: 0.80; 7.5–15: 0.69; 15–22.5: 0.63; 22.5–37.5: 0.61; flat
//          above (the ≥10× uptick rests on few people and is not followed).
//          Minutes come off the band's per-minute heart rate: 40–59 % of heart
//          rate reserve is moderate, ≥ 60 % vigorous (ACSM Guidelines, 11th
//          ed.); MET-h = (moderate + 2·vigorous minutes) / 20, the HHS 2018
//          equivalence (150 moderate min = 7.5 MET-h, 1 vigorous = 2 moderate).
//          Referent 7.5 MET-h/week (the guideline minimum) → ln 0.69.
//   Strength  Momma 2022, BJSM 56:755: any vs none 0.85; nadir 0.83
//          (0.79–0.86) at 40 min/week. Its J-shape (benefit fading by ~140
//          min/week) is NOT applied: sparse data, no harm shown, and HHS 2018
//          sets no upper limit — more is held at the nadir. Minutes from saved
//          strength sessions. Referent 40 min.
//          Abstains when no strength session was ever saved in the window —
//          "you never logged one" is not "you never lift".
//   Steps  Paluch 2022, Lancet Public Health 7:e219, age < 60: quartile
//          medians 3,553 / 5,801 / 7,842 steps → 1.00 / 0.59 / 0.51, plateau
//          from 8,000. Real pedometer counts only. Referent 8,000.
//   Sleep  Cappuccio 2010, Sleep 33:585: short sleep 1.12 (1.06–1.18) below
//          6 h, linear to 1.0 at 7 h, nothing for 7–9 h. Long sleep is not
//          penalised (WHOOP gives it no effect; the 1.30 likely reflects
//          illness confounding).
//   SRI    Windred 2023, Sleep 47:zsad253: the top four regularity quintiles
//          had 20–48 % lower mortality than the least regular; median SRI 81.
//          Ours: ln HR = −0.0284·(SRI − 81), SRI clamped 60–95 — the 0.52
//          spread laid evenly across ~23 SRI points (an approximation,
//          labelled; the quintile cut-points were not retrievable).
//
// COMBINING. Σ α_i·ln HR_i,rel, α = 1 except: aerobic and strength 0.96 each
// (so that MVPA + strength at their referents reproduce Momma's joint 0.60),
// and steps vs MVPA, which share variance — the larger-magnitude term counts
// fully and the smaller at 0.5.
//
// YEARS. impact = Σ / b with b = 0.10 (WHOOP's Gompertz slope, the
// conservative one); the NCHS 2021 US male life table gives b = 0.0705 over
// ages 40–80 and the same hazard moves the age 1.4× further — published as
// `impact_years_nchs` so the band is visible. Uncertainty: SE(ln HR) from
// each published 95 % CI, (ln U − ln L)/3.92, propagated in quadrature.
//
// PACE OF AGING. How fast the score is moving: 1.0 = one year per year.
// pace = 1 + (impact_30d − impact_window) / lag, lag = the gap between the
// two windows' centres in years; clamped to [−1, 3]. Needs ≥ 60 days.
//
// UNLOCK. ≥ 4 inputs, of which ≥ 2 are band-measured daily series (RHR,
// sleep, MVPA), each with ≥ 21 of the last 31 days — WHOOP's own rule. Fewer
// ⇒ absent with a `need_baseline:` note. WHOOP uses six months; Engine keeps
// 90 days of day rows, so the window is up to 90 days and says so.
//
// Pure and isolate-safe.

import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

/// Gompertz slopes (per year of age).
const double kHealthspanB = 0.10; // WHOOP white paper
const double kHealthspanBNchs = 0.0705; // NCHS 2021 US males, ages 40–80

/// Days of data in the last 31 an input needs to count.
const int kHealthspanMinDays = 21;
const int kHealthspanMinInputs = 4;
const int kHealthspanPaceMinSpanDays = 60;

/// A test result older than this does not enter.
const int kVo2maxTestMaxAgeDays = 365;

const String kHealthspanWarning =
    'Built from studies of people aged about 40 to 70. At your age it shows '
    'how your habits compare with the levels those studies link to lower '
    'risk, in years — not a prediction of how long you will live.';

/// Strength-training session types (resistance work, per Momma 2022).
const Set<String> kStrengthSessionTypes = {
  'weight_training',
  'powerlifting',
  'bodyweight',
  'calisthenics',
  'kettlebell',
  'crossfit',
  'functional',
  'circuit_training',
};

bool isStrengthSessionType(String? type) =>
    kStrengthSessionTypes
        .contains((type ?? '').trim().toLowerCase().replaceAll(' ', '_'));

/// Cooper 12-minute run → VO2max (mL/kg/min). Cooper 1968, JAMA 203:201.
double cooperVo2max(double metres12Min) => (metres12Min - 504.9) / 44.73;

/// Moderate (40–59 % HRR) and vigorous (≥ 60 % HRR) minutes off a per-minute
/// HR curve (`[{t, v}]`), or null without both anchors. ACSM intensity bands.
({int moderate, int vigorous})? mvpaMinutes(
  Object? hrCurve, {
  required double? restingHr,
  required double? maxHr,
}) {
  if (restingHr == null || maxHr == null || maxHr <= restingHr + 20) {
    return null;
  }
  if (hrCurve is! List) return null;
  var mod = 0, vig = 0;
  final reserve = maxHr - restingHr;
  for (final e in hrCurve) {
    if (e is! Map) continue;
    final v = (e['v'] as num?)?.toDouble();
    if (v == null || v <= 0) continue;
    final f = (v - restingHr) / reserve;
    if (f >= 0.60) {
      vig++;
    } else if (f >= 0.40) {
      mod++;
    }
  }
  return (moderate: mod, vigorous: vig);
}

/// One day of input.
class HealthspanDay {
  final String date; // YYYY-MM-DD
  final double? rhr;
  final double? tstMin;
  final double? steps;
  final int? mvpaModMin;
  final int? mvpaVigMin;
  final double? wornMin;
  final double strengthMin; // saved strength sessions that day (0 = none)
  const HealthspanDay({
    required this.date,
    this.rhr,
    this.tstMin,
    this.steps,
    this.mvpaModMin,
    this.mvpaVigMin,
    this.wornMin,
    this.strengthMin = 0,
  });

  bool get mvpaValid =>
      mvpaModMin != null && mvpaVigMin != null && (wornMin ?? 0) >= 600;
}

class HealthspanInput {
  final String key;
  final double value;
  final String unit;
  final double lnHr; // relative to the referent, before α
  final double alpha;
  final double se; // SE of lnHr
  final String referent;
  final String source;
  const HealthspanInput(this.key, this.value, this.unit, this.lnHr, this.alpha,
      this.se, this.referent, this.source);

  double get years => alpha * lnHr / kHealthspanB;

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'unit': unit,
        'ln_hr': lnHr,
        'alpha': alpha,
        'years': years,
        'se_years': alpha * se / kHealthspanB,
        'referent': referent,
        'source': source,
      };
}

class HealthspanResult {
  final double? engineAge;
  final int? chronologicalAge;
  final double impactYears;
  final double seYears;
  final double? pace;
  final int windowDays;
  final List<HealthspanInput> inputs;
  final Map<String, String> missing;
  final bool rhrFitnessAdjusted;
  const HealthspanResult({
    required this.engineAge,
    required this.chronologicalAge,
    required this.impactYears,
    required this.seYears,
    required this.pace,
    required this.windowDays,
    required this.inputs,
    required this.missing,
    required this.rhrFitnessAdjusted,
  });

  Map<String, dynamic> toJson() => {
        if (engineAge != null) 'engine_age': engineAge,
        if (chronologicalAge != null) 'chronological_age': chronologicalAge,
        'impact_years': impactYears,
        'impact_years_nchs': impactYears * kHealthspanB / kHealthspanBNchs,
        'se_years': seYears,
        if (pace != null) 'pace': pace,
        'window_days': windowDays,
        'b': kHealthspanB,
        'b_nchs': kHealthspanBNchs,
        'rhr_fitness_adjusted': rhrFitnessAdjusted,
        'inputs': [for (final i in inputs) i.toJson()],
        'missing': missing,
        'warning': kHealthspanWarning,
      };
}

double _se(double lo, double hi) => (math.log(hi) - math.log(lo)) / 3.92;

/// Piecewise-linear in ln HR over [knots] (x ascending), flat outside.
double _interp(List<(double, double)> knots, double x) {
  if (x <= knots.first.$1) return knots.first.$2;
  for (var i = 1; i < knots.length; i++) {
    if (x <= knots[i].$1) {
      final (x0, y0) = knots[i - 1];
      final (x1, y1) = knots[i];
      return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    }
  }
  return knots.last.$2;
}

final _aremKnots = <(double, double)>[
  (0, 0),
  (3.75, math.log(0.80)),
  (11.25, math.log(0.69)),
  (18.75, math.log(0.63)),
  (30, math.log(0.61)),
];
final _paluchKnots = <(double, double)>[
  (3553, 0),
  (5801, math.log(0.59)),
  (7842, math.log(0.51)),
];

/// Momma 2022's curve up to its nadir, then HELD there. The meta-analysis'
/// J-shape — benefit fading to nothing by ~140 min/week — rests on few people
/// at high volumes, with intervals crossing 1, and it describes the absence of
/// further benefit, not harm. HHS 2018 sets no upper limit on muscle
/// strengthening. So more lifting than 40 min/week counts as the nadir, never
/// as a cost: an athlete is not aged for training.
double _strengthLnHr(double minWk) {
  final nadir = math.log(0.83);
  if (minWk <= 40) return nadir * minWk / 40;
  return nadir;
}

double _sleepLnHr(double hours) {
  final short = math.log(1.12);
  if (hours < 6) return short;
  if (hours < 7) return short * (7 - hours);
  return 0;
}

int? _dayIndex(String date) {
  final d = DateTime.tryParse('${date}T00:00:00Z');
  return d == null ? null : d.millisecondsSinceEpoch ~/ 86400000;
}

double? _mean(Iterable<double> xs) {
  var s = 0.0, n = 0;
  for (final x in xs) {
    s += x;
    n++;
  }
  return n == 0 ? null : s / n;
}

/// The window's inputs, or the reason each one is missing.
({List<HealthspanInput> inputs, Map<String, String> missing}) _inputsFor(
  List<HealthspanDay> window, {
  required int spanDays,
  required double? sri,
  required double? vo2max,
  required String? sex,
}) {
  final inputs = <HealthspanInput>[];
  final missing = <String, String>{};

  // CRF first: it decides how RHR is adjusted.
  HealthspanInput? crf;
  if (vo2max == null) {
    missing['vo2max'] = 'need_input:name=vo2max_test';
  } else if (sex != 'm' && sex != 'male') {
    missing['vo2max'] = 'no_published_referent:sex';
  } else {
    final dMet = (vo2max - 44).clamp(-17.5, 17.5) / 3.5;
    crf = HealthspanInput('vo2max', vo2max, 'mL/kg/min',
        dMet * math.log(0.87), 1, dMet.abs() * _se(0.84, 0.90),
        '44 mL/kg/min', 'Kodama 2009, JAMA');
  }

  final rhr = _mean([for (final d in window) ?d.rhr]);
  if (rhr != null) {
    final per10 = (rhr.clamp(40.0, 100.0) - 60) / 10;
    inputs.add(crf != null
        ? HealthspanInput('rhr', rhr, 'bpm', per10 * math.log(1.16), 1,
            per10.abs() * _se(1.10, 1.22), '60 bpm',
            'Jensen 2013, Heart (fitness-adjusted)')
        : HealthspanInput('rhr', rhr, 'bpm', per10 * math.log(1.09), 1,
            per10.abs() * _se(1.07, 1.12), '60 bpm', 'Zhang 2016, CMAJ'));
  } else {
    missing['rhr'] = 'need_input:name=rhr';
  }
  if (crf != null) inputs.add(crf);

  final weeks = spanDays / 7;
  final mvpaDays = [for (final d in window) if (d.mvpaValid) d];
  HealthspanInput? mvpa;
  if (mvpaDays.isNotEmpty) {
    final perDay = _mean([
      for (final d in mvpaDays) (d.mvpaModMin! + 2 * d.mvpaVigMin!).toDouble()
    ])!;
    final metH = perDay * 7 / 20;
    mvpa = HealthspanInput('mvpa', metH, 'MET-h/week',
        _interp(_aremKnots, metH) - math.log(0.69), 0.96, 0.015,
        '7.5 MET-h/week', 'Arem 2015, JAMA Intern Med');
  } else {
    missing['mvpa'] = 'need_input:name=worn_day_hr';
  }

  final steps = _mean([for (final d in window) ?d.steps]);
  HealthspanInput? stepIn;
  if (steps != null) {
    stepIn = HealthspanInput('steps', steps, 'steps/day',
        _interp(_paluchKnots, steps) - math.log(0.51), 1,
        _se(0.51, 0.71), '8,000 steps/day', 'Paluch 2022, Lancet Public Health');
  } else {
    missing['steps'] = 'need_input:name=pedometer_steps';
  }
  // Steps and MVPA share variance: the larger counts fully, the smaller half.
  if (mvpa != null && stepIn != null) {
    if (mvpa.lnHr.abs() >= stepIn.lnHr.abs()) {
      stepIn = HealthspanInput(stepIn.key, stepIn.value, stepIn.unit,
          stepIn.lnHr, 0.5, stepIn.se, stepIn.referent, stepIn.source);
    } else {
      mvpa = HealthspanInput(mvpa.key, mvpa.value, mvpa.unit, mvpa.lnHr, 0.5,
          mvpa.se, mvpa.referent, mvpa.source);
    }
  }
  if (mvpa != null) inputs.add(mvpa);
  if (stepIn != null) inputs.add(stepIn);

  final strengthTotal = window.fold<double>(0, (s, d) => s + d.strengthMin);
  if (strengthTotal > 0 && weeks > 0) {
    final perWk = strengthTotal / weeks;
    inputs.add(HealthspanInput('strength', perWk, 'min/week',
        _strengthLnHr(perWk) - math.log(0.83), 0.96, _se(0.79, 0.86),
        '40 min/week', 'Momma 2022, BJSM'));
  } else {
    missing['strength'] = 'need_input:name=strength_session';
  }

  final tst = _mean([for (final d in window) if (d.tstMin != null) d.tstMin! / 60]);
  if (tst != null) {
    final ln = _sleepLnHr(tst);
    inputs.add(HealthspanInput('sleep', tst, 'h/night', ln, 1,
        ln == 0 ? 0 : _se(1.06, 1.18) * ln / math.log(1.12), '7–9 h',
        'Cappuccio 2010, Sleep'));
  } else {
    missing['sleep'] = 'need_input:name=tst_min';
  }

  if (sri != null) {
    final ln = -0.0284 * (sri.clamp(60.0, 95.0) - 81);
    inputs.add(HealthspanInput('sri', sri, 'SRI', ln, 1, ln.abs() * 0.5,
        '81 (UK Biobank median)', 'Windred 2023, Sleep'));
  } else {
    missing['sri'] = 'need_input:name=sleep_regularity';
  }
  return (inputs: inputs, missing: missing);
}

double _impact(List<HealthspanInput> xs) =>
    xs.fold<double>(0, (s, i) => s + i.alpha * i.lnHr) / kHealthspanB;

/// Engine Age over [daysOldestFirst] (up to 90 days of day rows).
///
/// [sriWindow] / [sri30] are the sleep regularity index over the whole window
/// and the last 30 days. [vo2maxTest] is the user's entered test, used only
/// when [vo2maxTestDate] is within [kVo2maxTestMaxAgeDays] of the last day.
ana.Metric<HealthspanResult> healthspan(
  List<HealthspanDay> daysOldestFirst, {
  required int? ageYears,
  required String? sex,
  double? sriWindow,
  double? sri30,
  double? vo2maxTest,
  String? vo2maxTestDate,
}) {
  const used = [
    'rhr',
    'tst',
    'hr_minutes',
    'steps',
    'strength_sessions',
    'sri',
    'vo2max_test',
  ];
  final days = [
    for (final d in daysOldestFirst)
      if (_dayIndex(d.date) != null) d,
  ];
  if (days.isEmpty) {
    return const ana.Metric.absent(
        tier: ana.Tier.estimate,
        inputs_used: used,
        note: 'need_baseline:have=0,need=21');
  }
  final lastIdx = _dayIndex(days.last.date)!;
  final firstIdx = _dayIndex(days.first.date)!;
  final spanDays = lastIdx - firstIdx + 1;
  final last31 = [
    for (final d in days)
      if (lastIdx - _dayIndex(d.date)! < 31) d,
  ];

  // A test only while it is recent enough to describe you.
  double? vo2;
  final testIdx = vo2maxTestDate == null ? null : _dayIndex(vo2maxTestDate);
  if (vo2maxTest != null &&
      testIdx != null &&
      lastIdx - testIdx <= kVo2maxTestMaxAgeDays &&
      testIdx <= lastIdx) {
    vo2 = vo2maxTest;
  }

  // Coverage gate on the band's daily series.
  final cov = <String, int>{
    'rhr': last31.where((d) => d.rhr != null).length,
    'sleep': last31.where((d) => d.tstMin != null).length,
    'mvpa': last31.where((d) => d.mvpaValid).length,
    'steps': last31.where((d) => d.steps != null).length,
  };
  bool covered(String k) => (cov[k] ?? 0) >= kHealthspanMinDays;

  final win = _inputsFor(days,
      spanDays: spanDays, sri: sriWindow, vo2max: vo2, sex: sex);
  final missing = {...win.missing};
  final counted = <HealthspanInput>[];
  for (final i in win.inputs) {
    if (cov.containsKey(i.key) && !covered(i.key)) {
      missing[i.key] =
          'need_baseline:have=${cov[i.key]},need=$kHealthspanMinDays';
      continue;
    }
    counted.add(i);
  }
  final daily = counted
      .where((i) => i.key == 'rhr' || i.key == 'sleep' || i.key == 'mvpa')
      .length;
  if (counted.length < kHealthspanMinInputs || daily < 2) {
    final best = cov.values.fold<int>(0, math.max);
    return ana.Metric.absent(
      tier: ana.Tier.estimate,
      inputs_used: used,
      note: daily < 2
          ? 'need_baseline:have=$best,need=$kHealthspanMinDays'
          : 'need_inputs:have=${counted.length},need=$kHealthspanMinInputs',
    );
  }

  final impact = _impact(counted);
  final se = math.sqrt(counted.fold<double>(
          0, (s, i) => s + i.alpha * i.alpha * i.se * i.se)) /
      kHealthspanB;

  // Pace: the last 30 days against the window, same inputs.
  double? pace;
  if (spanDays >= kHealthspanPaceMinSpanDays) {
    final recent = [
      for (final d in days)
        if (lastIdx - _dayIndex(d.date)! < 30) d,
    ];
    final r = _inputsFor(recent,
        spanDays: 30, sri: sri30, vo2max: vo2, sex: sex);
    final keys = {for (final i in counted) i.key};
    final rKeys = {for (final i in r.inputs) i.key};
    if (keys.every(rKeys.contains)) {
      final i30 = _impact([
        for (final i in r.inputs)
          if (keys.contains(i.key)) i,
      ]);
      final lagYears = (spanDays / 2 - 15) / 365.25;
      if (lagYears > 0) {
        pace = (1 + (i30 - impact) / lagYears).clamp(-1.0, 3.0).toDouble();
      }
    }
  }

  final result = HealthspanResult(
    engineAge: ageYears == null ? null : ageYears + impact,
    chronologicalAge: ageYears,
    impactYears: impact,
    seYears: se,
    pace: pace,
    windowDays: spanDays,
    inputs: counted,
    missing: missing,
    rhrFitnessAdjusted: counted.any((i) => i.key == 'vo2max'),
  );
  return ana.Metric<HealthspanResult>(
    value: result,
    confidence: (0.25 + 0.05 * counted.length).clamp(0.0, 0.6),
    tier: ana.Tier.estimate,
    inputs_used: used,
    note: ageYears == null
        ? 'need_input:name=age — impact in years only'
        : 'healthspan:inputs=${counted.length},window=${spanDays}d',
  );
}
