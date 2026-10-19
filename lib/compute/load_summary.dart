// The Strain tab's load summary: the latest lift's muscular load against the
// wearer's own sessions, today's strain with lifting (once calibrated), and
// the arm's acute:chronic throwing load. Pure arithmetic over rows the caller
// read — see muscular_load.dart and throw_load.dart for every formula.

import '../data/day_label.dart';
import 'muscular_load.dart';
import 'throw_load.dart';

/// Session types whose effort is mostly cardiovascular (the calibration set).
const Set<String> kCardioTypes = {
  'running', 'trail_running', 'walking', 'hiking', 'cycling', 'indoor_bike',
  'rowing', 'swimming', 'elliptical', 'stair_climber', 'treadmill',
  'jump_rope',
};

/// Session types where heart rate under-reads the work.
const Set<String> kLiftTypes = {
  'weight_training', 'powerlifting', 'bodyweight', 'calisthenics',
  'kettlebell', 'crossfit', 'functional', 'baseball',
};

class LiftSummary {
  final String date;
  final String type;
  final SessionLoad load;

  /// Patent-structure muscular load vs the user's V_max, or null.
  final double? muscular;
  final int pastSessions;
  const LiftSummary(
      this.date, this.type, this.load, this.muscular, this.pastSessions);
}

class LoadSummary {
  final LiftSummary? latestLift;

  /// Rated cardio sessions the strain calibration has (needs
  /// [kMinCalibrationSessions]).
  final int calibrationSessions;
  final double? k;

  /// Today's day strain with the lifts' missing load added, or null.
  final double? todayStrainWithLifting;
  final double? todayStrain;

  /// Today's lifts with a rating (the ones that can add load).
  final int todayRatedLifts;
  final int todayLifts;

  final ThrowRatio? throwRatio;
  final String? throwWhy;
  final int throws7d;
  const LoadSummary({
    this.latestLift,
    this.calibrationSessions = 0,
    this.k,
    this.todayStrainWithLifting,
    this.todayStrain,
    this.todayRatedLifts = 0,
    this.todayLifts = 0,
    this.throwRatio,
    this.throwWhy,
    this.throws7d = 0,
  });
}

double? _d(Object? v) => v is num ? v.toDouble() : null;

String _dayOf(Object? startTs) => dayLabelOf(DateTime.fromMillisecondsSinceEpoch(
    ((startTs as num?)?.toInt() ?? 0) * 1000));

List<StrengthSetIn> _liftSets(List<Map<String, Object?>> rows) => [
      for (final r in rows)
        if (!isThrowKey((r['exercise_key'] as String?) ?? ''))
          StrengthSetIn(
            exerciseKey: (r['exercise_key'] as String?) ?? '',
            reps: (r['reps'] as num?)?.toInt(),
            loadKg: _d(r['load_kg']),
            rpe: (r['rpe'] as num?)?.toInt(),
            rpeRated: r['rpe'] != null && r['rpe_source'] == 'user',
          ),
    ];

List<ThrowEntry> _throws(List<Map<String, Object?>> rows) => [
      for (final r in rows)
        if (throwTypeOf((r['exercise_key'] as String?) ?? '') != null &&
            r['reps'] is num &&
            r['rpe'] is num)
          ThrowEntry(throwTypeOf(r['exercise_key'] as String)!,
              (r['reps'] as num).toInt(), (r['rpe'] as num).toInt()),
    ];

