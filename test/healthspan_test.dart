// Engine Age / Pace of Aging (compute/healthspan.dart).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/crossday_pipeline.dart';
import 'package:openstrap_edge/compute/healthspan.dart';
import 'package:openstrap_edge/compute/profile.dart';

String _d(int i) =>
    DateTime.utc(2026, 6, 1).add(Duration(days: i)).toIso8601String().substring(0, 10);

List<HealthspanDay> _days(
  int n, {
  double rhr = 45,
  double tstMin = 480,
  int mod = 20,
  int vig = 10,
  double strengthPerSession = 60,
  double? steps,
  double Function(int i)? rhrAt,
}) =>
    [
      for (var i = 0; i < n; i++)
        HealthspanDay(
          date: _d(i),
          rhr: rhrAt?.call(i) ?? rhr,
          tstMin: tstMin,
          mvpaModMin: mod,
          mvpaVigMin: vig,
          wornMin: 900,
          steps: steps,
          // Mon/Wed/Fri lifting.
          strengthMin: i % 7 == 0 || i % 7 == 2 || i % 7 == 4
              ? strengthPerSession
              : 0,
        ),
    ];

Map<String, dynamic> _input(HealthspanResult r, String key) =>
    r.inputs.firstWhere((i) => i.key == key).toJson();

