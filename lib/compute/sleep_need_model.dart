// SLEEP NEED, SLEEP DEBT, SLEEP GOALS AND 4-DAY CONSISTENCY (v118).
//
// WHOOP's structure, from its patent US 12,318,226 B2 ("Determining sleep need
// from physiological measurements"):
//
//     SleepNeed = Baseline + f1(strain) + f2(debt) − Naps
//
// with the strain term written out as a logistic over the 0–21 scale,
//
//     f1(i) = 1.7 / (1 + e^((17 − i) / 3.5))
//
// The patent says "minutes"; evaluated in minutes the whole term is under two
// minutes at strain 21, which is no adjustment at all, so it is read in HOURS
// (≈12 min at strain 10, ≈51 min at 17, ≈77 min at 21) — labelled as our
// reading. Naps come off 1:1 ("a daytime nap reduces that night's sleep need by
// the time you napped", WHOOP Locker 2026).
//
// WHAT WHOOP DOES NOT PUBLISH, AND WHAT WE DO INSTEAD (each one ours, named):
//
//  * BASELINE. WHOOP "starts learning this from the day you begin wearing the
//    device". Ours starts from a POPULATION PRIOR — 8.4 h, the measured optimal
//    sleep duration of healthy young adults sleeping without restriction
//    (Kitamura et al. 2016, Sci Rep 6:35812: 8.41 ± 0.18 h; WHOOP's own member
//    average need is 8 h 34 min) — and moves to the wearer's own longer
//    unconstrained nights as they arrive (Bayesian shrinkage, prior worth
//    [kSleepNeedPriorNights] nights). Until the personal part dominates, the
//    result says so (`baseline_source: population_prior | blended | personal`)
//    and carries low confidence. It is an estimate with its basis printed,
//    never a silent default.
//
//  * DEBT. "Each short night adds to debt, and WHOOP adds that debt to the
//    following night's need"; it "follows you around for a few days"; the
//    patent's debt term is "scaled, and may be capped". Ours is a running
//    ledger over the recent nights:
//        D ← clamp(ρ^gap · D + (need_without_debt − slept), 0, cap)
//    so a short night adds its shortfall, a long night repays 1:1, and debt
//    that is never repaid fades by ρ per night (ρ = 2/3: a third forgiven each
//    night, ~70 % gone after three nights — "a few days"). Tonight's need adds
//    the debt up to [kSleepDebtCapSec]. A night with no measured sleep adds
//    nothing (the gap only decays) — an unmeasured night is not a zero-hour
//    night.
//
//  * HOURS VS NEED for last night is scored against LAST NIGHT'S need (the one
//    in force when the night began), not tonight's.
//
//  * CONSISTENCY. WHOOP: "the likelihood a user's state (sleep or wake) is the
//    same at a particular clock time on each of four consecutive days", 0–100.
//    Ours: over the clock minutes asleep on ANY of the last four nights, the
//    share asleep on ALL four. Identical nights score 100; one night an hour
//    late on an 8 h schedule scores ~89.
//
// Pure and isolate-safe.

import 'dart:math' as math;

/// Population prior for a rest-day sleep need (h): Kitamura 2016.
const double kSleepNeedPriorHours = 8.4;

/// How many nights of personal evidence the prior is worth.
const double kSleepNeedPriorNights = 5;

/// Fraction of unrepaid debt carried into the next night.
const double kSleepDebtCarry = 2 / 3;

/// Most debt added to one night's need (s).
const double kSleepDebtCapSec = 2 * 3600;

/// Most debt the ledger holds (s).
const double kSleepDebtLedgerMaxSec = 10 * 3600;

/// Need is kept inside this band (s).
const double kSleepNeedMinSec = 6 * 3600;
const double kSleepNeedMaxSec = 12 * 3600;

/// WHOOP's sleep goals as fractions of need: Peak, Perform, Get by.
const Map<String, double> kSleepGoals = {
  'peak': 1.0,
  'perform': 0.85,
  'get_by': 0.70,
};

/// The patent's strain term, read in hours, returned in SECONDS.
double strainSleepSec(double strain) {
  final i = strain.clamp(0.0, 21.0);
  return 1.7 / (1 + math.exp((17 - i) / 3.5)) * 3600;
}

