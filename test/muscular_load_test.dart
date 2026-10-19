// Muscular load and strain with lifting (compute/muscular_load.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/muscular_load.dart';
import 'package:openstrap_edge/compute/reserve_strain.dart';

void main() {
  group('effort', () {
    test('a rated set to failure counts 1, four in reserve a third', () {
      expect(effortFactor(10, rated: true).f, 1.0);
      expect(effortFactor(6, rated: true).f, closeTo(1 / 3, 1e-9));
    });

    test('an effort nobody picked is never read as measured', () {
      final e = effortFactor(7, rated: false);
      expect(e.rated, isFalse);
      expect(e.f, kUnratedEffort);
      expect(effortFactor(null, rated: true).rated, isFalse);
    });
  });

  group('effective load', () {
    test('a squat carries most of the body with the bar', () {
      const s = StrengthSetIn(exerciseKey: 'back_squat', reps: 5, loadKg: 100);
      expect(effectiveLoadKg(s, bodyKg: 90), closeTo(100 + 0.89 * 90, 1e-9));
      expect(effectiveLoadKg(s), 100, reason: 'no weight → bar only');
    });

    test('a bodyweight pull-up needs a body weight, else it is absent', () {
      const s = StrengthSetIn(exerciseKey: 'pull_up', reps: 8);
      expect(effectiveLoadKg(s, bodyKg: 80), closeTo(76, 1e-9));
      expect(effectiveLoadKg(s), isNull);
    });

    test('a bodyweight set of an unknown exercise is absent, never zero', () {
      const s = StrengthSetIn(exerciseKey: 'mystery_move', reps: 10);
      expect(effectiveLoadKg(s, bodyKg: 80), isNull);
    });
  });

  test('session load counts what it can and says what it skipped', () {
    final l = sessionLoad(const [
      StrengthSetIn(
          exerciseKey: 'bench_press', reps: 8, loadKg: 80, rpe: 9, rpeRated: true),
      StrengthSetIn(exerciseKey: 'bench_press', reps: 8, loadKg: 80, rpe: 7),
      StrengthSetIn(exerciseKey: 'mystery_move', reps: 10),
    ], bodyKg: 80)!;
    expect(l.setsCounted, 2);
    expect(l.setsWithoutLoad, 1);
    expect(l.setsUnrated, 1);
    final perSet = 8 * (80 + 0.10 * 80);
    expect(l.volumeKg, closeTo(2 * perSet, 1e-9));
    expect(l.effortVolumeKg,
        closeTo(perSet * (1 / 1.5) + perSet * kUnratedEffort, 1e-9));
    expect(sessionLoad(const [StrengthSetIn(exerciseKey: 'pull_up', reps: 5)]),
        isNull);
  });

  test('V_max is the patent yardstick and needs history', () {
    expect(personalVmax([1000, 1000, 1000]), isNull);
    final v = personalVmax([800, 1000, 1200, 1000])!;
    expect(v, closeTo(1000 + 2 * 163.299, 0.01));
    expect(muscularLoad(null, v), isNull);
  });

  test('the strain inverse round-trips exactly', () {
    for (final w in [0.0, 5.0, 60.0, 300.0, 1000.0]) {
      expect(weightedMinutesFromStrain(strainFromLoad(w)), closeTo(w, 1e-6));
    }
    expect(weightedMinutesFromStrain(null), isNull);
  });

  test('calibration needs eight rated cardio sessions', () {
    final seven = List.filled(7, const CardioSessionIn(10, 6, 45));
    expect(strainCalibration(seven), isNull);
    final eight = [...seven, const CardioSessionIn(10, 6, 45)];
    final c = strainCalibration(eight)!;
    expect(c.n, 8);
    expect(c.k, closeTo(weightedMinutesFromStrain(10)! / 270, 1e-9));
  });

  test('a lift adds only what heart rate missed, and never past 21', () {
    final k = weightedMinutesFromStrain(10)! / 270;
    // A lift rated 8 for 60 min whose heart rate only reached strain 6.
    final m = missingLoadMinutes(
        k: k, rpe: 8, minutes: 60, sessionStrain: 6)!;
    expect(m, greaterThan(0));
    // A lift whose heart rate already covered its rating adds nothing.
    expect(missingLoadMinutes(k: k, rpe: 2, minutes: 10, sessionStrain: 15),
        0);
    expect(missingLoadMinutes(k: k, rpe: null, minutes: 60, sessionStrain: 6),
        isNull);
    final day = dayStrainWithLifting(9, [m])!;
    expect(day, greaterThan(9));
    expect(day, lessThanOrEqualTo(21));
    expect(dayStrainWithLifting(9, const []), closeTo(9, 1e-9));
    expect(dayStrainWithLifting(null, [m]), isNull);
  });
}
