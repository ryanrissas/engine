import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/recovery_calibration.dart';

void main() {
  group('recoveryCalibrating', () {
    test('holds the grade back for the first week of nights', () {
      for (var n = 0; n < kRecoveryCalibrationNights; n++) {
        expect(recoveryCalibrating(n), isTrue, reason: '$n nights');
      }
    });

    test('releases it on the seventh night', () {
      expect(kRecoveryCalibrationNights, 7);
      expect(recoveryCalibrating(7), isFalse);
      expect(recoveryCalibrating(30), isFalse);
    });

    test('an unknown count never hides a score', () {
      expect(recoveryCalibrating(null), isFalse);
    });
  });
}
