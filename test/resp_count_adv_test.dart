// Count-adv respiratory rate (compute/resp_count_adv.dart).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/resp_count_adv.dart';

/// [minutes] of beats whose intervals swing with breathing at [brpm]
/// (respiratory sinus arrhythmia) around [meanMs], plus a little noise.
({List<double> nn, List<double> t}) _rsa(double brpm,
    {double minutes = 30, double meanMs = 1000, double ampMs = 60, int seed = 3}) {
  final rnd = math.Random(seed);
  final nn = <double>[], t = <double>[];
  var now = 0.0;
  while (now < minutes * 60000) {
    final v = meanMs +
        ampMs * math.sin(2 * math.pi * brpm / 60 * now / 1000) +
        (rnd.nextDouble() - 0.5) * 6;
    now += v;
    nn.add(v);
    t.add(now);
  }
  return (nn: nn, t: t);
}

void main() {
  for (final rate in [10.0, 13.0, 16.0]) {
    test('recovers $rate br/min from RSA', () {
      final s = _rsa(rate);
      final m = countAdvRespRate(s.nn, s.t);
      expect(m.present, isTrue, reason: m.note);
      expect(m.value!.brpm, closeTo(rate, 1.0));
    });
  }

  test('absent — never 0 — on too few beats', () {
    final s = _rsa(15, minutes: 0.5);
    final m = countAdvRespRate(s.nn, s.t);
    expect(m.present, isFalse);
    expect(m.value, isNull);
  });

  test('a gap splits the run instead of being bridged', () {
    final a = _rsa(15, minutes: 12);
    final b = _rsa(15, minutes: 12, seed: 9);
    final shift = a.t.last + 10 * 60000; // ten minutes with no beats
    final nn = [...a.nn, ...b.nn];
    final t = [...a.t, for (final x in b.t) x + shift];
    final m = countAdvRespRate(nn, t);
    expect(m.present, isTrue, reason: m.note);
    expect(m.value!.brpm, closeTo(15, 1.0));
  });

  group('fusion with the RSA estimate', () {
    ana.Metric<ana.RespEstimate> est(double? v, {double c = 0.8}) => v == null
        ? const ana.Metric<ana.RespEstimate>.absent(
            tier: ana.Tier.high, inputs_used: ['x'])
        : ana.Metric<ana.RespEstimate>(
            value: ana.RespEstimate(v, v / 60, null, 'rsa'),
            confidence: c,
            tier: ana.Tier.high,
            inputs_used: const ['x'],
          );

    test('agreement inside 2 br/min fuses between the two', () {
      final f = fusedNightRespRate(est(15.0), est(16.0));
      expect(f.decision, 'fused');
      expect(f.brpm, inInclusiveRange(15.0, 16.0));
    });

    test('disagreement keeps RSA at lower confidence', () {
      final f = fusedNightRespRate(est(15.0), est(19.0));
      expect(f.decision, 'disagree');
      expect(f.brpm, 15.0);
      expect(f.confidence, lessThan(0.8));
    });

    test('RSA withheld → no rate, even with count-adv present', () {
      final f = fusedNightRespRate(est(null), est(15.0));
      expect(f.brpm, isNull);
      expect(f.countAdvBrpm, 15.0);
    });

    test('count-adv absent → RSA unchanged', () {
      final f = fusedNightRespRate(est(14.2), est(null));
      expect(f.brpm, 14.2);
      expect(f.decision, 'rsa_only');
    });
  });
}