/// One day of input: the day's strain and naps, and the main sleep that ENDED
/// that morning ([tstMin]) with its window.
class SleepNeedDay {
  final String date; // YYYY-MM-DD, local
  final double? tstMin;
  final double? strain;
  final double? napMin;
  final int? onsetSec;
  final int? wakeSec;
  const SleepNeedDay({
    required this.date,
    this.tstMin,
    this.strain,
    this.napMin,
    this.onsetSec,
    this.wakeSec,
  });
}

class SleepNeedResult {
  final double needSec;
  final double baselineSec;
  final String baselineSource; // population_prior | blended | personal
  final int personalNights;
  final double strainSec;
  final double debtSec; // what tonight's need ADDS for debt (capped)
  final double debtLedgerSec; // the whole running debt
  final double napCreditSec;

  /// Need in force for the night that ended this morning, or null.
  final double? lastNightNeedSec;
  final double confidence;
  const SleepNeedResult({
    required this.needSec,
    required this.baselineSec,
    required this.baselineSource,
    required this.personalNights,
    required this.strainSec,
    required this.debtSec,
    required this.debtLedgerSec,
    required this.napCreditSec,
    required this.lastNightNeedSec,
    required this.confidence,
  });

  Map<String, double> get goalsSec => {
        for (final g in kSleepGoals.entries) g.key: needSec * g.value,
      };

  Map<String, dynamic> toJson() => {
        'need_sec': needSec,
        'baseline_sec': baselineSec,
        'baseline_source': baselineSource,
        'personal_nights': personalNights,
        'strain_sec': strainSec,
        'debt_sec': debtSec,
        'debt_ledger_sec': debtLedgerSec,
        'nap_credit_sec': napCreditSec,
        if (lastNightNeedSec != null) 'last_night_need_sec': lastNightNeedSec,
        'goals_sec': goalsSec,
        'method': 'patent_us12318226_logistic_strain+ledger_debt',
      };
}

/// The rest-day baseline (s) from the prior and [personalHours] (the wearer's
/// longer unconstrained nights, e.g. p75 of free nights) over [personalNights].
({double sec, String source, double confidence}) sleepNeedBaseline({
  double? personalHours,
  int personalNights = 0,
}) {
  if (personalHours == null || personalNights <= 0) {
    return (
      sec: kSleepNeedPriorHours * 3600,
      source: 'population_prior',
      confidence: 0.3,
    );
  }
  final p = personalHours.clamp(6.5, 10.0);
  final w = personalNights / (personalNights + kSleepNeedPriorNights);
  final h = w * p + (1 - w) * kSleepNeedPriorHours;
  return (
    sec: h * 3600,
    source: w >= 0.75 ? 'personal' : 'blended',
    confidence: 0.3 + 0.4 * w,
  );
}

int? _dayIndex(String date) {
  final d = DateTime.tryParse('${date}T00:00:00Z');
  return d == null ? null : d.millisecondsSinceEpoch ~/ 86400000;
}

double _needCore(double baseSec, double? strain, double? napMin) =>
    baseSec + (strain == null ? 0.0 : strainSleepSec(strain)) -
    (napMin ?? 0.0) * 60;

