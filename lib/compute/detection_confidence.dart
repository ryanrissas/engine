/// How sure a detected workout is, in words, from the evidence the detection
/// itself recorded — never a score invented at display time.
///
/// Two facts decide it. Which pass found the bout: the whole-day detector
/// holds a bout above its work floor the entire time (`likely`), while the
/// rests pass accepts a session that drops below it between efforts
/// (`probable`). And what the floor was priced on: the night's own resting HR
/// is the reference the detector was tuned for; the profile's, the trailing
/// nights' or the default is one step weaker. Both facts are in the stored
/// suggestion (`rests`, `rhr_ref` — absent when the night's own RHR was used).
enum DetectionConfidence { likely, probable, possible }

DetectionConfidence detectionConfidence(Map<String, dynamic> details) {
  var level = details['rests'] == true
      ? DetectionConfidence.probable
      : DetectionConfidence.likely;
  if (details['rhr_ref'] != null && level != DetectionConfidence.possible) {
    level = DetectionConfidence.values[level.index + 1];
  }
  return level;
}

/// The one line under the heading: the word, then why.
String detectionConfidenceLine(Map<String, dynamic> details) {
  final c = detectionConfidence(details);
  final word = switch (c) {
    DetectionConfidence.likely => 'Likely',
    DetectionConfidence.probable => 'Probable',
    DetectionConfidence.possible => 'Possible',
  };
  final why = [
    if (details['rests'] == true)
      'heart rate dropped between efforts'
    else
      'heart rate held high throughout',
    if (details['rhr_ref'] != null) 'no resting rate from your own night yet',
  ].join(' · ');
  return '$word · $why';
}
