import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/provisional_recovery.dart';
import 'package:openstrap_edge/compute/recovery_calibration.dart';

void main() {
  group('recoveryCalibrating', () {
    test('holds the grade back until four nights of baseline exist', () {
      for (var n = 0; n < kRecoveryCalibrationNights; n++) {
        expect(recoveryCalibrating(n), isTrue, reason: '$n nights');
      }
    });

    test('releases it on the fifth night, like WHOOP\'s first read', () {
      expect(kRecoveryCalibrationNights, 5);
      expect(recoveryCalibrating(5), isFalse);
      expect(recoveryCalibrating(30), isFalse);
    });

    test('an unknown count never hides a score', () {
      expect(recoveryCalibrating(null), isFalse);
    });

    test('nights 5–14 are an early read; 15 on is the full composite', () {
      expect(recoveryEarlyRead(4), isFalse);
      expect(recoveryEarlyRead(5), isTrue);
      expect(recoveryEarlyRead(14), isTrue);
      expect(recoveryEarlyRead(15), isFalse);
      expect(recoveryEarlyRead(null), isFalse);
    });
  });

  group('provisionalReadiness', () {
    // A steady baseline with real spread, and a night one spread above it.
    List<double> base(int n, double mid, double step) =>
        [for (var i = 0; i < n; i++) mid + step * ((i % 3) - 1)];
    List<ana.ReadinessInput> inputs(int n) => [
          ana.hrvInput(4.6 + 0.08, base(n, 4.6, 0.08)),
          ana.rhrInput(48, base(n, 50, 2)),
        ];
    ana.Metric<ana.Readiness> full(int n) =>
        ana.readinessComposite(inputs(n));

    test('below 14 nights the composite refuses, and the early read scores',
        () {
      final f = full(6);
      expect(f.present, isFalse);
      expect(f.note, startsWith('need_baseline:'));
      final p = provisionalReadiness(f, inputs(6), hrvNights: 6, rhrNights: 6)!;
      expect(p.value!.score, inInclusiveRange(0, 100));
      expect(p.note, startsWith('provisional:nights=6,need=14'));
      expect(p.confidence, lessThanOrEqualTo(0.3));
    });

    test('a short baseline is shrunk toward the middle', () {
      final p4 = provisionalReadiness(full(4), inputs(4),
          hrvNights: 4, rhrNights: 4)!;
      final p13 = provisionalReadiness(full(13), inputs(13),
          hrvNights: 13, rhrNights: 13)!;
      // A good night reads above 50 either way, closer to 50 on four nights.
      expect(p4.value!.score, greaterThan(50));
      expect(p13.value!.score, greaterThan(p4.value!.score));
    });

    test('nothing under four nights, and nothing once the full one scores', () {
      expect(
          provisionalReadiness(full(3), inputs(3), hrvNights: 3, rhrNights: 3),
          isNull);
      final f14 = full(14);
      expect(f14.present, isTrue);
      expect(
          provisionalReadiness(f14, inputs(14), hrvNights: 14, rhrNights: 14),
          isNull);
    });
  });
}
