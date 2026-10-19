// THROWING LOAD — the arm's workload, from throws the player logs.
//
// The band cannot count throws: the peer-reviewed throwing-workload work uses
// a forearm IMU at 100 Hz with a throw defined as forearm angular velocity
// above 800 °/s, and this band streams 1 Hz gravity. So throws are LOGGED, per
// session: how many, what kind, and how hard (intent 6–10).
//
// PUBLISHED:
//  * Acute:chronic workload — daily workload, a 7-day acute and a 28-day
//    chronic (IJSPT interval-throwing program built on 111,196 sensor throws,
//    "safe" ACWR 0.7–1.3). Injury risk "particularly evident" at ACWR ≥ 1.27
//    in baseball pitchers (Mehta 2019, Phys Ther Sport 40:66, as cited by
//    Tabaracci et al. 2025, IJSPT 20(2):221).
//  * Exponentially weighted averages rather than rolling sums, λ = 2/(N+1)
//    (Williams et al. 2017, Br J Sports Med).
//  * ACWR is DESCRIPTIVE. It is coupled by construction and has no causal
//    evidence behind it as a predictor (Impellizzeri 2020, IJSPP), so this
//    never states an injury probability and never issues an instruction.
//
// OURS (starting values, labelled): per-throw weight by type — game 1.0,
// bullpen 0.9, long toss 0.8, flat ground 0.6, catch play 0.3 — times intent/10.
// If a club's sensor workloads are ever available, these get refitted.
//
// HONESTY: a day with a Baseball session but no throw log is UNKNOWN, not
// zero, and any unknown day in the window makes the ratio abstain, naming the
// count. A day with no Baseball session at all is a real zero.
//
// Pure and isolate-safe.

/// Throw types and their per-throw weight (ours).
const Map<String, double> kThrowTypeWeight = {
  'game': 1.0,
  'bullpen': 0.9,
  'long_toss': 0.8,
  'flat_ground': 0.6,
  'catch_play': 0.3,
};

const Map<String, String> kThrowTypeLabel = {
  'game': 'Game',
  'bullpen': 'Bullpen',
  'long_toss': 'Long toss',
  'flat_ground': 'Flat ground',
  'catch_play': 'Catch play',
};

/// `strength_set.exercise_key` prefix for a throw entry.
const String kThrowKeyPrefix = 'throw_';

/// The ACWR above which the cited study saw more arm injuries.
const double kThrowAcwrCaution = 1.27;

/// The published "safe" band of the interval-throwing program.
const double kThrowAcwrLow = 0.7;
const double kThrowAcwrHigh = 1.3;

/// Days of history before a ratio is shown.
const int kThrowMinHistoryDays = 21;

/// Window that must be fully known.
const int kThrowChronicDays = 28;

bool isThrowKey(String key) => key.startsWith(kThrowKeyPrefix);

String throwKey(String type) => '$kThrowKeyPrefix$type';

String? throwTypeOf(String key) {
  if (!isThrowKey(key)) return null;
  final t = key.substring(kThrowKeyPrefix.length);
  return kThrowTypeWeight.containsKey(t) ? t : null;
}

class ThrowEntry {
  final String type;
  final int count;
  final int intent; // 6–10
  const ThrowEntry(this.type, this.count, this.intent);
}

/// One session's throwing load, or null when nothing countable was logged.
double? sessionThrowLoad(List<ThrowEntry> entries) {
  var t = 0.0;
  var any = false;
  for (final e in entries) {
    final w = kThrowTypeWeight[e.type];
    if (w == null || e.count <= 0 || e.intent < 1 || e.intent > 10) continue;
    t += e.count * w * e.intent / 10;
    any = true;
  }
  return any ? t : null;
}

/// One calendar day's throwing: [load] null means unknown (a Baseball session
/// with no log); 0 with [known] means a day without throwing.
class ThrowDay {
  final String date; // YYYY-MM-DD
  final double? load;
  final int throws;
  const ThrowDay(this.date, this.load, {this.throws = 0});
  bool get known => load != null;
}

class ThrowRatio {
  final double acute;
  final double chronic;
  final double ratio;
  final int historyDays;
  const ThrowRatio(this.acute, this.chronic, this.ratio, this.historyDays);
  bool get aboveCaution => ratio >= kThrowAcwrCaution;
  bool get insideSafeBand => ratio >= kThrowAcwrLow && ratio <= kThrowAcwrHigh;
}

/// EWMA acute:chronic over consecutive [days] (oldest first, one per calendar
/// day, ending today), or a reason it abstains.
({ThrowRatio? ratio, String? why}) throwAcwr(List<ThrowDay> days) {
  final first = days.indexWhere((d) => (d.load ?? 0) > 0);
  if (first < 0) return (ratio: null, why: 'no_throws_logged');
  final span = days.length - first;
  if (span < kThrowMinHistoryDays) {
    return (
      ratio: null,
      why: 'need_history:have=$span,need=$kThrowMinHistoryDays',
    );
  }
  // An unknown day is never read as zero: the averages start AFTER the most
  // recent one, and need the same history from there.
  final lastUnknown = days.lastIndexWhere((d) => !d.known);
  final start = lastUnknown >= first ? lastUnknown + 1 : first;
  if (days.length - start < kThrowMinHistoryDays) {
    final unknown = days.sublist(first).where((d) => !d.known).length;
    return (ratio: null, why: 'unlogged_sessions:n=$unknown');
  }
  const la = 2 / (7 + 1), lc = 2 / (kThrowChronicDays + 1);
  double? a, c;
  for (var i = start; i < days.length; i++) {
    final x = days[i].load!;
    a = a == null ? x : la * x + (1 - la) * a;
    c = c == null ? x : lc * x + (1 - lc) * c;
  }
  if (c == null || c <= 0 || a == null) {
    return (ratio: null, why: 'no_chronic_load');
  }
  return (ratio: ThrowRatio(a, c, a / c, days.length - start), why: null);
}