/// [sessions] oldest first (id, start_ts, type, strain, rpe, duration_min);
/// [sets] by session id. [today] is the local calendar day the summary is for
/// and [todayStrain] that day's strain, when it has one.
LoadSummary buildLoadSummary({
  required List<Map<String, Object?>> sessions,
  required Map<String, List<Map<String, Object?>>> sets,
  required DateTime today,
  double? bodyKg,
  double? todayStrain,
}) {
  final todayKey = dayLabelOf(today);

  // ── latest lift vs the user's own V_max ──
  final liftVolumes = <({String id, String date, String type, SessionLoad l})>[];
  for (final s in sessions) {
    final id = s['id'] as String?;
    if (id == null) continue;
    final l = sessionLoad(_liftSets(sets[id] ?? const []), bodyKg: bodyKg);
    if (l == null) continue;
    liftVolumes.add(
        (id: id, date: _dayOf(s['start_ts']), type: '${s['type']}', l: l));
  }
  LiftSummary? latest;
  if (liftVolumes.isNotEmpty) {
    final last = liftVolumes.last;
    final past = [
      for (final v in liftVolumes.sublist(0, liftVolumes.length - 1))
        v.l.volumeKg,
    ];
    latest = LiftSummary(last.date, last.type, last.l,
        muscularLoad(last.l, personalVmax(past)), past.length);
  }

  // ── strain with lifting, calibrated on the user's own cardio ──
  final cal = strainCalibration([
    for (final s in sessions)
      if (kCardioTypes.contains(s['type']) &&
          _d(s['strain']) != null &&
          _d(s['rpe']) != null &&
          _d(s['duration_min']) != null)
        CardioSessionIn(
            _d(s['strain'])!, _d(s['rpe'])!, _d(s['duration_min'])!),
  ]);
  final rated = sessions
      .where((s) =>
          kCardioTypes.contains(s['type']) &&
          _d(s['strain']) != null &&
          _d(s['rpe']) != null)
      .length;
  final todayLifts = [
    for (final s in sessions)
      if (kLiftTypes.contains(s['type']) && _dayOf(s['start_ts']) == todayKey) s,
  ];
  final missing = <double>[];
  var ratedLifts = 0;
  if (cal != null) {
    for (final s in todayLifts) {
      final m = missingLoadMinutes(
        k: cal.k,
        rpe: _d(s['rpe']),
        minutes: _d(s['duration_min']),
        sessionStrain: _d(s['strain']),
      );
      if (m != null) {
        missing.add(m);
        ratedLifts++;
      }
    }
  }
  final withLifting = (cal == null || ratedLifts == 0 || todayStrain == null)
      ? null
      : dayStrainWithLifting(todayStrain, missing);

  // ── throwing: one row per calendar day from the first logged throw ──
  final byDay = <String, ({double load, int throws, bool unknown})>{};
  DateTime? firstDay;
  for (final s in sessions) {
    if (s['type'] != 'baseball') continue;
    final id = s['id'] as String?;
    final day = _dayOf(s['start_ts']);
    final entries = _throws(id == null ? const [] : (sets[id] ?? const []));
    final t = sessionThrowLoad(entries);
    final prev = byDay[day] ?? (load: 0.0, throws: 0, unknown: false);
    byDay[day] = (
      load: prev.load + (t ?? 0),
      throws: prev.throws + entries.fold(0, (a, e) => a + e.count),
      unknown: prev.unknown || t == null,
    );
    if (t != null) {
      final d = DateTime.fromMillisecondsSinceEpoch(
          ((s['start_ts'] as num?)?.toInt() ?? 0) * 1000);
      final dd = DateTime(d.year, d.month, d.day);
      if (firstDay == null || dd.isBefore(firstDay)) firstDay = dd;
    }
  }
  final days = <ThrowDay>[];
  var throws7 = 0;
  if (firstDay != null) {
    final end = DateTime(today.year, today.month, today.day);
    for (var d = firstDay;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final key = dayLabelOf(d);
      final row = byDay[key];
      days.add(row == null
          ? ThrowDay(key, 0)
          : ThrowDay(key, row.unknown ? null : row.load, throws: row.throws));
      if (end.difference(d).inDays < 7) throws7 += row?.throws ?? 0;
    }
  }
  final acwr = days.isEmpty
      ? (ratio: null, why: 'no_throws_logged')
      : throwAcwr(days);

  return LoadSummary(
    latestLift: latest,
    calibrationSessions: cal?.n ?? rated,
    k: cal?.k,
    todayStrainWithLifting: withLifting,
    todayStrain: todayStrain,
    todayRatedLifts: ratedLifts,
    todayLifts: todayLifts.length,
    throwRatio: acwr.ratio,
    throwWhy: acwr.why,
    throws7d: throws7,
  );
}
