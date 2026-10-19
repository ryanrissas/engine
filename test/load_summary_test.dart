// The Strain tab's lift and arm load summary (compute/load_summary.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/load_summary.dart';
import 'package:openstrap_edge/compute/muscular_load.dart';

final _today = DateTime(2026, 10, 18);

int _ts(int daysAgo, [int hour = 17]) =>
    DateTime(_today.year, _today.month, _today.day - daysAgo, hour)
        .millisecondsSinceEpoch ~/
    1000;

Map<String, Object?> _session(String id, int daysAgo, String type,
        {double? strain, double? rpe, int? minutes}) =>
    {
      'id': id,
      'start_ts': _ts(daysAgo),
      'type': type,
      'strain': strain,
      'rpe': rpe,
      'duration_min': minutes,
    };

List<Map<String, Object?>> _squats(double kg, {int? rpe}) => [
      for (var i = 0; i < 4; i++)
        {
          'exercise_key': 'back_squat',
          'reps': 5,
          'load_kg': kg,
          'rpe': rpe,
          'rpe_source': rpe == null ? null : 'user',
          'seq': i,
        },
    ];

void main() {
  test('empty history is an empty summary, not zeros', () {
    final s = buildLoadSummary(sessions: const [], sets: const {}, today: _today);
    expect(s.latestLift, isNull);
    expect(s.todayStrainWithLifting, isNull);
    expect(s.throwRatio, isNull);
    expect(s.throwWhy, 'no_throws_logged');
  });

  test('the latest lift is scored against the earlier ones', () {
    final sessions = [
      for (var i = 0; i < 5; i++) _session('l$i', 20 - i * 4, 'weight_training'),
    ];
    final sets = {
      for (var i = 0; i < 5; i++) 'l$i': _squats(100.0 + i * 5, rpe: 8),
    };
    final s = buildLoadSummary(
        sessions: sessions, sets: sets, today: _today, bodyKg: 90);
    expect(s.latestLift, isNotNull);
    expect(s.latestLift!.pastSessions, 4);
    expect(s.latestLift!.muscular, isNotNull);
    expect(s.latestLift!.muscular, inExclusiveRange(0, 1.5));
  });

  test('strain with lifting waits for calibration, then adds the lift', () {
    final cardio = [
      for (var i = 0; i < 8; i++)
        _session('c$i', 30 - i, 'running', strain: 10, rpe: 6, minutes: 45),
    ];
    final lift =
        _session('lift', 0, 'weight_training', strain: 6, rpe: 8, minutes: 60);
    final noCal = buildLoadSummary(
        sessions: [...cardio.sublist(0, 7), lift],
        sets: const {},
        today: _today,
        todayStrain: 9);
    expect(noCal.k, isNull);
    expect(noCal.calibrationSessions, 7);
    expect(noCal.todayStrainWithLifting, isNull);

    final cal = buildLoadSummary(
        sessions: [...cardio, lift], sets: const {}, today: _today, todayStrain: 9);
    expect(cal.calibrationSessions, kMinCalibrationSessions);
    expect(cal.todayRatedLifts, 1);
    expect(cal.todayStrainWithLifting, greaterThan(9));
  });

  test('a Baseball session without a throw log blocks the arm ratio', () {
    final sessions = [
      for (var i = 0; i < 30; i++) _session('b$i', 30 - i, 'baseball'),
    ];
    final sets = {
      for (var i = 0; i < 30; i++)
        if (i != 27)
          'b$i': [
            {'exercise_key': 'throw_bullpen', 'reps': 30, 'rpe': 8, 'seq': 0},
          ],
    };
    final s = buildLoadSummary(sessions: sessions, sets: sets, today: _today);
    expect(s.throwRatio, isNull);
    expect(s.throwWhy, startsWith('unlogged_sessions'));

    final all = {
      for (var i = 0; i < 30; i++)
        'b$i': [
          {'exercise_key': 'throw_bullpen', 'reps': 30, 'rpe': 8, 'seq': 0},
        ],
    };
    final ok = buildLoadSummary(sessions: sessions, sets: all, today: _today);
    expect(ok.throwRatio, isNotNull);
    expect(ok.throws7d, 30 * 6); // six sessions in the last seven days
    // Throw entries are not lifts.
    expect(ok.latestLift, isNull);
  });
}
