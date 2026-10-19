// ILLNESS WATCH (v118) — a multi-signal early warning, IN ADDITION to the
// resting-HR CUSUM the app already runs.
//
// The pieces, each from a peer-reviewed source:
//
//  * RESTING HR ≥ baseline + 4 bpm — NightSignal (Alavi et al., Nat Med 2022;
//    medRxiv 2021.06.13.21258795). The baseline there is the streaming MEDIAN
//    of prior nights; +4 is its red-level threshold. NightSignal's resting HR
//    is a 00:00–07:00 mean at zero steps; ours is the night's lowest-30-min
//    mean, so the same +4 is applied to a slightly different quantity — OUR
//    adaptation, labelled.
//  * RESPIRATORY RATE robust z ≥ 2.33 against a 28-night median/MAD —
//    Natarajan et al. (npj Digit Med 2020/2021: respiratory and heart rate
//    rise and HRV falls before symptom onset; Z ≥ 2.326 as the cut).
//  * HRV (ln RMSSD) robust z ≤ −2 against the same window — the HRV fall in
//    Natarajan 2020. The −2 is ours.
//
// RULE (ours, from the research notes): a night is YELLOW when at least two
// of the three hold; RED on the second consecutive yellow night. Temperature
// is deliberately not an input: the gen4 channel is not verified as
// temperature.
//
// Every input is the nightly value of a SETTLED night. A night missing an
// input cannot count that input either way, and a night with fewer than two
// inputs scored is not judged at all (no verdict, not a green one).
//
// Pure and isolate-safe.

import 'dart:math' as math;

/// Fewest prior nights for each baseline.
const int kIllnessRhrMinNights = 7;
const int kIllnessRobustMinNights = 14;
const int kIllnessWindowNights = 28;

const double kIllnessRhrRiseBpm = 4;
const double kIllnessRespZ = 2.33;
const double kIllnessHrvZ = -2.0;

enum IllnessWatchLevel { clear, yellow, red }

class IllnessWatchNight {
  final String date;
  final IllnessWatchLevel level;

  /// Which inputs held this night: 'rhr', 'resp', 'hrv'.
  final List<String> signals;

  /// How many of the three inputs could be judged this night.
  final int judged;
  final double? rhrRiseBpm, respZ, hrvZ;
  const IllnessWatchNight({
    required this.date,
    required this.level,
    required this.signals,
    required this.judged,
    this.rhrRiseBpm,
    this.respZ,
    this.hrvZ,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'level': level.name,
        'signals': signals,
        'judged': judged,
        'rhr_rise_bpm': rhrRiseBpm,
        'resp_z': respZ,
        'hrv_z': hrvZ,
        'method': 'nightsignal_rhr+4 · resp_z>=2.33 · lnrmssd_z<=-2 · '
            '2_of_3_yellow · 2_yellow_nights_red',
      };
}

bool _nextDay(String a, String b) {
  final da = DateTime.tryParse('${a}T00:00:00Z');
  final db = DateTime.tryParse('${b}T00:00:00Z');
  return da != null && db != null && db.difference(da).inDays == 1;
}

double? _median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _robustZ(double x, List<double> base) {
  final med = _median(base);
  if (med == null) return null;
  final mad = _median([for (final b in base) (b - med).abs()]);
  if (mad == null || mad <= 0) return null;
  return (x - med) / (1.4826 * mad);
}

/// One verdict per night, parallel to [dates]; null where a night is
/// unsettled or could not be judged. Inputs are parallel to [dates].
List<IllnessWatchNight?> illnessWatch({
  required List<String> dates,
  required List<double?> rhr,
  required List<double?> resp,
  required List<double?> rmssd,
  required List<bool> unsettled,
}) {
  final n = dates.length;
  final out = List<IllnessWatchNight?>.filled(n, null);
  IllnessWatchLevel? prev;
  String? prevDate;
  for (var i = 0; i < n; i++) {
    // "Consecutive" is by calendar: a gap in the rows breaks the run.
    if (prevDate != null && !_nextDay(prevDate, dates[i])) prev = null;
    prevDate = dates[i];
    if (unsettled[i]) {
      prev = null;
      continue;
    }
    List<double> prior(List<double?> xs, {bool log = false}) {
      final lo = math.max(0, i - kIllnessWindowNights);
      return [
        for (var k = lo; k < i; k++)
          if (!unsettled[k] && xs[k] != null && (!log || xs[k]! > 0))
            log ? math.log(xs[k]!) : xs[k]!,
      ];
    }

    var judged = 0;
    final signals = <String>[];
    double? rise, rz, hz;
    final r = rhr[i];
    if (r != null) {
      // NightSignal's baseline is the median of ALL prior nights; bounded to
      // the same 28-night window here so a season-old baseline cannot judge
      // tonight.
      final base = prior(rhr);
      if (base.length >= kIllnessRhrMinNights) {
        judged++;
        rise = r - _median(base)!;
        if (rise >= kIllnessRhrRiseBpm) signals.add('rhr');
      }
    }
    final b = resp[i];
    if (b != null) {
      final base = prior(resp);
      if (base.length >= kIllnessRobustMinNights) {
        rz = _robustZ(b, base);
        if (rz != null) {
          judged++;
          if (rz >= kIllnessRespZ) signals.add('resp');
        }
      }
    }
    final h = rmssd[i];
    if (h != null && h > 0) {
      final base = prior(rmssd, log: true);
      if (base.length >= kIllnessRobustMinNights) {
        hz = _robustZ(math.log(h), base);
        if (hz != null) {
          judged++;
          if (hz <= kIllnessHrvZ) signals.add('hrv');
        }
      }
    }
    if (judged < 2) {
      prev = null;
      continue;
    }
    final yellow = signals.length >= 2;
    final level = !yellow
        ? IllnessWatchLevel.clear
        : (prev == IllnessWatchLevel.yellow || prev == IllnessWatchLevel.red)
            ? IllnessWatchLevel.red
            : IllnessWatchLevel.yellow;
    out[i] = IllnessWatchNight(
      date: dates[i],
      level: level,
      signals: signals,
      judged: judged,
      rhrRiseBpm: rise,
      respZ: rz,
      hrvZ: hz,
    );
    prev = level;
  }
  return out;
}