/// Tonight's need. [daysOldestFirst] are recent day rows; the LAST one is
/// today when [lastIsToday] (its strain and naps set tonight's need, its
/// [SleepNeedDay.tstMin] is the night that ended this morning).
SleepNeedResult? sleepNeedTonight(
  List<SleepNeedDay> daysOldestFirst, {
  required bool lastIsToday,
  double? personalHours,
  int personalNights = 0,
}) {
  final base = sleepNeedBaseline(
      personalHours: personalHours, personalNights: personalNights);
  final days = daysOldestFirst;

  // Debt ledger: the night after day i is scored against day i's need.
  var debt = 0.0;
  int? lastIdx;
  double? lastNightNeed;
  for (var i = 0; i + 1 < days.length; i++) {
    final a = _dayIndex(days[i].date);
    final b = _dayIndex(days[i + 1].date);
    if (a == null || b == null || b <= a) continue;
    if (lastIdx != null && a > lastIdx) {
      debt *= math.pow(kSleepDebtCarry, a - lastIdx).toDouble();
    }
    final needCore = _needCore(base.sec, days[i].strain, days[i].napMin);
    final needThatNight = (needCore + math.min(debt, kSleepDebtCapSec))
        .clamp(kSleepNeedMinSec, kSleepNeedMaxSec);
    if (i + 1 == days.length - 1) lastNightNeed = needThatNight;
    final slept = days[i + 1].tstMin;
    // Consecutive days only: across a gap the morning's sleep is not the
    // night after day i.
    if (b == a + 1 && slept != null) {
      debt = (kSleepDebtCarry * debt + (needCore - slept * 60))
          .clamp(0.0, kSleepDebtLedgerMaxSec);
    } else {
      debt *= math.pow(kSleepDebtCarry, b - a).toDouble();
    }
    lastIdx = b;
  }

  if (days.isEmpty) return null;
  // Today's strain and naps set tonight's need only when the last row IS
  // today; otherwise today has produced neither yet, and the need stands on
  // the baseline and the debt.
  final today = days.last;
  final strainSec = !lastIsToday || today.strain == null
      ? 0.0
      : strainSleepSec(today.strain!);
  final napSec = lastIsToday ? (today.napMin ?? 0.0) * 60 : 0.0;
  final debtAdd = math.min(debt, kSleepDebtCapSec);
  final need = (base.sec + strainSec + debtAdd - napSec)
      .clamp(kSleepNeedMinSec, kSleepNeedMaxSec);
  return SleepNeedResult(
    needSec: need,
    baselineSec: base.sec,
    baselineSource: base.source,
    personalNights: personalNights,
    strainSec: strainSec,
    debtSec: debtAdd,
    debtLedgerSec: debt,
    napCreditSec: napSec,
    lastNightNeedSec: lastIsToday ? lastNightNeed : null,
    confidence: base.confidence,
  );
}

/// Hours vs need, 0–100 (WHOOP's classic Sleep Performance).
double? hoursVsNeedPct(double? sleptMin, double? needSec) {
  if (sleptMin == null || needSec == null || needSec <= 0) return null;
  return (sleptMin * 60 / needSec * 100).clamp(0.0, 100.0);
}

/// WHOOP-style 4-day consistency (0–100), or null without four consecutive
/// nights that each have an onset and a wake. [localMinuteOfDay] maps an epoch
/// second to the local clock minute (the caller's timezone helper).
double? fourDayConsistency(
  List<SleepNeedDay> daysOldestFirst,
  double Function(int epochSec) localMinuteOfDay,
) {
  final withWindow = [
    for (final d in daysOldestFirst)
      if (d.onsetSec != null &&
          d.wakeSec != null &&
          d.wakeSec! > d.onsetSec! &&
          d.wakeSec! - d.onsetSec! < 16 * 3600)
        d,
  ];
  if (withWindow.length < 4) return null;
  final last4 = withWindow.sublist(withWindow.length - 4);
  final i0 = _dayIndex(last4.first.date);
  final i3 = _dayIndex(last4.last.date);
  if (i0 == null || i3 == null || i3 - i0 != 3) return null;
  final grids = <List<bool>>[];
  for (final d in last4) {
    final g = List<bool>.filled(1440, false);
    final start = localMinuteOfDay(d.onsetSec!).floor();
    final len = ((d.wakeSec! - d.onsetSec!) / 60).round();
    for (var m = 0; m < len; m++) {
      g[(start + m) % 1440] = true;
    }
    grids.add(g);
  }
  var any = 0, all = 0;
  for (var m = 0; m < 1440; m++) {
    final c = grids.where((g) => g[m]).length;
    if (c > 0) any++;
    if (c == 4) all++;
  }
  return any == 0 ? null : all / any * 100;
}

/// Restorative sleep (deep + REM) as a share of total sleep, 0–100, or null.
/// WHOOP's stated optimal band is 40–50 %.
double? restorativePct(double? deepMin, double? remMin, double? tstMin) {
  if (deepMin == null || remMin == null || tstMin == null || tstMin <= 0) {
    return null;
  }
  return ((deepMin + remMin) / tstMin * 100).clamp(0.0, 100.0);
}
