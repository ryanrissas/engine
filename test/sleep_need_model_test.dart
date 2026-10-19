// Sleep need on WHOOP's patent structure (compute/sleep_need_model.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_need_model.dart';

String _d(int i) =>
    DateTime.utc(2026, 10, 1 + i).toIso8601String().substring(0, 10);

List<SleepNeedDay> _days(List<double?> tstH,
        {List<double?>? strain, List<double?>? napMin}) =>
    [
      for (var i = 0; i < tstH.length; i++)
        SleepNeedDay(
          date: _d(i),
          tstMin: tstH[i] == null ? null : tstH[i]! * 60,
          strain: strain?[i],
          napMin: napMin?[i],
        ),
    ];

void main() {
  test('the strain term is the patent logistic, read in hours', () {
    expect(strainSleepSec(0) / 60, lessThan(1));
    expect(strainSleepSec(10) / 60, closeTo(12.1, 0.3));
    expect(strainSleepSec(17) / 60, closeTo(51, 0.1));
    expect(strainSleepSec(21) / 60, closeTo(77.3, 0.3));
    for (var s = 0.0; s < 21; s += 0.5) {
      expect(strainSleepSec(s + 0.5), greaterThan(strainSleepSec(s)));
    }
  });

  test('baseline starts at the 8.4 h prior and moves to the wearer', () {
    final prior = sleepNeedBaseline();
    expect(prior.sec, 8.4 * 3600);
    expect(prior.source, 'population_prior');
    final some = sleepNeedBaseline(personalHours: 7.6, personalNights: 3);
    expect(some.source, 'blended');
    expect(some.sec / 3600, inExclusiveRange(7.6, 8.4));
    final lots = sleepNeedBaseline(personalHours: 7.6, personalNights: 30);
    expect(lots.source, 'personal');
    expect(lots.sec / 3600, closeTo(7.6, 0.15));
    expect(lots.confidence, greaterThan(some.confidence));
  });

  test('sleeping exactly the need builds no debt', () {
    final r = sleepNeedTonight(_days(List.filled(10, 8.4)), lastIsToday: true)!;
    expect(r.debtLedgerSec, 0);
    expect(r.needSec, closeTo(8.4 * 3600, 1));
  });

  test('a short night adds its shortfall to tomorrow, and fades after', () {
    // Eight good nights, one 6.4 h night, then good again.
    final tst = [...List.filled(8, 8.4), 6.4];
    final r = sleepNeedTonight(_days(tst), lastIsToday: true)!;
    expect(r.debtLedgerSec / 3600, closeTo(2.0, 0.01));
    expect(r.debtSec, kSleepDebtCapSec); // capped at 2 h added
    final later = sleepNeedTonight(_days([...tst, 8.4, 8.4]), lastIsToday: true)!;
    // Two baseline nights after it: ~(2/3)² of it left, ≈ 0.9 h.
    expect(later.debtLedgerSec / 3600, closeTo(2.0 * 4 / 9, 0.01));
  });

  test('a long night repays debt 1:1', () {
    final r = sleepNeedTonight(_days([...List.filled(5, 8.4), 6.4, 10.4]),
        lastIsToday: true)!;
    expect(r.debtLedgerSec, 0);
  });

  test('an unmeasured night adds nothing — it only lets debt fade', () {
    final r = sleepNeedTonight(_days([8.4, 8.4, 6.4, null, 8.4]),
        lastIsToday: true)!;
    expect(r.debtLedgerSec / 3600, lessThan(2.0 * 2 / 3 + 1e-9));
  });

  test('naps come off 1:1 and today\'s strain adds the logistic', () {
    final base = sleepNeedTonight(_days(List.filled(5, 8.4)), lastIsToday: true)!;
    final hard = sleepNeedTonight(
        _days(List.filled(5, 8.4), strain: [null, null, null, null, 17]),
        lastIsToday: true)!;
    expect(hard.needSec - base.needSec, closeTo(strainSleepSec(17), 1));
    final nap = sleepNeedTonight(
        _days(List.filled(5, 8.4), napMin: [null, null, null, null, 30]),
        lastIsToday: true)!;
    expect(base.needSec - nap.needSec, closeTo(30 * 60, 1));
  });

  test('goals are 100 / 85 / 70 % of need', () {
    final r = sleepNeedTonight(_days(List.filled(5, 8.4)), lastIsToday: true)!;
    expect(r.goalsSec['peak'], r.needSec);
    expect(r.goalsSec['perform'], closeTo(r.needSec * 0.85, 1e-6));
    expect(r.goalsSec['get_by'], closeTo(r.needSec * 0.70, 1e-6));
  });

  test('last night is scored against last night\'s need', () {
    final r = sleepNeedTonight(
        _days([8.4, 8.4, 8.4, 8.4, 8.4], strain: [null, null, null, 21, null]),
        lastIsToday: true)!;
    expect(r.lastNightNeedSec,
        closeTo(8.4 * 3600 + strainSleepSec(21), 1));
    expect(hoursVsNeedPct(8.4 * 60, r.lastNightNeedSec), lessThan(100));
    expect(hoursVsNeedPct(null, r.lastNightNeedSec), isNull);
  });

  test('not today → no tonight', () {
    expect(sleepNeedTonight(_days([8.0, 8.0]), lastIsToday: false), isNull);
  });

  group('four-day consistency', () {
    int at(int day, int h, [int m = 0]) =>
        DateTime(2026, 10, 1 + day, h, m).millisecondsSinceEpoch ~/ 1000;
    double tod(int s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s * 1000);
      return t.hour * 60.0 + t.minute;
    }

    SleepNeedDay night(int i, int onH, int onM, int offH) => SleepNeedDay(
          date: _d(i),
          onsetSec: at(i - 1, onH, onM),
          wakeSec: at(i, offH),
        );

    test('identical nights score 100', () {
      final days = [for (var i = 1; i <= 4; i++) night(i, 23, 0, 7)];
      expect(fourDayConsistency(days, tod), closeTo(100, 1e-9));
    });

    test('one night an hour late scores lower', () {
      final days = [
        night(1, 23, 0, 7),
        night(2, 23, 0, 7),
        SleepNeedDay(date: _d(3), onsetSec: at(3, 0), wakeSec: at(3, 8)),
        night(4, 23, 0, 7),
      ];
      final c = fourDayConsistency(days, tod)!;
      expect(c, closeTo(7 / 9 * 100, 0.5));
    });

    test('fewer than four consecutive nights → null', () {
      final days = [night(1, 23, 0, 7), night(2, 23, 0, 7), night(4, 23, 0, 7)];
      expect(fourDayConsistency(days, tod), isNull);
    });
  });

  test('restorative share', () {
    expect(restorativePct(90, 110, 450), closeTo(44.4, 0.1));
    expect(restorativePct(null, 110, 450), isNull);
  });
}
