// The lab-trained sleep-stage model (compute/sleep_stage_model.dart): the Dart
// features, trees and Viterbi pass must reproduce the Python training code on
// the same night (fixture written by the training script).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_stage_model.dart';

const int _n = 240;

double _hr(int i) =>
    55 + 8 * math.sin(i / 600) + 3 * math.sin(i / 37) +
    (i >= 3000 && i < 3300 ? 15 : 0);

double _ang(int i) =>
    10 * math.sin(i / 900) + (i % 997 < 20 ? 30 * math.sin(i.toDouble()) : 0);

void main() {
  final fx = jsonDecode(
          File('test/fixtures/sleep_stage_model_parity.json').readAsStringSync())
      as Map<String, dynamic>;
  final secs = _n * kStageEpochSec;
  final hr = [for (var i = 0; i < secs; i++) _hr(i)];
  final grav = <List<double>?>[
    for (var i = 0; i < secs; i++)
      i >= 5000 && i < 5060
          ? null
          : [
              math.cos(_ang(i) * math.pi / 180),
              0.0,
              math.sin(_ang(i) * math.pi / 180),
            ],
  ];

  test('features match the training code', () {
    final f = stageFeatures(hr, grav, _n);
    final want = (fx['features'] as List).cast<List>();
    expect(f.length, want.length);
    for (var e = 0; e < _n; e++) {
      for (var k = 0; k < 15; k++) {
        expect(f[e][k], closeTo((want[e][k] as num).toDouble(), 1e-6),
            reason: 'epoch $e feature $k');
      }
    }
  });

  test('tree probabilities match scikit-learn', () {
    final want = (fx['probs'] as List).cast<List>();
    final p = stageProbabilities(
        [for (final r in (fx['features'] as List).cast<List>())
            [for (final v in r) (v as num).toDouble()]]);
    for (var e = 0; e < _n; e++) {
      for (var k = 0; k < 4; k++) {
        expect(p[e][k], closeTo((want[e][k] as num).toDouble(), 1e-9));
      }
    }
  });

  test('the decoded night matches', () {
    final want = (fx['path'] as List).cast<int>();
    final p = stageViterbi(stageProbabilities(stageFeatures(hr, grav, _n)));
    var same = 0;
    for (var e = 0; e < _n; e++) {
      if (p[e] == want[e]) same++;
    }
    // Float rounding may flip an epoch at a threshold; nothing more.
    expect(same, greaterThanOrEqualTo(_n - 2));
  });

  test('labels every second; unobserved stays unobserved; thin nights refuse',
      () {
    final base = List<String>.filled(secs, 'light');
    for (var i = 600; i < 900; i++) {
      base[i] = 'unobserved';
    }
    final out = modelStageNight(hr: hr, gravity: grav, baseStages4: base)!;
    expect(out.length, secs);
    for (var i = 600; i < 900; i++) {
      expect(out[i], 'unobserved');
    }
    expect(out.toSet().difference({...kStageLabels, 'unobserved'}), isEmpty);
    expect(
        modelStageNight(
            hr: hr.sublist(0, 3000),
            gravity: grav.sublist(0, 3000),
            baseStages4: List<String>.filled(3000, 'light')),
        isNull);
  });
}
