// Nightly HRV on WHOOP's described method (compute/night_hrv.dart):
// overlapping 5-min windows stepping 30 s, wake removed, likely slow-wave
// windows weighted double, each window scored by the analytics estimator.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/night_hrv.dart';

const int _start = 1786669200; // a whole second

/// [hours] of beats: an AR(1) wander around [meanRr] ms (φ 0.8, so successive
/// differences are not the alternating jitter the estimator refuses), from a
/// fixed LCG so the test is reproducible.
({List<double> rr, List<double> ts}) _night(double hours,
    {double meanRr = 1000, double amp = 25, int seed = 7}) {
  final rr = <double>[], ts = <double>[];
  var x = 0.0, t = _start * 1000.0, s = seed;
  double u() {
    s = (1103515245 * s + 12345) & 0x7fffffff;
    return s / 0x7fffffff * 2 - 1;
  }

  while (t < (_start + hours * 3600) * 1000) {
    x = 0.8 * x + amp * u();
    final r = meanRr + x;
    t += r;
    rr.add(r);
    ts.add(t);
  }
  return (rr: rr, ts: ts);
}

void main() {
  test('on a steady night it agrees with the consecutive-window estimator', () {
    final n = _night(6);
    final end = _start + 6 * 3600;
    final consecutive = ana.sleepSessionRmssdDetail(n.rr, n.ts,
        startSec: _start, endSec: end);
    expect(consecutive.present, isTrue, reason: 'fixture must pass the gates');
    final overlap = overlappingNightRmssd(
        rrMs: n.rr, rrTsMs: n.ts, startSec: _start, endSec: end)!;
    expect(overlap, closeTo(consecutive.value!.rmssd, consecutive.value!.rmssd * 0.05));
  });

  test('windows that are mostly awake are removed', () {
    final n = _night(2);
    final end = _start + 2 * 3600;
    expect(
        overlappingNightRmssd(
            rrMs: n.rr,
            rrTsMs: n.ts,
            startSec: _start,
            endSec: end,
            stagesPerSec: List.filled(2 * 3600, 'wake')),
        isNull);
  });

  test('likely slow-wave windows weigh double', () {
    // First half: low heart rate (long intervals), high variability — the
    // slow-wave signature. Second half: higher heart rate, lower variability.
    final a = _night(2, meanRr: 1150, amp: 40, seed: 3);
    final shift = a.ts.last - _start * 1000.0;
    final b = _night(2, meanRr: 850, amp: 15, seed: 5);
    final rr = [...a.rr, ...b.rr];
    final ts = [...a.ts, for (final t in b.ts) t + shift];
    final end = _start + 4 * 3600;
    final weighted =
        overlappingNightRmssd(rrMs: rr, rrTsMs: ts, startSec: _start, endSec: end)!;
    final plain = ana.sleepSessionRmssdDetail(rr, ts,
        startSec: _start, endSec: end).value!.rmssd;
    // Weighting the slow-wave half pulls the night toward its higher RMSSD.
    expect(weighted, greaterThan(plain));
  });

  test('absent — never 0 — without beats or a full window', () {
    expect(
        overlappingNightRmssd(
            rrMs: const [], rrTsMs: const [], startSec: _start, endSec: _start + 3600),
        isNull);
    final n = _night(0.05);
    expect(
        overlappingNightRmssd(
            rrMs: n.rr, rrTsMs: n.ts, startSec: _start, endSec: _start + 120),
        isNull);
  });
}
