import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/detection_confidence.dart';

void main() {
  test('a continuous bout on the night\'s own resting HR is likely', () {
    expect(detectionConfidence({'avg_bpm': 150}), DetectionConfidence.likely);
    expect(detectionConfidenceLine({}), startsWith('Likely · '));
  });

  test('a session with rests is one step down', () {
    expect(detectionConfidence({'rests': true}), DetectionConfidence.probable);
    expect(detectionConfidenceLine({'rests': true}),
        contains('dropped between efforts'));
  });

  test('a weaker resting reference is one step down, never below possible', () {
    expect(detectionConfidence({'rhr_ref': 'manual'}),
        DetectionConfidence.probable);
    expect(detectionConfidence({'rests': true, 'rhr_ref': 'none'}),
        DetectionConfidence.possible);
    expect(detectionConfidenceLine({'rests': true, 'rhr_ref': 'none'}),
        startsWith('Possible · '));
  });
}
