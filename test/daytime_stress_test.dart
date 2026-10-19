// The waking-day stress monitor (compute/daytime_stress.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/daytime_stress.dart';

const int _t0 = 1786694400; // a whole minute

class _Day {
  final tsSec = <int>[];
  final hr = <int>[];
  final ax = <double>[], ay = <double>[], az = <double>[];
  final rrMs = <double>[], rrTsMs = <double>[];
}

/// [minutes] of 1 Hz data. [stressedFrom]..[stressedTo] (minute indices) run
/// at a higher HR with suppressed variability; [movingFrom]..[movingTo] jiggle
/// the gravity vector.
_Day _day(int minutes,
    {int stressedFrom = -1,
    int stressedTo = -1,
    int movingFrom = -1,
    int movingTo = -1,
    int seed = 11}) {
  final d = _Day();
  var s = seed;
  double u() {
    s = (1103515245 * s + 12345) & 0x7fffffff;
    return s / 0x7fffffff * 2 - 1;
  }

  var x = 0.0;
  var beatT = _t0 * 1000.0;
  for (var sec = 0; sec < minutes * 60; sec++) {
    final m = sec ~/ 60;
    final stressed = m >= stressedFrom && m < stressedTo;
    final moving = m >= movingFrom && m < movingTo;
    final meanRr = stressed ? 760.0 : 1000.0;
    final amp = stressed ? 6.0 : 25.0;
    final t = _t0 + sec;
    while (beatT < (t + 1) * 1000) {
      x = 0.8 * x + amp * u();
      final r = meanRr + x;
      beatT += r;
      d.rrMs.add(r);
      d.rrTsMs.add(beatT);
    }
    d.tsSec.add(t);
    d.hr.add((60000 / meanRr).round());
    if (moving) {
      d.ax.add(0.3 * u());
      d.ay.add(0.3 * u());
      d.az.add(0.9 + 0.2 * u());
    } else {
      d.ax.add(0);
      d.ay.add(0);
      d.az.add(1);
    }
  }
  return d;
}

DaytimeStressResult _score(_Day d,
        {StressHistory history = const StressHistory(),
        List<(int, int)> exercise = const [],
        double? cut = 0.02}) =>
    daytimeStress(
      tsSec: d.tsSec,
      hr: d.hr,
      ax: d.ax,
      ay: d.ay,
      az: d.az,
      rrMs: d.rrMs,
      rrTsMs: d.rrTsMs,
      excludeSpans: const [],
      exerciseSpans: exercise,
      restingHr: 50,
      maxHr: 190,
      quietCutG: cut,
      history: history,
    );

StressHistory _historyOf(StressDaySummary s, int days) => StressHistory(
      hMed: List.filled(days, s.hMed!),
      hMad: List.filled(days, s.hMad!),
      xMed: List.filled(days, s.xMed!),
      xMad: List.filled(days, s.xMad!),
      sP05: List.filled(days, s.sP05!),
      sP99: List.filled(days, s.sP99!),
      nStill: List.filled(days, s.nStill.toDouble()),
    );

void main() {
  test('no reference yet → absent with the baseline it needs, summary kept', () {
    final r = _score(_day(240));
    expect(r.dayScore, isNull);
    expect(r.block['value'], '—');
    expect(r.block['note'], startsWith('need_baseline:'));
    expect(r.summary.nStill, greaterThan(200));
    expect(r.summary.xMed, isNotNull);
  });

  test('a calm day against its own kind of days reads low-to-middle', () {
    final calm = _score(_day(240)).summary;
    final r = _score(_day(240, seed: 5), history: _historyOf(calm, 5));
    expect(r.dayScore, isNotNull);
    // Calm against calm sits in the low band — never in the high one.
    expect(r.dayScore!, inInclusiveRange(0.0, 1.5));
    final v = r.block['value'] as Map;
    expect(v['scored_min'], greaterThan(200));
    expect(v['high_min'], lessThan(20));
  });

  test('an activated hour while still reads high', () {
    final calm = _score(_day(240)).summary;
    final r = _score(_day(240, stressedFrom: 100, stressedTo: 160),
        history: _historyOf(calm, 5));
    final quiet = _score(_day(240, seed: 5), history: _historyOf(calm, 5));
    expect(r.dayScore!, greaterThan(quiet.dayScore! + 0.3));
    final v = r.block['value'] as Map;
    expect(v['high_min'], greaterThan(30));
    expect(v['peak'], greaterThan(2.5));
    expect(v['longest_high_min'], greaterThan(20));
  });

  test('workouts and their tail are not scored', () {
    final calm = _score(_day(240)).summary;
    final day = _day(240, stressedFrom: 100, stressedTo: 160);
    final r = _score(day,
        history: _historyOf(calm, 5),
        exercise: [(_t0 + 100 * 60, _t0 + 160 * 60)]);
    final v = r.block['value'] as Map;
    expect(v['high_min'], lessThan(10));
    expect(v['scored_min'], lessThan(190));
  });

  test('moving minutes are not scored', () {
    final calm = _score(_day(240)).summary;
    final r = _score(_day(240, movingFrom: 0, movingTo: 200),
        history: _historyOf(calm, 5));
    // 40 still minutes left: under the hour a day needs.
    expect(r.dayScore, isNull);
    expect(r.block['note'], startsWith('need_input:name=still_minutes'));
  });

  test('an unknown strap and a missing resting HR both refuse by name', () {
    expect(_score(_day(120), cut: null).block['note'],
        'need_input:name=device_family_stillness_cut');
    final d = _day(120);
    final r = daytimeStress(
      tsSec: d.tsSec,
      hr: d.hr,
      ax: d.ax,
      ay: d.ay,
      az: d.az,
      rrMs: d.rrMs,
      rrTsMs: d.rrTsMs,
      excludeSpans: const [],
      exerciseSpans: const [],
      restingHr: null,
      maxHr: 190,
      quietCutG: 0.02,
    );
    expect(r.block['note'], 'need_input:name=resting_hr');
  });

  test('resting reference is the median of the last 14 nights', () {
    expect(stressRestingHr([50, 52, 48], 46), 49);
    expect(stressRestingHr([], null), isNull);
    expect(stressRestingHr(List.filled(20, 60), 40), 60);
  });
}