void main() {
  test('fewer than 21 days → absent with a need_baseline note', () {
    final m = healthspan(_days(15), ageYears: 23, sex: 'm', sriWindow: 85);
    expect(m.present, isFalse);
    expect(m.note, startsWith('need_baseline:'));
  });

  test('too few inputs → absent, never a fabricated age', () {
    final days = [
      for (var i = 0; i < 30; i++)
        HealthspanDay(date: _d(i), rhr: 45, tstMin: 480),
    ];
    final m = healthspan(days, ageYears: 23, sex: 'm');
    expect(m.present, isFalse);
    expect(m.note, startsWith('need_inputs:'));
  });

  test('each input on its published curve', () {
    final m = healthspan(_days(30), ageYears: 23, sex: 'm', sriWindow: 85);
    final r = m.value!;
    // RHR 45: (45 − 60)/10 · ln 1.09 (Zhang), no fitness term.
    expect(_input(r, 'rhr')['ln_hr'], closeTo(-1.5 * math.log(1.09), 1e-9));
    expect(r.rhrFitnessAdjusted, isFalse);
    // 8 h: no sleep-duration effect.
    expect(_input(r, 'sleep')['ln_hr'], 0);
    // (20 + 2·10) min/day → 14 MET-h/week, between Arem's 11.25 and 18.75.
    final mvpa = _input(r, 'mvpa');
    expect(mvpa['value'], closeTo(14, 1e-9));
    final lnAt14 = math.log(0.69) +
        (math.log(0.63) - math.log(0.69)) * (14 - 11.25) / 7.5;
    expect(mvpa['ln_hr'], closeTo(lnAt14 - math.log(0.69), 1e-9));
    // 3 × 60 min/week is past the nadir and held there: no cost for lifting.
    expect(_input(r, 'strength')['ln_hr'], closeTo(0, 1e-12));
    // SRI 85: −0.0284 per point above 81.
    expect(_input(r, 'sri')['ln_hr'], closeTo(-0.0284 * 4, 1e-12));
    // Age = chronological + Σ α·lnHR / 0.10.
    final sum = r.inputs.fold<double>(0, (s, i) => s + i.alpha * i.lnHr);
    expect(r.impactYears, closeTo(sum / kHealthspanB, 1e-9));
    expect(r.engineAge, closeTo(23 + r.impactYears, 1e-9));
    expect(r.engineAge, lessThan(23)); // good habits read younger
    expect(r.seYears, greaterThan(0));
    expect(r.toJson()['warning'], kHealthspanWarning);
    expect(r.toJson()['impact_years_nchs'],
        closeTo(r.impactYears * 0.10 / 0.0705, 1e-9));
  });

  test('little strength still earns part of the benefit', () {
    final m = healthspan(_days(30, strengthPerSession: 5),
        ageYears: 23, sex: 'm', sriWindow: 85);
    final s = _input(m.value!, 'strength');
    // ~15 min/week, below the 40-min nadir → a cost relative to the referent.
    expect(s['ln_hr'], greaterThan(0));
  });

  test('no strength session saved → strength abstains, not zero', () {
    final m = healthspan(_days(30, strengthPerSession: 0),
        ageYears: 23, sex: 'm', sriWindow: 85);
    expect(m.value!.inputs.any((i) => i.key == 'strength'), isFalse);
    expect(m.value!.missing['strength'], 'need_input:name=strength_session');
  });

  group('VO2max only from an entered test', () {
    test('a recent test adds fitness and switches RHR to fitness-adjusted', () {
      final m = healthspan(_days(30),
          ageYears: 23,
          sex: 'm',
          sriWindow: 85,
          vo2maxTest: 55,
          vo2maxTestDate: _d(20));
      final r = m.value!;
      expect(_input(r, 'vo2max')['ln_hr'],
          closeTo((11 / 3.5) * math.log(0.87), 1e-9));
      expect(_input(r, 'rhr')['ln_hr'], closeTo(-1.5 * math.log(1.16), 1e-9));
      expect(r.rhrFitnessAdjusted, isTrue);
    });

    test('a test over a year old does not enter', () {
      final m = healthspan(_days(30),
          ageYears: 23,
          sex: 'm',
          sriWindow: 85,
          vo2maxTest: 55,
          vo2maxTestDate: '2025-01-01');
      expect(m.value!.inputs.any((i) => i.key == 'vo2max'), isFalse);
    });

    test('no published referent for women → abstains, never borrows men\'s',
        () {
      final m = healthspan(_days(30),
          ageYears: 23,
          sex: 'f',
          sriWindow: 85,
          vo2maxTest: 50,
          vo2maxTestDate: _d(20));
      expect(m.value!.missing['vo2max'], 'no_published_referent:sex');
    });

    test('the profile keeps only a dated, plausible test', () {
      expect(vo2maxTestFromProfile({'vo2max_test': 55}), isNull);
      expect(
          vo2maxTestFromProfile(
              {'vo2max_test': 55, 'vo2max_test_date': '2026-10-01'}),
          55);
      expect(
          vo2maxTestFromProfile(
              {'vo2max_test': 150, 'vo2max_test_date': '2026-10-01'}),
          isNull);
      final p = Profile.fromMap(
          {'vo2max_test': 55, 'vo2max_test_date': '2026-10-01'});
      expect(p.toMap()['vo2max_test'], 55);
      expect(p.toMap()['vo2max_test_date'], '2026-10-01');
    });

    test('Cooper 12-minute run', () {
      expect(cooperVo2max(3000), closeTo((3000 - 504.9) / 44.73, 1e-12));
    });
  });

  test('steps and MVPA share variance: the smaller counts half', () {
    final m = healthspan(_days(30, steps: 12000),
        ageYears: 23, sex: 'm', sriWindow: 85);
    final r = m.value!;
    final alphas = {for (final i in r.inputs) i.key: i.alpha};
    expect(alphas.containsKey('steps'), isTrue);
    expect([alphas['steps'], alphas['mvpa']], contains(0.5));
  });

  test('pace of aging: a better last month reads below 1×', () {
    // RHR 60 for two months, then 45 for the last 30 days.
    final m = healthspan(
      _days(90, rhrAt: (i) => i < 60 ? 60 : 45),
      ageYears: 23,
      sex: 'm',
      sriWindow: 85,
      sri30: 85,
    );
    expect(m.value!.pace, isNotNull);
    expect(m.value!.pace!, lessThan(1));
    expect(m.value!.pace!, greaterThanOrEqualTo(-1));
  });

  test('no pace before 60 days', () {
    final m = healthspan(_days(40), ageYears: 23, sex: 'm', sriWindow: 85);
    expect(m.value!.pace, isNull);
  });

  test('MVPA minutes from heart rate reserve bands', () {
    final curve = [
      for (final v in [50, 80, 100, 120, 150, 190]) {'t': 0, 'v': v},
    ];
    // RHR 50, max 190 → reserve 140: 40 % = 106, 60 % = 134.
    final m = mvpaMinutes(curve, restingHr: 50, maxHr: 190)!;
    expect(m.moderate, 1); // 120
    expect(m.vigorous, 2); // 150, 190
    expect(mvpaMinutes(curve, restingHr: null, maxHr: 190), isNull);
  });

  test('strength session types', () {
    expect(isStrengthSessionType('Weight training'), isTrue);
    expect(isStrengthSessionType('weight_training'), isTrue);
    expect(isStrengthSessionType('Baseball'), isFalse);
    expect(isStrengthSessionType('HIIT'), isFalse);
  });

  test('the cross-day bundle carries healthspan and still no VO2max', () {
    final days = [
      for (var i = 0; i < 30; i++)
        {'date': _d(i), 'rhr': 45.0, 'tst_min': 480},
    ];
    final out = buildCrossDayBundle(days, const {'age': 23, 'sex': 'm'});
    expect(out.containsKey('healthspan'), isTrue);
    expect((out['healthspan'] as Map)['value'], '—');
    expect(out.containsKey('vo2max'), isFalse);
    expect(out.containsKey('fitness_age'), isFalse);
  });
}
