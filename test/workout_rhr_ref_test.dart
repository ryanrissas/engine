// Pins the resting reference auto workout detection prices its floor on.
// Detection used to require the day's OWN nocturnal resting HR and skip the
// day otherwise, so a fresh install could not detect a workout before its
// first recorded night (and no day whose sleep went undetected ever could).
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/workout_rhr_ref.dart';

void main() {
  group('workoutRestingRef', () {
    test("the night's own resting HR wins when there is one", () {
      final r = workoutRestingRef(
        nocturnal: 47.6,
        manual: 55,
        recentNocturnal: const [50, 51],
      );
      expect(r.bpm, 48);
      expect(r.ref, WorkoutRhrRef.night);
    });

    test('no night: the profile resting HR is used', () {
      final r = workoutRestingRef(manual: 52, recentNocturnal: const [50]);
      expect(r.bpm, 52);
      expect(r.ref, WorkoutRhrRef.manual);
    });

    test('no night, no profile: the median of the trailing nights', () {
      final r = workoutRestingRef(recentNocturnal: const [49, 60, 51, 50]);
      expect(r.bpm, 51); // (50 + 51) / 2 = 50.5 → 51
      expect(r.ref, WorkoutRhrRef.recent);
    });

    test('a fresh install has nothing: no bpm, the detector defaults', () {
      final r = workoutRestingRef();
      expect(r.bpm, isNull);
      expect(r.ref, WorkoutRhrRef.none);
    });

    test('a zero or negative reading is not a reference', () {
      expect(workoutRestingRef(nocturnal: 0, manual: 0).ref,
          WorkoutRhrRef.none);
      expect(workoutRestingRef(recentNocturnal: const [0, -3]).ref,
          WorkoutRhrRef.none);
    });
  });
}
