/// The resting-HR reference auto workout detection prices its floor on.
///
/// Detection used to run only on a day with its OWN nocturnal resting HR and
/// skip the day outright otherwise. The detector's floor is
/// `max(RHR+40, RHR + 0.45·(HRmax−RHR))`, so it needs *a* resting reference
/// — not tonight's. The old gate meant a fresh install (no night recorded yet)
/// and any day whose sleep went undetected could not detect a workout at all,
/// however obvious: the band read every beat of it and the app said nothing.
///
/// Preference, most specific first; [none] leaves the detector on its own
/// documented default (60 bpm), which with an unknown HRmax prices the floor
/// at ~119 bpm sustained for 12 min — a real effort, never a brisk walk.
enum WorkoutRhrRef {
  /// This day's nocturnal resting HR — the same number readiness uses.
  night,

  /// The resting HR the user entered in their profile.
  manual,

  /// The median of the trailing nocturnal resting HRs (prior days).
  recent,

  /// Nothing to go on; the detector's own default applies.
  none,
}

typedef WorkoutRestingRef = ({int? bpm, WorkoutRhrRef ref});

WorkoutRestingRef workoutRestingRef({
  double? nocturnal,
  int? manual,
  List<double> recentNocturnal = const [],
}) {
  if (nocturnal != null && nocturnal > 0) {
    return (bpm: nocturnal.round(), ref: WorkoutRhrRef.night);
  }
  if (manual != null && manual > 0) {
    return (bpm: manual, ref: WorkoutRhrRef.manual);
  }
  final xs = [for (final v in recentNocturnal) if (v > 0) v]..sort();
  if (xs.isNotEmpty) {
    final mid = xs.length ~/ 2;
    final med = xs.length.isOdd ? xs[mid] : (xs[mid - 1] + xs[mid]) / 2;
    return (bpm: med.round(), ref: WorkoutRhrRef.recent);
  }
  return (bpm: null, ref: WorkoutRhrRef.none);
}
