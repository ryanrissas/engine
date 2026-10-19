// The per-night HMM stager (compute/night_stager.dart).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/night_stager.dart';

const int _on = 1786700000;

/// A 7 h synthetic night: still and slow early (deep-like), a movement-and-
/// HR burst at 3 h (wake), faster and more variable HR late (REM-like).
({
  List<double> hr,
  List<ana.AccelSample> accel,
  List<double> rr,
  List<double> rrTs,
}) _night({int seconds = 7 * 3600}) {
  final hr = <double>[];
  final accel = <ana.AccelSample>[];
  final rr = <double>[];
  final rrTs = <double>[];
  var s = 12345;
  double u() {
    s = (1103515245 * s + 12345) & 0x7fffffff;
    return s / 0x7fffffff - 0.5;
  }

  var t = _on * 1000.0;
  for (var i = 0; i < seconds; i++) {
    final h = i / 3600.0;
    final waking = h >= 3.0 && h < 3.25;
    final base = waking ? 72.0 : (h < 2 ? 48.0 : (h > 5 ? 58.0 : 53.0));
    final jitter = h > 5 ? 4.0 : 1.0;
    hr.add(base + jitter * u());
    final ang = waking ? 20 * math.sin(i / 3) : 0.2 * u();
    final rad = ang * math.pi / 180;
    accel.add(ana.AccelSample((_on + i) * 1000.0, math.cos(rad), 0, math.sin(rad)));
    while (t < (_on + i + 1) * 1000.0) {
      final r = 60000 / (base + jitter * u()) + (h < 2 ? 40 : 15) * u();
      t += r;
      rr.add(r);
      rrTs.add(t);
    }
  }
  return (hr: hr, accel: accel, rr: rr, rrTs: rrTs);
}

void main() {
  test('labels every second, keeps unobserved seconds unobserved', () {
    final n = _night();
    final base = List<String>.filled(n.hr.length, 'light');
    for (var i = 4 * 3600; i < 4 * 3600 + 600; i++) {
      base[i] = 'unobserved';
    }
    final out = restageNight(
      hr: n.hr,
      accel: n.accel,
      rrMs: n.rr,
      rrTsMs: n.rrTs,
      onsetSec: _on,
      baseStages4: base,
    )!;
    expect(out.length, base.length);
    for (var i = 4 * 3600; i < 4 * 3600 + 600; i++) {
      expect(out[i], 'unobserved');
    }
    expect(out.toSet().difference({'wake', 'light', 'deep', 'rem', 'unobserved'}),
        isEmpty);
    // The movement-and-HR burst reads as wake.
    final burst = out.sublist(3 * 3600 + 120, 3 * 3600 + 780);
    expect(burst.where((s) => s == 'wake').length, greaterThan(burst.length ~/ 2));
    // Deep sits early, REM late.
    int count(String st, int fromH, int toH) =>
        out.sublist(fromH * 3600, toH * 3600).where((s) => s == st).length;
    expect(count('deep', 0, 2), greaterThan(count('deep', 5, 7)));
    expect(count('rem', 5, 7), greaterThan(count('rem', 0, 2)));
  });

  test('a thin night (< 1 h observed) is left to the base labels', () {
    final n = _night(seconds: 3000);
    expect(
      restageNight(
        hr: n.hr,
        accel: n.accel,
        rrMs: n.rr,
        rrTsMs: n.rrTs,
        onsetSec: _on,
        baseStages4: List<String>.filled(n.hr.length, 'light'),
      ),
      isNull,
    );
  });

  test('no beats at all still stages on movement and heart rate', () {
    final n = _night();
    final out = restageNight(
      hr: n.hr,
      accel: n.accel,
      rrMs: const [],
      rrTsMs: const [],
      onsetSec: _on,
      baseStages4: List<String>.filled(n.hr.length, 'light'),
    );
    expect(out, isNotNull);
  });
}
